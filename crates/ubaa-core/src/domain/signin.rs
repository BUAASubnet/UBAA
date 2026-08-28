use serde::{Deserialize, Serialize};

/// 一条 iClass 课堂签到状态。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SigninClass {
    /// 上游课程安排标识。
    pub course_id: String,
    /// 课程显示名称。
    pub course_name: String,
    /// 上课开始时间。
    pub class_begin_time: String,
    /// 上课结束时间。
    pub class_end_time: String,
    /// 签到状态：零表示未签到，一表示已签到。
    pub sign_status: i32,
}

/// 课堂签到写操作结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SigninActionResult {
    pub code: i32,
    pub success: bool,
    pub message: String,
}
