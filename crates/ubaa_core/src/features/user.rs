//! SSO 会话状态与按需激活的用户中心资料读取。

use crate::connection::from_webvpn_url;
use crate::domain::{AuthStatus, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use crate::upstream::{UC_USERINFO_URL, parse_user_info};

pub(crate) async fn auth_status(
    runtime: &mut ClientRuntime,
    clear_workflow: &mut (dyn FnMut() + Send),
) -> Result<AuthStatus> {
    if !runtime.has_local_session() {
        return Err(authentication_required());
    }
    validate_status(runtime, clear_workflow).await
}

pub(crate) async fn get_user_info(
    runtime: &mut ClientRuntime,
    clear_workflow: &mut (dyn FnMut() + Send),
) -> Result<UserProfile> {
    if !runtime.has_local_session() {
        return Err(authentication_required());
    }
    let mut response = runtime
        .request(HttpRequest::get(runtime.url(UC_USERINFO_URL)?))
        .await?;
    if looks_unauthenticated(response.status, &response.final_url, &body_text(&response))
        || serde_json::from_slice::<serde_json::Value>(&response.body)
            .ok()
            .is_some_and(|body| body["code"].as_i64().is_some_and(|code| code != 0))
    {
        crate::auth::activate_user_center(runtime).await?;
        response = runtime
            .request(HttpRequest::get(runtime.url(UC_USERINFO_URL)?))
            .await?;
    }
    let body = body_text(&response);
    if looks_unauthenticated(response.status, &response.final_url, &body) {
        crate::auth::sso_identity::validate_status(runtime, clear_workflow).await?;
    }
    if response.status >= 500 {
        return Err(status_error(response.status, "用户中心不可用"));
    }
    if response.status != 200 {
        return Err(status_error(response.status, "用户中心资料请求失败"));
    }
    parse_user_info(&body)
}

pub(crate) async fn validate_status(
    runtime: &mut ClientRuntime,
    clear_workflow: &mut (dyn FnMut() + Send),
) -> Result<AuthStatus> {
    crate::auth::sso_identity::validate_status(runtime, clear_workflow).await
}

pub(crate) fn looks_unauthenticated(status: u16, final_url: &str, body: &str) -> bool {
    if status == 401 {
        return true;
    }
    let direct_url = from_webvpn_url(final_url).unwrap_or_else(|_| final_url.into());
    if url::Url::parse(&direct_url).is_ok_and(|url| {
        crate::connection::is_valid_auth_target(&url, &["sso.buaa.edu.cn"], false, &[])
            && url.path() == "/login"
    }) {
        return true;
    }
    let trimmed = body.trim_start();
    starts_with_ignore_ascii_case(trimmed, "<!DOCTYPE html")
        || starts_with_ignore_ascii_case(trimmed, "<html")
        || body.contains("input name=\"execution\"")
        || body.contains("input name='execution'")
        || body.contains("统一身份认证")
}

fn starts_with_ignore_ascii_case(value: &str, prefix: &str) -> bool {
    value
        .get(..prefix.len())
        .is_some_and(|candidate| candidate.eq_ignore_ascii_case(prefix))
}

fn body_text(response: &HttpResponse) -> String {
    String::from_utf8_lossy(&response.body).into_owned()
}

fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "需要认证",
    )
}

fn status_error(status: u16, message: impl Into<String>) -> UbaaError {
    if status >= 500 {
        UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            message,
        )
    } else {
        UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            message,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::looks_unauthenticated;

    #[test]
    fn 用户认证失效只识别精确的_sso_login_地址() {
        let body = r#"{"code":0}"#;
        assert!(looks_unauthenticated(
            200,
            "https://sso.buaa.edu.cn/login?execution=fixture",
            body
        ));
        for url in [
            "https://sso.buaa.edu.cn/login-extra",
            "https://sso.buaa.edu.cn/not-login",
            "https://sso.buaa.edu.cn.evil.example/login",
            "https://user@sso.buaa.edu.cn/login",
            "https://sso.buaa.edu.cn:8443/login",
        ] {
            assert!(
                !looks_unauthenticated(200, url, body),
                "不应把非认证落点判为认证失效: {url}"
            );
        }
    }
}
