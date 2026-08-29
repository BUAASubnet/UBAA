//! 阳光打卡照片 multipart 正文构造。

use super::ygdk::YgdkCredential;
use crate::domain::YgdkPhotoUpload;

pub(crate) fn build_upload_body(
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
