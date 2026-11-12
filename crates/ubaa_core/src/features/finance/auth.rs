//! 财务门户与查询系统的路线内认证。
use super::parser::invalid;
use crate::domain::{ConnectionMode, SecretValue};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::internal::route_state::FinanceCredential;
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use url::Url;

pub(super) fn check(runtime: &ClientRuntime, generation: u64) -> Result<()> {
    crate::features::require_session(runtime)?;
    if runtime.feature_state().finance.generation() != generation {
        return Err(required());
    }
    Ok(())
}

pub(super) fn check_response(
    runtime: &ClientRuntime,
    response: &HttpResponse,
    expected: &str,
    generation: u64,
) -> Result<()> {
    check(runtime, generation)?;
    if response.final_url != expected {
        return Err(invalid());
    }
    // 网关缺少会话时会用自己的登录页拦截业务请求；不向登录页转发原请求。
    if runtime.mode() == ConnectionMode::WebVpn
        && response.status == 302
        && response.header_first("location").is_some_and(|location| {
            Url::parse(expected)
                .and_then(|base| base.join(location))
                .is_ok_and(|url| {
                    crate::connection::is_valid_webvpn_gateway(&url)
                        && url.path() == "/login"
                        && url.query().is_none()
                        && url.fragment().is_none()
                })
        })
    {
        return Err(required());
    }
    Ok(())
}

fn required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "财务会话需要恢复，请重新登录后重试",
    )
}
pub(super) fn target(raw: &str, mode: ConnectionMode) -> Result<Url> {
    let parsed = Url::parse(raw).map_err(|_| invalid())?;
    if parsed.host_str() == Some("d.buaa.edu.cn") && mode != ConnectionMode::WebVpn {
        return Err(invalid());
    }
    let direct = crate::connection::from_webvpn_url(raw)?;
    let mut url = Url::parse(&direct).map_err(|_| invalid())?;
    if !crate::connection::is_valid_auth_target(
        &url,
        &[
            "sso.buaa.edu.cn",
            "icw.buaa.edu.cn",
            "chaxun.icw.buaa.edu.cn",
        ],
        false,
        &[],
    ) || url.fragment().is_some()
    {
        return Err(invalid());
    }
    let allowed = match url.host_str() {
        Some("sso.buaa.edu.cn") => url.path() == "/login",
        Some("icw.buaa.edu.cn") => matches!(
            url.path(),
            "/checkbuaa.aspx" | "/Newindex.aspx" | "/jump.aspx"
        ),
        Some("chaxun.icw.buaa.edu.cn") => url.path() == "/gxzhcxzhb/login",
        _ => false,
    };
    if !allowed {
        return Err(invalid());
    }
    // Direct 已观察到同路径 HTTP→HTTPS 跳转；CAS service 字符串保持原值。
    url.set_scheme("https").map_err(|()| invalid())?;
    url.set_port(None).map_err(|()| invalid())?;
    Ok(url)
}
async fn get(runtime: &mut ClientRuntime, url: &Url, generation: u64) -> Result<HttpResponse> {
    let expected = runtime.url(url.as_str())?;
    let response = runtime
        .request_with_pre_send_check(HttpRequest::get(&expected), |r| check(r, generation))
        .await?;
    check_response(runtime, &response, &expected, generation)?;
    Ok(response)
}
pub(super) async fn ensure(runtime: &mut ClientRuntime) -> Result<FinanceCredential> {
    crate::features::require_session(runtime)?;
    let state = runtime.feature_state();
    let _guard = state.finance.login_guard().await;
    if let Some(value) = state.finance.credential() {
        return Ok(value);
    }
    let generation = state.finance.generation();
    portal(runtime, generation).await?;
    let jump = target(
        "https://icw.buaa.edu.cn/jump.aspx?sysid=wscx",
        runtime.mode(),
    )?;
    let response = get(runtime, &jump, generation).await?;
    if response.status != 302 {
        return Err(invalid());
    }
    let location = target(
        Url::parse(&response.final_url)
            .map_err(|_| invalid())?
            .join(response.header_first("location").ok_or_else(invalid)?)
            .map_err(|_| invalid())?
            .as_str(),
        runtime.mode(),
    )?;
    if location.host_str() != Some("chaxun.icw.buaa.edu.cn")
        || location.path() != "/gxzhcxzhb/login"
    {
        return Err(invalid());
    }
    let field = |name: &str| -> Result<String> {
        let values: Vec<_> = location.query_pairs().filter(|(k, _)| k == name).collect();
        if values.len() != 1 || values[0].1.is_empty() {
            return Err(invalid());
        }
        Ok(values[0].1.to_string())
    };
    let user = field("Userid")?;
    let body = url::form_urlencoded::Serializer::new(String::new())
        .append_pair("username", &user)
        .append_pair("password", &field("Cypt")?)
        .append_pair("yzm", "yzm")
        .append_pair("stamp", &field("Stamp")?)
        .finish();
    let expected = runtime.url("https://chaxun.icw.buaa.edu.cn/api-zhcx/login")?;
    let request = HttpRequest::post(&expected, body.into_bytes())
        .with_header("Content-Type", "application/x-www-form-urlencoded")
        .with_header("Referer", runtime.url(location.as_str())?);
    let response = runtime
        .request_with_pre_send_check(request, |r| check(r, generation))
        .await?;
    check_response(runtime, &response, &expected, generation)?;
    if response.status != 200 {
        return Err(invalid());
    }
    let value = super::parser::envelope(&response.body)?;
    let token = value
        .get("token")
        .and_then(serde_json::Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(invalid)?;
    let credential = FinanceCredential {
        user,
        token: SecretValue::new(token),
    };
    if !state
        .finance
        .store_credential(generation, credential.clone())
    {
        return Err(required());
    }
    Ok(credential)
}

async fn portal(runtime: &mut ClientRuntime, generation: u64) -> Result<()> {
    let mut next = target(
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Ficw.buaa.edu.cn%2Fcheckbuaa.aspx",
        runtime.mode(),
    )?;
    let mut ready = false;
    for _ in 0..12 {
        let response = get(runtime, &next, generation).await?;
        if response.status == 200 {
            if next.host_str() == Some("sso.buaa.edu.cn") {
                return Err(required());
            }
            ready = next.host_str() == Some("icw.buaa.edu.cn") && next.path() == "/Newindex.aspx";
            break;
        }
        if !matches!(response.status, 301 | 302 | 303 | 307 | 308) {
            return Err(invalid());
        }
        let location = response.header_first("location").ok_or_else(invalid)?;
        next = target(
            Url::parse(&response.final_url)
                .map_err(|_| invalid())?
                .join(location)
                .map_err(|_| invalid())?
                .as_str(),
            runtime.mode(),
        )?;
    }
    if !ready {
        return Err(invalid());
    }
    Ok(())
}
