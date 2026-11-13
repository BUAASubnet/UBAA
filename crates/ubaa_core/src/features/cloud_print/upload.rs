use std::path::Path;
use std::time::UNIX_EPOCH;

use rand::{RngExt as _, distr::Alphanumeric};
use tokio::io::AsyncReadExt as _;
use url::Url;

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::facade::cloud_print::PrintOptions;
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

use super::{HOST, PAGE, QUEUE_PAGE, endpoint, https_origin, redirect_target, refused, unknown};

const MAX_UPLOAD_BYTES: usize = 32 * 1024 * 1024;

pub(crate) async fn send_upload(
    runtime: &mut ClientRuntime,
    path: &Path,
    name: &str,
    options: PrintOptions,
) -> Result<()> {
    let (mut mime, image) = file_type(name)?;
    let mut bytes = Vec::new();
    if !tokio::fs::metadata(path).await.is_ok_and(|m| m.is_file()) {
        return Err(UbaaError::invalid_input("无法读取选中的打印文件"));
    }
    tokio::fs::File::open(path)
        .await
        .map_err(|_| UbaaError::invalid_input("无法打开选中的打印文件"))?
        .take((MAX_UPLOAD_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .await
        .map_err(|_| UbaaError::invalid_input("无法读取选中的打印文件"))?;
    if bytes.is_empty() || bytes.len() > MAX_UPLOAD_BYTES {
        return Err(UbaaError::invalid_input(
            "打印文件需大于 0 字节且不超过 32 MiB",
        ));
    }
    let converted;
    let name = if image {
        converted = format!("{name}.pdf");
        mime = file_type(&converted)?.0;
        bytes = tokio::task::spawn_blocking(move || super::pdf::image_pdf(&bytes, options.paper))
            .await
            .map_err(|_| UbaaError::invalid_input("无法转换打印图片"))??;
        if bytes.len() > MAX_UPLOAD_BYTES {
            return Err(UbaaError::invalid_input("图片转为 PDF 后超过 32 MiB"));
        }
        converted.as_str()
    } else {
        name
    };
    let boundary = rand::rng()
        .sample_iter(Alphanumeric)
        .take(48)
        .map(char::from)
        .collect::<String>();
    let tick = runtime
        .now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| UbaaError::invalid_input("本机时间无效"))?
        .as_millis();
    let mut body = Vec::with_capacity(bytes.len() + 1024);
    body.extend_from_slice(format!("--{boundary}\r\nContent-Disposition: form-data; name=\"szPath\"; filename=\"{name}\"\r\nContent-Type: {mime}\r\n\r\n").as_bytes());
    body.append(&mut bytes);
    body.extend_from_slice(b"\r\n");
    let (from, to) = if image {
        (0, 0)
    } else {
        options.pages.unwrap_or((0, 0))
    };
    let paper = if (image || mime == "text/plain") && options.paper == -1 {
        9
    } else {
        options.paper
    };
    for (key, value) in [
        ("dwColor", if options.color { "2" } else { "1" }.into()),
        ("dwPaperId", paper.to_string()),
        ("dwDuplex", options.duplex.to_string()),
        ("dwFrom", from.to_string()),
        ("dwTo", to.to_string()),
        ("dwCopies", options.copies.to_string()),
        ("BackURL", runtime.url(&format!("{QUEUE_PAGE}?t={tick}"))?),
    ] {
        body.extend_from_slice(
            format!(
                "--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n"
            )
            .as_bytes(),
        );
    }
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    let url = runtime.url(endpoint("CloudPrint/Upload").as_str())?;
    let referer = runtime.url(PAGE)?;
    let origin = Url::parse(&referer)
        .map_err(|_| super::invalid())?
        .origin()
        .ascii_serialization();
    let reply = runtime
        .request_non_idempotent(
            HttpRequest::post(&url, body)
                .with_header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .with_header("Origin", origin)
                .with_header("Referer", referer),
        )
        .await?;
    runtime.ensure_session_revision().map_err(|_| unknown())?;
    if !crate::ports::same_url(&reply.final_url, &url) {
        return Err(unknown());
    }
    upload_result(&reply, runtime.mode())
}

fn file_type(name: &str) -> Result<(&'static str, bool)> {
    if name.is_empty()
        || name.len() > 240
        || name.trim() != name
        || name
            .chars()
            .any(|c| c.is_control() || matches!(c, '/' | '\\' | '"'))
    {
        return Err(UbaaError::invalid_input("打印文件名无效"));
    }
    match name
        .rsplit_once('.')
        .map(|(_, ext)| ext.to_ascii_lowercase())
        .as_deref()
    {
        Some("jpg" | "jpeg") => Ok(("image/jpeg", true)),
        Some("png") => Ok(("image/png", true)),
        Some("pdf") => Ok(("application/pdf", false)),
        Some("docx") => Ok((
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            false,
        )),
        Some("xlsx") => Ok((
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            false,
        )),
        Some("pptx") => Ok((
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            false,
        )),
        Some("txt") => Ok(("text/plain", false)),
        Some(
            "heic" | "doc" | "xls" | "xslx" | "ppt" | "wps" | "wpt" | "dot" | "rtf" | "dotx"
            | "docm" | "dotm" | "xml" | "mht" | "mhtml" | "html" | "htm" | "xps" | "odt" | "xlsm"
            | "xlsb" | "csv" | "xltx" | "xltm" | "xlt" | "prn" | "dif" | "slk" | "xla" | "xlam"
            | "ods" | "dps" | "dpt" | "pot" | "pps" | "pptm" | "potm" | "ppsm",
        ) => Ok(("application/octet-stream", false)),
        _ => Err(UbaaError::invalid_input(
            "官网未列出此文件格式，请选择 PDF 或常见图片、Office 文件",
        )),
    }
}

pub(crate) fn upload_result(response: &HttpResponse, mode: ConnectionMode) -> Result<()> {
    if response.status == 413 {
        return Err(UbaaError::new(
            ErrorCode::BusinessUnavailable,
            ErrorKind::Upstream,
            false,
            "文件超过云打印服务器的大小限制",
        ));
    }
    if !matches!(response.status, 302 | 303) {
        return Err(unknown());
    }
    let locations = response.header_values("location").ok_or_else(unknown)?;
    let [location] = locations else {
        return Err(unknown());
    };
    let url = redirect_target(mode, &response.final_url, location).map_err(|_| unknown())?;
    if !https_origin(&url, HOST) || url.path() != "/client/new/cprintPc/printDoc.html" {
        return Err(unknown());
    }
    let mut code = url.query_pairs().filter(|(key, _)| key == "code");
    let number = code.next().and_then(|(_, value)| value.parse::<i32>().ok());
    if code.next().is_some() {
        return Err(unknown());
    }
    match number {
        Some(0) => Ok(()),
        Some(_) => Err(refused()),
        None => Err(unknown()),
    }
}
