//! Core facade 与宿主绑定共享的稳定领域值。

use std::fmt;

use serde::{Deserialize, Serialize};

mod auth;
pub use auth::*;
mod route;
pub use route::*;
mod bykc;
pub use bykc::*;
mod libbook;
pub use libbook::*;
mod ygdk;
pub use ygdk::*;
mod evaluation;
pub use evaluation::*;
mod signin;
pub use signin::*;
mod schedule;
pub use schedule::*;
mod grades;
pub use grades::*;

/// 场馆预约站点。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyVenueSite {
    pub id: i32,
    pub site_name: String,
    pub venue_name: String,
    pub campus_name: String,
    pub seat_count: Option<i32>,
    pub reservation_space_count: Option<i32>,
    pub site_telephone: Option<String>,
    pub open_start_date: Option<String>,
    pub open_end_date: Option<String>,
}

/// 场馆预约用途类型。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyPurposeType {
    pub key: i32,
    pub name: String,
}

/// 场馆预约时段。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyTimeSlot {
    pub id: i32,
    pub begin_time: String,
    pub end_time: String,
    pub label: String,
}

/// 场馆空间在一个时段内的状态。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyySlotStatus {
    pub time_id: i32,
    pub reservation_status: i32,
    pub is_reservable: bool,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub trade_no: Option<String>,
    pub order_id: Option<i32>,
    pub use_num: Option<i32>,
    pub already_num: Option<i32>,
    pub take_up: Option<bool>,
    pub take_up_explain: Option<String>,
}

/// 场馆空间及其时段状态。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyySpaceAvailability {
    pub space_id: i32,
    pub space_name: String,
    pub venue_site_id: i32,
    pub venue_space_group_id: Option<i32>,
    pub slots: Vec<CgyySlotStatus>,
}

/// 指定日期的场馆可预约信息。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyDayInfo {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<CgyyTimeSlot>,
    pub spaces: Vec<CgyySpaceAvailability>,
    pub reservation_token: Option<String>,
    pub reservation_total_num: Option<i32>,
}

/// 场馆预约订单。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyOrder {
    pub id: i32,
    pub trade_no: Option<String>,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub venue_space_name: Option<String>,
    pub campus_name: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
    pub phone: Option<String>,
    pub order_status: Option<i32>,
    pub pay_status: Option<i32>,
    pub check_status: Option<i32>,
    pub theme: Option<String>,
    pub purpose_type: Option<i32>,
    pub purpose_type_name: Option<String>,
    pub joiner_num: Option<i32>,
    pub activity_content: Option<String>,
    pub joiners: Option<String>,
    pub check_content: Option<String>,
    pub handle_reason: Option<String>,
    pub remark: Option<String>,
}

/// 场馆预约订单分页。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyOrdersPage {
    pub content: Vec<CgyyOrder>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}

/// 场馆预约写操作结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyActionResult {
    /// 上游返回的中文提示。
    pub message: String,
    /// 受影响的订单（取消操作通常为空）。
    pub order: Option<CgyyOrder>,
}

/// 场馆预约提交时选择的空间及时段。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationSelection {
    pub space_id: i32,
    pub time_id: i32,
    pub venue_space_group_id: Option<i32>,
}

/// 场馆预约提交请求。
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationSubmitRequest {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub selections: Vec<CgyyReservationSelection>,
    pub phone: String,
    pub theme: String,
    pub purpose_type: i32,
    pub joiner_num: i32,
    pub activity_content: String,
    pub joiners: String,
    pub is_philosophy_social_sciences: bool,
    pub is_off_school_joiner: bool,
    /// 外部验证码服务返回的校验串；仅用于当前请求，不得持久化或输出。
    #[serde(skip_serializing)]
    pub captcha_verification: String,
    /// 验证码滑块点位 JSON，仅用于当前请求。
    #[serde(skip_serializing)]
    pub captcha_point_json: String,
    /// 验证码挑战令牌，仅用于当前请求。
    #[serde(skip_serializing)]
    pub captcha_token: String,
    /// 验证码挑战 AES 密钥，仅用于当前请求。
    #[serde(skip_serializing)]
    pub captcha_secret_key: Option<String>,
    /// 验证码背景图 base64，仅用于当前请求。
    #[serde(skip_serializing)]
    pub captcha_original_image_base64: Option<String>,
    /// 验证码滑块图 base64，仅用于当前请求。
    #[serde(skip_serializing)]
    pub captcha_jigsaw_image_base64: Option<String>,
}

impl fmt::Debug for CgyyReservationSubmitRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CgyyReservationSubmitRequest")
            .field("venue_site_id", &self.venue_site_id)
            .field("reservation_date", &self.reservation_date)
            .field("selections", &self.selections)
            .field("phone", &"<redacted>")
            .field("theme", &self.theme)
            .field("purpose_type", &self.purpose_type)
            .field("joiner_num", &self.joiner_num)
            .field("activity_content", &self.activity_content)
            .field("joiners", &"<redacted>")
            .field(
                "is_philosophy_social_sciences",
                &self.is_philosophy_social_sciences,
            )
            .field("is_off_school_joiner", &self.is_off_school_joiner)
            .field("captcha_verification", &"<redacted>")
            .field("captcha_point_json", &"<redacted>")
            .field("captcha_token", &"<redacted>")
            .field("captcha_secret_key", &"<redacted>")
            .field("captcha_original_image_base64", &"<redacted>")
            .field("captcha_jigsaw_image_base64", &"<redacted>")
            .finish()
    }
}

/// 场馆预约提交结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyReservationResult {
    pub success: bool,
    pub message: String,
    pub order: Option<CgyyOrder>,
}

/// 场馆门锁码响应的安全不透明载荷。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CgyyLockCode {
    pub raw_data: serde_json::Value,
}

/// 空闲教室查询响应。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassroomQuery {
    /// 上游结果代码。
    pub code: i32,
    /// 上游消息。
    pub message: String,
    /// 按楼层/楼栋分组的教室。
    pub floors: std::collections::BTreeMap<String, Vec<ClassroomInfo>>,
}

/// 一间可用教室。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassroomInfo {
    /// 教室标识。
    pub id: String,
    /// 楼层/楼栋标识。
    pub floor_id: String,
    /// 教室名称。
    pub name: String,
    /// 可用节次。
    pub available_sections: String,
}

/// SPOC 提交状态。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SpocSubmissionStatus {
    /// 已提交。
    Submitted,
    /// 未提交。
    Unsubmitted,
    /// 未知的上游状态。
    #[default]
    Unknown,
}

/// SPOC 作业摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentSummary {
    /// 作业标识。
    pub assignment_id: String,
    /// 课程标识。
    pub course_id: String,
    /// 课程名称。
    pub course_name: String,
    /// 教师姓名。
    pub teacher_name: Option<String>,
    /// 作业标题。
    pub title: String,
    /// 开始时间。
    pub start_time: Option<String>,
    /// 截止时间。
    pub due_time: Option<String>,
    /// 成绩。
    pub score: Option<String>,
    /// 提交状态。
    pub submission_status: SpocSubmissionStatus,
    /// 可安全展示的状态文本。
    pub submission_status_text: String,
}

/// SPOC 作业列表。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignments {
    /// 当前学期代码。
    pub term_code: String,
    /// 当前学期名称。
    pub term_name: Option<String>,
    /// 作业列表。
    pub assignments: Vec<SpocAssignmentSummary>,
}

/// 一次 SPOC 全局列表操作的安全完成证据。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentsDiagnostics {
    /// 成功解析的权威全局作业页数量。
    pub global_page_count: u32,
    /// 普通稳定作业列表结果。
    pub result: SpocAssignments,
}

/// SPOC 作业详情。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentDetail {
    /// Assignment ID.
    pub assignment_id: String,
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Teacher name.
    pub teacher_name: Option<String>,
    /// Assignment title.
    pub title: String,
    /// Start time.
    pub start_time: Option<String>,
    /// Due time.
    pub due_time: Option<String>,
    /// Score.
    pub score: Option<String>,
    /// Submission status.
    pub submission_status: SpocSubmissionStatus,
    /// Safe status text.
    pub submission_status_text: String,
    /// 纯文本描述。
    pub content_plain_text: Option<String>,
    /// 提交时间。
    pub submitted_at: Option<String>,
}

/// 希冀提交状态。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum JudgeSubmissionStatus {
    /// 已全部提交。
    Submitted,
    /// 部分提交。
    Partial,
    /// 未提交。
    Unsubmitted,
    /// 未知状态。
    #[default]
    Unknown,
}

/// 希冀作业摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentSummary {
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Assignment ID.
    pub assignment_id: String,
    /// Assignment title.
    pub title: String,
    /// Start time.
    pub start_time: Option<String>,
    /// Due time.
    pub due_time: Option<String>,
    /// 最高分。
    pub max_score: Option<String>,
    /// 用户得分。
    pub my_score: Option<String>,
    /// 题目数量。
    pub total_problems: i32,
    /// 已提交数量。
    pub submitted_count: i32,
    /// 提交状态。
    pub submission_status: JudgeSubmissionStatus,
    /// 可安全展示的状态文本。
    pub submission_status_text: String,
}

/// 一次希冀列表操作的安全解析诊断。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentsDiagnostics {
    /// 跳过历史课程前解析出的课程数量。
    pub course_count: usize,
    /// 过滤和去重前发现的数字作业锚点数量。
    pub raw_anchor_count: usize,
    /// 解析器过滤后保留的非空唯一作业数量。
    pub filtered_unique_count: usize,
    /// 应用 `include_expired` 后的普通希冀摘要。
    pub summaries: Vec<JudgeAssignmentSummary>,
}

/// 希冀作业详情键。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentKey {
    /// Course ID.
    pub course_id: String,
    /// Assignment ID.
    pub assignment_id: String,
}

/// 希冀题目详情。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeProblem {
    /// 题目名称。
    pub name: String,
    /// 获得分数。
    pub score: Option<String>,
    /// 最高分。
    pub max_score: Option<String>,
    /// 提交状态。
    pub status: JudgeSubmissionStatus,
    /// 可安全展示的状态文本。
    pub status_text: String,
}

/// 希冀作业详情。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentDetail {
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Assignment ID.
    pub assignment_id: String,
    /// Assignment title.
    pub title: String,
    /// Start time.
    pub start_time: Option<String>,
    /// Due time.
    pub due_time: Option<String>,
    /// Maximum score.
    pub max_score: Option<String>,
    /// 用户得分。
    pub my_score: Option<String>,
    /// Number of problems.
    pub total_problems: i32,
    /// Number submitted.
    pub submitted_count: i32,
    /// Submission state.
    pub submission_status: JudgeSubmissionStatus,
    /// Safe status text.
    pub submission_status_text: String,
    /// 解析后的题目列表。
    pub problems: Vec<JudgeProblem>,
    /// HTML 内容转换后的纯文本。
    pub content_plain_text: Option<String>,
}
