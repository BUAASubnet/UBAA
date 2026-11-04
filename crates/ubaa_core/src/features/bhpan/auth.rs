use super::{
    parse,
    wire::{self, ORIGIN},
};
use crate::domain::{ConnectionMode, SecretValue};
use crate::error::{Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;
use url::Url;

const LOGIN: &str =
    "https://bhpan.buaa.edu.cn/anyshare/oauth2/login?redirect=%2Fanyshare%2Fzh-cn%2Fportal";
const CALLBACK: &str = "/anyshare/oauth2/login/callback";
const SSO: &str =
    "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbhpan.buaa.edu.cn%2Foauth2%2Fsignin";

pub(crate) async fn login(runtime: &mut ClientRuntime) -> Result<SecretValue> {
    if runtime.mode() != ConnectionMode::Direct {
        return Err(unavailable());
    }
    let result = login_inner(runtime).await;
    runtime.set_scoped_cookie("login_challenge=; Path=/; Secure; Max-Age=0", ORIGIN)?;
    result
}
async fn login_inner(runtime: &mut ClientRuntime) -> Result<SecretValue> {
    let landing = navigate(runtime, LOGIN, true).await?;
    if landing.path() == "/oauth2/signin" {
        let raw = landing.query().ok_or_else(parse::invalid)?;
        let mut values = raw
            .split('&')
            .filter_map(|p| p.strip_prefix("login_challenge="));
        let value = values
            .next()
            .filter(|v| !v.is_empty())
            .ok_or_else(parse::invalid)?;
        if values.next().is_some() || value.contains([';', '\r', '\n']) {
            return Err(parse::invalid());
        }
        runtime.set_scoped_cookie(&format!("login_challenge={value}; Path=/; Secure"), ORIGIN)?;
        let callback = navigate(runtime, SSO, false).await?;
        if callback.path() != CALLBACK {
            return Err(parse::invalid());
        }
    } else if landing.path() == CALLBACK {
        let refresh = format!("{ORIGIN}/anyshare/oauth2/login/refreshToken");
        let final_url = navigate(runtime, &refresh, false).await?;
        if final_url.path() != "/anyshare/oauth2/login/refreshToken" && final_url.path() != CALLBACK
        {
            return Err(parse::invalid());
        }
    } else {
        return Err(parse::invalid());
    }
    let token = runtime
        .cookie_value("client.oauth2_token", &format!("{ORIGIN}/"))?
        .filter(|t| !t.is_empty())
        .ok_or_else(|| {
            UbaaError::new(
                crate::error::ErrorCode::PermissionDenied,
                crate::error::ErrorKind::Authentication,
                false,
                "云盘回调未取得有效授权，请恢复学校登录后重新打开",
            )
        })?;
    runtime.refresh_authentication(&mut || {})?;
    Ok(SecretValue::new(token))
}

async fn navigate(runtime: &mut ClientRuntime, start: &str, stop_signin: bool) -> Result<Url> {
    let mut current = checked(start)?;
    for _ in 0..20 {
        let response = runtime
            .request_with_pre_send_check(
                HttpRequest::get(current.as_str()),
                ClientRuntime::ensure_session_revision,
            )
            .await?;
        if response.final_url != current.as_str() {
            return Err(parse::invalid());
        }
        if (200..=299).contains(&response.status) {
            if current.host_str() == Some("sso.buaa.edu.cn") {
                return Err(UbaaError::new(
                    crate::error::ErrorCode::PermissionDenied,
                    crate::error::ErrorKind::Authentication,
                    false,
                    "学校 SSO 会话需要恢复，请重新登录后打开云盘",
                ));
            }
            return Ok(current);
        }
        if !matches!(response.status, 301 | 302 | 303 | 307 | 308) {
            wire::status(&response, false)?;
            return Err(parse::invalid());
        }
        // callback 本身需要执行，之后的 portal 跳转不属于认证请求。
        if current.path() == CALLBACK || (stop_signin && current.path() == "/oauth2/signin") {
            return Ok(current);
        }
        let next = current
            .join(
                response
                    .header_first("location")
                    .ok_or_else(parse::invalid)?,
            )
            .map_err(|_| parse::invalid())?;
        current = checked(next.as_str())?;
    }
    Err(UbaaError::upstream_changed("云盘认证跳转次数超过上限"))
}
pub(crate) fn checked(raw: &str) -> Result<Url> {
    let u = Url::parse(raw).map_err(|_| parse::invalid())?;
    if u.scheme() != "https"
        || u.port_or_known_default() != Some(443)
        || !u.username().is_empty()
        || u.password().is_some()
        || u.fragment().is_some()
    {
        return Err(parse::invalid());
    }
    let valid = match u.host_str() {
        Some("bhpan.buaa.edu.cn") => matches!(
            u.path(),
            "/anyshare/oauth2/login"
                | "/oauth2/signin"
                | "/oauth2/auth"
                | "/oauth2/consent"
                | CALLBACK
                | "/anyshare/oauth2/login/refreshToken"
        ),
        Some("sso.buaa.edu.cn") if u.path() == "/login" => {
            let q: Vec<_> = u.query_pairs().collect();
            q.len() == 1
                && q[0].0 == "service"
                && q[0].1 == "https://bhpan.buaa.edu.cn/oauth2/signin"
        }
        _ => false,
    };
    if valid { Ok(u) } else { Err(parse::invalid()) }
}
pub(crate) fn unavailable() -> UbaaError {
    UbaaError::new(
        crate::error::ErrorCode::PermissionDenied,
        crate::error::ErrorKind::Input,
        false,
        "北航云盘 WebVPN 完整链路尚缺协议证据，请选择 Direct 路线",
    )
}
