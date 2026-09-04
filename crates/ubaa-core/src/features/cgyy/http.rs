//! Cgyy 请求签名、认证重试、响应判定与安全日志。

use std::collections::BTreeMap;

use tracing::{debug, warn};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpMethod, HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

use super::parser::{error, object};
use super::sign::{sign, timestamp_millis};

const BASE_URL: &str = "https://cgyy.buaa.edu.cn/venue-zhjs-server";
const APP_KEY: &str = "8fceb735082b5a529312040b58ea780b";

pub(super) fn signed_request(
    runtime: &ClientRuntime,
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
    let mut direct =
        url::Url::parse(&format!("{BASE_URL}{path}")).map_err(|_| error("场馆请求地址无效"))?;
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
    };
    request
        .headers
        .insert("Accept".into(), "application/json, text/plain, */*".into());
    request.headers.insert(
        "Referer".into(),
        runtime.url("https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation")?,
    );
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
        || is_sso_url(&response.final_url)
        || response_location_targets_sso(response)
        || (text.contains("name=\"execution\"") && text.contains("username_password"))
    {
        debug!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, auth_marker = true, "Cgyy 响应识别为认证失效");
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            format!("{feature}需要认证"),
        ));
    }
    if (300..400).contains(&response.status) {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            true,
            format!("{feature}返回了未处理的重定向"),
        ));
    }
    let root = object(&text)?;
    let code = root.get("code").and_then(|value| {
        value
            .as_i64()
            .or_else(|| value.as_str()?.parse::<i64>().ok())
    });
    if code != Some(200) {
        warn!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, business_code = ?code, "Cgyy 业务 code 非成功值");
        return Err(error("场馆预约请求失败"));
    }
    debug!(target: "ubaa::cgyy", feature = "cgyy", response_status = response.status, business_code = 200, "Cgyy 业务响应通过");
    Ok(())
}

fn response_location_targets_sso(response: &HttpResponse) -> bool {
    response
        .headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("location"))
        .and_then(|(_, values)| values.first())
        .and_then(|location| {
            url::Url::parse(&response.final_url)
                .ok()
                .and_then(|base| base.join(location).ok())
                .map(|target| target.to_string())
                .or_else(|| Some(location.clone()))
        })
        .is_some_and(|target| is_sso_url(&target))
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
    let body = &response.body;
    debug!(
        target: "ubaa::cgyy",
        feature = "cgyy",
        route = ?runtime.mode(),
        operation,
        status = response.status,
        final_url = %safe_url(&response.final_url),
        body_len = body.len(),
        body_sha1 = %sha1_hex(body),
        content_type = ?response.headers.get("content-type").and_then(|values| values.first()),
        "收到 Cgyy 响应"
    );
}

pub(super) fn safe_url(value: &str) -> String {
    url::Url::parse(value).map_or_else(
        |_| "<无效 URL>".into(),
        |parsed| {
            let host = parsed.host_str().unwrap_or("<无主机>");
            let path = parsed
                .path_segments()
                .map(|segments| {
                    segments
                        .map(safe_path_segment)
                        .collect::<Vec<_>>()
                        .join("/")
                })
                .unwrap_or_default();
            format!(
                "{}://{}{}",
                parsed.scheme(),
                host,
                if path.is_empty() {
                    String::new()
                } else {
                    format!("/{path}")
                }
            )
        },
    )
}

fn safe_path_segment(segment: &str) -> String {
    if segment.chars().all(|character| character.is_ascii_digit())
        || segment.len() >= 24
            && segment
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || "-_".contains(character))
    {
        "<id>".into()
    } else {
        segment.into()
    }
}

fn sha1_hex(value: &[u8]) -> String {
    use sha1::{Digest, Sha1};
    use std::fmt::Write as _;
    let mut result = String::with_capacity(40);
    for byte in Sha1::digest(value) {
        write!(&mut result, "{byte:02x}").expect("写入 String 不会失败");
    }
    result
}

fn is_sso_url(candidate: &str) -> bool {
    let direct =
        crate::connection::from_webvpn_url(candidate).unwrap_or_else(|_| candidate.to_owned());
    url::Url::parse(&direct)
        .ok()
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
        .is_some_and(|host| host == "sso.buaa.edu.cn")
}
