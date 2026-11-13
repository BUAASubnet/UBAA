//! 图书馆云打印，登录材料与接口字段仅留在 Core。
pub(crate) mod auth;
pub(crate) mod pdf;
pub(crate) mod read;
mod upload;
pub(crate) use upload::send_upload;
#[cfg(test)]
pub(crate) use upload::upload_result;

use serde_json::Value;
use url::Url;

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse, same_url};
use crate::runtime::ClientRuntime;

pub(crate) const HOST: &str = "print.lib.buaa.edu.cn";
pub(crate) const ORIGIN: &str = "https://print.lib.buaa.edu.cn";
pub(crate) const PAGE: &str = "https://print.lib.buaa.edu.cn/client/new/cprintPc/cprint.html";
pub(crate) const QUEUE_PAGE: &str =
    "https://print.lib.buaa.edu.cn/client/new/cprintPc/printDoc.html";

pub(crate) fn invalid() -> UbaaError {
    UbaaError::upstream_changed("云打印返回了无法识别的结果")
}

pub(crate) fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "云打印需要有效的学校登录，请恢复登录后重试",
    )
}

pub(crate) fn refused() -> UbaaError {
    UbaaError::new(
        ErrorCode::BusinessUnavailable,
        ErrorKind::Upstream,
        false,
        "云打印服务器拒绝了该操作",
    )
}

pub(crate) fn unknown() -> UbaaError {
    UbaaError::outcome_unknown("云打印操作结果未知，请刷新文档列表核对后再决定是否重试")
}

fn https_origin(url: &Url, host: &str) -> bool {
    url.scheme() == "https"
        && url.host_str() == Some(host)
        && url.port_or_known_default() == Some(443)
        && url.username().is_empty()
        && url.password().is_none()
        && url.fragment().is_none()
}

pub(crate) fn endpoint(path: &str) -> Url {
    Url::parse(&format!("{ORIGIN}/api/client/{path}")).expect("固定云打印 URL")
}

fn timestamped(path: &str) -> Url {
    let mut url = endpoint(path);
    url.query_pairs_mut()
        .append_pair("timestamp", &rand::random::<f64>().to_string());
    url
}

pub(crate) async fn request(
    runtime: &mut ClientRuntime,
    mut request: HttpRequest,
) -> Result<HttpResponse> {
    request.url = runtime.url(&request.url)?;
    let expected = request.url.clone();
    let response = runtime
        .request_with_pre_send_check(request, ClientRuntime::ensure_session_revision)
        .await?;
    runtime.ensure_session_revision()?;
    if !same_url(&expected, &response.final_url) {
        return Err(invalid());
    }
    if runtime.mode() == ConnectionMode::WebVpn
        && matches!(response.status, 301 | 302 | 303 | 307 | 308)
        && response.header_first("location").is_some_and(|location| {
            Url::parse(&expected)
                .and_then(|base| base.join(location))
                .is_ok_and(|url| {
                    crate::connection::is_valid_webvpn_gateway(&url)
                        && url.path() == "/login"
                        && url.query().is_none()
                        && url.fragment().is_none()
                })
        })
    {
        return Err(authentication_required());
    }
    Ok(response)
}

fn redirect_target(mode: ConnectionMode, base: &str, location: &str) -> Result<Url> {
    if mode == ConnectionMode::WebVpn {
        crate::connection::business_redirect_target(base, location).map_err(|_| invalid())
    } else {
        Url::parse(base)
            .and_then(|url| url.join(location))
            .map_err(|_| invalid())
    }
}

fn auth_target(mode: ConnectionMode, raw: &str) -> Result<Url> {
    Url::parse(raw).map_err(|_| invalid())?;
    redirect_target(mode, PAGE, raw)
}

fn integer(value: &Value) -> Option<i64> {
    value.as_i64().or_else(|| value.as_str()?.parse().ok())
}

fn envelope(response: &HttpResponse) -> Result<Value> {
    if matches!(response.status, 401 | 403) {
        return Err(authentication_required());
    }
    if response.status != 200 {
        return Err(invalid());
    }
    let value: Value = serde_json::from_slice(&response.body).map_err(|_| invalid())?;
    match value.get("code").and_then(integer) {
        Some(0) => Ok(value),
        Some(4) => Err(authentication_required()),
        Some(_) => Err(refused()),
        None => Err(invalid()),
    }
}
