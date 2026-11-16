//! 校园功能复用的会话检查、HTTP 编排与响应判定。

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
            if feature == "研讨室预约" {
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
            .header_first("location")
            .ok_or_else(|| feature_redirect_error(feature))?;
        let next =
            resolve_feature_redirect(&response.final_url, location, runtime.mode(), feature)?;
        if feature == "研讨室预约" {
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
    crate::logging::safe_url(value)
}

fn resolve_feature_redirect(
    current: &str,
    location: &str,
    mode: crate::domain::ConnectionMode,
    feature: &str,
) -> Result<String> {
    let target = crate::connection::upstream_redirect_target(current, location)
        .map_err(|_| feature_redirect_error(feature))?;
    let Some(host) = target.host_str() else {
        return Err(feature_redirect_error(feature));
    };
    if !matches!(target.scheme(), "http" | "https")
        || !target.username().is_empty()
        || target.password().is_some()
    {
        return Err(feature_redirect_error(feature));
    }
    if !(matches!(
        host.to_ascii_lowercase().as_str(),
        "sso.buaa.edu.cn"
            | "uc.buaa.edu.cn"
            | "byxt.buaa.edu.cn"
            | "app.buaa.edu.cn"
            | "spoc.buaa.edu.cn"
            | "judge.buaa.edu.cn"
            | "cgyy.buaa.edu.cn"
            | "d.buaa.edu.cn"
    ) || (matches!(feature, "研究生课表" | "GSMIS")
        && host.eq_ignore_ascii_case("gsmis.buaa.edu.cn")))
    {
        return Err(feature_redirect_error(feature));
    }
    let is_gateway = host.eq_ignore_ascii_case("d.buaa.edu.cn");
    if is_gateway
        && (mode != crate::domain::ConnectionMode::WebVpn
            || !crate::connection::is_valid_webvpn_gateway(&target))
    {
        return Err(feature_redirect_error(feature));
    }
    if mode == crate::domain::ConnectionMode::WebVpn && !is_gateway {
        crate::connection::to_webvpn_url(target.as_str())
    } else {
        Ok(target.to_string())
    }
}

#[track_caller]
fn feature_redirect_error(feature: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        format!("{feature} 不支持该重定向"),
    )
    .with_diagnostic("redirect", "redirect_invalid")
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

#[track_caller]
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
        )
        .with_diagnostic("response", "authentication_required")
        .with_response(&response.body, Some(response.status)));
    }
    if response.status != 200 {
        return Err(http_status_error(response, feature));
    }
    Ok(())
}

/// 按 HTTP 语义分类；调用方先处理各业务的成功状态和有证据的认证标记。
#[track_caller]
pub(crate) fn http_status_error(response: &HttpResponse, feature: &str) -> UbaaError {
    let (code, kind, retryable, reason, message) = match response.status {
        401 => (
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "authentication_required",
            "需要认证",
        ),
        403 => (
            ErrorCode::PermissionDenied,
            ErrorKind::Upstream,
            false,
            "http_forbidden",
            "服务器拒绝访问",
        ),
        408 => (
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "http_request_timeout",
            "上游请求超时",
        ),
        429 => (
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "http_rate_limited",
            "请求过于频繁，请稍后重试",
        ),
        500..=599 => (
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "http_server_error",
            "上游暂时不可用",
        ),
        400..=499 => (
            ErrorCode::BusinessRejected,
            ErrorKind::Upstream,
            false,
            "http_client_error",
            "服务器拒绝请求",
        ),
        _ => (
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "http_status_unexpected",
            "返回了非预期的 HTTP 状态",
        ),
    };
    UbaaError::new(code, kind, retryable, format!("{feature}：{message}"))
        .with_diagnostic("response", reason)
        .with_response(&response.body, Some(response.status))
}

#[cfg(test)]
mod redirect_tests {
    use super::resolve_feature_redirect;
    use crate::connection::to_webvpn_url;
    use crate::domain::ConnectionMode;

    #[test]
    fn 业务跳转升级sso但不改写业务service或其他主机() {
        let query =
            "service=http%3a%2f%2fbyxt.buaa.edu.cn%2fjwapp%2fsys%2fhomeapp%2findex.do%3fx%3d%2526";
        let target = format!("http://sso.buaa.edu.cn/login?{query}");
        for location in [target.clone(), to_webvpn_url(&target).unwrap()] {
            for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
                let actual = resolve_feature_redirect(
                    "https://byxt.buaa.edu.cn/",
                    &location,
                    mode,
                    "schedule",
                )
                .unwrap();
                let expected = format!("https://sso.buaa.edu.cn/login?{query}");
                assert_eq!(
                    actual,
                    if mode == ConnectionMode::WebVpn {
                        to_webvpn_url(&expected).unwrap()
                    } else {
                        expected
                    }
                );
            }
        }
        let unchanged = "http://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do";
        assert_eq!(
            resolve_feature_redirect(
                "https://byxt.buaa.edu.cn/",
                unchanged,
                ConnectionMode::Direct,
                "schedule"
            )
            .unwrap(),
            unchanged
        );
    }

    #[test]
    fn 业务跳转仍拒绝网关内未登记主机及非http协议() {
        for target in [
            "https://unknown.example.invalid/",
            "ftp://sso.buaa.edu.cn/login",
        ] {
            for location in [target.to_string(), to_webvpn_url(target).unwrap()] {
                for feature in ["schedule", "GSMIS"] {
                    assert!(
                        resolve_feature_redirect(
                            "https://byxt.buaa.edu.cn/",
                            &location,
                            ConnectionMode::WebVpn,
                            feature
                        )
                        .is_err()
                    );
                }
            }
        }
    }
}

#[cfg(test)]
mod error_classification_tests {
    use super::*;

    #[test]
    fn diagnostics_contract_http拒绝限流和服务异常各有明确原因() {
        for (status, code, reason, retryable) in [
            (
                401,
                ErrorCode::AuthenticationRequired,
                "authentication_required",
                false,
            ),
            (403, ErrorCode::PermissionDenied, "http_forbidden", false),
            (
                429,
                ErrorCode::UpstreamUnavailable,
                "http_rate_limited",
                true,
            ),
            (
                503,
                ErrorCode::UpstreamUnavailable,
                "http_server_error",
                true,
            ),
        ] {
            let response = HttpResponse::new(
                status,
                "https://example.invalid/",
                br#"{"code":403,"status":"503","data":"private"}"#.to_vec(),
            );
            let error = check_response(&response, "测试服务").unwrap_err();
            assert_eq!(error.code, code);
            assert_eq!(error.retryable, retryable);
            assert_eq!(error.diagnostic().status, Some(status));
            assert_eq!(error.diagnostic().reason.as_deref(), Some(reason));
            assert_eq!(error.diagnostic().upstream_code, None);
            assert!(!error.diagnostic().to_json().unwrap().contains("private"));
        }
    }
}
