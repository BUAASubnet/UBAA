use async_trait::async_trait;
use clap::Parser;
use std::io::Cursor;

use ubaa_cli::{
    CLI_JSON_SCHEMA_VERSION, Cli, CliBackend, RoutedCliBackend, run_with_backend,
    run_with_routed_backend,
};
use ubaa_core::facade::*;
use ubaa_core::facade::{
    ActionEligibility, AuthStatus, ConnectionMode, ErrorCode, ErrorKind, EvaluationBatchResult,
    EvaluationCourse, EvaluationCourseOutcome, EvaluationCourseResult, EvaluationCoursesResponse,
    EvaluationProgress, EvaluationSubmitCoursesRequest, EvaluationSubmitTarget, FeatureResult,
    LoginInput, NetworkState, Result, RouteDiagnostic, RoutePolicy, RouteResolution, Routed,
    RoutedResult, UbaaError, UserProfile,
};

use crate::common::assert_cli_schema;

#[derive(Clone, Copy, Default)]
enum BatchFixture {
    #[default]
    Success,
    Partial,
    OutcomeUnknown,
}

#[derive(Default)]
struct EvaluationBackend {
    courses: Vec<EvaluationCourse>,
    batch: BatchFixture,
    route: Option<ConnectionMode>,
    read_calls: usize,
    submit_calls: usize,
    readback_calls: usize,
    readback_routes: Vec<ConnectionMode>,
    submitted: Option<EvaluationSubmitCoursesRequest>,
    expected_submit_route: Option<ConnectionMode>,
    readback_fails: bool,
    commit_auth_fails: bool,
}

#[async_trait]
impl RoutedCliBackend for EvaluationBackend {
    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        self.read_calls += 1;
        Ok(Routed {
            data: response(self.courses.clone()),
            resolution: resolution(self.route.unwrap_or(ConnectionMode::Direct)),
        })
    }

    async fn evaluation_submit_courses_if_route_matches(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<EvaluationBatchResult> {
        self.submit_calls += 1;
        self.submitted = Some(request.clone());
        self.expected_submit_route = Some(expected_route);
        if self.commit_auth_fails {
            return Err(ubaa_core::facade::RoutedError {
                error: authentication_required(),
                resolution: Some(resolution(expected_route)),
            });
        }
        Ok(Routed {
            data: batch(self.batch, &request.targets),
            resolution: resolution(expected_route),
        })
    }

    async fn evaluation_all_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse> {
        self.readback_calls += 1;
        self.readback_routes.push(route);
        if self.readback_fails {
            Err(UbaaError::new(
                ErrorCode::UpstreamUnavailable,
                ErrorKind::Upstream,
                false,
                "fixture readback unavailable",
            ))
        } else {
            Ok(response(self.courses.clone()))
        }
    }

    async fn ihome_page(&mut self, _query: IhomeQuery) -> RoutedResult<IhomePage> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ihome_detail(&mut self, _id: i64, _mine: bool) -> RoutedResult<IhomeAppeal> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ihome_config(&mut self) -> RoutedResult<IhomeConfig> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ihome_notices(&mut self) -> RoutedResult<Vec<IhomeNotice>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ihome_notice(&mut self, _id: i64) -> RoutedResult<IhomeNotice> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn signin_perform(&mut self, _course_id: &str) -> RoutedResult<SigninActionResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_libraries(&mut self, _day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_area_detail(&mut self, _area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn libbook_cancel_booking(
        &mut self,
        _request: LibBookCancelRequest,
    ) -> RoutedResult<LibBookCancelResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_course_detail(&mut self, _id: i64) -> RoutedResult<BykcCourse> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_select_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_deselect_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> RoutedResult<CgyyDayInfo> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_orders(&mut self, _page: i32, _size: i32) -> RoutedResult<CgyyOrdersPage> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_order_detail(&mut self, _id: i32) -> RoutedResult<CgyyOrder> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_cancel_order(
        &mut self,
        _request: CgyyCancelOrderRequest,
    ) -> RoutedResult<CgyyCancelOrderResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ygdk_records(&mut self, _page: i32, _size: i32) -> RoutedResult<YgdkRecordsPage> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ygdk_submit(
        &mut self,
        _request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn ygdk_overview_on_route(&mut self, _route: ConnectionMode) -> Result<YgdkOverview> {
        Err(crate::common::test_unavailable())
    }

    async fn ygdk_records_on_route(
        &mut self,
        _route: ConnectionMode,
        _page: i32,
        _size: i32,
    ) -> Result<YgdkRecordsPage> {
        Err(crate::common::test_unavailable())
    }

    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn schedule_weeks(&mut self, _term: &str) -> RoutedResult<Vec<Week>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn schedule_week(&mut self, _term: &str, _week: i32) -> RoutedResult<WeeklySchedule> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn exam_arrangement(&mut self, _term: &str) -> RoutedResult<ExamArrangement> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn grades(&mut self, _term: &str) -> RoutedResult<GradeData> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> RoutedResult<ClassroomQuery> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn spoc_assignment(&mut self, _id: &str) -> RoutedResult<SpocAssignmentDetail> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        Err(crate::common::test_routed_unavailable())
    }

    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        Err(crate::common::test_routed_unavailable())
    }
}

#[derive(Default)]
struct FixedEvaluationBackend {
    courses: Vec<EvaluationCourse>,
    submit_calls: usize,
    readback_calls: usize,
    submitted: Option<EvaluationSubmitCoursesRequest>,
    commit_auth_fails: bool,
}

#[async_trait]
impl CliBackend for FixedEvaluationBackend {
    fn mode(&self) -> ConnectionMode {
        ConnectionMode::Direct
    }

    async fn login(&mut self, _input: LoginInput) -> Result<UserProfile> {
        unreachable!("本测试不执行登录")
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        unreachable!("本测试不查询认证状态")
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        unreachable!("本测试不查询用户资料")
    }

    async fn logout(&mut self) -> Result<()> {
        unreachable!("本测试不执行登出")
    }

    async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        Ok(FeatureResult {
            data: response(self.courses.clone()),
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn evaluation_submit_courses(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
    ) -> Result<FeatureResult<EvaluationBatchResult>> {
        self.submit_calls += 1;
        self.submitted = Some(request.clone());
        if self.commit_auth_fails {
            return Err(authentication_required());
        }
        Ok(FeatureResult {
            data: batch(BatchFixture::Success, &request.targets),
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn evaluation_all_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse> {
        assert_eq!(route, ConnectionMode::Direct);
        self.readback_calls += 1;
        Ok(response(self.courses.clone()))
    }

    async fn ihome_page(&mut self, _query: IhomeQuery) -> Result<FeatureResult<IhomePage>> {
        Err(crate::common::test_unavailable())
    }

    async fn ihome_detail(&mut self, _id: i64, _mine: bool) -> Result<FeatureResult<IhomeAppeal>> {
        Err(crate::common::test_unavailable())
    }

    async fn ihome_config(&mut self) -> Result<FeatureResult<IhomeConfig>> {
        Err(crate::common::test_unavailable())
    }

    async fn ihome_notices(&mut self) -> Result<FeatureResult<Vec<IhomeNotice>>> {
        Err(crate::common::test_unavailable())
    }

    async fn ihome_notice(&mut self, _id: i64) -> Result<FeatureResult<IhomeNotice>> {
        Err(crate::common::test_unavailable())
    }

    async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        Err(crate::common::test_unavailable())
    }

    async fn signin_perform(
        &mut self,
        _course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_libraries(
        &mut self,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_area_detail(
        &mut self,
        _area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn libbook_cancel_booking(
        &mut self,
        _request: LibBookCancelRequest,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_course_detail(&mut self, _id: i64) -> Result<FeatureResult<BykcCourse>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_select_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_deselect_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_orders(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_order_detail(&mut self, _id: i32) -> Result<FeatureResult<CgyyOrder>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_cancel_order(
        &mut self,
        _request: CgyyCancelOrderRequest,
    ) -> Result<FeatureResult<CgyyCancelOrderResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        Err(crate::common::test_unavailable())
    }

    async fn ygdk_records(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        Err(crate::common::test_unavailable())
    }

    async fn ygdk_submit(
        &mut self,
        _request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        Err(crate::common::test_unavailable())
    }

    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        Err(crate::common::test_unavailable())
    }

    async fn schedule_weeks(&mut self, _term: &str) -> Result<FeatureResult<Vec<Week>>> {
        Err(crate::common::test_unavailable())
    }

    async fn schedule_week(
        &mut self,
        _term: &str,
        _week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        Err(crate::common::test_unavailable())
    }

    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        Err(crate::common::test_unavailable())
    }

    async fn exam_arrangement(&mut self, _term: &str) -> Result<FeatureResult<ExamArrangement>> {
        Err(crate::common::test_unavailable())
    }

    async fn grades(&mut self, _term: &str) -> Result<FeatureResult<GradeData>> {
        Err(crate::common::test_unavailable())
    }

    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        Err(crate::common::test_unavailable())
    }

    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        Err(crate::common::test_unavailable())
    }

    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        Err(crate::common::test_unavailable())
    }

    async fn spoc_assignment(&mut self, _id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        Err(crate::common::test_unavailable())
    }

    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        Err(crate::common::test_unavailable())
    }

    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        Err(crate::common::test_unavailable())
    }

    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        Err(crate::common::test_unavailable())
    }

    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        Err(crate::common::test_unavailable())
    }
}
