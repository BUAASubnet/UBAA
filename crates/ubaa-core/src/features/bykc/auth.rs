//! 博雅业务登录与加密 API 请求。
#![allow(clippy::missing_errors_doc)]

use serde_json::Value;

use super::crypto::{decrypt_response, encrypt_request};
use super::parser::envelope;
use super::{BykcCredential, error};
use crate::connection::from_webvpn_url;
use crate::error::Result;
use crate::ports::HttpRequest;

pub(super) const BASE_URL: &str = "https://bykc.buaa.edu.cn";
pub(super) const LOGIN_URL: &str = "https://bykc.buaa.edu.cn/sscv/cas/login";

/// 通过 CAS 跳转获取博雅业务令牌。
pub(crate) async fn ensure_login(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcCredential> {
    super::super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(value) = state.bykc.credential() {
        return Ok(value);
    }
    let _guard = state.bykc.login_guard().await;
    if let Some(value) = state.bykc.credential() {
        return Ok(value);
    }
    let mut current = runtime.url(LOGIN_URL)?;
    for _ in 0..8 {
        let response = runtime.request(HttpRequest::get(current.clone())).await?;
        for candidate in [
            response.final_url.as_str(),
            response
                .headers
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case("location"))
                .and_then(|(_, v)| v.first())
                .map_or("", |value| value.as_str()),
        ] {
            if let Some(token) = token_from_url(candidate) {
                let value = BykcCredential { token };
                state.bykc.set(value.clone());
                return Ok(value);
            }
        }
        let location = response
            .headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("location"))
            .and_then(|(_, v)| v.first())
            .ok_or_else(|| error("博雅登录跳转缺少目标地址"))?;
        let target = resolve_login_target(&response.final_url, location)?;
        let parsed = url::Url::parse(&target).map_err(|_| error("博雅登录跳转地址无效"))?;
        if !matches!(
            parsed.host_str().unwrap_or_default(),
            "sso.buaa.edu.cn" | "bykc.buaa.edu.cn"
        ) {
            return Err(error("博雅登录跳转到未允许的主机"));
        }
        // 业务跳转必须继续沿用当前路线，WebVPN 模式不能回落到直连地址。
        current = runtime.url(&target)?;
    }
    Err(error("博雅登录跳转次数超过限制"))
}

fn token_from_url(raw: &str) -> Option<String> {
    url::Url::parse(raw)
        .ok()?
        .query_pairs()
        .find(|(k, _)| k == "token")
        .map(|(_, v)| v.into_owned())
        .filter(|v| !v.is_empty())
}

pub(super) fn resolve_login_target(final_url: &str, location: &str) -> Result<String> {
    let direct_final = from_webvpn_url(final_url)?;
    let direct_location = from_webvpn_url(location)?;
    let base = url::Url::parse(&direct_final).map_err(|_| error("博雅登录跳转地址无效"))?;
    base.join(&direct_location)
        .map(|target| target.to_string())
        .map_err(|_| error("博雅登录跳转地址无效"))
}

pub(super) async fn request_api(
    runtime: &mut crate::runtime::ClientRuntime,
    api_name: &str,
    payload: Value,
) -> Result<Value> {
    let credential = ensure_login(runtime).await?;
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| error("系统时间无效"))?
        .as_millis();
    let timestamp = i64::try_from(timestamp).map_err(|_| error("系统时间无效"))?;
    let encrypted = encrypt_request(&payload.to_string(), timestamp)?;
    let mut request = HttpRequest::post(
        runtime.url(&format!("{BASE_URL}/sscv/{api_name}"))?,
        encrypted.encrypted_data.clone().into_bytes(),
    );
    request.headers.insert(
        "Content-Type".into(),
        "application/json; charset=UTF-8".into(),
    );
    request
        .headers
        .insert("Accept".into(), "application/json".into());
    request.headers.insert(
        "Referer".into(),
        runtime.url("https://bykc.buaa.edu.cn/system/course-select")?,
    );
    request
        .headers
        .insert("Origin".into(), runtime.url(BASE_URL)?);
    request
        .headers
        .insert("auth_token".into(), credential.token.clone());
    request.headers.insert("authtoken".into(), credential.token);
    request.headers.insert("ak".into(), encrypted.ak);
    request.headers.insert("sk".into(), encrypted.sk);
    request.headers.insert("ts".into(), encrypted.ts);
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(error("博雅服务暂时不可用"));
    }
    let text = super::super::body(&response);
    let plain = decrypt_response(&text, &encrypted.aes_key).unwrap_or(text);
    envelope(&plain)
}
