//! 阳光打卡照片 multipart 正文构造。

use crate::domain::YgdkPhotoUpload;
use crate::error::Result;
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::YgdkCredential;
use super::http::FRONT_BASE;
use super::parser::{error, parse_envelope, string};

pub(super) fn build_upload_body(
    credential: &YgdkCredential,
    photo: &YgdkPhotoUpload,
    boundary: &str,
) -> Vec<u8> {
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
    body
}

pub(super) async fn upload_photo(
    runtime: &mut ClientRuntime,
    credential: &YgdkCredential,
    photo: &YgdkPhotoUpload,
) -> Result<String> {
    let boundary = "ubaa-ygdk-boundary";
    let body = build_upload_body(credential, photo, boundary);
    let mut request = HttpRequest::post(
        runtime.url(&format!("{FRONT_BASE}/api/Front/Upload/File/post"))?,
        body,
    );
    request.headers.insert(
        "Content-Type".into(),
        format!("multipart/form-data; boundary={boundary}"),
    );
    request
        .headers
        .insert("X-Requested-With".into(), "XMLHttpRequest".into());
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(error("阳光打卡图片上传失败"));
    }
    let value = parse_envelope(&super::super::body(&response))?;
    value
        .as_object()
        .and_then(|object| string(object, "file_name"))
        .ok_or_else(|| error("阳光打卡图片上传响应无效"))
}
