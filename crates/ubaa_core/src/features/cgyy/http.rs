//! Cgyy 请求签名、认证重试、响应判定与安全日志。

use std::collections::BTreeMap;

use tracing::debug;

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpMethod, HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

use super::parser::{check_code, error, object};
use super::sign::{sign, timestamp_millis};
use super::site::CgyySite;

/// 北京与杭州前端公开配置解码后相同（见杭州专项记录）。
const APP_KEY: &str = "8fceb735082b5a529312040b58ea780b";

pub(super) fn signed_request(
    runtime: &ClientRuntime,
    method: HttpMethod,
    path: &str,
    params: BTreeMap<String, String>,
    token: Option<&str>,
) -> Result<HttpRequest> {
    signed_request_at(runtime, CgyySite::Beijing, method, path, params, token)
}

pub(super) fn signed_request_at(
    runtime: &ClientRuntime,
    site: CgyySite,
    method: HttpMethod,
    path: &str,
    mut params: BTreeMap<String, String>,
    token: Option<&str>,
) -> Result<HttpRequest> {
    let timestamp = timestamp_millis()?;
    if method == HttpMethod::Get {
        params
            .entry("nocache".into())
            .or_insert_with(|| timestamp.to_string());
    }
    let signature = sign(path, &params, timestamp);
    let mut direct = url::Url::parse(&format!("{}{path}", site.base_url()))
        .map_err(|_| error("研讨室请求地址无效"))?;
    if method == HttpMethod::Get {
        direct.query_pairs_mut().extend_pairs(
            params
                .iter()
                .map(|(key, value)| (key.as_str(), value.as_str())),
        );
    }
    let request_url = runtime.url(direct.as_str())?;
    let mut request = match method {
        HttpMethod::Get => HttpRequest::get(request_url),
        HttpMethod::Post => HttpRequest::post(request_url, Vec::new()),
        HttpMethod::Put | HttpMethod::Delete => {
            return Err(crate::error::UbaaError::invalid_input(
                "研讨室请求方法不受支持",
            ));
        }
    };
    request
        .headers
        .insert("Accept".into(), "application/json, text/plain, */*".into());
    request
        .headers
        .insert("Referer".into(), runtime.url(site.referer())?);
    request.headers.insert("app-key".into(), APP_KEY.into());
    request
        .headers
        .insert("timestamp".into(), timestamp.to_string());
    request.headers.insert("sign".into(), signature);
    if method == HttpMethod::Post {
        request.headers.insert(
            "Content-Type".into(),
            "application/x-www-form-urlencoded".into(),
        );
    }
    if let Some(token) = token {
        request
            .headers
            .insert("cgAuthorization".into(), token.into());
    }
    debug!(
        target: "ubaa::cgyy",
        feature = "cgyy",
        route = ?runtime.mode(),
        operation = operation_name(method, path),
        method = method_name_value(method),
        request_url = %safe_url(&request.url),
        parameter_count = params.len(),
        token_present = token.is_some(),
        token_len = token.map_or(0, str::len),
        "已构造 Cgyy HTTP 请求"
    );
    Ok(request)
}

/// 按冻结旧版 `LocalCgyyApi.requestJson` 的顺序检查响应。
/// Cgyy 上游曾出现 HTTP 状态与业务 `code` 不一致的响应，旧版以业务信封为准。
pub(super) fn check_business_response(response: &HttpResponse, feature: &str) -> Result<()> {
    let text = super::super::body(response);
    if response.status == 401
        || crate::connection::is_sso_url(&response.final_url)
        || crate::connection::response_location_targets_sso(response)
        || (text.contains("name=\"execution\"") && text.contains("username_password"))
    {
        debug!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, auth_marker = true, "Cgyy 响应识别为认证失效");
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            format!("{feature}需要认证"),
        )
        .with_diagnostic("authentication", "business_session_required")
        .with_response(&response.body, Some(response.status)));
    }
    if (300..400).contains(&response.status) {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            format!("{feature}返回了未处理的重定向"),
        )
        .with_diagnostic("redirect", "redirect_unexpected")
        .with_response(&response.body, Some(response.status)));
    }
    let result = object(&text).and_then(|root| check_code(&root, &text));
    if let Err(error) = result {
        if response.status == 429 {
            let limited = super::super::http::http_status_error(response, feature);
            return Err(match error.diagnostic().upstream_code {
                Some(code) => limited.with_upstream_code(code),
                None => limited,
            });
        }
        if response.status != 200 && error.code != ErrorCode::BusinessRejected {
            return Err(super::super::http::http_status_error(response, feature));
        }
        return Err(error.with_http_status(response.status));
    }
    debug!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, business_code = 200, "Cgyy 业务响应通过");
    Ok(())
}

pub(super) fn operation_name(method: HttpMethod, path: &str) -> &'static str {
    match path {
        "/api/orders/mine" => "orders.list",
        path if path.starts_with("/api/orders/") && !path.contains("/lock/") => {
            "orders.detail_or_cancel"
        }
        "/api/orders/lock/code" => "orders.lock_code",
        "/api/front/website/venues" => "sites.list",
        "/api/reservation/day/info" => "day.info",
        "/api/codes" => "purposes.list",
        "/api/login" => "business_login.api",
        _ if method == HttpMethod::Post => "business.write",
        _ => "business.read",
    }
}

pub(super) const fn method_name_value(method: HttpMethod) -> &'static str {
    match method {
        HttpMethod::Get => "GET",
        HttpMethod::Post => "POST",
        HttpMethod::Put => "PUT",
        HttpMethod::Delete => "DELETE",
    }
}

pub(super) fn safe_parameter_summary(
    params: &BTreeMap<String, String>,
) -> BTreeMap<String, String> {
    params
        .iter()
        .map(|(key, value)| (key.clone(), format!("<存在，长度={}>", value.len())))
        .collect()
}

pub(super) fn log_response(runtime: &ClientRuntime, operation: &str, response: &HttpResponse) {
    if operation == "orders.lock_code" {
        debug!(target: "ubaa::cgyy", feature = "cgyy", route = ?runtime.mode(), operation,
            status = response.status, "收到门锁响应");
        return;
    }
    let body = &response.body;
    debug!(
        target: "ubaa::cgyy",
        feature = "cgyy",
        route = ?runtime.mode(),
        operation,
        status = response.status,
        final_url = %safe_url(&response.final_url),
        body_len = body.len(),
        content_type = ?response.headers.get("content-type").and_then(|values| values.first()),
        "收到 Cgyy 响应"
    );
}

pub(super) fn safe_url(value: &str) -> String {
    crate::logging::safe_url(value)
}

#[cfg(test)]
mod diagnostic_tests {
    use super::*;

    #[test]
    fn 研讨室限流保留http语义与已验证的业务码() {
        let response = HttpResponse::new(
            429,
            "https://cgyy.buaa.edu.cn/",
            br#"{"code":429,"data":null}"#.to_vec(),
        );
        let error = check_business_response(&response, "研讨室").unwrap_err();
        assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
        assert_eq!(
            error.diagnostic().reason.as_deref(),
            Some("http_rate_limited")
        );
        assert_eq!(error.diagnostic().upstream_code, Some(429));
    }

    #[test]
    fn diagnostics_contract_研讨室http业务错误保留明确业务码() {
        let response = HttpResponse::new(
            500,
            "https://cgyy.buaa.edu.cn/",
            br#"{"code":34,"message":"synthetic-private","data":null}"#.to_vec(),
        );
        let error = check_business_response(&response, "研讨室").unwrap_err();
        assert_eq!(
            serde_json::to_value(error.code).unwrap(),
            "business_rejected"
        );
        assert_eq!(error.diagnostic().upstream_code, Some(34));
        assert_eq!(error.diagnostic().status, Some(500));
        assert!(
            !error
                .diagnostic()
                .to_json()
                .unwrap()
                .contains("synthetic-private")
        );
    }
}
