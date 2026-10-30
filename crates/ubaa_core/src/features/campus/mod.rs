//! 用户提供的 HAR 所证明的门户与网费只读协议。

mod network;
mod parser;
mod portal;
#[cfg(test)]
mod tests;

use crate::connection::{business_redirect_target, from_webvpn_url};
use crate::domain::ConnectionMode;
use crate::error::{ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use url::Url;

pub(crate) use network::get_usage;
pub(crate) use portal::{get_metrics, get_profile};
pub(super) const PORTAL_HOME: &str = "https://it.buaa.edu.cn/home/";
pub(super) const NETWORK_HOME: &str = "https://zfw.buaa.edu.cn/home";
pub(super) const NETWORK_LOGIN: &str = "https://zfw.buaa.edu.cn/sso/cas/index";

#[derive(Clone, Copy)]
pub(super) enum Service {
    Portal,
    Network,
}

fn decode(raw: &str, mode: ConnectionMode) -> Result<Url> {
    let outer = Url::parse(raw).map_err(|_| parser::invalid())?;
    if outer.host_str() == Some("d.buaa.edu.cn") && mode != ConnectionMode::WebVpn {
        return Err(parser::invalid());
    }
    let url = Url::parse(&from_webvpn_url(raw)?).map_err(|_| parser::invalid())?;
    if url.scheme() != "https"
        || url.port_or_known_default() != Some(443)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(parser::invalid());
    }
    Ok(url)
}

fn pairs(url: &Url) -> Result<std::collections::BTreeMap<String, String>> {
    let mut result = std::collections::BTreeMap::new();
    for (key, value) in url.query_pairs() {
        if result
            .insert(key.into_owned(), value.into_owned())
            .is_some()
        {
            return Err(parser::invalid());
        }
    }
    Ok(result)
}

fn callback(service: Service, url: &Url, mode: ConnectionMode, allow_ticket: bool) -> Result<()> {
    let query = pairs(url)?;
    let allowed = match service {
        Service::Portal => {
            url.host_str() == Some("it.buaa.edu.cn")
                && url.path() == "/manage/common/cas_login/30001"
                && query
                    .get("redirect")
                    .is_some_and(|v| decode(v, mode).is_ok_and(|u| u.as_str() == PORTAL_HOME))
                && query.iter().all(|(key, value)| match key.as_str() {
                    "redirect" => true,
                    "to_bind" => value == "0",
                    "ticket" => allow_ticket && !value.is_empty(),
                    _ => false,
                })
        }
        Service::Network => {
            url.host_str() == Some("zfw.buaa.edu.cn")
                && url.path() == "/sso/cas/index"
                && query
                    .iter()
                    .all(|(key, value)| key == "ticket" && allow_ticket && !value.is_empty())
        }
    };
    if allowed {
        Ok(())
    } else {
        Err(parser::invalid())
    }
}

pub(super) fn login_target(service: Service, raw: &str, mode: ConnectionMode) -> Result<Url> {
    let url = decode(raw, mode)?;
    let query = pairs(&url)?;
    if url.host_str() == Some("sso.buaa.edu.cn") && url.path() == "/login" {
        if query.len() != 1 {
            return Err(parser::invalid());
        }
        let nested = decode(query.get("service").ok_or_else(parser::invalid)?, mode)?;
        callback(service, &nested, mode, false)?;
        return Ok(url);
    }
    let landing = match service {
        Service::Portal => PORTAL_HOME,
        Service::Network => "https://zfw.buaa.edu.cn/pay/card",
    };
    if url.as_str() == landing {
        return Ok(url);
    }
    if matches!(service, Service::Portal)
        && url.host_str() == Some("it.buaa.edu.cn")
        && url.path() == "/manage/common/login/index"
        && query.len() == 1
        && query
            .get("redirect")
            .is_some_and(|v| decode(v, mode).is_ok_and(|u| u.as_str() == PORTAL_HOME))
    {
        return Ok(url);
    }
    callback(service, &url, mode, true)?;
    Ok(url)
}

pub(super) fn now(runtime: &ClientRuntime) -> Result<i64> {
    runtime
        .now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_secs()).ok())
        .ok_or_else(|| UbaaError::parse_error("读取时间无效"))
}

pub(super) async fn get(
    runtime: &mut ClientRuntime,
    direct: &str,
    api: bool,
    referer: &str,
) -> Result<HttpResponse> {
    crate::features::require_session(runtime)?;
    runtime.ensure_session_revision()?;
    let expected = runtime.url(direct)?;
    let mut request = HttpRequest::get(&expected)
        .with_header(
            "Accept",
            if api {
                "application/json, text/plain, */*"
            } else {
                "text/html,*/*"
            },
        )
        .with_header("Referer", runtime.url(referer)?);
    if api {
        request = request.with_header("X-Requested-With", "XMLHttpRequest");
    }
    let response = runtime
        .request_with_pre_send_check(request, ClientRuntime::ensure_session_revision)
        .await?;
    runtime.ensure_session_revision()?;
    if response.final_url != expected || response.body.len() > 2 * 1024 * 1024 {
        return Err(parser::invalid());
    }
    Ok(response)
}

pub(super) fn status(response: &HttpResponse) -> Result<()> {
    match response.status {
        200 => Ok(()),
        401 | 403 => Err(parser::business_login_required()),
        500..=599 => Err(UbaaError::upstream_unavailable("校园账户服务暂时不可用")),
        _ => Err(parser::invalid()),
    }
}

pub(super) async fn json(runtime: &mut ClientRuntime, direct: &str) -> Result<serde_json::Value> {
    let response = get(runtime, direct, true, PORTAL_HOME).await?;
    status(&response)?;
    serde_json::from_slice(&response.body).map_err(|_| parser::invalid())
}

pub(super) async fn activate(runtime: &mut ClientRuntime, service: Service) -> Result<()> {
    let mut current = match service {
        Service::Portal => format!(
            "https://it.buaa.edu.cn/manage/common/login/index?{}",
            url::form_urlencoded::Serializer::new(String::new())
                .append_pair("redirect", PORTAL_HOME)
                .finish()
        ),
        Service::Network => NETWORK_LOGIN.into(),
    };
    for _ in 0..10 {
        let target = login_target(service, &current, runtime.mode())?;
        let response = get(
            runtime,
            target.as_str(),
            false,
            match service {
                Service::Portal => PORTAL_HOME,
                Service::Network => NETWORK_HOME,
            },
        )
        .await?;
        if matches!(response.status, 301 | 302 | 303 | 307 | 308) {
            let location = response
                .header_first("location")
                .ok_or_else(parser::invalid)?;
            let raw_target = Url::parse(&response.final_url)
                .map_err(|_| parser::invalid())?
                .join(location)
                .map_err(|_| parser::invalid())?;
            if raw_target.host_str() == Some("d.buaa.edu.cn")
                && runtime.mode() != ConnectionMode::WebVpn
            {
                return Err(parser::invalid());
            }
            let next = business_redirect_target(&response.final_url, location)?;
            current = login_target(service, next.as_str(), runtime.mode())?.to_string();
            continue;
        }
        status(&response)?;
        let landing = match service {
            Service::Portal => PORTAL_HOME,
            Service::Network => "https://zfw.buaa.edu.cn/pay/card",
        };
        if target.as_str() == landing {
            return Ok(());
        }
        if target.host_str() == Some("sso.buaa.edu.cn") {
            return Err(parser::business_login_required());
        }
        return Err(parser::invalid());
    }
    Err(parser::invalid())
}

pub(super) fn record<T>(
    result: Result<T>,
    fetched_at: i64,
) -> Result<crate::domain::CampusMetric<T>> {
    use crate::domain::CampusMetric;
    match result {
        Ok(value) => Ok(CampusMetric::Success { value, fetched_at }),
        Err(error)
            if error.is_session_conflict()
                || error.code == crate::error::ErrorCode::AuthenticationRequired
                || !matches!(
                    error.kind,
                    ErrorKind::Network
                        | ErrorKind::Upstream
                        | ErrorKind::Parse
                        | ErrorKind::Authentication
                ) =>
        {
            Err(error)
        }
        Err(error) => Ok(CampusMetric::Failure {
            error: UbaaError::new(
                error.code,
                error.kind,
                error.retryable,
                "该校园指标暂时不可用",
            ),
            fetched_at,
        }),
    }
}

pub(super) fn persist(runtime: &mut ClientRuntime) -> Result<()> {
    runtime.ensure_session_revision()?;
    runtime.refresh_authentication(&mut || {})?;
    Ok(())
}
