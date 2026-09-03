//! 构建于 Core 认证会话之上的校园功能模块。

pub mod bykc;
pub mod cgyy;
pub mod classroom;
pub mod evaluation;
pub mod grades;
pub mod judge;
pub mod libbook;
pub mod schedule;
pub mod signin;
pub mod spoc;
pub(crate) use crate::internal::route_state as state;
pub(crate) mod user;
pub mod ygdk;
pub(crate) mod ygdk_upload;

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
            "需要认证",
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

/// 跟随本地业务门户探测使用的有界、主机白名单重定向。
pub(crate) async fn get_with_redirects(
    runtime: &mut ClientRuntime,
    url: String,
    headers: &[(&str, &str)],
    feature: &str,
) -> Result<HttpResponse> {
    require_session(runtime)?;
    let mut current = url;
    for hop in 0..8 {
        let mut request = HttpRequest::get(current.clone());
        for (name, value) in headers {
            request.headers.insert((*name).into(), (*value).into());
        }
        let response = runtime.request(request).await?;
        if !(300..400).contains(&response.status) {
            if feature == "场馆预约" {
                tracing::debug!(
                    target: "ubaa::cgyy",
                    feature = "cgyy",
                    route = ?runtime.mode(),
                    operation = "business_login.sso",
                    redirect_hops = hop,
                    status = response.status,
                    final_url = %safe_feature_url(&response.final_url),
                    "Cgyy SSO 重定向结束"
                );
            }
            return Ok(response);
        }
        let location = response
            .headers
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case("location"))
            .and_then(|(_, values)| values.first())
            .ok_or_else(|| feature_redirect_error(feature))?;
        let next =
            resolve_feature_redirect(&response.final_url, location, runtime.mode(), feature)?;
        if feature == "场馆预约" {
            tracing::debug!(
                target: "ubaa::cgyy",
                feature = "cgyy",
                route = ?runtime.mode(),
                operation = "business_login.sso",
                redirect_hop = hop + 1,
                status = response.status,
                from_url = %safe_feature_url(&response.final_url),
                to_url = %safe_feature_url(&next),
                "Cgyy SSO 跟随重定向"
            );
        }
        current = next;
    }
    Err(feature_redirect_error(feature))
}

fn safe_feature_url(value: &str) -> String {
    url::Url::parse(value).map_or_else(
        |_| "<无效 URL>".into(),
        |parsed| {
            let host = parsed.host_str().unwrap_or("<无主机>");
            format!("{}://{}{}", parsed.scheme(), host, parsed.path())
        },
    )
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
        format!("{feature} 不支持该重定向"),
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
            format!("{feature} 需要认证"),
        ));
    }
    if response.status >= 500 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            format!("{feature} 上游不可用"),
        ));
    }
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            format!("{feature} 请求失败"),
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
