//! Core facade 与宿主绑定共享的稳定领域值。

use std::fmt;

use serde::{Deserialize, Serialize, Serializer};

/// 客户端所有请求使用的网络路线。
#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionMode {
    /// Reach upstream services directly.
    Direct,
    /// 通过北航 `WebVPN` 网关访问上游服务。
    WebVpn,
}

/// 用户可选择的路线策略。`Auto` 在 Core 内部解析，宿主无需选择具体连接模式。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RoutePolicy {
    /// 根据当前校园网关可达性信号和功能矩阵解析。
    #[default]
    Auto,
    /// 使用上游直连路线。
    Direct,
    /// 使用北航 `WebVPN` 网关路线。
    WebVpn,
}

/// 注册到路由矩阵中的只读功能名称。
#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ReadonlyFeature {
    /// 博雅课程只读查询。
    Bykc,
    /// 场馆预约只读查询。
    Cgyy,
    /// 图书馆座位只读查询。
    LibBook,
    /// 阳光打卡只读查询。
    Ygdk,
    /// 课堂签到状态查询。
    Signin,
    /// Schedule and teaching-week operations.
    Schedule,
    /// 考试安排。
    Exam,
    /// 成绩列表操作。
    Grades,
    /// Empty classroom search.
    Classroom,
    /// SPOC assignment queries.
    Spoc,
    /// Judge assignment queries.
    Judge,
}

impl ReadonlyFeature {
    /// 稳定的配置键。
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Bykc => "bykc",
            Self::Cgyy => "cgyy",
            Self::LibBook => "libbook",
            Self::Ygdk => "ygdk",
            Self::Signin => "signin",
            Self::Schedule => "schedule",
            Self::Exam => "exam",
            Self::Grades => "grades",
            Self::Classroom => "classroom",
            Self::Spoc => "spoc",
            Self::Judge => "judge",
        }
    }
}

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
    pub course_max_count: Option<i32>,
    pub course_current_count: Option<i32>,
    pub selected: Option<bool>,
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
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BykcChosenCourse {
    pub id: i64,
    pub course_id: Option<i64>,
    pub course_name: Option<String>,
    pub select_date: Option<String>,
    pub checkin: Option<i32>,
    pub score: Option<i32>,
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

/// SPOC submission status.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SpocSubmissionStatus {
    /// Submitted.
    Submitted,
    /// Not submitted.
    Unsubmitted,
    /// Unknown upstream status.
    #[default]
    Unknown,
}

/// SPOC assignment summary.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentSummary {
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
}

/// SPOC assignment list.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignments {
    /// Current term code.
    pub term_code: String,
    /// Current term name.
    pub term_name: Option<String>,
    /// Assignments.
    pub assignments: Vec<SpocAssignmentSummary>,
}

/// Safe completion evidence for one SPOC global-list operation.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpocAssignmentsDiagnostics {
    /// Number of authoritative global assignment pages parsed successfully.
    pub global_page_count: u32,
    /// The ordinary stable assignment-list result.
    pub result: SpocAssignments,
}

/// SPOC assignment detail.
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
    /// Plain text description.
    pub content_plain_text: Option<String>,
    /// Submission time.
    pub submitted_at: Option<String>,
}

/// Judge submission status.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum JudgeSubmissionStatus {
    /// Fully submitted.
    Submitted,
    /// Partially submitted.
    Partial,
    /// Not submitted.
    Unsubmitted,
    /// Unknown state.
    #[default]
    Unknown,
}

/// Judge assignment summary.
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
    /// Maximum score.
    pub max_score: Option<String>,
    /// User score.
    pub my_score: Option<String>,
    /// Number of problems.
    pub total_problems: i32,
    /// Number submitted.
    pub submitted_count: i32,
    /// Submission state.
    pub submission_status: JudgeSubmissionStatus,
    /// Safe status text.
    pub submission_status_text: String,
}

/// Safe parser diagnostics for one Judge list operation.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentsDiagnostics {
    /// Number of parsed courses before historical-course skipping.
    pub course_count: usize,
    /// Numeric assignment anchors seen before filtering and deduplication.
    pub raw_anchor_count: usize,
    /// Nonblank unique assignments retained after parser filtering.
    pub filtered_unique_count: usize,
    /// The ordinary Judge summaries after applying `include_expired`.
    pub summaries: Vec<JudgeAssignmentSummary>,
}

/// Judge assignment detail key.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeAssignmentKey {
    /// Course ID.
    pub course_id: String,
    /// Assignment ID.
    pub assignment_id: String,
}

/// Judge problem detail.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JudgeProblem {
    /// Problem name.
    pub name: String,
    /// Earned score.
    pub score: Option<String>,
    /// Maximum score.
    pub max_score: Option<String>,
    /// Submission state.
    pub status: JudgeSubmissionStatus,
    /// Safe status text.
    pub status_text: String,
}

/// Judge assignment detail.
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
    /// User score.
    pub my_score: Option<String>,
    /// Number of problems.
    pub total_problems: i32,
    /// Number submitted.
    pub submitted_count: i32,
    /// Submission state.
    pub submission_status: JudgeSubmissionStatus,
    /// Safe status text.
    pub submission_status_text: String,
    /// Parsed problem list.
    pub problems: Vec<JudgeProblem>,
    /// Plain text HTML content.
    pub content_plain_text: Option<String>,
}

/// Result of a read-only operation with the concrete route used internally.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FeatureResult<T> {
    /// Parsed, stable DTO.
    pub data: T,
    /// Concrete route used for this request.
    pub resolved_route: ConnectionMode,
}

/// A value that redacts its contents in all ordinary formatting and serialization.
#[derive(Clone, Eq, PartialEq)]
pub struct SecretValue(String);

impl SecretValue {
    /// Wrap a secret without exposing it through formatting traits.
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// Explicitly borrow the secret for the narrow scope of an upstream request.
    #[must_use]
    pub fn expose_secret(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SecretValue([REDACTED])")
    }
}

impl fmt::Display for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("[REDACTED]")
    }
}

impl Serialize for SecretValue {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str("[REDACTED]")
    }
}

/// Credentials for one login submission.
#[derive(Clone)]
pub struct LoginInput {
    /// SSO account name.
    pub username: String,
    /// SSO password, always redacted outside the request boundary.
    pub password: SecretValue,
}

impl fmt::Debug for LoginInput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LoginInput")
            .field("username", &"[REDACTED]")
            .field("password", &self.password)
            .finish()
    }
}

/// Login readiness across the two independent route sessions.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LoginReadiness {
    /// Both routes are ready.
    AllReady,
    /// Exactly one route is ready.
    Partial,
    /// Neither route is ready.
    NoneReady,
}

/// Safe state for one route during an aggregate login.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RouteLoginState {
    /// The route has an authenticated session.
    Ready,
    /// The route failed without exposing protocol details.
    Failed,
}

/// Public, non-sensitive error projection for aggregate authentication.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SafeError {
    /// Stable machine error code.
    pub code: String,
    /// Stable error category.
    pub kind: String,
    /// Whether retrying may succeed.
    pub retryable: bool,
    /// Safe human-facing message.
    pub message: String,
}

/// Result for one route in an aggregate login operation.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteLoginResult {
    /// Concrete route attempted.
    pub route: ConnectionMode,
    /// Safe route state.
    pub state: RouteLoginState,
    /// Sanitized failure, when the route was not ready.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<SafeError>,
}

/// Aggregate login result with fixed Direct, `WebVPN` route ordering.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginOutcome {
    /// Aggregate readiness.
    pub readiness: LoginReadiness,
    /// Exactly two route entries, Direct then `WebVPN`.
    pub routes: [RouteLoginResult; 2],
    /// Profile from any successfully authenticated route.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile: Option<UserProfile>,
}

/// Result of preparing both route login pages.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DualLoginPreparation {
    /// Fixed Direct, `WebVPN` state ordering.
    pub routes: [RouteLoginResult; 2],
}

/// Credentials for aggregate login.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DualLoginInput {
    /// SSO account name shared by both route attempts.
    pub username: String,
    /// Password held only in memory for this operation.
    pub password: SecretValue,
}

impl fmt::Debug for DualLoginInput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DualLoginInput")
            .field("username", &"[REDACTED]")
            .field("password", &self.password)
            .finish()
    }
}

/// User Center profile mapped from the legacy `UserInfo` DTO.
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserProfile {
    /// Identity-document type code.
    pub id_card_type: Option<String>,
    /// Human-readable identity-document type.
    pub id_card_type_name: Option<String>,
    /// Phone value as returned by User Center.
    pub phone: Option<String>,
    /// School identifier. The upstream field is spelled `schoolid`.
    #[serde(alias = "schoolid")]
    pub school_id: Option<String>,
    /// Display name.
    pub name: Option<String>,
    /// Identity-document number.
    pub id_card_number: Option<String>,
    /// Email address.
    pub email: Option<String>,
    /// User Center account name.
    pub username: Option<String>,
}

impl fmt::Debug for UserProfile {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserProfile")
            .field(
                "id_card_type",
                &redacted_option(self.id_card_type.as_deref()),
            )
            .field(
                "id_card_type_name",
                &redacted_option(self.id_card_type_name.as_deref()),
            )
            .field("phone", &redacted_option(self.phone.as_deref()))
            .field("school_id", &redacted_option(self.school_id.as_deref()))
            .field("name", &redacted_option(self.name.as_deref()))
            .field(
                "id_card_number",
                &redacted_option(self.id_card_number.as_deref()),
            )
            .field("email", &redacted_option(self.email.as_deref()))
            .field("username", &redacted_option(self.username.as_deref()))
            .finish()
    }
}

/// User Center JSON wrapper used by both status and profile endpoints.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct UserInfoResponse {
    /// Upstream result code; zero denotes success in the frozen implementation.
    pub code: i64,
    /// Optional profile payload.
    pub data: Option<UserProfile>,
}

/// Validated authentication state returned to hosts.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatus {
    /// User Center identity summary.
    pub user: UserProfile,
    /// Unix timestamp when the current session was authenticated.
    pub authenticated_at: i64,
    /// Unix timestamp of the latest successful status check.
    pub last_activity: i64,
}

impl fmt::Debug for UserInfoResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserInfoResponse")
            .field("code", &self.code)
            .field("data_present", &self.data.is_some())
            .finish()
    }
}

impl fmt::Debug for AuthStatus {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AuthStatus")
            .field("user", &self.user)
            .field("authenticated_at", &self.authenticated_at)
            .field("last_activity", &self.last_activity)
            .finish()
    }
}

fn redacted_option(value: Option<&str>) -> Option<&'static str> {
    value.map(|_| "[REDACTED]")
}
