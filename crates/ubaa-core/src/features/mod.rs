//! Campus feature modules built on authenticated Core sessions.

pub mod bykc;
pub mod cgyy;
pub mod classroom;
pub mod grades;
pub mod judge;
pub mod libbook;
pub mod schedule;
pub mod signin;
pub mod spoc;
pub(crate) mod state;
pub(crate) mod user;
pub mod ygdk;

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

pub(crate) fn require_session(runtime: &ClientRuntime) -> Result<()> {
    if runtime.has_local_session() {
        Ok(())
    } else {
        Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "authentication is required",
        ))
    }
}

pub(crate) async fn get_with_headers(
    runtime: &mut ClientRuntime,
    url: String,
    headers: &[(&str, &str)],
) -> Result<HttpResponse> {
    require_session(runtime)?;
    let mut request = HttpRequest::get(url);
    for (name, value) in headers {
        request.headers.insert((*name).into(), (*value).into());
    }
    runtime.request(request).await
}

/// Follow the bounded, host-allow-listed redirects used by local business portal probes.
pub(crate) async fn get_with_redirects(
    runtime: &mut ClientRuntime,
    url: String,
    headers: &[(&str, &str)],
    feature: &str,
) -> Result<HttpResponse> {
    require_session(runtime)?;
    let mut current = url;
    for _ in 0..8 {
        let mut request = HttpRequest::get(current.clone());
        for (name, value) in headers {
            request.headers.insert((*name).into(), (*value).into());
        }
        let response = runtime.request(request).await?;
        if !(300..400).contains(&response.status) {
            return Ok(response);
        }
        let location = response
            .headers
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case("location"))
            .and_then(|(_, values)| values.first())
            .ok_or_else(|| feature_redirect_error(feature))?;
        current = resolve_feature_redirect(&response.final_url, location, runtime.mode(), feature)?;
    }
    Err(feature_redirect_error(feature))
}

fn resolve_feature_redirect(
    current: &str,
    location: &str,
    mode: crate::domain::ConnectionMode,
    feature: &str,
) -> Result<String> {
    let base = url::Url::parse(current).map_err(|_| feature_redirect_error(feature))?;
    let target = base
        .join(location)
        .map_err(|_| feature_redirect_error(feature))?;
    let Some(host) = target.host_str() else {
        return Err(feature_redirect_error(feature));
    };
    if !matches!(
        host.to_ascii_lowercase().as_str(),
        "sso.buaa.edu.cn"
            | "uc.buaa.edu.cn"
            | "byxt.buaa.edu.cn"
            | "app.buaa.edu.cn"
            | "spoc.buaa.edu.cn"
            | "judge.buaa.edu.cn"
            | "cgyy.buaa.edu.cn"
            | "d.buaa.edu.cn"
    ) {
        return Err(feature_redirect_error(feature));
    }
    if mode == crate::domain::ConnectionMode::WebVpn && host != "d.buaa.edu.cn" {
        crate::connection::to_webvpn_url(target.as_str())
    } else {
        Ok(target.to_string())
    }
}

fn feature_redirect_error(feature: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        format!("{feature} redirect is not supported"),
    )
}

pub(crate) async fn post_form(
    runtime: &mut ClientRuntime,
    url: String,
    form: &[(&str, String)],
    headers: &[(&str, &str)],
) -> Result<HttpResponse> {
    require_session(runtime)?;
    let body = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(form.iter().map(|(key, value)| (*key, value.as_str())))
        .finish()
        .into_bytes();
    let mut request = HttpRequest::post(url, body);
    request.headers.insert(
        "Content-Type".into(),
        "application/x-www-form-urlencoded".into(),
    );
    for (name, value) in headers {
        request.headers.insert((*name).into(), (*value).into());
    }
    runtime.request(request).await
}

pub(crate) async fn post_json(
    runtime: &mut ClientRuntime,
    url: String,
    body: Vec<u8>,
    headers: &[(&str, &str)],
) -> Result<HttpResponse> {
    require_session(runtime)?;
    let mut request = HttpRequest::post(url, body);
    request
        .headers
        .insert("Content-Type".into(), "application/json".into());
    for (name, value) in headers {
        request.headers.insert((*name).into(), (*value).into());
    }
    runtime.request(request).await
}

pub(crate) fn body(response: &HttpResponse) -> String {
    String::from_utf8_lossy(&response.body).into_owned()
}

pub(crate) fn check_response(response: &HttpResponse, feature: &str) -> Result<()> {
    let text = body(response);
    let direct_final_url = crate::connection::from_webvpn_url(&response.final_url)
        .unwrap_or_else(|_| response.final_url.clone());
    let sso_final_url = url::Url::parse(&direct_final_url)
        .ok()
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
        .is_some_and(|host| host == "sso.buaa.edu.cn");
    if response.status == 401
        || sso_final_url
        || text.contains("input name=\"execution\"")
        || text.contains("统一身份认证")
    {
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            format!("{feature} authentication is required"),
        ));
    }
    if response.status >= 500 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            format!("{feature} upstream is unavailable"),
        ));
    }
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            format!("{feature} request failed"),
        ));
    }
    Ok(())
}

pub(crate) fn feature_result<T>(
    runtime: &ClientRuntime,
    data: T,
) -> crate::domain::FeatureResult<T> {
    crate::domain::FeatureResult {
        data,
        resolved_route: runtime.mode(),
    }
}
