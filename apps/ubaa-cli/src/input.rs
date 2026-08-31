//! CLI 输入读取、请求输入校验和稳定错误构造。

use std::io::{BufRead, Read, Write};
use std::path::PathBuf;

use serde_json::Value;
use ubaa_core::domain::{CgyyReservationSubmitRequest, YgdkClockinSubmitRequest, YgdkPhotoUpload};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(crate) fn prompt_line<R: BufRead, E: Write>(
    input: &mut R,
    stderr: &mut E,
    prompt: &str,
) -> Result<String> {
    loop {
        write!(stderr, "{prompt}").map_err(|_| internal_error("无法写入提示"))?;
        stderr.flush().map_err(|_| internal_error("无法刷新提示"))?;
        let mut value = String::new();
        let read = input
            .read_line(&mut value)
            .map_err(|_| invalid_input("无法读取必填输入"))?;
        if read == 0 {
            return Err(invalid_input("缺少必填输入"));
        }
        let value = value.trim_end_matches(['\r', '\n']).to_string();
        if !value.is_empty() {
            return Ok(value);
        }
        writeln!(stderr, "必须提供一个值。").map_err(|_| internal_error("无法写入提示"))?;
    }
}

pub(crate) fn read_secret_line<R: BufRead>(input: &mut R, missing_message: &str) -> Result<String> {
    let mut value = String::new();
    input
        .read_line(&mut value)
        .map_err(|_| invalid_input(missing_message))?;
    let value = value.trim_end_matches(['\r', '\n']).to_string();
    if value.is_empty() {
        Err(invalid_input(missing_message))
    } else {
        Ok(value)
    }
}

pub(crate) fn read_evaluation_payload(path: &PathBuf) -> Result<Vec<Value>> {
    let bytes = std::fs::read(path).map_err(|_| invalid_input("无法读取评教 payload 文件"))?;
    let value: Value = serde_json::from_slice(&bytes)
        .map_err(|_| invalid_input("评教 payload 必须是 JSON 数组"))?;
    let values = value
        .as_array()
        .ok_or_else(|| invalid_input("评教 payload 必须是 JSON 数组"))?;
    if values.is_empty() {
        return Err(invalid_input("评教 payload 不能为空"));
    }
    Ok(values.clone())
}

pub(crate) fn read_cgyy_request_stdin() -> Result<CgyyReservationSubmitRequest> {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .map_err(|_| invalid_input("无法读取场馆预约请求"))?;
    parse_cgyy_request(&input)
}

pub(crate) fn parse_cgyy_request(input: &str) -> Result<CgyyReservationSubmitRequest> {
    serde_json::from_str(input).map_err(|_| invalid_input("场馆预约请求必须是 JSON 对象"))
}

pub(crate) fn write_json<W: Write, T: serde::Serialize>(
    stdout: &mut W,
    value: &T,
) -> std::io::Result<()> {
    serde_json::to_writer(&mut *stdout, value)?;
    writeln!(stdout)
}

pub(crate) fn invalid_input(message: impl Into<String>) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

pub(crate) fn build_ygdk_request(
    item_id: Option<i32>,
    start_time: String,
    end_time: String,
    place: Option<String>,
    photo: &PathBuf,
    share_to_square: bool,
) -> Result<YgdkClockinSubmitRequest> {
    if start_time.trim().is_empty() || end_time.trim().is_empty() {
        return Err(invalid_input("打卡开始和结束时间不能为空"));
    }
    let bytes = std::fs::read(photo).map_err(|_| invalid_input("无法读取打卡照片"))?;
    if bytes.is_empty() {
        return Err(invalid_input("打卡照片不能为空"));
    }
    let file_name = photo
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("photo.bin")
        .to_owned();
    let mime_type = match photo
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "webp" => "image/webp",
        _ => "application/octet-stream",
    }
    .to_owned();
    Ok(YgdkClockinSubmitRequest {
        item_id,
        start_time: Some(start_time),
        end_time: Some(end_time),
        place,
        share_to_square: Some(share_to_square),
        photo: Some(YgdkPhotoUpload {
            bytes,
            file_name,
            mime_type,
        }),
    })
}

pub(crate) fn internal_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

#[cfg(test)]
mod tests {
    use super::parse_cgyy_request;

    #[test]
    fn 场馆预约请求可以省略由_core_内部获取的验证码材料() {
        let input = r#"{
            "venueSiteId": 4,
            "reservationDate": "2026-03-29",
            "selections": [{"spaceId": 6, "timeId": 242}],
            "phone": "010-00000000",
            "theme": "test reservation",
            "purposeType": 1,
            "joinerNum": 1,
            "activityContent": "test content",
            "joiners": "tester",
            "isPhilosophySocialSciences": false,
            "isOffSchoolJoiner": false
        }"#;

        let request = parse_cgyy_request(input).unwrap();

        assert!(!request.has_captcha_material());
    }
}
