//! 博雅选课、退选与签到写操作。
#![allow(clippy::missing_errors_doc)]

use serde_json::Value;

use super::auth::request_api;
use super::error;
use crate::domain::{BykcActionResult, BykcSignRequest};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 选课写操作。
pub(crate) async fn select_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
) -> Result<BykcActionResult> {
    if course_id <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程标识必须为正数",
        ));
    }
    let value = request_api(
        runtime,
        "choseCourse",
        serde_json::json!({"courseId": course_id}),
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or("选课成功")
            .to_owned(),
    })
}

/// 退选写操作。
pub(crate) async fn deselect_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
) -> Result<BykcActionResult> {
    if course_id <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程标识必须为正数",
        ));
    }
    let value = request_api(
        runtime,
        "delChosenCourse",
        serde_json::json!({"id": course_id}),
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or("退选成功")
            .to_owned(),
    })
}

/// 博雅签到或签退写操作。
pub(crate) async fn sign_course(
    runtime: &mut crate::runtime::ClientRuntime,
    request: BykcSignRequest,
) -> Result<BykcActionResult> {
    if request.course_id <= 0 || !matches!(request.sign_type, 1 | 2) {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "课程标识或签到类型无效",
        ));
    }
    let value = request_api(
        runtime,
        "signCourseByUser",
        serde_json::to_value(&request).map_err(|_| error("博雅签到参数无效"))?,
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or(if request.sign_type == 1 {
                "签到成功"
            } else {
                "签退成功"
            })
            .to_owned(),
    })
}
