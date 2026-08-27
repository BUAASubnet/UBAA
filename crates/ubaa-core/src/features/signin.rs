//! 课堂签到只读查询的冻结响应解析。
#![allow(clippy::missing_errors_doc)]

use serde::Deserialize;
use serde_json::Value;

use crate::domain::SigninClass;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

#[derive(Deserialize)]
struct Response {
    #[serde(rename = "STATUS")]
    status: Value,
    #[serde(default)]
    result: Vec<Row>,
}

#[derive(Deserialize)]
struct Row {
    id: String,
    #[serde(rename = "courseName")]
    course_name: String,
    #[serde(rename = "classBeginTime")]
    class_begin_time: String,
    #[serde(rename = "classEndTime")]
    class_end_time: String,
    #[serde(rename = "stuSignStatus")]
    sign_status: Value,
}

/// 解析旧版 iClass 今日课程响应，不向调用方暴露上游包装字段。
pub fn parse_today(body: &str) -> Result<Vec<SigninClass>> {
    let response: Response = serde_json::from_str(body).map_err(|_| parse_error())?;
    if !success(&response.status) {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "签到响应返回了非成功状态",
        ));
    }
    response.result.into_iter().map(map_row).collect()
}

fn success(value: &Value) -> bool {
    matches!(value, Value::Number(number) if number.as_i64() == Some(0) || number.as_i64() == Some(200))
        || matches!(value, Value::String(text) if matches!(text.as_str(), "0" | "200" | "success"))
}

fn map_row(row: Row) -> Result<SigninClass> {
    let sign_status = match row.sign_status {
        Value::Number(number) => number.as_i64(),
        Value::String(text) => text.parse::<i64>().ok(),
        _ => None,
    }
    .and_then(|value| i32::try_from(value).ok())
    .ok_or_else(parse_error)?;
    Ok(SigninClass {
        course_id: row.id,
        course_name: row.course_name,
        class_begin_time: row.class_begin_time,
        class_end_time: row.class_end_time,
        sign_status,
    })
}

fn parse_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::ParseError,
        ErrorKind::Parse,
        false,
        "签到响应格式无效",
    )
}
