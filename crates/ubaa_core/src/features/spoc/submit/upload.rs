use super::{CHUNK, Source, chunk_count, chunk_len, encode, file::unreadable};
use crate::{
    domain::{
        ConnectionMode,
        bhpan::{BhpanTransferPhase as Phase, transfer::BhpanTransfer},
    },
    error::{ErrorCode, Result, UbaaError},
    features::spoc::{SpocCredential, auth::with_spoc_auth_retry, files::file_response},
    ports::{HttpFileRange, HttpRequest, HttpResponse},
    runtime::ClientRuntime,
};
use serde_json::Value;
use std::{fmt::Write as _, path::Path};
use tokio::fs::File;

const UPLOAD: &str = "https://spoc.buaa.edu.cn/inco-filesystem/fileManagerSystem/uploadFile";
const MERGE: &str = "https://spoc.buaa.edu.cn/inco-filesystem/fileManagerSystem/mergeFile";

fn fields(source: &Source, number: u64) -> [(&'static str, String); 8] {
    [
        ("chunkNumber", number.to_string()),
        ("chunkSize", CHUNK.to_string()),
        (
            "currentChunkSize",
            chunk_len(source.size, number).to_string(),
        ),
        ("totalSize", source.size.to_string()),
        ("identifier", source.md5.clone()),
        ("filename", source.name.clone()),
        ("relativePath", source.name.clone()),
        ("totalChunks", chunk_count(source.size).to_string()),
    ]
}

async fn send(runtime: &mut ClientRuntime, request: HttpRequest, write: bool) -> Result<Value> {
    let endpoint = request.url.clone();
    let response = if runtime.mode() == ConnectionMode::Direct {
        runtime.request_bearer_only(request, write).await
    } else if write {
        runtime.request_non_idempotent(request).await
    } else {
        runtime.request(request).await
    }
    .map_err(|error| upload_error(error, write))?;
    response_json(&endpoint, &response)
}
fn upload_error(error: UbaaError, write: bool) -> UbaaError {
    if write && error.code == ErrorCode::OutcomeUnknown {
        UbaaError::upstream_changed("文件上传未完成，请重新准备以探测已上传分片")
    } else {
        error
    }
}
fn response_json(endpoint: &str, response: &HttpResponse) -> Result<Value> {
    file_response(response)?;
    if response.status != 200 || response.final_url != endpoint {
        return Err(invalid());
    }
    serde_json::from_slice(&response.body).map_err(|_| invalid())
}

pub(super) async fn upload(
    runtime: &mut ClientRuntime,
    source: &Source,
    file: &mut File,
    progress: &BhpanTransfer,
) -> Result<(String, SpocCredential)> {
    let mut probe = url::Url::parse(&runtime.url(UPLOAD)?).map_err(|_| invalid())?;
    probe.query_pairs_mut().extend_pairs(fields(source, 1));
    progress.set(Phase::Uploading, 0, source.size);
    let (reply, credential) = with_spoc_auth_retry(runtime, move |runtime, credential| {
        let request =
            HttpRequest::get(probe.as_str()).with_header("Token", credential.token_header());
        Box::pin(async move { Ok((send(runtime, request, false).await?, credential.clone())) })
    })
    .await?;
    match reply["mc"].as_bool() {
        Some(true) => return Ok((file_id(&reply["data"])?, credential)),
        Some(false) => {}
        None => return Err(invalid()),
    }
    let existing = match reply.get("data") {
        Some(Value::Null) => vec![],
        Some(Value::Array(values)) => values
            .iter()
            .map(|item| item.as_u64().ok_or_else(invalid))
            .collect::<Result<Vec<_>>>()?,
        _ => return Err(invalid()),
    };
    for number in 1..=chunk_count(source.size) {
        progress.ensure_active()?;
        source.check_metadata(file).await?;
        let length = chunk_len(source.size, number);
        if existing.contains(&number) {
            progress.advance(length);
            continue;
        }
        let url = runtime.url(UPLOAD)?;
        let (request, range) = multipart(url.clone(), source, file, number).await?;
        let request = request.with_header("Token", credential.token_header());
        progress.ensure_active()?;
        let response = runtime
            .upload_file_part(request, range, progress)
            .await
            .map_err(|error| upload_error(error, true))?;
        let response = response_json(&url, &response)?;
        if response.get("mc").and_then(Value::as_bool) != Some(false)
            || response.get("data") != Some(&Value::Null)
        {
            return Err(invalid());
        }
    }
    source.check_metadata(file).await?;
    progress.ensure_active()?;
    progress.set(Phase::Finalizing, source.size, source.size);
    let body = encode(&[
        ("identifier", &source.md5),
        ("filename", &source.name),
        ("totalSize", &source.size.to_string()),
    ]);
    let request = HttpRequest::post(runtime.url(MERGE)?, body.into_bytes())
        .with_header(
            "Content-Type",
            "application/x-www-form-urlencoded; charset=UTF-8",
        )
        .with_header("Token", credential.token_header());
    Ok((file_id(&send(runtime, request, true).await?)?, credential))
}
fn invalid() -> UbaaError {
    UbaaError::upstream_changed("SPOC 文件服务未返回可确认的结果")
}
fn file_id(value: &Value) -> Result<String> {
    value["id"]
        .as_str()
        .filter(|id| !id.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(invalid)
}

async fn multipart(
    url: String,
    source: &Source,
    file: &mut File,
    number: u64,
) -> Result<(HttpRequest, HttpFileRange)> {
    let boundary = format!("ubaa-{}", uuid::Uuid::new_v4().simple());
    let mut head = String::new();
    for (key, value) in fields(source, number) {
        write!(
            head,
            "--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n"
        )
        .expect("写入字符串");
    }
    let name = source.name.replace('"', "%22");
    let kind = mime(&source.name);
    write!(head,"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\nContent-Type: {kind}\r\n\r\n").expect("写入字符串");
    let range = HttpFileRange {
        file: file
            .try_clone()
            .await
            .map_err(|_| unreadable())?
            .into_std()
            .await,
        offset: (number - 1) * CHUNK,
        length: chunk_len(source.size, number),
        framing: Some((
            head.into_bytes(),
            format!("\r\n--{boundary}--\r\n").into_bytes(),
        )),
    };
    Ok((
        HttpRequest::post(url, vec![]).with_header(
            "Content-Type",
            format!("multipart/form-data; boundary={boundary}"),
        ),
        range,
    ))
}
fn mime(name: &str) -> &'static str {
    match Path::new(name)
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "pdf" => "application/pdf",
        "zip" => "application/zip",
        "rar" => "application/vnd.rar",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "doc" => "application/msword",
        "ppt" => "application/vnd.ms-powerpoint",
        "txt" => "text/plain",
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        _ => "application/octet-stream",
    }
}
