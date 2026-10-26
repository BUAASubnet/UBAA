//! Cgyy 业务登录、路线内 token 与 `WebVPN` Cookie 同步。

use std::collections::BTreeMap;
use std::time::Instant;

use serde_json::Value;
use tracing::{debug, info, warn};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpMethod, HttpRequest};
use crate::runtime::ClientRuntime;

use super::http::{
    check_business_response, log_response, method_name_value, operation_name,
    safe_parameter_summary, safe_url, signed_request,
};
use super::parser::{data, string};
use super::sign::timestamp_millis;

const LOGIN_URL: &str = "https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin";
const SSO_COOKIE: &str = "sso_buaa_zhjs_token";
const WEBVPN_COOKIE_URL: &str = "https://d.buaa.edu.cn/wengine-vpn/cookie";
const WEBVPN_COOKIE_PATH: &str = "/venue-zhjs";

pub(super) async fn ensure_login(runtime: &mut ClientRuntime) -> Result<String> {
    super::super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(token) = state.cgyy.token() {
        debug!(target: "ubaa::cgyy", operation = "business_login", cached = true, "复用 Cgyy 业务会话");
        return Ok(token);
    }
    info!(target: "ubaa::cgyy", operation = "business_login", route = ?runtime.mode(), "开始建立 Cgyy 业务会话");
    let _guard = state.cgyy.login_guard().await;
    if let Some(token) = state.cgyy.token() {
        return Ok(token);
    }
    debug!(target: "ubaa::cgyy", operation = "business_login.sso", route = ?runtime.mode(), bootstrap_url = %safe_url(LOGIN_URL), "请求 Cgyy SSO 引导");
    let response =
        super::super::get_with_redirects(runtime, runtime.url(LOGIN_URL)?, &[], "场馆预约").await?;
    log_response(runtime, "business_login.sso", &response);
    super::super::check_response(&response, "场馆预约")?;
    let Some(sso_token) = get_sso_token(runtime).await? else {
        warn!(target: "ubaa::cgyy", operation = "business_login.sso", route = ?runtime.mode(), sso_cookie_present = false, "Cgyy SSO 响应未写入令牌 Cookie");
        return Err(authentication_error("未获取到场馆预约 SSO 令牌"));
    };
    debug!(target: "ubaa::cgyy", operation = "business_login.sso", sso_cookie_present = true, sso_cookie_len = sso_token.len(), "已取得 Cgyy SSO Cookie");
    let mut request = signed_request(
        runtime,
        HttpMethod::Post,
        "/api/login",
        BTreeMap::new(),
        None,
    )?;
    request.headers.insert("Sso-Token".into(), sso_token);
    debug!(
        target: "ubaa::cgyy",
        operation = "business_login.api",
        route = ?runtime.mode(),
        body_len = request.body.len(),
        "发送 Cgyy 业务登录请求"
    );
    let response = runtime.request(request).await?;
    log_response(runtime, "business_login.api", &response);
    super::super::check_response(&response, "场馆预约")?;
    let value = data(&super::super::body(&response))?;
    let token = value
        .get("token")
        .and_then(Value::as_object)
        .and_then(|token| string(token, "access_token"))
        .filter(|token| !token.is_empty())
        .ok_or_else(|| authentication_error("场馆预约登录未返回访问令牌"))?;
    state.cgyy.set(token.clone());
    info!(target: "ubaa::cgyy", operation = "business_login", access_token_len = token.len(), "Cgyy 业务会话建立完成");
    Ok(token)
}

pub(super) async fn business_request(
    runtime: &mut ClientRuntime,
    method: HttpMethod,
    path: &str,
    params: BTreeMap<String, String>,
) -> Result<String> {
    let started = Instant::now();
    let operation = operation_name(method, path);
    info!(target: "ubaa::cgyy", feature = "cgyy", operation, method = method_name_value(method), "开始 Cgyy 请求");
    debug!(target: "ubaa::cgyy", feature = "cgyy", operation, parameter_keys = ?params.keys().collect::<Vec<_>>(), parameter_summary = ?safe_parameter_summary(&params), "构造 Cgyy 请求");
    for attempt in 0..2 {
        let access_token = match ensure_login(runtime).await {
            Ok(token) => token,
            Err(error) => {
                warn!(
                    target: "ubaa::cgyy",
                    feature = "cgyy",
                    route = ?runtime.mode(),
                    operation,
                    elapsed_ms = elapsed_millis(started),
                    error_code = ?error.code,
                    "Cgyy 业务登录失败"
                );
                return Err(error);
            }
        };
        let mut request =
            signed_request(runtime, method, path, params.clone(), Some(&access_token))?;
        if method == HttpMethod::Post {
            request.body = crate::upstream::encode_form(&params);
        }
        debug!(
            target: "ubaa::cgyy",
            feature = "cgyy",
            route = ?runtime.mode(),
            operation,
            attempt = attempt + 1,
            request_url = %safe_url(&request.url),
            body_len = request.body.len(),
            "发送 Cgyy HTTP 请求"
        );
        let response = runtime.request(request).await?;
        log_response(runtime, operation, &response);
        match check_business_response(&response, "场馆预约") {
            Ok(()) => {
                info!(target: "ubaa::cgyy", feature = "cgyy", operation, attempt = attempt + 1, elapsed_ms = elapsed_millis(started), "Cgyy 请求成功");
                return Ok(super::super::body(&response));
            }
            Err(error) if attempt == 0 && error.code == ErrorCode::AuthenticationRequired => {
                warn!(target: "ubaa::cgyy", feature = "cgyy", operation, attempt = attempt + 1, error_code = ?error.code, "Cgyy 业务会话失效，清理令牌并重试");
                runtime.feature_state().cgyy.clear();
            }
            Err(error) => {
                warn!(target: "ubaa::cgyy", feature = "cgyy", operation, attempt = attempt + 1, elapsed_ms = elapsed_millis(started), error_code = ?error.code, "Cgyy 请求失败");
                return Err(error);
            }
        }
    }
    unreachable!("场馆请求认证重试次数已耗尽")
}

pub(super) async fn get(
    runtime: &mut ClientRuntime,
    path: &str,
    params: BTreeMap<String, String>,
) -> Result<String> {
    business_request(runtime, HttpMethod::Get, path, params).await
}

fn elapsed_millis(started: Instant) -> u64 {
    u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX)
}

/// 从路线会话或 `WebVPN` 网关的 Cookie 同步接口取得 Cgyy SSO 令牌。
///
/// 浏览器端 `WebVPN` 通过脚本读取 `/wengine-vpn/cookie` 的纯文本 Cookie 快照；
/// Core 不执行网页脚本，因此在 `WebVPN` 路线显式重放这个只读同步请求。令牌只在
/// 当前请求内存中流转，不写入 Core 会话、日志或文件。
async fn get_sso_token(runtime: &mut ClientRuntime) -> Result<Option<String>> {
    // Cookie 的路径按实际场馆服务根目录匹配；不能使用 WebVPN 前端别名路径，
    // 否则上游返回 `Path=/venue-zhjs-server/` 时会被错误过滤。
    if let Some(token) = runtime.cookie_value(SSO_COOKIE, LOGIN_URL)? {
        return Ok((!token.is_empty()).then_some(token));
    }
    if runtime.mode() != crate::domain::ConnectionMode::WebVpn {
        return Ok(None);
    }
    let timestamp = timestamp_millis()?;
    let mut url = url::Url::parse(WEBVPN_COOKIE_URL)
        .map_err(|_| authentication_error("WebVPN Cookie 同步地址无效"))?;
    url.query_pairs_mut()
        .append_pair("method", "get")
        .append_pair("host", "cgyy.buaa.edu.cn")
        .append_pair("scheme", "https")
        .append_pair("path", WEBVPN_COOKIE_PATH)
        .append_pair("vpn_timestamp", &timestamp.to_string());
    let mut request = HttpRequest::get(url.to_string());
    request.headers.insert(
        "Referer".into(),
        runtime.url("https://cgyy.buaa.edu.cn/venue-zhjs")?,
    );
    debug!(
        target: "ubaa::cgyy",
        operation = "business_login.webvpn_cookie",
        route = ?runtime.mode(),
        host = "cgyy.buaa.edu.cn",
        path = WEBVPN_COOKIE_PATH,
        "读取 WebVPN Cgyy Cookie 快照"
    );
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(authentication_error("WebVPN Cookie 同步失败"));
    }
    let body = String::from_utf8_lossy(&response.body);
    Ok(parse_cookie_snapshot(&body, SSO_COOKIE))
}

fn parse_cookie_snapshot(body: &str, name: &str) -> Option<String> {
    body.split(';').find_map(|part| {
        let (key, value) = part.trim().split_once('=')?;
        (key.trim() == name)
            .then(|| value.trim().to_owned())
            .filter(|value| !value.is_empty())
    })
}

fn authentication_error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        message,
    )
}
