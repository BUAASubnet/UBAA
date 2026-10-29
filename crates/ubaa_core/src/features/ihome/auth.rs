//! 严格限制主机和路径的业务 CAS 认证。
use super::parser::invalid;
use crate::connection::from_webvpn_url;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

pub(super) fn check_generation(runtime: &ClientRuntime, generation: u64) -> Result<()> {
    crate::features::require_session(runtime)?;
    if runtime.feature_state().ihome.snapshot().0 != generation {
        return Err(auth_error());
    }
    Ok(())
}
fn auth_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamUnavailable,
        ErrorKind::Upstream,
        false,
        "无法复用 iHome 登录，请重新登录后重试",
    )
}
pub(super) fn callback(raw: &str) -> Result<(url::Url, Option<String>)> {
    let mut url = url::Url::parse(&from_webvpn_url(raw)?).map_err(|_| invalid())?;
    if !matches!(url.host_str(), Some("sso.buaa.edu.cn" | "i.buaa.edu.cn"))
        || !matches!(url.scheme(), "http" | "https")
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some_and(|p| p != 80 && p != 443)
    {
        return Err(auth_error());
    }
    let token = if url.host_str() == Some("i.buaa.edu.cn") && url.path() == "/web/" {
        let fragment = url.fragment().unwrap_or_default();
        let params: Vec<_> =
            url::form_urlencoded::parse(fragment.split_once('?').map_or("", |(_, q)| q).as_bytes())
                .collect();
        if fragment.starts_with("/login?") && params.iter().any(|(k, v)| k == "type" && v == "0") {
            params
                .iter()
                .find(|(k, v)| k == "token" && !v.trim().is_empty())
                .map(|(_, v)| v.to_string())
        } else {
            None
        }
    } else {
        None
    };
    url.set_scheme("https").map_err(|()| invalid())?;
    url.set_port(None).map_err(|()| invalid())?;
    url.set_fragment(None);
    Ok((url, token))
}
pub(super) async fn ensure_token(runtime: &mut ClientRuntime) -> Result<String> {
    crate::features::require_session(runtime)?;
    let state = runtime.feature_state();
    let _guard = state.ihome.login_guard().await;
    let (generation, cached) = state.ihome.snapshot();
    if let Some(token) = cached {
        return Ok(token);
    }
    let mut next =
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fi.buaa.edu.cn%2Fapi%2FauthLogin"
            .to_owned();
    for _ in 0..12 {
        check_generation(runtime, generation)?;
        let (url, token) = callback(&next)?;
        if let Some(token) = token {
            if state.ihome.store(generation, token.clone()) {
                return Ok(token);
            }
            return Err(auth_error());
        }
        let request_url = runtime.url(url.as_str())?;
        let response = runtime
            .request_with_pre_send_check(HttpRequest::get(&request_url), |r| {
                check_generation(r, generation)
            })
            .await?;
        check_generation(runtime, generation)?;
        if response.final_url != request_url || !(300..400).contains(&response.status) {
            return Err(auth_error());
        }
        let location = response.header_first("location").ok_or_else(auth_error)?;
        next = url::Url::parse(&response.final_url)
            .map_err(|_| invalid())?
            .join(location)
            .map_err(|_| invalid())?
            .to_string();
    }
    Err(auth_error())
}
