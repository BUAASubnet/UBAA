//! Core 聚合路由 adapter。

use async_trait::async_trait;
use serde_json::Value;
use ubaa_core::domain::{
    BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder,
    CgyyOrdersPage, CgyyPurposeType, CgyyReservationResult, CgyyReservationSubmitRequest,
    CgyyVenueSite, ClassroomQuery, EvaluationCoursesResponse, ExamArrangement, GradeData,
    JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary, JudgeAssignmentsDiagnostics,
    LibBookArea, LibBookAreaDetail, LibBookBookingsPage, LibBookCancelResult, LibBookLibrary,
    LibBookReserveRequest, LibBookReserveResult, LibBookSeat, SigninActionResult, SigninClass,
    SpocAssignmentDetail, SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass,
    UserProfile, Week, WeeklySchedule, YgdkClockinSubmitRequest, YgdkClockinSubmitResult,
    YgdkOverview, YgdkRecordsPage,
};
use ubaa_core::facade::{RoutedResult, UbaaClient};

use super::RoutedCliBackend;

#[async_trait]
impl RoutedCliBackend for UbaaClient {
    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        UbaaClient::evaluation_all(self).await
    }
    async fn evaluation_submit(
        &mut self,
        payload: Vec<Value>,
    ) -> RoutedResult<Vec<ubaa_core::domain::EvaluationResult>> {
        UbaaClient::evaluation_submit(self, payload).await
    }
    async fn evaluation_submit_courses(
        &mut self,
        courses: Vec<ubaa_core::domain::EvaluationCourse>,
    ) -> RoutedResult<Vec<ubaa_core::domain::EvaluationResult>> {
        UbaaClient::evaluation_submit_courses(self, courses).await
    }
    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        UbaaClient::signin_today(self).await
    }
    async fn signin_perform(&mut self, course_id: &str) -> RoutedResult<SigninActionResult> {
        UbaaClient::signin_perform(self, course_id).await
    }
    async fn libbook_libraries(&mut self, day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        UbaaClient::libbook_libraries(self, day).await
    }
    async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        UbaaClient::libbook_areas(self, premises_id, storey_id, day).await
    }
    async fn libbook_area_detail(&mut self, area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        UbaaClient::libbook_area_detail(self, area_id).await
    }
    async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        UbaaClient::libbook_seats(self, area_id, day, start_time, end_time).await
    }
    async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        UbaaClient::libbook_bookings(self, page, limit).await
    }
    async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        UbaaClient::libbook_reserve(self, request).await
    }
    async fn libbook_cancel_booking(&mut self, id: &str) -> RoutedResult<LibBookCancelResult> {
        UbaaClient::libbook_cancel_booking(self, id).await
    }
    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        UbaaClient::cgyy_sites(self).await
    }
    async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        UbaaClient::cgyy_lock_code(self).await
    }
    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        UbaaClient::cgyy_purpose_types(self).await
    }
    async fn cgyy_day(&mut self, site_id: i32, date: &str) -> RoutedResult<CgyyDayInfo> {
        UbaaClient::cgyy_day_info(self, site_id, date).await
    }
    async fn cgyy_orders(&mut self, page: i32, size: i32) -> RoutedResult<CgyyOrdersPage> {
        UbaaClient::cgyy_orders(self, page, size).await
    }
    async fn cgyy_order_detail(&mut self, id: i32) -> RoutedResult<CgyyOrder> {
        UbaaClient::cgyy_order_detail(self, id).await
    }
    async fn cgyy_cancel_order(&mut self, id: i32) -> RoutedResult<CgyyActionResult> {
        UbaaClient::cgyy_cancel_order(self, id).await
    }
    async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        UbaaClient::cgyy_submit_reservation(self, request).await
    }
    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        UbaaClient::bykc_profile(self).await
    }
    async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        UbaaClient::bykc_courses(self, page, size, all).await
    }
    async fn bykc_course_detail(&mut self, id: i64) -> RoutedResult<BykcCourse> {
        UbaaClient::bykc_course_detail(self, id).await
    }
    async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        UbaaClient::bykc_chosen_courses(self).await
    }
    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        UbaaClient::bykc_statistics(self).await
    }
    async fn bykc_select_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        UbaaClient::bykc_select_course(self, course_id).await
    }
    async fn bykc_deselect_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        UbaaClient::bykc_deselect_course(self, course_id).await
    }
    async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        UbaaClient::bykc_sign_course(self, request).await
    }
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        UbaaClient::ygdk_overview(self).await
    }
    async fn ygdk_records(&mut self, page: i32, size: i32) -> RoutedResult<YgdkRecordsPage> {
        UbaaClient::ygdk_records(self, page, size).await
    }
    async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        UbaaClient::ygdk_submit(self, request).await
    }
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        UbaaClient::get_user_info(self).await
    }

    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        UbaaClient::schedule_terms(self).await
    }

    async fn schedule_weeks(&mut self, term: &str) -> RoutedResult<Vec<Week>> {
        UbaaClient::schedule_weeks(self, term).await
    }

    async fn schedule_week(&mut self, term: &str, week: i32) -> RoutedResult<WeeklySchedule> {
        UbaaClient::schedule_week(self, term, week).await
    }

    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        UbaaClient::schedule_today(self).await
    }

    async fn exam_arrangement(&mut self, term: &str) -> RoutedResult<ExamArrangement> {
        UbaaClient::exam_arrangement(self, term).await
    }

    async fn grades(&mut self, term: &str) -> RoutedResult<GradeData> {
        UbaaClient::grades(self, term).await
    }

    async fn classroom_search(&mut self, campus: i32, date: &str) -> RoutedResult<ClassroomQuery> {
        UbaaClient::classroom_search(self, campus, date).await
    }

    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        UbaaClient::spoc_assignments(self).await
    }
    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        UbaaClient::spoc_assignments_diagnostics(self).await
    }

    async fn spoc_assignment(&mut self, id: &str) -> RoutedResult<SpocAssignmentDetail> {
        UbaaClient::spoc_assignment(self, id).await
    }

    async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        UbaaClient::judge_assignments(self, include_expired).await
    }
    async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        UbaaClient::judge_assignments_diagnostics(self, include_expired).await
    }

    async fn judge_assignment(
        &mut self,
        course_id: &str,
        id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        UbaaClient::judge_assignment(self, course_id, id).await
    }

    async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        UbaaClient::judge_assignment_details(self, keys).await
    }
}
