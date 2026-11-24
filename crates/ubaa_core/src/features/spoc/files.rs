use super::{
    SpocCredential,
    auth::{check_business_response, resolve_required_spoc_result, with_spoc_auth_retry},
    parser::{parse_optional_envelope, spoc_auth_error},
};
use crate::{
    domain::{SpocDownloadReceipt, SpocDownloadTarget},
    error::{Result, UbaaError},
    ports::{HttpRequest, HttpResponse, StreamDownload},
    runtime::ClientRuntime,
};
use serde::Deserialize;
use std::path::Path;

const META: &str = "https://spoc.buaa.edu.cn/inco-filesystem/fileManagerSystem/queryFileById";
const DOWNLOAD: &str = "https://spoc.buaa.edu.cn/inco-filesystem/fileManagerSystem/downLoadFile";
const COURSE_DOWNLOAD: &str = "https://spoc.buaa.edu.cn/spocnewht/grwj1/downLoadFile";
const FILE_LIMIT: u64 = 512 * 1024 * 1024;

pub(super) fn url(
    runtime: &ClientRuntime,
    endpoint: &str,
    pairs: &[(&str, &str)],
) -> Result<String> {
    let mut url = url::Url::parse(&runtime.url(endpoint)?)
        .map_err(|_| UbaaError::upstream_changed("SPOC 地址无效"))?;
    url.query_pairs_mut().extend_pairs(pairs.iter().copied());
    Ok(url.into())
}

pub(super) fn require_id(id: &str) -> Result<()> {
    if id.trim().is_empty() {
        Err(UbaaError::invalid_input("SPOC 标识不能为空"))
    } else {
        Ok(())
    }
}

pub(super) fn business_post(url: String, credential: &SpocCredential) -> HttpRequest {
    HttpRequest::post(url, vec![])
        .with_header("Token", credential.token_header())
        .with_header("RoleCode", &credential.role)
        .with_header("X-Requested-With", "XMLHttpRequest")
}

pub(super) fn file_response(response: &HttpResponse) -> Result<()> {
    if response.status == 403
        && serde_json::from_slice::<serde_json::Value>(&response.body)
            .is_ok_and(|json| json["code"].as_i64() == Some(0))
    {
        return Err(spoc_auth_error());
    }
    check_business_response(response)
}

#[derive(Deserialize)]
pub(super) struct Metadata {
    wjysmc: Option<String>,
    pub(super) wjhzm: Option<String>,
    #[serde(rename = "fileSize")]
    pub(super) file_size: Option<String>,
}
impl Metadata {
    pub(super) fn name(&self) -> Option<String> {
        self.wjysmc
            .as_deref()
            .filter(|name| !name.trim().is_empty())
            .map(safe_name)
    }
}

pub(super) async fn metadata(runtime: &mut ClientRuntime, id: &str) -> Option<Metadata> {
    let url = url(runtime, META, &[("wjid", id)]).ok()?;
    with_spoc_auth_retry(runtime, move |runtime, credential| {
        let request =
            HttpRequest::post(url.clone(), vec![]).with_header("Token", credential.token_header());
        Box::pin(async move {
            let response = if runtime.mode() == crate::domain::ConnectionMode::Direct {
                runtime.request_bearer_only(request, false).await?
            } else {
                runtime.request(request).await?
            };
            file_response(&response)?;
            serde_json::from_slice(&response.body)
                .map_err(|_| UbaaError::upstream_changed("SPOC 文件元数据无法解析"))
        })
    })
    .await
    .ok()
}

pub(super) fn safe_name(value: &str) -> String {
    let cleaned = value
        .replace(
            |ch: char| ch.is_control() || "/\\:<>\"|?*".contains(ch),
            "_",
        )
        .replace("..", "_");
    let cleaned = cleaned.trim_matches(|ch: char| ch == '.' || ch.is_whitespace());
    if cleaned.is_empty() {
        "下载文件".into()
    } else {
        cleaned.into()
    }
}

fn decoded_name(value: &str) -> String {
    let encoded = format!("name={}", value.replace('&', "%26"));
    url::form_urlencoded::parse(encoded.as_bytes())
        .next()
        .map_or_else(String::new, |(_, name)| name.into_owned())
}

pub(crate) async fn download(
    runtime: &mut ClientRuntime,
    target: &SpocDownloadTarget,
    destination: &Path,
) -> Result<SpocDownloadReceipt> {
    let (endpoint, key, id, fallback, file_service) = match target {
        SpocDownloadTarget::AssignmentFile { file_id, file_name } => (
            DOWNLOAD,
            "scjlid",
            file_id,
            file_name.as_deref().unwrap_or(""),
            true,
        ),
        SpocDownloadTarget::CourseFile { id, name } => {
            (COURSE_DOWNLOAD, "id", id, name.as_str(), false)
        }
    };
    require_id(id)?;
    let metadata_name = if file_service && fallback.is_empty() {
        metadata(runtime, id).await.and_then(|meta| meta.name())
    } else {
        None
    };
    let fallback = metadata_name.as_deref().unwrap_or(fallback);
    let url = url(runtime, endpoint, &[(key, id)])?;
    let destination = destination.to_owned();
    let result = with_spoc_auth_retry(runtime, move |runtime, credential| {
        let request = if file_service {
            HttpRequest::get(url.clone()).with_header("Token", credential.token_header())
        } else {
            business_post(url.clone(), credential)
        };
        let path = destination.clone();
        Box::pin(async move {
            let session_cookies =
                !file_service || runtime.mode() == crate::domain::ConnectionMode::WebVpn;
            match runtime
                .download_stream(request, &path, FILE_LIMIT, session_cookies)
                .await?
            {
                StreamDownload::File {
                    final_path,
                    byte_len,
                    content_disposition_filename,
                } => {
                    debug_assert_eq!(final_path, path);
                    Ok((byte_len, content_disposition_filename))
                }
                StreamDownload::Body {
                    response,
                    truncated,
                } => {
                    if file_service {
                        file_response(&response)?;
                    } else {
                        check_business_response(&response)?;
                    }
                    if !truncated
                        && response
                            .header_first("Content-Type")
                            .is_some_and(|value| value.to_ascii_lowercase().contains("json"))
                    {
                        parse_optional_envelope::<serde_json::Value>(&crate::features::body(
                            &response,
                        ))
                        .map_err(|err| err.with_http_status(response.status))?;
                    }
                    Err(UbaaError::upstream_changed("SPOC 未返回文件正文")
                        .with_http_status(response.status))
                }
            }
        })
    })
    .await;
    let (byte_len, header) = resolve_required_spoc_result(runtime, result).await?;
    let name = header
        .filter(|value| file_service && !value.is_empty())
        .map(|name| decoded_name(&name));
    Ok(SpocDownloadReceipt {
        file_name: safe_name(name.as_deref().unwrap_or(fallback)),
        byte_len,
    })
}
