//! CLI 后端契约与默认不可用错误。

use async_trait::async_trait;
use serde_json::Value;
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
use ubaa_core::facade::{Result, UbaaError};
use ubaa_core::facade::{RoutedError, RoutedResult};

use crate::io::input::internal_error;

mod fixed;
mod routed;

/// 命令执行所需的认证门面。
#[async_trait]
pub trait CliBackend {
    /// 当前后端固定使用的连接模式。
    fn mode(&self) -> ConnectionMode;
    /// 提交凭据并返回已认证的用户资料。
    async fn login(&mut self, input: LoginInput) -> Result<UserProfile>;
    /// 验证活动会话。
    async fn auth_status(&mut self) -> Result<AuthStatus>;
    /// 获取用户中心资料。
    async fn get_user_info(&mut self) -> Result<UserProfile>;
    /// 退出并清理本地状态。
    async fn logout(&mut self) -> Result<()>;

    /// 查询今日签到课程。
    async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        Err(unavailable("签到功能不可用"))
    }
    async fn signin_perform(
        &mut self,
        _course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        Err(unavailable("签到功能不可用"))
    }
    /// 查询图书馆楼馆列表。
    async fn libbook_libraries(
        &mut self,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        Err(unavailable("图书馆功能不可用"))
    }
    /// 查询图书馆分区列表。
    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        Err(unavailable("图书馆功能不可用"))
    }
    /// 查询图书馆分区详情。
    async fn libbook_area_detail(
        &mut self,
        _area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        Err(unavailable("图书馆功能不可用"))
    }
    /// 查询图书馆座位状态。
    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        Err(unavailable("图书馆功能不可用"))
    }
    /// 查询当前用户的图书馆预约记录。
    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        Err(unavailable("图书馆功能不可用"))
    }
    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        Err(unavailable("图书馆写功能不可用"))
    }
    async fn libbook_cancel_booking(
        &mut self,
        _id: &str,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        Err(unavailable("图书馆写功能不可用"))
    }
    /// 查询博雅用户资料。
    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        Err(unavailable("博雅功能不可用"))
    }
    /// 分页查询博雅课程。
    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        Err(unavailable("博雅功能不可用"))
    }
    /// 查询博雅课程详情。
    async fn bykc_course_detail(&mut self, _id: i64) -> Result<FeatureResult<BykcCourse>> {
        Err(unavailable("博雅功能不可用"))
    }
    /// 查询博雅已选课程。
    async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        Err(unavailable("博雅功能不可用"))
    }
    /// 查询博雅修读统计。
    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        Err(unavailable("博雅功能不可用"))
    }
    async fn bykc_select_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(unavailable("博雅写功能不可用"))
    }
    async fn bykc_deselect_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(unavailable("博雅写功能不可用"))
    }
    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(unavailable("博雅写功能不可用"))
    }
    /// 查询场馆站点。
    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    /// 查询预约用途。
    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    /// 查询日期预约信息。
    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    /// 查询当前用户订单。
    async fn cgyy_orders(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    /// 查询订单详情。
    async fn cgyy_order_detail(&mut self, _id: i32) -> Result<FeatureResult<CgyyOrder>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    /// 取消预约订单。
    async fn cgyy_cancel_order(&mut self, _id: i32) -> Result<FeatureResult<CgyyActionResult>> {
        Err(unavailable("场馆预约功能不可用"))
    }
    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        Err(unavailable("场馆预约写功能不可用"))
    }
    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        Err(unavailable("阳光打卡不可用"))
    }
    async fn ygdk_records(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        Err(unavailable("阳光打卡不可用"))
    }
    async fn ygdk_submit(
        &mut self,
        _request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        Err(unavailable("阳光打卡写功能不可用"))
    }
    /// 查询全部评教课程。
    async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        Err(unavailable("评教功能不可用"))
    }
    async fn evaluation_submit(
        &mut self,
        _payload: Vec<Value>,
    ) -> Result<FeatureResult<Vec<ubaa_core::facade::EvaluationResult>>> {
        Err(unavailable("评教写功能不可用"))
    }
    async fn evaluation_submit_courses(
        &mut self,
        _courses: Vec<ubaa_core::facade::EvaluationCourse>,
    ) -> Result<FeatureResult<Vec<ubaa_core::facade::EvaluationResult>>> {
        Err(unavailable("评教写功能不可用"))
    }

    /// 查询学期。
    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        Err(unavailable("课表功能不可用"))
    }
    /// 查询教学周。
    async fn schedule_weeks(&mut self, _term: &str) -> Result<FeatureResult<Vec<Week>>> {
        Err(unavailable("课表功能不可用"))
    }
    /// 查询指定教学周。
    async fn schedule_week(
        &mut self,
        _term: &str,
        _week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        Err(unavailable("课表功能不可用"))
    }
    /// 查询今日课程。
    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        Err(unavailable("课表功能不可用"))
    }
    /// 查询考试。
    async fn exam_arrangement(&mut self, _term: &str) -> Result<FeatureResult<ExamArrangement>> {
        Err(unavailable("考试功能不可用"))
    }
    /// 查询成绩。
    async fn grades(&mut self, _term: &str) -> Result<FeatureResult<GradeData>> {
        Err(unavailable("成绩功能不可用"))
    }
    /// 查询空闲教室。
    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        Err(unavailable("空教室功能不可用"))
    }
    /// 查询 SPOC 作业。
    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        Err(unavailable("SPOC 功能不可用"))
    }
    /// 查询安全的 SPOC 全局分页诊断。
    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        Err(unavailable("SPOC 诊断功能不可用"))
    }
    /// 查询 SPOC 作业详情。
    async fn spoc_assignment(&mut self, _id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        Err(unavailable("SPOC 功能不可用"))
    }
    /// 查询希冀作业。
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        Err(unavailable("希冀功能不可用"))
    }
    /// 查询安全的希冀解析诊断。
    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        Err(unavailable("希冀诊断功能不可用"))
    }
    /// 查询希冀作业详情。
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        Err(unavailable("希冀功能不可用"))
    }
    /// 批量查询希冀作业详情。
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        Err(unavailable("希冀功能不可用"))
    }
}

/// 普通用户命令和只读命令所需的聚合 Core 门面。
///
/// Core 会把每个已完成的路由决策与操作结果一起返回。CLI 仅展示该决策，
/// 不自行选择或修复路由。
#[async_trait]
pub trait RoutedCliBackend {
    /// 通过 Core 路由查询全部评教课程。
    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        Err(routed_unavailable("评教功能不可用"))
    }
    async fn evaluation_submit(
        &mut self,
        _payload: Vec<Value>,
    ) -> RoutedResult<Vec<ubaa_core::facade::EvaluationResult>> {
        Err(routed_unavailable("评教写功能不可用"))
    }
    async fn evaluation_submit_courses(
        &mut self,
        _courses: Vec<ubaa_core::facade::EvaluationCourse>,
    ) -> RoutedResult<Vec<ubaa_core::facade::EvaluationResult>> {
        Err(routed_unavailable("评教写功能不可用"))
    }
    /// 查询今日课堂签到状态。
    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        Err(routed_unavailable("签到功能不可用"))
    }
    async fn signin_perform(&mut self, _course_id: &str) -> RoutedResult<SigninActionResult> {
        Err(routed_unavailable("签到功能不可用"))
    }
    /// 通过 Core 路由查询图书馆楼馆列表。
    async fn libbook_libraries(&mut self, _day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆分区列表。
    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆分区详情。
    async fn libbook_area_detail(&mut self, _area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆座位状态。
    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆预约记录。
    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        Err(routed_unavailable("图书馆写功能不可用"))
    }
    async fn libbook_cancel_booking(&mut self, _id: &str) -> RoutedResult<LibBookCancelResult> {
        Err(routed_unavailable("图书馆写功能不可用"))
    }
    /// 通过 Core 路由查询博雅用户资料。
    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由分页查询博雅课程。
    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询博雅课程详情。
    async fn bykc_course_detail(&mut self, _id: i64) -> RoutedResult<BykcCourse> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询博雅已选课程。
    async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询博雅修读统计。
    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    async fn bykc_select_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult> {
        Err(routed_unavailable("博雅写功能不可用"))
    }
    async fn bykc_deselect_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult> {
        Err(routed_unavailable("博雅写功能不可用"))
    }
    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        Err(routed_unavailable("博雅写功能不可用"))
    }
    /// 通过 Core 路由查询场馆站点。
    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询预约用途。
    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询日期预约信息。
    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> RoutedResult<CgyyDayInfo> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询当前用户订单。
    async fn cgyy_orders(&mut self, _page: i32, _size: i32) -> RoutedResult<CgyyOrdersPage> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询订单详情。
    async fn cgyy_order_detail(&mut self, _id: i32) -> RoutedResult<CgyyOrder> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由取消预约订单。
    async fn cgyy_cancel_order(&mut self, _id: i32) -> RoutedResult<CgyyActionResult> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        Err(routed_unavailable("场馆预约写功能不可用"))
    }
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        Err(routed_unavailable("阳光打卡不可用"))
    }
    async fn ygdk_records(&mut self, _page: i32, _size: i32) -> RoutedResult<YgdkRecordsPage> {
        Err(routed_unavailable("阳光打卡不可用"))
    }
    async fn ygdk_submit(
        &mut self,
        _request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        Err(routed_unavailable("阳光打卡写功能不可用"))
    }
    /// 通过 Core 路由获取用户中心资料。
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        Err(routed_unavailable("用户资料功能不可用"))
    }
    /// 通过 Core 路由查询学期。
    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询教学周。
    async fn schedule_weeks(&mut self, _term: &str) -> RoutedResult<Vec<Week>> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询指定教学周。
    async fn schedule_week(&mut self, _term: &str, _week: i32) -> RoutedResult<WeeklySchedule> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询今日课程。
    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询考试。
    async fn exam_arrangement(&mut self, _term: &str) -> RoutedResult<ExamArrangement> {
        Err(routed_unavailable("考试功能不可用"))
    }
    /// 通过 Core 路由查询成绩。
    async fn grades(&mut self, _term: &str) -> RoutedResult<GradeData> {
        Err(routed_unavailable("成绩功能不可用"))
    }
    /// 通过 Core 路由查询空闲教室。
    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> RoutedResult<ClassroomQuery> {
        Err(routed_unavailable("空教室功能不可用"))
    }
    /// 通过 Core 路由查询 SPOC 作业。
    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        Err(routed_unavailable("SPOC 功能不可用"))
    }
    /// 通过 Core 路由查询安全的 SPOC 全局分页诊断。
    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        Err(routed_unavailable("SPOC 诊断功能不可用"))
    }
    /// 通过 Core 路由查询一项 SPOC 作业。
    async fn spoc_assignment(&mut self, _id: &str) -> RoutedResult<SpocAssignmentDetail> {
        Err(routed_unavailable("SPOC 功能不可用"))
    }
    /// 通过 Core 路由查询希冀作业。
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        Err(routed_unavailable("希冀功能不可用"))
    }
    /// 通过 Core 路由查询安全的希冀解析诊断。
    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        Err(routed_unavailable("希冀诊断功能不可用"))
    }
    /// 通过 Core 路由查询一项希冀作业。
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        Err(routed_unavailable("希冀功能不可用"))
    }
    /// 通过一次 Core 路由决策查询多项希冀作业详情。
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        Err(routed_unavailable("希冀功能不可用"))
    }
}

fn unavailable(message: impl Into<String>) -> UbaaError {
    internal_error(message)
}

fn routed_unavailable(message: impl Into<String>) -> RoutedError {
    RoutedError {
        error: unavailable(message),
        resolution: None,
    }
}
