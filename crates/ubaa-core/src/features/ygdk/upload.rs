//! 阳光打卡照片 multipart 正文构造。

use rand::{Rng, distributions::Alphanumeric};

use crate::domain::YgdkPhotoUpload;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::YgdkCredential;
use super::http::{FRONT_BASE, ensure_active_credential, is_pre_send_credential_error};
use super::parser::parse_envelope;

pub(super) fn build_upload_body(
    credential: &YgdkCredential,
    photo: &YgdkPhotoUpload,
    boundary: &str,
) -> Result<Vec<u8>> {
    validate_photo(photo)?;
    let mut body = Vec::new();
    let mut field = |name: &str, value: &str| {
        body.extend_from_slice(
            format!(
                "--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"
            )
            .as_bytes(),
        );
    };
    field("uid", &credential.uid.to_string());
    field("token", &credential.token);
    body.extend_from_slice(
        format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{}\"\r\nContent-Type: {}\r\n\r\n",
            photo.file_name, photo.mime_type
        )
        .as_bytes(),
    );
    body.extend_from_slice(&photo.bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    Ok(body)
}

pub(super) fn validate_photo(photo: &YgdkPhotoUpload) -> Result<()> {
    const MAX_PHOTO_BYTES: usize = 10 * 1024 * 1024;
    if !(1..=MAX_PHOTO_BYTES).contains(&photo.bytes.len()) {
        return Err(invalid_photo("打卡照片大小必须在 1 字节至 10 MiB 之间"));
    }
    let file_name = photo.file_name.as_str();
    let file_name_length = file_name.chars().count();
    if file_name != file_name.trim()
        || !(1..=128).contains(&file_name_length)
        || matches!(file_name, "." | "..")
        || file_name
            .chars()
            .any(|character| matches!(character, '/' | '\\' | '"') || character.is_control())
    {
        return Err(invalid_photo("打卡照片文件名无效"));
    }
    if photo.normalized_mime_type().is_none() {
        return Err(invalid_photo("打卡照片 MIME 类型无效"));
    }
    Ok(())
}

fn invalid_photo(message: &str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

fn upload_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamUnavailable,
        ErrorKind::Upstream,
        false,
        "阳光打卡照片上传未完成",
    )
}

pub(super) async fn upload_photo(
    runtime: &mut ClientRuntime,
    credential: &YgdkCredential,
    generation: u64,
    photo: &YgdkPhotoUpload,
) -> Result<String> {
    let boundary = generate_boundary(&photo.bytes);
    let body = build_upload_body(credential, photo, &boundary)?;
    let mut request = HttpRequest::post(
        runtime.url(&format!("{FRONT_BASE}/api/Front/Upload/File/post"))?,
        body,
    );
    let expected_final_url = request.url.clone();
    request.headers.insert(
        "Content-Type".into(),
        format!("multipart/form-data; boundary={boundary}"),
    );
    request
        .headers
        .insert("X-Requested-With".into(), "XMLHttpRequest".into());
    let response = runtime
        .request_with_pre_send_check(request, |runtime| {
            ensure_active_credential(runtime, generation, credential)
        })
        .await
        .map_err(upload_request_error)?;
    if response.status != 200 || response.final_url != expected_final_url {
        return Err(upload_error());
    }
    let value = parse_envelope(&super::super::body(&response)).map_err(|_| upload_error())?;
    value
        .as_object()
        .and_then(|object| object.get("file_name"))
        .and_then(serde_json::Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(upload_error)
}

fn upload_request_error(error: UbaaError) -> UbaaError {
    if is_pre_send_credential_error(&error) {
        error
    } else {
        upload_error()
    }
}

fn generate_boundary(photo: &[u8]) -> String {
    loop {
        let suffix = rand::thread_rng()
            .sample_iter(Alphanumeric)
            .take(48)
            .map(char::from)
            .collect::<String>();
        let boundary = format!("ubaaYgdk{suffix}");
        if !photo
            .windows(boundary.len())
            .any(|window| window == boundary.as_bytes())
        {
            return boundary;
        }
    }
}
