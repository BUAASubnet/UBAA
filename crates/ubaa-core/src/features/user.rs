//! 状态和资料操作共用的用户中心响应分类。

use crate::connection::from_webvpn_url;
use crate::domain::{AuthStatus, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use crate::upstream::{UC_STATUS_URL, UC_USERINFO_URL, parse_user_info};

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
    let response = runtime
        .request(HttpRequest::get(runtime.url(UC_USERINFO_URL)?))
        .await?;
    let body = body_text(&response);
    if looks_unauthenticated(response.status, &response.final_url, &body) {
        clear_local(runtime, clear_workflow)?;
        return Err(authentication_required());
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
    let response = runtime
        .request(HttpRequest::get(runtime.url(UC_STATUS_URL)?))
        .await?;
    let body = body_text(&response);
    if response.status >= 500 {
        return Err(status_error(response.status, "认证服务不可用"));
    }
    if looks_unauthenticated(response.status, &response.final_url, &body)
        || !body.trim_start().starts_with('{')
    {
        clear_local(runtime, clear_workflow)?;
        return Err(authentication_required());
    }
    if response.status != 200 {
        clear_local(runtime, clear_workflow)?;
        return Err(authentication_required());
    }
    let user = match parse_user_info(&body) {
        Ok(user) => user,
        Err(error) if error.code == ErrorCode::ParseError => return Err(error),
        Err(_) => {
            clear_local(runtime, clear_workflow)?;
            return Err(authentication_required());
        }
    };
    let (authenticated_at, last_activity) = runtime.refresh_authentication(clear_workflow)?;
    Ok(AuthStatus {
        user,
        authenticated_at,
        last_activity,
    })
}

pub(crate) fn looks_unauthenticated(status: u16, final_url: &str, body: &str) -> bool {
    if status == 401 {
        return true;
    }
    let direct_url = from_webvpn_url(final_url).unwrap_or_else(|_| final_url.into());
    if direct_url.contains("sso.buaa.edu.cn") {
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

fn clear_local(
    runtime: &mut ClientRuntime,
    clear_workflow: &mut (dyn FnMut() + Send),
) -> Result<()> {
    runtime.clear_with(clear_workflow)
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
