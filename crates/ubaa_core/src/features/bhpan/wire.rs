use super::parse;
use crate::domain::SecretValue;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpMethod, HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use serde_json::Value;

pub(crate) const ORIGIN: &str = "https://bhpan.buaa.edu.cn";
pub(crate) const EFAST: &str = "/api/efast/v1";
pub(crate) const LINKS: &str = "/api/shared-link/v1";

pub(crate) async fn api(
    runtime: &mut ClientRuntime,
    token: &SecretValue,
    method: HttpMethod,
    path: &str,
    body: Option<Value>,
    secondary: Option<&SecretValue>,
    write: bool,
) -> Result<Vec<u8>> {
    let request = request(token, method, path, body, secondary)?;
    let url = request.url.clone();
    let response = runtime.request_bearer_only(request, write).await?;
    finish(&url, response, write)
}
pub(crate) fn request(
    token: &SecretValue,
    method: HttpMethod,
    path: &str,
    body: Option<Value>,
    secondary: Option<&SecretValue>,
) -> Result<HttpRequest> {
    let url = format!("{ORIGIN}{path}");
    let mut request = HttpRequest::get(&url);
    request.method = method;
    request = request.with_header("Authorization", format!("Bearer {}", token.expose_secret()));
    if let Some(secondary) = secondary {
        request = request.with_header(
            "x-as-authorization",
            format!("Bearer {}", secondary.expose_secret()),
        );
    }
    if let Some(body) = body {
        request.body =
            serde_json::to_vec(&body).map_err(|_| UbaaError::invalid_input("云盘参数无效"))?;
        request = request.with_header("Content-Type", "application/json");
    }
    Ok(request)
}
pub(crate) async fn read_checked<F>(
    runtime: &mut ClientRuntime,
    request: HttpRequest,
    pre_send: F,
) -> Result<Vec<u8>>
where
    F: FnOnce(&ClientRuntime) -> Result<()>,
{
    let url = request.url.clone();
    let response = runtime
        .request_bearer_only_checked(request, false, pre_send)
        .await?;
    finish(&url, response, false)
}
pub(crate) async fn write_checked<F>(
    runtime: &mut ClientRuntime,
    request: HttpRequest,
    pre_send: F,
) -> Result<Vec<u8>>
where
    F: FnOnce(&ClientRuntime) -> Result<()>,
{
    let url = request.url.clone();
    let response = runtime
        .request_bearer_only_checked(request, true, pre_send)
        .await?;
    finish(&url, response, true)
}
fn finish(url: &str, response: HttpResponse, write: bool) -> Result<Vec<u8>> {
    if response.final_url != url {
        return Err(if write { unknown() } else { parse::invalid() });
    }
    status(&response, write)?;
    Ok(response.body)
}
pub(crate) fn status(response: &HttpResponse, write: bool) -> Result<()> {
    match response.status {
        200..=299 => Ok(()),
        401 => Err(UbaaError::new(
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            false,
            "云盘授权已失效，请重新打开云盘或分享",
        )),
        403 => Err(UbaaError::new(
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            false,
            "没有权限执行此云盘操作",
        )),
        400 | 404 | 409 => Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "云盘拒绝操作，请检查目标、同名文件与输入",
        )),
        _ if write => Err(unknown()),
        500..=599 => Err(UbaaError::upstream_unavailable("北航云盘暂时不可用")),
        _ => Err(parse::invalid()),
    }
}
pub(crate) fn unknown() -> UbaaError {
    UbaaError::outcome_unknown("云盘操作结果待核对，请在原账号与路线刷新目标，不要重复提交")
}

pub(crate) fn segment(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes())
        .collect::<String>()
        .replace('+', "%20")
}
