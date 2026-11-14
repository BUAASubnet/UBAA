//! 通过 SSO 一次性票据核验身份，不访问业务落地页。

use serde_json::Value;
use url::Url;

use crate::domain::{AuthStatus, UserProfile};
use crate::error::{ErrorCode, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

const SERVICE: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp";
const VALIDATE: &str = "https://sso.buaa.edu.cn/serviceValidate";

pub(crate) async fn validate_status(
    runtime: &mut ClientRuntime,
    clear_workflow: &mut (dyn FnMut() + Send),
) -> Result<AuthStatus> {
    let result = identity(runtime).await;
    let user = match result {
        Err(error) if error.code == ErrorCode::AuthenticationRequired => {
            runtime.clear_with(clear_workflow)?;
            return Err(error);
        }
        result => result?,
    };
    if runtime.account_name().is_some_and(|expected| {
        user.school_id.as_deref() != Some(expected) && user.username.as_deref() != Some(expected)
    }) {
        runtime.clear_with(clear_workflow)?;
        return Err(UbaaError::authentication_required(
            "SSO 身份已变化，请重新登录",
        ));
    }
    let (authenticated_at, last_activity) = runtime.refresh_authentication(clear_workflow)?;
    runtime.remember_account_name(user.school_id.as_deref());
    Ok(AuthStatus {
        user,
        authenticated_at,
        last_activity,
    })
}

async fn identity(runtime: &mut ClientRuntime) -> Result<UserProfile> {
    let login = runtime.url(crate::features::schedule::AAS_LOGIN_URL)?;
    let response = runtime.request(HttpRequest::get(&login)).await?;
    if response.final_url != login {
        return Err(super::upstream_changed("SSO 取票响应地址发生变化")
            .with_auth_reason(crate::error::AuthReason::RedirectInvalid));
    }
    if response.status == 401
        || (response.status == 200
            && crate::upstream::extract_execution(&super::body_text(&response)).is_some())
    {
        return Err(UbaaError::authentication_required("SSO 会话需要恢复"));
    }
    if response.status != 302 {
        return Err(super::status_error(response.status, "SSO 未返回有效票据"));
    }
    let ticket = callback_ticket(&response)?;
    let mut target = Url::parse(VALIDATE).expect("固定 SSO 验票地址");
    target
        .query_pairs_mut()
        .append_pair("service", SERVICE)
        .append_pair("ticket", &ticket)
        .append_pair("format", "JSON");
    let target = runtime.url(target.as_str())?;
    let response = runtime.request(HttpRequest::get(&target)).await?;
    if response.status == 401 {
        return Err(UbaaError::authentication_required("SSO 会话需要恢复"));
    }
    if response.final_url != target || response.status != 200 {
        return Err(super::status_error(response.status, "SSO 验票未完成"));
    }
    parse_identity(&response.body)
}

fn callback_ticket(response: &HttpResponse) -> Result<String> {
    let raw = response
        .header_first("location")
        .ok_or_else(invalid_response)?;
    let direct = crate::connection::from_webvpn_url(raw)?;
    let target = Url::parse(&direct).map_err(|_| invalid_response())?;
    let mut ticket = None;
    let mut query = Vec::new();
    for (key, value) in target.query_pairs() {
        if key == "ticket" {
            if ticket.is_some() || value.trim().is_empty() {
                return Err(invalid_response());
            }
            ticket = Some(value.into_owned());
        } else {
            query.push((key.into_owned(), value.into_owned()));
        }
    }
    let expected = Url::parse(SERVICE).expect("固定 service");
    if target.origin() != expected.origin()
        || target.path() != expected.path()
        || !target.username().is_empty()
        || target.password().is_some()
        || target.fragment().is_some()
        || query
            != expected
                .query_pairs()
                .map(|(key, value)| (key.into_owned(), value.into_owned()))
                .collect::<Vec<_>>()
    {
        return Err(invalid_response());
    }
    ticket.ok_or_else(invalid_response)
}

fn parse_identity(body: &[u8]) -> Result<UserProfile> {
    let payload: Value = serde_json::from_slice(body)
        .map_err(|_| UbaaError::parse_error("SSO 验票响应不是有效 JSON"))?;
    if payload
        .pointer("/serviceResponse/authenticationFailure/code")
        .and_then(Value::as_str)
        == Some("INVALID_TICKET")
    {
        return Err(UbaaError::authentication_required("SSO 票据已经失效"));
    }
    let username = identifier(&payload["user"])?;
    let attributes = &payload["attributes"];
    let ids = attributes["employeeNumber"]
        .as_array()
        .ok_or_else(invalid_response)?;
    if ids.len() != 1 {
        return Err(invalid_response());
    }
    let school_id = identifier(&ids[0])?;
    let name = attributes["name"]
        .as_array()
        .filter(|items| items.len() == 1)
        .and_then(|items| items[0].as_str())
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_owned);
    Ok(UserProfile {
        school_id: Some(school_id.to_owned()),
        username: Some(username.to_owned()),
        name,
        ..UserProfile::default()
    })
}

fn identifier(value: &Value) -> Result<&str> {
    value
        .as_str()
        .map(str::trim)
        .filter(|value| {
            !value.is_empty() && value.len() <= 128 && !value.chars().any(char::is_control)
        })
        .ok_or_else(invalid_response)
}

fn invalid_response() -> UbaaError {
    super::upstream_changed("SSO 未返回已证明的身份信息")
        .with_auth_reason(crate::error::AuthReason::IdentityResponseInvalid)
}
