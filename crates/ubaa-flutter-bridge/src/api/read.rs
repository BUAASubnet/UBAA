//! Core 读取 DTO 的最小、稳定 FRB 投影。
//!
//! 这里的类型刻意不复用 Core DTO，避免把协议内部字段或未来新增字段自动
//! 暴露给 Dart。每个方法都携带 Core 已解析的路线决策。
#![allow(
    clippy::missing_errors_doc,
    clippy::needless_pass_by_value,
    clippy::similar_names
)]

use std::future::Future;
use std::pin::Pin;

use ubaa_core::domain;
use ubaa_core::facade::{RoutedResult, UbaaClient};

use super::client::{BridgeClient, BridgeError, BridgeRouteDecision, catch_panic, map_route};

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
    pub sign_config: Option<BridgeBykcSignConfig>,
    pub course_sign_type: Option<i32>,
    pub homework: Option<String>,
    pub homework_attachment_name: Option<String>,
    pub homework_attachment_path: Option<String>,
    pub sign_info: Option<String>,
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
    pub images: Vec<String>,
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
    pub trade_no: Option<String>,
    pub order_id: Option<i32>,
    pub use_num: Option<i32>,
    pub already_num: Option<i32>,
    pub take_up: Option<bool>,
    pub take_up_explain: Option<String>,
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

impl BridgeClient {
    async fn execute_read<T, O, F>(
        &self,
        call: F,
        mapper: fn(T) -> O,
    ) -> Result<(O, BridgeRouteDecision), BridgeError>
    where
        F: for<'a> FnOnce(
            &'a mut UbaaClient,
        ) -> Pin<Box<dyn Future<Output = RoutedResult<T>> + Send + 'a>>,
    {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(super::client::disposed_error)?;
            let routed = call(client).await.map_err(BridgeError::from_routed)?;
            Ok((mapper(routed.data), map_route(routed.resolution)))
        })
        .await
    }

    pub async fn schedule_terms(&self) -> Result<BridgeRoutedTerms, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.schedule_terms().await }),
                map_terms,
            )
            .await?;
        Ok(BridgeRoutedTerms { data, route })
    }
    pub async fn schedule_weeks(&self, term: String) -> Result<BridgeRoutedWeeks, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.schedule_weeks(&term).await }),
                map_weeks,
            )
            .await?;
        Ok(BridgeRoutedWeeks { data, route })
    }
    pub async fn schedule_week(
        &self,
        term: String,
        week: i32,
    ) -> Result<BridgeRoutedWeeklySchedule, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.schedule_week(&term, week).await }),
                map_weekly_schedule,
            )
            .await?;
        Ok(BridgeRoutedWeeklySchedule { data, route })
    }
    pub async fn schedule_today(&self) -> Result<BridgeRoutedTodayClasses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.schedule_today().await }),
                map_today_classes,
            )
            .await?;
        Ok(BridgeRoutedTodayClasses { data, route })
    }
    pub async fn exam_arrangement(
        &self,
        term: String,
    ) -> Result<BridgeRoutedExamArrangement, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.exam_arrangement(&term).await }),
                map_exam_arrangement,
            )
            .await?;
        Ok(BridgeRoutedExamArrangement { data, route })
    }
    pub async fn grades(&self, term: String) -> Result<BridgeRoutedGrades, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.grades(&term).await }),
                map_grade_data,
            )
            .await?;
        Ok(BridgeRoutedGrades { data, route })
    }
    pub async fn classroom_search(
        &self,
        campus: i32,
        date: String,
    ) -> Result<BridgeRoutedClassroomQuery, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.classroom_search(campus, &date).await }),
                map_classroom_query,
            )
            .await?;
        Ok(BridgeRoutedClassroomQuery { data, route })
    }
    pub async fn signin_today(&self) -> Result<BridgeRoutedSigninClasses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.signin_today().await }),
                map_signin_classes,
            )
            .await?;
        Ok(BridgeRoutedSigninClasses { data, route })
    }
    pub async fn spoc_assignments(&self) -> Result<BridgeRoutedSpocAssignments, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.spoc_assignments().await }),
                map_spoc_assignments,
            )
            .await?;
        Ok(BridgeRoutedSpocAssignments { data, route })
    }
    pub async fn spoc_assignment(
        &self,
        assignment_id: String,
    ) -> Result<BridgeRoutedSpocAssignmentDetail, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.spoc_assignment(&assignment_id).await }),
                map_spoc_detail,
            )
            .await?;
        Ok(BridgeRoutedSpocAssignmentDetail { data, route })
    }
    pub async fn judge_assignments(
        &self,
        include_expired: bool,
    ) -> Result<BridgeRoutedJudgeSummaries, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.judge_assignments(include_expired).await }),
                map_judge_summaries,
            )
            .await?;
        Ok(BridgeRoutedJudgeSummaries { data, route })
    }
    pub async fn judge_assignment(
        &self,
        course_id: String,
        assignment_id: String,
    ) -> Result<BridgeRoutedJudgeAssignmentDetail, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| {
                    Box::pin(
                        async move { client.judge_assignment(&course_id, &assignment_id).await },
                    )
                },
                map_judge_detail,
            )
            .await?;
        Ok(BridgeRoutedJudgeAssignmentDetail { data, route })
    }
    pub async fn judge_assignment_details(
        &self,
        keys: Vec<BridgeJudgeAssignmentKey>,
    ) -> Result<BridgeRoutedJudgeAssignmentDetails, BridgeError> {
        let keys = keys
            .into_iter()
            .map(|key| domain::JudgeAssignmentKey {
                course_id: key.course_id,
                assignment_id: key.assignment_id,
            })
            .collect::<Vec<_>>();
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.judge_assignment_details(&keys).await }),
                map_judge_details,
            )
            .await?;
        Ok(BridgeRoutedJudgeAssignmentDetails { data, route })
    }
    pub async fn bykc_profile(&self) -> Result<BridgeRoutedBykcProfile, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_profile().await }),
                map_bykc_profile,
            )
            .await?;
        Ok(BridgeRoutedBykcProfile { data, route })
    }
    pub async fn bykc_courses(
        &self,
        page: i32,
        size: i32,
        all: bool,
    ) -> Result<BridgeRoutedBykcCourses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_courses(page, size, all).await }),
                map_bykc_course_page,
            )
            .await?;
        Ok(BridgeRoutedBykcCourses { data, route })
    }
    pub async fn bykc_course_detail(&self, id: i64) -> Result<BridgeRoutedBykcCourse, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_course_detail(id).await }),
                map_bykc_course,
            )
            .await?;
        Ok(BridgeRoutedBykcCourse { data, route })
    }
    pub async fn bykc_chosen_courses(&self) -> Result<BridgeRoutedBykcChosenCourses, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_chosen_courses().await }),
                map_bykc_chosen_courses,
            )
            .await?;
        Ok(BridgeRoutedBykcChosenCourses { data, route })
    }
    pub async fn bykc_statistics(&self) -> Result<BridgeRoutedBykcStatistics, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.bykc_statistics().await }),
                map_bykc_statistics,
            )
            .await?;
        Ok(BridgeRoutedBykcStatistics { data, route })
    }
    pub async fn libbook_libraries(
        &self,
        day: String,
    ) -> Result<BridgeRoutedLibBookLibraries, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.libbook_libraries(&day).await }),
                map_libbook_libraries,
            )
            .await?;
        Ok(BridgeRoutedLibBookLibraries { data, route })
    }
    pub async fn libbook_areas(
        &self,
        premises_id: String,
        storey_id: Option<String>,
        day: String,
    ) -> Result<BridgeRoutedLibBookAreas, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| {
                    Box::pin(async move {
                        client
                            .libbook_areas(&premises_id, storey_id.as_deref(), &day)
                            .await
                    })
                },
                map_libbook_areas,
            )
            .await?;
        Ok(BridgeRoutedLibBookAreas { data, route })
    }
    pub async fn libbook_area_detail(
        &self,
        area_id: String,
    ) -> Result<BridgeRoutedLibBookAreaDetail, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.libbook_area_detail(&area_id).await }),
                map_libbook_area_detail,
            )
            .await?;
        Ok(BridgeRoutedLibBookAreaDetail { data, route })
    }
    pub async fn libbook_seats(
        &self,
        area_id: String,
        day: String,
        start_time: String,
        end_time: String,
    ) -> Result<BridgeRoutedLibBookSeats, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| {
                    Box::pin(async move {
                        client
                            .libbook_seats(&area_id, &day, &start_time, &end_time)
                            .await
                    })
                },
                map_libbook_seats,
            )
            .await?;
        Ok(BridgeRoutedLibBookSeats { data, route })
    }
    pub async fn libbook_bookings(
        &self,
        page: i32,
        limit: i32,
    ) -> Result<BridgeRoutedLibBookBookings, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.libbook_bookings(page, limit).await }),
                map_libbook_bookings,
            )
            .await?;
        Ok(BridgeRoutedLibBookBookings { data, route })
    }
    pub async fn ygdk_overview(&self) -> Result<BridgeRoutedYgdkOverview, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.ygdk_overview().await }),
                map_ygdk_overview,
            )
            .await?;
        Ok(BridgeRoutedYgdkOverview { data, route })
    }
    pub async fn ygdk_records(
        &self,
        page: i32,
        size: i32,
    ) -> Result<BridgeRoutedYgdkRecords, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.ygdk_records(page, size).await }),
                map_ygdk_records,
            )
            .await?;
        Ok(BridgeRoutedYgdkRecords { data, route })
    }
    pub async fn cgyy_sites(&self) -> Result<BridgeRoutedCgyySites, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_sites().await }),
                map_cgyy_sites,
            )
            .await?;
        Ok(BridgeRoutedCgyySites { data, route })
    }
    pub async fn cgyy_purpose_types(&self) -> Result<BridgeRoutedCgyyPurposeTypes, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_purpose_types_diagnostics().await }),
                map_cgyy_purpose_types,
            )
            .await?;
        Ok(BridgeRoutedCgyyPurposeTypes { data, route })
    }
    pub async fn cgyy_day_info(
        &self,
        site_id: i32,
        date: String,
    ) -> Result<BridgeRoutedCgyyDayInfo, BridgeError> {
        let (data, route) = self
            .execute_read(
                move |client| Box::pin(async move { client.cgyy_day_info(site_id, &date).await }),
                map_cgyy_day_info,
            )
            .await?;
        Ok(BridgeRoutedCgyyDayInfo { data, route })
    }
    pub async fn cgyy_orders(
        &self,
        page: i32,
        size: i32,
    ) -> Result<BridgeRoutedCgyyOrders, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_orders(page, size).await }),
                map_cgyy_orders,
            )
            .await?;
        Ok(BridgeRoutedCgyyOrders { data, route })
    }
    pub async fn cgyy_order_detail(&self, id: i32) -> Result<BridgeRoutedCgyyOrder, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_order_detail(id).await }),
                map_cgyy_order,
            )
            .await?;
        Ok(BridgeRoutedCgyyOrder { data, route })
    }
    pub async fn cgyy_lock_code(&self) -> Result<BridgeRoutedCgyyLockCode, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.cgyy_lock_code().await }),
                map_cgyy_lock_code,
            )
            .await?;
        Ok(BridgeRoutedCgyyLockCode { data, route })
    }
    pub async fn evaluation_all(&self) -> Result<BridgeRoutedEvaluation, BridgeError> {
        let (data, route) = self
            .execute_read(
                |client| Box::pin(async move { client.evaluation_all().await }),
                map_evaluation,
            )
            .await?;
        Ok(BridgeRoutedEvaluation { data, route })
    }
}

// 转换函数保持显式字段清单；禁止使用 serde/json 反射把 Core DTO 整体透传。
fn map_terms(values: Vec<domain::Term>) -> Vec<BridgeTerm> {
    values
        .into_iter()
        .map(|v| BridgeTerm {
            item_code: v.item_code,
            item_name: v.item_name,
            selected: v.selected,
            item_index: v.item_index,
        })
        .collect()
}
fn map_weeks(values: Vec<domain::Week>) -> Vec<BridgeWeek> {
    values
        .into_iter()
        .map(|v| BridgeWeek {
            start_date: v.start_date,
            end_date: v.end_date,
            term: v.term,
            cur_week: v.cur_week,
            serial_number: v.serial_number,
            name: v.name,
        })
        .collect()
}
fn map_course(v: domain::CourseClass) -> BridgeCourseClass {
    BridgeCourseClass {
        course_code: v.course_code,
        course_name: v.course_name,
        course_serial_no: v.course_serial_no,
        credit: v.credit,
        begin_time: v.begin_time,
        end_time: v.end_time,
        begin_section: v.begin_section,
        end_section: v.end_section,
        place_name: v.place_name,
        weeks_and_teachers: v.weeks_and_teachers,
        teaching_target: v.teaching_target,
        color: v.color,
        day_of_week: v.day_of_week,
    }
}
fn map_weekly_schedule(v: domain::WeeklySchedule) -> BridgeWeeklySchedule {
    BridgeWeeklySchedule {
        arranged_list: v.arranged_list.into_iter().map(map_course).collect(),
        code: v.code,
        name: v.name,
    }
}
fn map_today_classes(values: Vec<domain::TodayClass>) -> Vec<BridgeTodayClass> {
    values
        .into_iter()
        .map(|v| BridgeTodayClass {
            biz_name: v.biz_name,
            place: v.place,
            time: v.time,
            short_name: v.short_name,
        })
        .collect()
}
fn map_exam(v: domain::Exam) -> BridgeExam {
    BridgeExam {
        course_name: v.course_name,
        course_no: v.course_no,
        exam_time_description: v.exam_time_description,
        exam_date: v.exam_date,
        start_time: v.start_time,
        end_time: v.end_time,
        exam_place: v.exam_place,
        exam_seat_no: v.exam_seat_no,
        week: v.week,
        exam_status: v.exam_status,
        exam_type: v.exam_type,
        task_id: v.task_id,
    }
}
fn map_exam_arrangement(v: domain::ExamArrangement) -> BridgeExamArrangement {
    BridgeExamArrangement {
        arranged: v.arranged.into_iter().map(map_exam).collect(),
        not_arranged: v.not_arranged.into_iter().map(map_exam).collect(),
    }
}
fn map_grade(v: domain::Grade) -> BridgeGrade {
    BridgeGrade {
        course_name: v.course_name,
        course_code: v.course_code,
        credit: v.credit,
        score: v.score,
        grade_point: v.grade_point,
        course_type: v.course_type,
        score_type: v.score_type,
        term_code: v.term_code,
    }
}
fn map_grade_data(v: domain::GradeData) -> BridgeGradeData {
    BridgeGradeData {
        term_code: v.term_code,
        grades: v.grades.into_iter().map(map_grade).collect(),
    }
}
fn map_classroom_query(v: domain::ClassroomQuery) -> BridgeClassroomQuery {
    BridgeClassroomQuery {
        code: v.code,
        message: v.message,
        floors: v
            .floors
            .into_iter()
            .map(|(name, rooms)| BridgeClassroomFloor {
                name,
                rooms: rooms
                    .into_iter()
                    .map(|r| BridgeClassroomInfo {
                        id: r.id,
                        floor_id: r.floor_id,
                        name: r.name,
                        available_sections: r.available_sections,
                    })
                    .collect(),
            })
            .collect(),
    }
}
fn map_signin_classes(values: Vec<domain::SigninClass>) -> Vec<BridgeSigninClass> {
    values
        .into_iter()
        .map(|v| BridgeSigninClass {
            course_id: v.course_id,
            course_name: v.course_name,
            class_begin_time: v.class_begin_time,
            class_end_time: v.class_end_time,
            sign_status: v.sign_status,
        })
        .collect()
}
fn map_spoc_status(v: domain::SpocSubmissionStatus) -> BridgeSpocSubmissionStatus {
    match v {
        domain::SpocSubmissionStatus::Submitted => BridgeSpocSubmissionStatus::Submitted,
        domain::SpocSubmissionStatus::Unsubmitted => BridgeSpocSubmissionStatus::Unsubmitted,
        domain::SpocSubmissionStatus::Unknown => BridgeSpocSubmissionStatus::Unknown,
    }
}
fn map_spoc_summary(v: domain::SpocAssignmentSummary) -> BridgeSpocAssignmentSummary {
    BridgeSpocAssignmentSummary {
        assignment_id: v.assignment_id,
        course_id: v.course_id,
        course_name: v.course_name,
        teacher_name: v.teacher_name,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        score: v.score,
        submission_status: map_spoc_status(v.submission_status),
        submission_status_text: v.submission_status_text,
    }
}
fn map_spoc_assignments(v: domain::SpocAssignments) -> BridgeSpocAssignments {
    BridgeSpocAssignments {
        term_code: v.term_code,
        term_name: v.term_name,
        assignments: v.assignments.into_iter().map(map_spoc_summary).collect(),
    }
}
fn map_spoc_detail(v: domain::SpocAssignmentDetail) -> BridgeSpocAssignmentDetail {
    BridgeSpocAssignmentDetail {
        assignment_id: v.assignment_id,
        course_id: v.course_id,
        course_name: v.course_name,
        teacher_name: v.teacher_name,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        score: v.score,
        submission_status: map_spoc_status(v.submission_status),
        submission_status_text: v.submission_status_text,
        content_plain_text: v.content_plain_text,
        submitted_at: v.submitted_at,
    }
}
fn map_judge_status(v: domain::JudgeSubmissionStatus) -> BridgeJudgeSubmissionStatus {
    match v {
        domain::JudgeSubmissionStatus::Submitted => BridgeJudgeSubmissionStatus::Submitted,
        domain::JudgeSubmissionStatus::Partial => BridgeJudgeSubmissionStatus::Partial,
        domain::JudgeSubmissionStatus::Unsubmitted => BridgeJudgeSubmissionStatus::Unsubmitted,
        domain::JudgeSubmissionStatus::Unknown => BridgeJudgeSubmissionStatus::Unknown,
    }
}
fn map_judge_summary(v: domain::JudgeAssignmentSummary) -> BridgeJudgeAssignmentSummary {
    BridgeJudgeAssignmentSummary {
        course_id: v.course_id,
        course_name: v.course_name,
        assignment_id: v.assignment_id,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        max_score: v.max_score,
        my_score: v.my_score,
        total_problems: v.total_problems,
        submitted_count: v.submitted_count,
        submission_status: map_judge_status(v.submission_status),
        submission_status_text: v.submission_status_text,
    }
}
fn map_judge_problem(v: domain::JudgeProblem) -> BridgeJudgeProblem {
    BridgeJudgeProblem {
        name: v.name,
        score: v.score,
        max_score: v.max_score,
        status: map_judge_status(v.status),
        status_text: v.status_text,
    }
}
fn map_judge_detail(v: domain::JudgeAssignmentDetail) -> BridgeJudgeAssignmentDetail {
    BridgeJudgeAssignmentDetail {
        course_id: v.course_id,
        course_name: v.course_name,
        assignment_id: v.assignment_id,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        max_score: v.max_score,
        my_score: v.my_score,
        total_problems: v.total_problems,
        submitted_count: v.submitted_count,
        submission_status: map_judge_status(v.submission_status),
        submission_status_text: v.submission_status_text,
        problems: v.problems.into_iter().map(map_judge_problem).collect(),
        content_plain_text: v.content_plain_text,
    }
}
fn map_judge_summaries(
    v: Vec<domain::JudgeAssignmentSummary>,
) -> Vec<BridgeJudgeAssignmentSummary> {
    v.into_iter().map(map_judge_summary).collect()
}
fn map_judge_details(v: Vec<domain::JudgeAssignmentDetail>) -> Vec<BridgeJudgeAssignmentDetail> {
    v.into_iter().map(map_judge_detail).collect()
}
fn map_bykc_status(v: domain::BykcCourseStatus) -> BridgeBykcCourseStatus {
    match v {
        domain::BykcCourseStatus::Expired => BridgeBykcCourseStatus::Expired,
        domain::BykcCourseStatus::Selected => BridgeBykcCourseStatus::Selected,
        domain::BykcCourseStatus::Preview => BridgeBykcCourseStatus::Preview,
        domain::BykcCourseStatus::Ended => BridgeBykcCourseStatus::Ended,
        domain::BykcCourseStatus::Full => BridgeBykcCourseStatus::Full,
        domain::BykcCourseStatus::Available => BridgeBykcCourseStatus::Available,
    }
}
fn map_bykc_course(v: domain::BykcCourse) -> BridgeBykcCourse {
    BridgeBykcCourse {
        id: v.id,
        course_name: v.course_name,
        course_position: v.course_position,
        course_teacher: v.course_teacher,
        course_start_date: v.course_start_date,
        course_end_date: v.course_end_date,
        course_select_start_date: v.course_select_start_date,
        course_select_end_date: v.course_select_end_date,
        course_cancel_end_date: v.course_cancel_end_date,
        course_max_count: v.course_max_count,
        course_current_count: v.course_current_count,
        status: map_bykc_status(v.status),
        selected: v.selected,
    }
}
fn map_bykc_profile(v: domain::BykcUserProfile) -> BridgeBykcUserProfile {
    BridgeBykcUserProfile {
        id: v.id,
        employee_id: v.employee_id,
        real_name: v.real_name,
        student_no: v.student_no,
        college_name: v.college_name,
    }
}
fn map_bykc_course_page(v: domain::BykcCoursePage) -> BridgeBykcCoursePage {
    BridgeBykcCoursePage {
        content: v.content.into_iter().map(map_bykc_course).collect(),
        total_elements: v.total_elements,
        total_pages: v.total_pages,
        size: v.size,
        number: v.number,
    }
}
fn map_bykc_category(v: domain::BykcCourseCategory) -> BridgeBykcCourseCategory {
    match v {
        domain::BykcCourseCategory::Boya => BridgeBykcCourseCategory::Boya,
        domain::BykcCourseCategory::Unknown => BridgeBykcCourseCategory::Unknown,
    }
}
fn map_bykc_subcategory(v: domain::BykcCourseSubCategory) -> BridgeBykcCourseSubCategory {
    match v {
        domain::BykcCourseSubCategory::Moral => BridgeBykcCourseSubCategory::Moral,
        domain::BykcCourseSubCategory::Aesthetic => BridgeBykcCourseSubCategory::Aesthetic,
        domain::BykcCourseSubCategory::Labor => BridgeBykcCourseSubCategory::Labor,
        domain::BykcCourseSubCategory::SafetyHealth => BridgeBykcCourseSubCategory::SafetyHealth,
        domain::BykcCourseSubCategory::Other => BridgeBykcCourseSubCategory::Other,
        domain::BykcCourseSubCategory::Unknown => BridgeBykcCourseSubCategory::Unknown,
    }
}
fn map_bykc_sign_config(v: domain::BykcSignConfig) -> BridgeBykcSignConfig {
    BridgeBykcSignConfig {
        sign_start_date: v.sign_start_date,
        sign_end_date: v.sign_end_date,
        sign_out_start_date: v.sign_out_start_date,
        sign_out_end_date: v.sign_out_end_date,
        sign_points: v
            .sign_points
            .into_iter()
            .map(|p| BridgeBykcSignPoint {
                lat: p.lat,
                lng: p.lng,
                radius: p.radius,
            })
            .collect(),
    }
}
fn map_bykc_chosen(v: domain::BykcChosenCourse) -> BridgeBykcChosenCourse {
    BridgeBykcChosenCourse {
        id: v.id,
        course_id: v.course_id,
        course_name: v.course_name,
        course_position: v.course_position,
        course_teacher: v.course_teacher,
        course_start_date: v.course_start_date,
        course_end_date: v.course_end_date,
        select_date: v.select_date,
        course_cancel_end_date: v.course_cancel_end_date,
        category: v.category.map(map_bykc_category),
        sub_category: v.sub_category.map(map_bykc_subcategory),
        checkin: v.checkin,
        score: v.score,
        pass: v.pass,
        can_sign: v.can_sign,
        can_sign_out: v.can_sign_out,
        sign_config: v.sign_config.map(map_bykc_sign_config),
        course_sign_type: v.course_sign_type,
        homework: v.homework,
        homework_attachment_name: v.homework_attachment_name,
        homework_attachment_path: v.homework_attachment_path,
        sign_info: v.sign_info,
    }
}
fn map_bykc_chosen_courses(v: Vec<domain::BykcChosenCourse>) -> Vec<BridgeBykcChosenCourse> {
    v.into_iter().map(map_bykc_chosen).collect()
}
fn map_bykc_statistics(v: domain::BykcStatistics) -> BridgeBykcStatistics {
    BridgeBykcStatistics {
        total_valid_count: v.total_valid_count,
        categories: v
            .categories
            .into_iter()
            .map(|s| BridgeBykcStatistic {
                category_name: s.category_name,
                sub_category_name: s.sub_category_name,
                required_count: s.required_count,
                passed_count: s.passed_count,
                qualified: s.qualified,
            })
            .collect(),
    }
}
fn map_libbook_storey(v: domain::LibBookStorey) -> BridgeLibBookStorey {
    BridgeLibBookStorey {
        id: v.id,
        name: v.name,
        free_num: v.free_num,
        total_num: v.total_num,
    }
}
fn map_libbook_libraries(v: Vec<domain::LibBookLibrary>) -> Vec<BridgeLibBookLibrary> {
    v.into_iter()
        .map(|l| BridgeLibBookLibrary {
            id: l.id,
            name: l.name,
            free_num: l.free_num,
            total_num: l.total_num,
            storeys: l.storeys.into_iter().map(map_libbook_storey).collect(),
        })
        .collect()
}
fn map_libbook_areas(v: Vec<domain::LibBookArea>) -> Vec<BridgeLibBookArea> {
    v.into_iter()
        .map(|a| BridgeLibBookArea {
            id: a.id,
            name: a.name,
            area_name: a.area_name,
            premises_id: a.premises_id,
            storey_id: a.storey_id,
            free_num: a.free_num,
            total_num: a.total_num,
        })
        .collect()
}
fn map_libbook_area_detail(v: domain::LibBookAreaDetail) -> BridgeLibBookAreaDetail {
    BridgeLibBookAreaDetail {
        id: v.id,
        name: v.name,
        available_dates: v.available_dates,
        time_slots: v
            .time_slots
            .into_iter()
            .map(|s| BridgeLibBookTimeSlot {
                id: s.id,
                start: s.start,
                end: s.end,
                label: s.label,
            })
            .collect(),
    }
}
fn map_libbook_seats(v: Vec<domain::LibBookSeat>) -> Vec<BridgeLibBookSeat> {
    v.into_iter()
        .map(|s| BridgeLibBookSeat {
            id: s.id,
            name: s.name,
            no: s.no,
            status: s.status,
            status_name: s.status_name,
            is_available: s.is_available,
        })
        .collect()
}
fn map_libbook_booking(v: domain::LibBookBooking) -> BridgeLibBookBooking {
    BridgeLibBookBooking {
        id: v.id,
        name_merge: v.name_merge,
        area_name: v.area_name,
        seat_no: v.seat_no,
        day: v.day,
        begin_time: v.begin_time,
        end_time: v.end_time,
        status: v.status,
        status_name: v.status_name,
    }
}
fn map_libbook_bookings(v: domain::LibBookBookingsPage) -> BridgeLibBookBookingsPage {
    BridgeLibBookBookingsPage {
        bookings: v.bookings.into_iter().map(map_libbook_booking).collect(),
        page: v.page,
        limit: v.limit,
        total: v.total,
    }
}
fn map_ygdk_summary(v: domain::YgdkTermSummary) -> BridgeYgdkTermSummary {
    BridgeYgdkTermSummary {
        term_id: v.term_id,
        term_name: v.term_name,
        term_count: v.term_count,
        term_target: v.term_target,
        week_count: v.week_count,
        week_target: v.week_target,
        month_count: v.month_count,
        month_target: v.month_target,
        day_count: v.day_count,
        good_count: v.good_count,
    }
}
fn map_ygdk_overview(v: domain::YgdkOverview) -> BridgeYgdkOverview {
    BridgeYgdkOverview {
        summary: map_ygdk_summary(v.summary),
        classify_id: v.classify_id,
        classify_name: v.classify_name,
        default_item_id: v.default_item_id,
        default_item_name: v.default_item_name,
        items: v
            .items
            .into_iter()
            .map(|i| BridgeYgdkItem {
                item_id: i.item_id,
                name: i.name,
                kind: i.kind,
                sort: i.sort,
            })
            .collect(),
    }
}
fn map_ygdk_records(v: domain::YgdkRecordsPage) -> BridgeYgdkRecordsPage {
    BridgeYgdkRecordsPage {
        content: v
            .content
            .into_iter()
            .map(|r| BridgeYgdkRecord {
                record_id: r.record_id,
                item_id: r.item_id,
                item_name: r.item_name,
                start_time: r.start_time,
                end_time: r.end_time,
                place: r.place,
                images: r.images,
                is_open: r.is_open,
                state: r.state,
                created_at: r.created_at,
                created_at_label: r.created_at_label,
            })
            .collect(),
        total: v.total,
        page: v.page,
        size: v.size,
        has_more: v.has_more,
    }
}
fn map_cgyy_sites(v: Vec<domain::CgyyVenueSite>) -> Vec<BridgeCgyyVenueSite> {
    v.into_iter()
        .map(|s| BridgeCgyyVenueSite {
            id: s.id,
            site_name: s.site_name,
            venue_name: s.venue_name,
            campus_name: s.campus_name,
            seat_count: s.seat_count,
            reservation_space_count: s.reservation_space_count,
            site_telephone: s.site_telephone,
            open_start_date: s.open_start_date,
            open_end_date: s.open_end_date,
        })
        .collect()
}
fn map_cgyy_purpose_types(v: domain::CgyyPurposeTypes) -> BridgeCgyyPurposeTypes {
    BridgeCgyyPurposeTypes {
        items: v
            .items
            .into_iter()
            .map(|p| BridgeCgyyPurposeType {
                key: p.key,
                name: p.name,
            })
            .collect(),
        source: match v.source {
            domain::CgyyPurposeSource::Upstream => BridgeCgyyPurposeSource::Upstream,
            domain::CgyyPurposeSource::StaticFallback => BridgeCgyyPurposeSource::StaticFallback,
        },
    }
}
fn map_cgyy_time_slot(v: domain::CgyyTimeSlot) -> BridgeCgyyTimeSlot {
    BridgeCgyyTimeSlot {
        id: v.id,
        begin_time: v.begin_time,
        end_time: v.end_time,
        label: v.label,
    }
}
fn map_cgyy_slot(v: domain::CgyySlotStatus) -> BridgeCgyySlotStatus {
    BridgeCgyySlotStatus {
        time_id: v.time_id,
        reservation_status: v.reservation_status,
        is_reservable: v.is_reservable,
        start_date: v.start_date,
        end_date: v.end_date,
        trade_no: v.trade_no,
        order_id: v.order_id,
        use_num: v.use_num,
        already_num: v.already_num,
        take_up: v.take_up,
        take_up_explain: v.take_up_explain,
    }
}
fn map_cgyy_day_info(v: domain::CgyyDayInfo) -> BridgeCgyyDayInfo {
    BridgeCgyyDayInfo {
        venue_site_id: v.venue_site_id,
        reservation_date: v.reservation_date,
        available_dates: v.available_dates,
        time_slots: v.time_slots.into_iter().map(map_cgyy_time_slot).collect(),
        spaces: v
            .spaces
            .into_iter()
            .map(|s| BridgeCgyySpaceAvailability {
                space_id: s.space_id,
                space_name: s.space_name,
                venue_site_id: s.venue_site_id,
                venue_space_group_id: s.venue_space_group_id,
                slots: s.slots.into_iter().map(map_cgyy_slot).collect(),
            })
            .collect(),
        reservation_total_num: v.reservation_total_num,
    }
}
pub(crate) fn map_cgyy_order(v: domain::CgyyOrder) -> BridgeCgyyOrder {
    BridgeCgyyOrder {
        id: v.id,
        venue_site_id: v.venue_site_id,
        reservation_date: v.reservation_date,
        reservation_date_detail: v.reservation_date_detail,
        venue_space_name: v.venue_space_name,
        campus_name: v.campus_name,
        venue_name: v.venue_name,
        site_name: v.site_name,
        reservation_start_date: v.reservation_start_date,
        reservation_end_date: v.reservation_end_date,
        order_status: v.order_status,
        check_status: v.check_status,
        theme: v.theme,
        purpose_type_name: v.purpose_type_name,
        joiner_num: v.joiner_num,
    }
}
fn map_cgyy_orders(v: domain::CgyyOrdersPage) -> BridgeCgyyOrdersPage {
    BridgeCgyyOrdersPage {
        content: v.content.into_iter().map(map_cgyy_order).collect(),
        total_elements: v.total_elements,
        total_pages: v.total_pages,
        size: v.size,
        number: v.number,
    }
}
fn map_cgyy_lock_code(v: domain::CgyyLockCode) -> BridgeCgyyLockCode {
    BridgeCgyyLockCode {
        available: v.available,
    }
}
fn map_evaluation(v: domain::EvaluationCoursesResponse) -> BridgeEvaluationCoursesResponse {
    BridgeEvaluationCoursesResponse {
        courses: v
            .courses
            .into_iter()
            .map(|c| BridgeEvaluationCourse {
                id: c.id,
                kcmc: c.kcmc,
                bpmc: c.bpmc,
                is_evaluated: c.is_evaluated,
                rwid: c.rwid,
                wjid: c.wjid,
                kcdm: c.kcdm,
                bpdm: c.bpdm,
                pjrdm: c.pjrdm,
                pjrmc: c.pjrmc,
                xnxq: c.xnxq,
                msid: c.msid,
                zdmc: c.zdmc,
                ypjcs: c.ypjcs,
                xypjcs: c.xypjcs,
                sxz: c.sxz,
                rwh: c.rwh,
                xn: c.xn,
                xq: c.xq,
                pjlxid: c.pjlxid,
                sfksqbpj: c.sfksqbpj,
                yxsfktjst: c.yxsfktjst,
            })
            .collect(),
        progress: BridgeEvaluationProgress {
            total_courses: v.progress.total_courses,
            evaluated_courses: v.progress.evaluated_courses,
            pending_courses: v.progress.pending_courses,
        },
    }
}
