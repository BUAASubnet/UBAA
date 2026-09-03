//! Core 读取 DTO 的最小、稳定 FRB 投影。
//!
//! 这里的类型刻意不复用 Core DTO，避免把协议内部字段或未来新增字段自动
//! 暴露给 Dart。每个方法都携带 Core 已解析的路线决策。
#![allow(
    clippy::missing_errors_doc,
    clippy::needless_pass_by_value,
    clippy::similar_names
)]

mod mappers;
mod methods;

use super::client::BridgeRouteDecision;

pub(crate) use mappers::map_cgyy_order;

macro_rules! routed {
    ($name:ident, $data:ty) => {
        #[derive(Clone, Debug)]
        pub struct $name {
            pub data: $data,
            pub route: BridgeRouteDecision,
        }
    };
}

#[derive(Clone, Debug)]
pub struct BridgeTerm {
    pub item_code: String,
    pub item_name: String,
    pub selected: bool,
    pub item_index: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeWeek {
    pub start_date: String,
    pub end_date: String,
    pub term: String,
    pub cur_week: bool,
    pub serial_number: i32,
    pub name: String,
}
#[derive(Clone, Debug)]
pub struct BridgeCourseClass {
    pub course_code: String,
    pub course_name: String,
    pub course_serial_no: Option<String>,
    pub credit: Option<String>,
    pub begin_time: Option<String>,
    pub end_time: Option<String>,
    pub begin_section: Option<i32>,
    pub end_section: Option<i32>,
    pub place_name: Option<String>,
    pub weeks_and_teachers: Option<String>,
    pub teaching_target: Option<String>,
    pub color: Option<String>,
    pub day_of_week: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeWeeklySchedule {
    pub arranged_list: Vec<BridgeCourseClass>,
    pub code: String,
    pub name: String,
}
#[derive(Clone, Debug)]
pub struct BridgeTodayClass {
    pub biz_name: String,
    pub place: Option<String>,
    pub time: Option<String>,
    pub short_name: Option<String>,
}
#[derive(Clone, Debug)]
pub struct BridgeExam {
    pub course_name: String,
    pub course_no: Option<String>,
    pub exam_time_description: Option<String>,
    pub exam_date: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub exam_place: Option<String>,
    pub exam_seat_no: Option<String>,
    pub week: Option<i32>,
    pub exam_status: Option<i32>,
    pub exam_type: Option<String>,
    pub task_id: Option<String>,
}
#[derive(Clone, Debug)]
pub struct BridgeExamArrangement {
    pub arranged: Vec<BridgeExam>,
    pub not_arranged: Vec<BridgeExam>,
}
#[derive(Clone, Debug)]
pub struct BridgeGrade {
    pub course_name: Option<String>,
    pub course_code: Option<String>,
    pub credit: Option<f64>,
    pub score: Option<String>,
    pub grade_point: Option<String>,
    pub course_type: Option<String>,
    pub score_type: Option<String>,
    pub term_code: Option<String>,
}
#[derive(Clone, Debug)]
pub struct BridgeGradeData {
    pub term_code: String,
    pub grades: Vec<BridgeGrade>,
}
#[derive(Clone, Debug)]
pub struct BridgeClassroomInfo {
    pub id: String,
    pub floor_id: String,
    pub name: String,
    pub available_sections: String,
}
#[derive(Clone, Debug)]
pub struct BridgeClassroomFloor {
    pub name: String,
    pub rooms: Vec<BridgeClassroomInfo>,
}
#[derive(Clone, Debug)]
pub struct BridgeClassroomQuery {
    pub code: i32,
    pub message: String,
    pub floors: Vec<BridgeClassroomFloor>,
}
#[derive(Clone, Debug)]
pub struct BridgeSigninClass {
    pub course_id: String,
    pub course_name: String,
    pub class_begin_time: String,
    pub class_end_time: String,
    pub sign_status: i32,
}

#[derive(Clone, Copy, Debug)]
pub enum BridgeSpocSubmissionStatus {
    Submitted,
    Unsubmitted,
    Unknown,
}
#[derive(Clone, Debug)]
pub struct BridgeSpocAssignmentSummary {
    pub assignment_id: String,
    pub course_id: String,
    pub course_name: String,
    pub teacher_name: Option<String>,
    pub title: String,
    pub start_time: Option<String>,
    pub due_time: Option<String>,
    pub score: Option<String>,
    pub submission_status: BridgeSpocSubmissionStatus,
    pub submission_status_text: String,
}
#[derive(Clone, Debug)]
pub struct BridgeSpocAssignments {
    pub term_code: String,
    pub term_name: Option<String>,
    pub assignments: Vec<BridgeSpocAssignmentSummary>,
}
#[derive(Clone, Debug)]
pub struct BridgeSpocAssignmentDetail {
    pub assignment_id: String,
    pub course_id: String,
    pub course_name: String,
    pub teacher_name: Option<String>,
    pub title: String,
    pub start_time: Option<String>,
    pub due_time: Option<String>,
    pub score: Option<String>,
    pub submission_status: BridgeSpocSubmissionStatus,
    pub submission_status_text: String,
    pub content_plain_text: Option<String>,
    pub submitted_at: Option<String>,
}

#[derive(Clone, Copy, Debug)]
pub enum BridgeJudgeSubmissionStatus {
    Submitted,
    Partial,
    Unsubmitted,
    Unknown,
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeAssignmentSummary {
    pub course_id: String,
    pub course_name: String,
    pub assignment_id: String,
    pub title: String,
    pub start_time: Option<String>,
    pub due_time: Option<String>,
    pub max_score: Option<String>,
    pub my_score: Option<String>,
    pub total_problems: i32,
    pub submitted_count: i32,
    pub submission_status: BridgeJudgeSubmissionStatus,
    pub submission_status_text: String,
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeAssignmentKey {
    pub course_id: String,
    pub assignment_id: String,
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeProblem {
    pub name: String,
    pub score: Option<String>,
    pub max_score: Option<String>,
    pub status: BridgeJudgeSubmissionStatus,
    pub status_text: String,
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeAssignmentDetail {
    pub course_id: String,
    pub course_name: String,
    pub assignment_id: String,
    pub title: String,
    pub start_time: Option<String>,
    pub due_time: Option<String>,
    pub max_score: Option<String>,
    pub my_score: Option<String>,
    pub total_problems: i32,
    pub submitted_count: i32,
    pub submission_status: BridgeJudgeSubmissionStatus,
    pub submission_status_text: String,
    pub problems: Vec<BridgeJudgeProblem>,
    pub content_plain_text: Option<String>,
}

#[derive(Clone, Debug)]
pub struct BridgeBykcUserProfile {
    pub id: i64,
    pub employee_id: Option<String>,
    pub real_name: Option<String>,
    pub student_no: Option<String>,
    pub college_name: Option<String>,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBykcCourseStatus {
    Expired,
    Selected,
    Preview,
    Ended,
    Full,
    Available,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeActionEligibility {
    Allowed,
    Denied,
    Unknown,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcCourse {
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
    pub status: BridgeBykcCourseStatus,
    pub selected: Option<bool>,
    pub select_eligibility: BridgeActionEligibility,
    pub deselect_eligibility: BridgeActionEligibility,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcCoursePage {
    pub content: Vec<BridgeBykcCourse>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBykcCourseCategory {
    Boya,
    Unknown,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBykcCourseSubCategory {
    Moral,
    Aesthetic,
    Labor,
    SafetyHealth,
    Other,
    Unknown,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcSignPoint {
    pub lat: f64,
    pub lng: f64,
    pub radius: f64,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcSignConfig {
    pub sign_start_date: Option<String>,
    pub sign_end_date: Option<String>,
    pub sign_out_start_date: Option<String>,
    pub sign_out_end_date: Option<String>,
    pub sign_points: Vec<BridgeBykcSignPoint>,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcChosenCourse {
    pub id: i64,
    pub course_id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub select_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub category: Option<BridgeBykcCourseCategory>,
    pub sub_category: Option<BridgeBykcCourseSubCategory>,
    pub checkin: i32,
    pub score: Option<i32>,
    pub pass: Option<i32>,
    pub can_sign: bool,
    pub can_sign_out: bool,
    pub deselect_eligibility: BridgeActionEligibility,
    pub sign_config: Option<BridgeBykcSignConfig>,
    pub course_sign_type: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcStatistic {
    pub category_name: Option<String>,
    pub sub_category_name: Option<String>,
    pub required_count: Option<i32>,
    pub passed_count: Option<i32>,
    pub qualified: Option<bool>,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcStatistics {
    pub total_valid_count: Option<i32>,
    pub categories: Vec<BridgeBykcStatistic>,
}

#[derive(Clone, Debug)]
pub struct BridgeLibBookLibrary {
    pub id: String,
    pub name: String,
    pub free_num: i32,
    pub total_num: i32,
    pub storeys: Vec<BridgeLibBookStorey>,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookStorey {
    pub id: String,
    pub name: String,
    pub free_num: i32,
    pub total_num: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookArea {
    pub id: String,
    pub name: String,
    pub area_name: String,
    pub premises_id: String,
    pub storey_id: String,
    pub free_num: i32,
    pub total_num: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookTimeSlot {
    pub id: String,
    pub start: String,
    pub end: String,
    pub label: String,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookAreaDetail {
    pub id: String,
    pub name: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<BridgeLibBookTimeSlot>,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookSeat {
    pub id: String,
    pub name: String,
    pub no: String,
    pub status: String,
    pub status_name: String,
    pub is_available: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookBooking {
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
#[derive(Clone, Debug)]
pub struct BridgeLibBookBookingsPage {
    pub bookings: Vec<BridgeLibBookBooking>,
    pub page: i32,
    pub limit: i32,
    pub total: i32,
}

#[derive(Clone, Debug)]
pub struct BridgeYgdkItem {
    pub item_id: i32,
    pub name: String,
    pub kind: Option<i32>,
    pub sort: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeYgdkTermSummary {
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
#[derive(Clone, Debug)]
pub struct BridgeYgdkOverview {
    pub summary: BridgeYgdkTermSummary,
    pub classify_id: i32,
    pub classify_name: String,
    pub default_item_id: i32,
    pub default_item_name: String,
    pub items: Vec<BridgeYgdkItem>,
}
#[derive(Clone, Debug)]
pub struct BridgeYgdkRecord {
    pub record_id: i32,
    pub item_id: Option<i32>,
    pub item_name: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub place: Option<String>,
    pub image_count: i32,
    pub is_open: bool,
    pub state: Option<i32>,
    pub created_at: Option<String>,
    pub created_at_label: Option<String>,
}
#[derive(Clone, Debug)]
pub struct BridgeYgdkRecordsPage {
    pub content: Vec<BridgeYgdkRecord>,
    pub total: i32,
    pub page: i32,
    pub size: i32,
    pub has_more: bool,
}

#[derive(Clone, Debug)]
pub struct BridgeCgyyVenueSite {
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
#[derive(Clone, Debug)]
pub struct BridgeCgyyPurposeType {
    pub key: i32,
    pub name: String,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeCgyyPurposeSource {
    Upstream,
    StaticFallback,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyPurposeTypes {
    pub items: Vec<BridgeCgyyPurposeType>,
    pub source: BridgeCgyyPurposeSource,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyTimeSlot {
    pub id: i32,
    pub begin_time: String,
    pub end_time: String,
    pub label: String,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyySlotStatus {
    pub time_id: i32,
    pub reservation_status: i32,
    pub is_reservable: bool,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyySpaceAvailability {
    pub space_id: i32,
    pub space_name: String,
    pub venue_site_id: i32,
    pub venue_space_group_id: Option<i32>,
    pub slots: Vec<BridgeCgyySlotStatus>,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyDayInfo {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<BridgeCgyyTimeSlot>,
    pub spaces: Vec<BridgeCgyySpaceAvailability>,
    pub reservation_total_num: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyOrder {
    pub id: i32,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub venue_space_name: Option<String>,
    pub campus_name: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
    pub order_status: Option<i32>,
    pub check_status: Option<i32>,
    pub theme: Option<String>,
    pub purpose_type_name: Option<String>,
    pub joiner_num: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyOrdersPage {
    pub content: Vec<BridgeCgyyOrder>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyLockCode {
    pub available: bool,
}

#[derive(Clone, Debug)]
pub struct BridgeEvaluationCourse {
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
#[derive(Clone, Debug)]
pub struct BridgeEvaluationProgress {
    pub total_courses: i32,
    pub evaluated_courses: i32,
    pub pending_courses: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeEvaluationCoursesResponse {
    pub courses: Vec<BridgeEvaluationCourse>,
    pub progress: BridgeEvaluationProgress,
}

routed!(BridgeRoutedTerms, Vec<BridgeTerm>);
routed!(BridgeRoutedWeeks, Vec<BridgeWeek>);
routed!(BridgeRoutedWeeklySchedule, BridgeWeeklySchedule);
routed!(BridgeRoutedTodayClasses, Vec<BridgeTodayClass>);
routed!(BridgeRoutedExamArrangement, BridgeExamArrangement);
routed!(BridgeRoutedGrades, BridgeGradeData);
routed!(BridgeRoutedClassroomQuery, BridgeClassroomQuery);
routed!(BridgeRoutedSigninClasses, Vec<BridgeSigninClass>);
routed!(BridgeRoutedSpocAssignments, BridgeSpocAssignments);
routed!(BridgeRoutedSpocAssignmentDetail, BridgeSpocAssignmentDetail);
routed!(
    BridgeRoutedJudgeSummaries,
    Vec<BridgeJudgeAssignmentSummary>
);
routed!(
    BridgeRoutedJudgeAssignmentDetail,
    BridgeJudgeAssignmentDetail
);
routed!(
    BridgeRoutedJudgeAssignmentDetails,
    Vec<BridgeJudgeAssignmentDetail>
);
routed!(BridgeRoutedBykcProfile, BridgeBykcUserProfile);
routed!(BridgeRoutedBykcCourses, BridgeBykcCoursePage);
routed!(BridgeRoutedBykcCourse, BridgeBykcCourse);
routed!(BridgeRoutedBykcChosenCourses, Vec<BridgeBykcChosenCourse>);
routed!(BridgeRoutedBykcStatistics, BridgeBykcStatistics);
routed!(BridgeRoutedLibBookLibraries, Vec<BridgeLibBookLibrary>);
routed!(BridgeRoutedLibBookAreas, Vec<BridgeLibBookArea>);
routed!(BridgeRoutedLibBookAreaDetail, BridgeLibBookAreaDetail);
routed!(BridgeRoutedLibBookSeats, Vec<BridgeLibBookSeat>);
routed!(BridgeRoutedLibBookBookings, BridgeLibBookBookingsPage);
routed!(BridgeRoutedYgdkOverview, BridgeYgdkOverview);
routed!(BridgeRoutedYgdkRecords, BridgeYgdkRecordsPage);
routed!(BridgeRoutedCgyySites, Vec<BridgeCgyyVenueSite>);
routed!(BridgeRoutedCgyyPurposeTypes, BridgeCgyyPurposeTypes);
routed!(BridgeRoutedCgyyDayInfo, BridgeCgyyDayInfo);
routed!(BridgeRoutedCgyyOrders, BridgeCgyyOrdersPage);
routed!(BridgeRoutedCgyyOrder, BridgeCgyyOrder);
routed!(BridgeRoutedCgyyLockCode, BridgeCgyyLockCode);
routed!(BridgeRoutedEvaluation, BridgeEvaluationCoursesResponse);
