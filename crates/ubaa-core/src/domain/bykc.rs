use serde::{Deserialize, Serialize};

use super::ActionEligibility;

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
    /// 当前课程的选课资格；`Unknown` 必须按拒绝处理。
    pub select_eligibility: ActionEligibility,
    /// 当前课程的退选资格；`Unknown` 必须按拒绝处理。
    pub deselect_eligibility: ActionEligibility,
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
    /// 原始考勤状态；缺失时不得推断为未签到。
    pub checkin: Option<i32>,
    pub score: Option<i32>,
    pub pass: Option<i32>,
    /// 当前课程的签到资格；`Unknown` 必须按拒绝处理。
    pub sign_eligibility: ActionEligibility,
    /// 当前课程的签退资格；`Unknown` 必须按拒绝处理。
    pub sign_out_eligibility: ActionEligibility,
    /// 当前已选课程的退选资格；目标始终是内层课程标识。
    pub deselect_eligibility: ActionEligibility,
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

/// 博雅签到预检确认摘要。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcSignPreflight {
    pub course_id: i64,
    pub course_name: String,
    pub sign_type: i32,
    pub window_start: String,
    pub window_end: String,
    pub location_requirement: BykcSignLocationRequirement,
}

/// 博雅签到本次提交使用的位置来源。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BykcSignLocationRequirement {
    /// Core 将从上游给出的签到范围生成本次坐标。
    ConfiguredRange,
    /// 上游完整签到点列表不能保证每次都可生成坐标，调用方已提供安全回退坐标。
    ProvidedCoordinates,
}
