//! 固定路线 Core adapter。

use async_trait::async_trait;
use serde_json::Value;
use ubaa_core::facade::Result;
use ubaa_core::facade::RouteClient;
use ubaa_core::facade::{
    AuthStatus, BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder,
    CgyyOrdersPage, CgyyPurposeType, CgyyReservationResult, CgyyReservationSubmitRequest,
    CgyyVenueSite, ClassroomQuery, ConnectionMode, EvaluationCoursesResponse, ExamArrangement,
    FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary,
    JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail, LibBookBookingsPage,
    LibBookCancelResult, LibBookLibrary, LibBookReserveRequest, LibBookReserveResult, LibBookSeat,
    LoginInput, SigninActionResult, SigninClass, SpocAssignmentDetail, SpocAssignments,
    SpocAssignmentsDiagnostics, Term, TodayClass, UserProfile, Week, WeeklySchedule,
    YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkOverview, YgdkRecordsPage,
};

use super::CliBackend;

#[async_trait]
impl CliBackend for RouteClient {
    fn mode(&self) -> ConnectionMode {
        self.mode()
    }

    async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        self.login(input).await
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        self.auth_status().await
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        self.get_user_info().await
    }

    async fn logout(&mut self) -> Result<()> {
        self.logout().await
    }

    async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        self.signin_today().await
    }
    async fn signin_perform(
        &mut self,
        course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        self.signin_perform(course_id).await
    }
    async fn libbook_libraries(&mut self, day: &str) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        self.libbook_libraries(day).await
    }
    async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        self.libbook_areas(premises_id, storey_id, day).await
    }
    async fn libbook_area_detail(
        &mut self,
        area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        self.libbook_area_detail(area_id).await
    }
    async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        self.libbook_seats(area_id, day, start_time, end_time).await
    }
    async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        self.libbook_bookings(page, limit).await
    }
    async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        self.libbook_reserve(request).await
    }
    async fn libbook_cancel_booking(
        &mut self,
        id: &str,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        self.libbook_cancel_booking(id).await
    }
    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        self.bykc_profile().await
    }
    async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        self.bykc_courses(page, size, all).await
    }
    async fn bykc_course_detail(&mut self, id: i64) -> Result<FeatureResult<BykcCourse>> {
        self.bykc_course_detail(id).await
    }
    async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        self.bykc_chosen_courses().await
    }
    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        self.bykc_statistics().await
    }
    async fn bykc_select_course(
        &mut self,
        course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.bykc_select_course(course_id).await
    }
    async fn bykc_deselect_course(
        &mut self,
        course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.bykc_deselect_course(course_id).await
    }
    async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.bykc_sign_course(request).await
    }
    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        self.cgyy_sites().await
    }
    async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        self.cgyy_lock_code().await
    }
    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        self.cgyy_purposes().await
    }
    async fn cgyy_day(&mut self, site_id: i32, date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        self.cgyy_day(site_id, date).await
    }
    async fn cgyy_orders(&mut self, page: i32, size: i32) -> Result<FeatureResult<CgyyOrdersPage>> {
        self.cgyy_orders(page, size).await
    }
    async fn cgyy_order_detail(&mut self, id: i32) -> Result<FeatureResult<CgyyOrder>> {
        self.cgyy_order_detail(id).await
    }
    async fn cgyy_cancel_order(&mut self, id: i32) -> Result<FeatureResult<CgyyActionResult>> {
        self.cgyy_cancel_order(id).await
    }
    async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        self.cgyy_submit_reservation(request).await
    }
    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        self.ygdk_overview().await
    }
    async fn ygdk_records(
        &mut self,
        page: i32,
        size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        self.ygdk_records(page, size).await
    }
    async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        self.ygdk_submit(request).await
    }
    async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        self.evaluation_all().await
    }
    async fn evaluation_submit(
        &mut self,
        payload: Vec<Value>,
    ) -> Result<FeatureResult<Vec<ubaa_core::facade::EvaluationResult>>> {
        self.evaluation_submit(payload).await
    }
    async fn evaluation_submit_courses(
        &mut self,
        courses: Vec<ubaa_core::facade::EvaluationCourse>,
    ) -> Result<FeatureResult<Vec<ubaa_core::facade::EvaluationResult>>> {
        self.evaluation_submit_courses(courses).await
    }

    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        self.schedule_terms().await
    }
    async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        self.schedule_weeks(term).await
    }
    async fn schedule_week(
        &mut self,
        term: &str,
        week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        self.schedule_week(term, week).await
    }
    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        self.schedule_today().await
    }
    async fn exam_arrangement(&mut self, term: &str) -> Result<FeatureResult<ExamArrangement>> {
        self.exam_arrangement(term).await
    }
    async fn grades(&mut self, term: &str) -> Result<FeatureResult<GradeData>> {
        self.grades(term).await
    }
    async fn classroom_search(
        &mut self,
        campus: i32,
        date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        self.classroom_search(campus, date).await
    }
    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.spoc_assignments().await
    }
    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        self.spoc_assignments_diagnostics().await
    }
    async fn spoc_assignment(&mut self, id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        self.spoc_assignment(id).await
    }
    async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        self.judge_assignments(include_expired).await
    }
    async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        self.judge_assignments_diagnostics(include_expired).await
    }
    async fn judge_assignment(
        &mut self,
        course_id: &str,
        id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        self.judge_assignment(course_id, id).await
    }
    async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        self.judge_assignment_details(keys).await
    }
}
