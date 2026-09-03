//! 阳光打卡 OAuth 跳转、业务登录与路线内凭据。

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::YgdkCredential;
use super::parser::{error, integer, parse_envelope, string};

const OAUTH_URL: &str = "https://app.buaa.edu.cn/uc/api/oauth/index?redirect=https%3A%2F%2Fygdk.buaa.edu.cn%2F%23%2Fhome&appid=200230221144501510&state=STATE&qrcode=1";
const LOGIN_URL: &str = "https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin";
const REDIRECT_LIMIT: usize = 10;

pub(super) async fn ensure_login(runtime: &mut ClientRuntime) -> Result<YgdkCredential> {
    super::super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(value) = state.ygdk.credential() {
        return Ok(value);
    }
    let _guard = state.ygdk.login_guard().await;
    if let Some(value) = state.ygdk.credential() {
        return Ok(value);
    }
    let generation = state.ygdk.generation();
    let code = oauth_code(runtime).await?;
    let mut url =
        url::Url::parse(&runtime.url(LOGIN_URL)?).map_err(|_| error("阳光打卡登录地址无效"))?;
    url.query_pairs_mut().append_pair("code", &code);
    let response = runtime.request(HttpRequest::get(url.to_string())).await?;
    if response.status != 200 {
        return Err(error("阳光打卡登录失败"));
    }
    let value = parse_envelope(&super::super::body(&response))?;
    let data = value
        .get("data")
        .unwrap_or(&value)
        .as_object()
        .ok_or_else(|| error("阳光打卡登录响应无效"))?;
    let uid = integer(data, "uid").ok_or_else(|| error("阳光打卡返回 uid 缺失"))?;
    let token = string(data, "token").ok_or_else(|| error("阳光打卡返回 token 缺失"))?;
    let credential = YgdkCredential {
        uid,
        token: percent_decode(&token),
    };
    if !state.ygdk.store_credential(generation, credential.clone()) {
        return Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            true,
            "阳光打卡业务会话在登录期间已失效",
        ));
    }
    Ok(credential)
}

async fn oauth_code(runtime: &mut ClientRuntime) -> Result<String> {
    let mut current = OAUTH_URL.to_owned();
    for _ in 0..REDIRECT_LIMIT {
        let response = runtime
            .request(HttpRequest::get(runtime.url(&current)?))
            .await?;
        if let Some(code) = code_from_url(&response.final_url) {
            return Ok(code);
        }
        let location = response
            .headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("location"))
            .and_then(|(_, v)| v.first())
            .ok_or_else(|| error("阳光打卡登录跳转缺少目标地址"))?;
        let base =
            url::Url::parse(&response.final_url).map_err(|_| error("阳光打卡登录跳转地址无效"))?;
        current = base
            .join(location)
            .map_err(|_| error("阳光打卡登录跳转地址无效"))?
            .to_string();
        if let Some(code) = code_from_url(&current) {
            return Ok(code);
        }
    }
    Err(error("阳光打卡登录跳转次数超限"))
}

pub(super) fn code_from_url(raw: &str) -> Option<String> {
    let url = url::Url::parse(raw).ok()?;
    url.query_pairs()
        .find(|(k, _)| k == "code")
        .map(|(_, v)| v.into_owned())
        .or_else(|| {
            let query = url.fragment()?.split_once('?')?.1;
            url::form_urlencoded::parse(query.as_bytes())
                .find(|(key, _)| key == "code")
                .map(|(_, value)| value.into_owned())
        })
}

pub(super) fn percent_decode(value: &str) -> String {
    let encoded = format!("value={value}");
    url::form_urlencoded::parse(encoded.as_bytes())
        .next()
        .map_or_else(|| value.to_owned(), |(_, v)| v.into_owned())
}
