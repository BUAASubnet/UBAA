//! Core facade 与宿主绑定共享的稳定领域值。

use std::fmt;

use serde::{Deserialize, Serialize};

mod auth;
pub use auth::*;
mod route;
pub use route::*;

/// 博雅用户资料。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcUserProfile {
    pub id: i64,
    pub employee_id: Option<String>,
    pub real_name: Option<String>,
    pub student_no: Option<String>,
    pub college_name: Option<String>,
}

/// 博雅课程列表项。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcCourse {
    pub id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub course_select_start_date: Option<String>,
    pub course_select_end_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub course_max_count: Option<i32>,
    pub course_current_count: Option<i32>,
    pub status: BykcCourseStatus,
    pub selected: Option<bool>,
}

/// 博雅课程状态。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BykcCourseStatus {
    /// 课程已经开始。
    Expired,
    /// 当前用户已经选择课程。
    Selected,
    /// 尚未开始选课。
    Preview,
    /// 选课已经结束。
    Ended,
    /// 课程人数已满。
    Full,
    /// 当前可以选课。
    #[default]
    Available,
}

/// 博雅课程分页结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcCoursePage {
    pub content: Vec<BykcCourse>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}

/// 博雅已选课程记录。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcChosenCourse {
    pub id: i64,
    pub course_id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub select_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub category: Option<BykcCourseCategory>,
    pub sub_category: Option<BykcCourseSubCategory>,
    pub checkin: i32,
    pub score: Option<i32>,
    pub pass: Option<i32>,
    pub can_sign: bool,
    pub can_sign_out: bool,
    pub sign_config: Option<BykcSignConfig>,
    pub course_sign_type: Option<i32>,
    pub homework: Option<String>,
    pub homework_attachment_name: Option<String>,
    pub homework_attachment_path: Option<String>,
    pub sign_info: Option<String>,
}

/// 博雅课程一级分类。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum BykcCourseCategory {
    /// 博雅课程。
    #[serde(rename = "博雅课程")]
    Boya,
    /// 未识别的一级分类。
    #[serde(rename = "未知分类")]
    Unknown,
}

/// 博雅课程二级分类。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum BykcCourseSubCategory {
    /// 德育。
    #[serde(rename = "德育")]
    Moral,
    /// 美育。
    #[serde(rename = "美育")]
    Aesthetic,
    /// 劳动教育。
    #[serde(rename = "劳动教育")]
    Labor,
    /// 安全健康。
    #[serde(rename = "安全健康")]
    SafetyHealth,
    /// 其他方面。
    #[serde(rename = "其他方面")]
    Other,
    /// 未识别的二级分类。
    #[serde(rename = "未知类型")]
    Unknown,
}

/// 博雅签到配置。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcSignConfig {
    pub sign_start_date: Option<String>,
    pub sign_end_date: Option<String>,
    pub sign_out_start_date: Option<String>,
    pub sign_out_end_date: Option<String>,
    pub sign_points: Vec<BykcSignPoint>,
}

/// 博雅签到地理位置。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct BykcSignPoint {
    pub lat: f64,
    pub lng: f64,
    pub radius: f64,
}

/// 博雅统计明细。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcStatistic {
    pub category_name: Option<String>,
    pub sub_category_name: Option<String>,
    pub required_count: Option<i32>,
    pub passed_count: Option<i32>,
    pub qualified: Option<bool>,
}

/// 博雅统计结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcStatistics {
    pub total_valid_count: Option<i32>,
    pub categories: Vec<BykcStatistic>,
}

/// 阳光打卡项目。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkItem {
    pub item_id: i32,
    pub name: String,
    pub kind: Option<i32>,
    pub sort: Option<i32>,
}

/// 阳光打卡学期统计。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkTermSummary {
    pub term_id: Option<i32>,
    pub term_name: Option<String>,
    pub term_count: i32,
    pub term_target: Option<i32>,
    pub week_count: Option<i32>,
    pub week_target: Option<i32>,
    pub month_count: Option<i32>,
    pub month_target: Option<i32>,
    pub day_count: Option<i32>,
    pub good_count: Option<i32>,
}

/// 阳光打卡概览。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkOverview {
    pub summary: YgdkTermSummary,
    pub classify_id: i32,
    pub classify_name: String,
    pub default_item_id: i32,
    pub default_item_name: String,
    pub items: Vec<YgdkItem>,
}

/// 阳光打卡记录。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkRecord {
    pub record_id: i32,
    pub item_id: Option<i32>,
    pub item_name: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub place: Option<String>,
    pub images: Vec<String>,
    pub is_open: bool,
    pub state: Option<i32>,
    pub created_at: Option<String>,
    pub created_at_label: Option<String>,
}

/// 阳光打卡记录分页。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkRecordsPage {
    pub content: Vec<YgdkRecord>,
    pub total: i32,
    pub page: i32,
    pub size: i32,
    pub has_more: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookLibrary {
    pub id: String,
    pub name: String,
    pub free_num: i32,
    pub total_num: i32,
    pub storeys: Vec<LibBookStorey>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookStorey {
    pub id: String,
    pub name: String,
    pub free_num: i32,
    pub total_num: i32,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookArea {
    pub id: String,
    pub name: String,
    pub area_name: String,
    pub premises_id: String,
    pub storey_id: String,
    pub free_num: i32,
    pub total_num: i32,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookAreaDetail {
    pub id: String,
    pub name: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<LibBookTimeSlot>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookTimeSlot {
    pub id: String,
    pub start: String,
    pub end: String,
    pub label: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookSeat {
    pub id: String,
    pub name: String,
    pub no: String,
    pub status: String,
    pub status_name: String,
    pub is_available: bool,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookBooking {
    pub id: String,
    pub name_merge: String,
    pub area_name: String,
    pub seat_no: String,
    pub day: String,
    pub begin_time: String,
    pub end_time: String,
    pub status: String,
    pub status_name: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookBookingsPage {
    pub bookings: Vec<LibBookBooking>,
    pub page: i32,
    pub limit: i32,
    pub total: i32,
}

/// 图书馆座位预约请求。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookReserveRequest {
    pub area_id: String,
    pub seat_id: String,
    pub day: String,
    pub segment: String,
    pub start_time: String,
    pub end_time: String,
}

/// 图书馆预约结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookReserveResult {
    pub success: bool,
    pub message: String,
    pub booking: Option<LibBookBooking>,
}

/// 图书馆取消结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibBookCancelResult {
    pub success: bool,
    pub message: String,
}

/// 博雅课程写操作结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcActionResult {
    pub message: String,
}

/// 博雅签到/签退请求。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcSignRequest {
    pub course_id: i64,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub sign_type: i32,
}

/// 评教任务。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationTask {
    pub rwid: String,
    pub rwmc: String,
    pub questionnaires: Vec<EvaluationQuestionnaire>,
}

/// 评教问卷。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationQuestionnaire {
    pub wjid: String,
    pub wjmc: String,
    pub msid: String,
    pub courses: Vec<EvaluationCourse>,
}

/// 一门待评教课程及调用上游所需的稳定字段。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationCourse {
    pub id: String,
    pub kcmc: String,
    pub bpmc: String,
    pub is_evaluated: bool,
    pub rwid: String,
    pub wjid: String,
    pub kcdm: String,
    pub bpdm: Option<String>,
    pub pjrdm: Option<String>,
    pub pjrmc: Option<String>,
    pub xnxq: Option<String>,
    pub msid: String,
    pub zdmc: Option<String>,
    pub ypjcs: Option<i32>,
    pub xypjcs: Option<i32>,
    pub sxz: Option<String>,
    pub rwh: Option<String>,
    pub xn: Option<String>,
    pub xq: Option<String>,
    pub pjlxid: Option<String>,
    pub sfksqbpj: Option<String>,
    pub yxsfktjst: Option<String>,
}

/// 评教进度。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationProgress {
    pub total_courses: i32,
    pub evaluated_courses: i32,
    pub pending_courses: i32,
}

impl EvaluationProgress {
    #[must_use]
    pub fn progress_percent(&self) -> i32 {
        if self.total_courses > 0 {
            self.evaluated_courses.saturating_mul(100) / self.total_courses
        } else {
            0
        }
    }
}

/// 评教课程列表及进度。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationCoursesResponse {
    pub courses: Vec<EvaluationCourse>,
    pub progress: EvaluationProgress,
}

/// 单门评教结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvaluationResult {
    pub success: bool,
    pub message: String,
    pub course_name: String,
}

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

/// 阳光打卡图片上传。图片字节只在一次请求内存中存在，不写入会话或输出。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkPhotoUpload {
    #[serde(skip_serializing)]
    pub bytes: Vec<u8>,
    #[serde(skip_serializing)]
    pub file_name: String,
    #[serde(skip_serializing)]
    pub mime_type: String,
}

impl fmt::Debug for YgdkPhotoUpload {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("YgdkPhotoUpload")
            .field("bytes", &format_args!("[{} bytes]", self.bytes.len()))
            .field("file_name", &"[REDACTED]")
            .field("mime_type", &self.mime_type)
            .finish()
    }
}

/// 阳光打卡提交请求。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkClockinSubmitRequest {
    pub item_id: Option<i32>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub place: Option<String>,
    pub share_to_square: Option<bool>,
    pub photo: Option<YgdkPhotoUpload>,
}

/// 阳光打卡提交结果。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct YgdkClockinSubmitResult {
    pub success: bool,
    pub message: String,
    pub record_id: Option<i32>,
    pub summary: Option<YgdkTermSummary>,
}

/// 一条已验证的学期信息。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Term {
    /// 上游学期代码，例如 `2025-2026-1`。
    pub item_code: String,
    /// 供用户阅读的学期名称。
    pub item_name: String,
    /// 门户是否选中了该学期。
    pub selected: bool,
    /// 上游排序索引。
    pub item_index: i32,
}

/// 一条教学周信息。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Week {
    /// 周起始日期。
    pub start_date: String,
    /// 周结束日期。
    pub end_date: String,
    /// 所属学期代码。
    pub term: String,
    /// 是否为当前教学周。
    pub cur_week: bool,
    /// 数字形式的周序号。
    pub serial_number: i32,
    /// 显示名称。
    pub name: String,
}

/// 一节课程安排。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseClass {
    /// 课程代码。
    pub course_code: String,
    /// 课程显示名称。
    pub course_name: String,
    /// 可选的课程序号。
    pub course_serial_no: Option<String>,
    /// 门户表示的学分。
    pub credit: Option<String>,
    /// 开始时间。
    pub begin_time: Option<String>,
    /// 结束时间。
    pub end_time: Option<String>,
    /// 起始节次。
    pub begin_section: Option<i32>,
    /// 结束节次。
    pub end_section: Option<i32>,
    /// 教室。
    pub place_name: Option<String>,
    /// 周次和教师描述。
    pub weeks_and_teachers: Option<String>,
    /// 授课对象。
    pub teaching_target: Option<String>,
    /// 显示颜色。
    pub color: Option<String>,
    /// 星期，取值 1-7。
    pub day_of_week: Option<i32>,
}

/// 教学周课表包装。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WeeklySchedule {
    /// 已安排的课程。
    pub arranged_list: Vec<CourseClass>,
    /// 门户返回的学期代码。
    pub code: String,
    /// 学期显示名称。
    pub name: String,
}

/// 一条今日课程摘要。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodayClass {
    /// 业务/课程名称。
    pub biz_name: String,
    /// 教室。
    pub place: Option<String>,
    /// 显示时间。
    pub time: Option<String>,
    /// 课程简称。
    pub short_name: Option<String>,
}

/// 考试安排。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExamArrangement {
    /// 已安排的考试。
    pub arranged: Vec<Exam>,
    /// 上游提供的未安排考试。
    pub not_arranged: Vec<Exam>,
}

/// 一条考试信息。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Exam {
    /// 课程名称。
    pub course_name: String,
    /// 课程编号。
    pub course_no: Option<String>,
    /// 显示时间描述。
    pub exam_time_description: Option<String>,
    /// 考试日期。
    pub exam_date: Option<String>,
    /// 开始时间。
    pub start_time: Option<String>,
    /// 结束时间。
    pub end_time: Option<String>,
    /// 考试地点。
    pub exam_place: Option<String>,
    /// 座位号。
    pub exam_seat_no: Option<String>,
    /// 周序号。
    pub week: Option<i32>,
    /// 上游状态。
    pub exam_status: Option<i32>,
    /// 考试类型。
    pub exam_type: Option<String>,
    /// 上游任务标识。
    pub task_id: Option<String>,
}

/// 一门课程成绩。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Grade {
    /// 课程名称。
    pub course_name: Option<String>,
    /// 课程代码。
    pub course_code: Option<String>,
    /// 学分值。
    pub credit: Option<f64>,
    /// 上游展示的成绩。
    pub score: Option<String>,
    /// 绩点。
    pub grade_point: Option<String>,
    /// 课程类别/类型。
    pub course_type: Option<String>,
    /// 成绩认定类型。
    pub score_type: Option<String>,
    /// 学期代码。
    pub term_code: Option<String>,
}

/// 指定学期的成绩。
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GradeData {
    /// 请求的学期代码。
    pub term_code: String,
    /// 解析后的成绩。
    pub grades: Vec<Grade>,
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
