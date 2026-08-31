//! UBAA Core 的命令行解析与输出展示。

use std::io::{BufRead, Write};

use async_trait::async_trait;
use serde::Serialize;
use serde_json::{Value, json};
use ubaa_core::connection::RouteResolution;
use ubaa_core::domain::{
    AuthStatus, BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder,
    CgyyOrdersPage, CgyyPurposeType, CgyyReservationResult, CgyyReservationSubmitRequest,
    CgyyVenueSite, ClassroomQuery, ConnectionMode, DualLoginInput, EvaluationCoursesResponse,
    ExamArrangement, FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey,
    JudgeAssignmentSummary, JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail,
    LibBookBookingsPage, LibBookCancelResult, LibBookLibrary, LibBookReserveRequest,
    LibBookReserveResult, LibBookSeat, LoginInput, LoginReadiness, RoutePolicy, SafeError,
    SecretValue, SigninActionResult, SigninClass, SpocAssignmentDetail, SpocAssignments,
    SpocAssignmentsDiagnostics, Term, TodayClass, UserProfile, Week, WeeklySchedule,
    YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkOverview, YgdkRecordsPage,
};
use ubaa_core::error::{ExitCode, Result, UbaaError};
use ubaa_core::facade::{RouteClient, Routed, RoutedError, RoutedResult, UbaaClient};
use ubaa_core::output::{
    AggregateJsonEnvelope, CliFeature, CliJsonError, ResolvedRoutedJsonMeta, RoutedJsonEnvelope,
    UnresolvedRoutedJsonMeta,
};

mod routing;
pub use routing::ReadonlyRouteContext;
mod login_args;
pub use login_args::LoginArgs;
mod render;
use render::{
    redacted_profile, redacted_status, render_human, safe_lock_code_value, write_profile,
};
mod input;
use input::{
    build_ygdk_request, internal_error, invalid_input, prompt_line, read_cgyy_request_stdin,
    read_evaluation_payload, read_secret_line, write_json,
};
mod connection_mode;
pub use connection_mode::CliConnectionMode;
mod commands;
pub use commands::{Cli, Command};
mod execution;
use execution::command_feature;
pub use execution::run_with_backend;
mod command_output;
pub(crate) use command_output::CommandOutput;
use command_output::{command_output_value, readonly};
mod cgyy_args;
pub use cgyy_args::{CgyyArgs, CgyyCommand};
mod bykc_args;
pub use bykc_args::{BykcArgs, BykcCommand};
mod evaluation_args;
pub use evaluation_args::{EvaluationArgs, EvaluationCommand};
mod libbook_args;
pub use libbook_args::{LibBookArgs, LibBookCommand};
mod ygdk_args;
pub use ygdk_args::{YgdkArgs, YgdkCommand};
mod signin_args;
pub use signin_args::{SigninArgs, SigninCommand};
mod auth_args;
pub use auth_args::{AuthArgs, AuthCommand};
mod schedule_args;
pub use schedule_args::{ScheduleArgs, ScheduleCommand};
mod user_args;
pub use user_args::{UserArgs, UserCommand};
mod exam_args;
pub use exam_args::{ExamArgs, ExamCommand};
mod grades_args;
pub use grades_args::{GradesArgs, GradesCommand};
mod classroom_args;
pub use classroom_args::{ClassroomArgs, ClassroomCommand};
mod spoc_args;
pub use spoc_args::{SpocArgs, SpocAssignmentCommand, SpocCommand};
mod judge_args;
pub use judge_args::{JudgeArgs, JudgeAssignmentCommand, JudgeCommand};

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
        Err(internal_error("签到功能不可用"))
    }
    async fn signin_perform(
        &mut self,
        _course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        Err(internal_error("签到功能不可用"))
    }
    /// 查询图书馆楼馆列表。
    async fn libbook_libraries(
        &mut self,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询图书馆分区列表。
    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询图书馆分区详情。
    async fn libbook_area_detail(
        &mut self,
        _area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询图书馆座位状态。
    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询当前用户的图书馆预约记录。
    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        Err(internal_error("图书馆功能不可用"))
    }
    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        Err(internal_error("图书馆写功能不可用"))
    }
    async fn libbook_cancel_booking(
        &mut self,
        _id: &str,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        Err(internal_error("图书馆写功能不可用"))
    }
    /// 查询博雅用户资料。
    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 分页查询博雅课程。
    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询博雅课程详情。
    async fn bykc_course_detail(&mut self, _id: i64) -> Result<FeatureResult<BykcCourse>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询博雅已选课程。
    async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询博雅修读统计。
    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        Err(internal_error("博雅功能不可用"))
    }
    async fn bykc_select_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(internal_error("博雅写功能不可用"))
    }
    async fn bykc_deselect_course(
        &mut self,
        _course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(internal_error("博雅写功能不可用"))
    }
    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        Err(internal_error("博雅写功能不可用"))
    }
    /// 查询场馆站点。
    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询预约用途。
    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询日期预约信息。
    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询当前用户订单。
    async fn cgyy_orders(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询订单详情。
    async fn cgyy_order_detail(&mut self, _id: i32) -> Result<FeatureResult<CgyyOrder>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 取消预约订单。
    async fn cgyy_cancel_order(&mut self, _id: i32) -> Result<FeatureResult<CgyyActionResult>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        Err(internal_error("场馆预约写功能不可用"))
    }
    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        Err(internal_error("阳光打卡不可用"))
    }
    async fn ygdk_records(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        Err(internal_error("阳光打卡不可用"))
    }
    async fn ygdk_submit(
        &mut self,
        _request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        Err(internal_error("阳光打卡写功能不可用"))
    }
    /// 查询全部评教课程。
    async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        Err(internal_error("评教功能不可用"))
    }
    async fn evaluation_submit(
        &mut self,
        _payload: Vec<Value>,
    ) -> Result<FeatureResult<Vec<ubaa_core::domain::EvaluationResult>>> {
        Err(internal_error("评教写功能不可用"))
    }
    async fn evaluation_submit_courses(
        &mut self,
        _courses: Vec<ubaa_core::domain::EvaluationCourse>,
    ) -> Result<FeatureResult<Vec<ubaa_core::domain::EvaluationResult>>> {
        Err(internal_error("评教写功能不可用"))
    }

    /// 查询学期。
    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询教学周。
    async fn schedule_weeks(&mut self, _term: &str) -> Result<FeatureResult<Vec<Week>>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询指定教学周。
    async fn schedule_week(
        &mut self,
        _term: &str,
        _week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询今日课程。
    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询考试。
    async fn exam_arrangement(&mut self, _term: &str) -> Result<FeatureResult<ExamArrangement>> {
        Err(internal_error("考试功能不可用"))
    }
    /// 查询成绩。
    async fn grades(&mut self, _term: &str) -> Result<FeatureResult<GradeData>> {
        Err(internal_error("成绩功能不可用"))
    }
    /// 查询空闲教室。
    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        Err(internal_error("空教室功能不可用"))
    }
    /// 查询 SPOC 作业。
    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        Err(internal_error("SPOC 功能不可用"))
    }
    /// 查询安全的 SPOC 全局分页诊断。
    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        Err(internal_error("SPOC 诊断功能不可用"))
    }
    /// 查询 SPOC 作业详情。
    async fn spoc_assignment(&mut self, _id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        Err(internal_error("SPOC 功能不可用"))
    }
    /// 查询希冀作业。
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        Err(internal_error("希冀功能不可用"))
    }
    /// 查询安全的希冀解析诊断。
    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        Err(internal_error("希冀诊断功能不可用"))
    }
    /// 查询希冀作业详情。
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        Err(internal_error("希冀功能不可用"))
    }
    /// 批量查询希冀作业详情。
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        Err(internal_error("希冀功能不可用"))
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
    ) -> RoutedResult<Vec<ubaa_core::domain::EvaluationResult>> {
        Err(routed_unavailable("评教写功能不可用"))
    }
    async fn evaluation_submit_courses(
        &mut self,
        _courses: Vec<ubaa_core::domain::EvaluationCourse>,
    ) -> RoutedResult<Vec<ubaa_core::domain::EvaluationResult>> {
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

/// 通过双路门面执行普通聚合登录流程。
pub async fn run_dual_login<R, O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    input: &mut R,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    R: BufRead,
    O: Write,
    E: Write,
{
    let json_mode = cli.json;
    let route_policy = backend.default_route_policy();
    let Command::Auth(AuthArgs {
        command: AuthCommand::Login(arguments),
    }) = cli.command
    else {
        return render_aggregate_input_error(
            json_mode,
            invalid_input("聚合登录必须先执行 auth login"),
            stdout,
            stderr,
        );
    };
    let (username, password) = match read_dual_credentials(json_mode, &arguments, input, stderr) {
        Ok(credentials) => credentials,
        Err(error) => {
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
        }
    };
    let mut outcome = match backend
        .login(DualLoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
    {
        Ok(outcome) => outcome,
        Err(error) => {
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
        }
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(json_mode, outcome, route_policy, stdout, stderr)
}

/// 执行普通聚合认证状态流程。
pub async fn run_dual_status<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let route_policy = backend.default_route_policy();
    let mut outcome = match backend.auth_status().await {
        Ok(outcome) => outcome,
        Err(error) => return render_aggregate_input_error(cli.json, error, stdout, stderr),
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(cli.json, outcome, route_policy, stdout, stderr)
}

/// 使用固定的聚合路由元数据退出两个路由槽位。
pub async fn run_dual_logout<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let route_policy = backend.default_route_policy();
    let result = backend.logout().await;
    match result {
        Ok(()) => {
            if cli.json {
                let envelope = AggregateJsonEnvelope::logout_success(route_policy);
                if write_json(stdout, &envelope).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if writeln!(stdout, "已退出登录。").is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_startup_error(cli.json, CliFeature::Auth, error, stdout, stderr),
    }
}

fn read_dual_credentials<R: BufRead, E: Write>(
    json_mode: bool,
    arguments: &LoginArgs,
    input: &mut R,
    stderr: &mut E,
) -> Result<(String, String)> {
    let username = if arguments.username_stdin {
        if arguments.username.is_some() {
            return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
        }
        let username = read_secret_line(input, "标准输入中缺少用户名")?;
        if username.trim().is_empty() {
            return Err(invalid_input("用户名不能为空"));
        }
        username
    } else {
        match arguments.username.as_deref() {
            Some(username) if !username.trim().is_empty() => username.to_owned(),
            Some(_) => return Err(invalid_input("用户名不能为空")),
            None if json_mode => return Err(invalid_input("JSON 模式必须提供 --username")),
            None => prompt_line(input, stderr, "用户名：")?,
        }
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "标准输入中缺少密码")?
    } else if json_mode {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    } else {
        rpassword::prompt_password("密码：").map_err(|_| internal_error("无法安全读取密码"))?
    };
    Ok((username, password))
}

fn render_dual_outcome<O: Write, E: Write>(
    json_mode: bool,
    outcome: ubaa_core::domain::LoginOutcome,
    route_policy: RoutePolicy,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let error = aggregate_error(&outcome);
    let exit_code = aggregate_exit_code(&outcome, error.as_ref());
    if json_mode {
        let envelope = match error {
            Some(error) => AggregateJsonEnvelope::auth_failure(outcome, error, route_policy),
            None => AggregateJsonEnvelope::auth_success(outcome, route_policy),
        };
        let envelope = match envelope {
            Ok(envelope) => envelope,
            Err(error) => {
                return render_startup_error(true, CliFeature::Auth, error, stdout, stderr);
            }
        };
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else {
        for route in &outcome.routes {
            let _ = writeln!(stdout, "{:?}: {:?}", route.route, route.state);
        }
        if outcome
            .profile
            .as_ref()
            .is_some_and(|profile| write_profile(stdout, profile).is_err())
        {
            return ExitCode::Internal as i32;
        }
        if let Some(error) = error {
            let _ = writeln!(stderr, "错误：{}", error.message);
        }
    }
    exit_code
}

fn aggregate_error(outcome: &ubaa_core::domain::LoginOutcome) -> Option<SafeError> {
    if outcome.readiness == LoginReadiness::NoneReady {
        Some(
            outcome
                .routes
                .iter()
                .find_map(|route| route.error.clone())
                .unwrap_or_else(|| SafeError {
                    code: "internal_error".into(),
                    kind: "internal".into(),
                    retryable: false,
                    message: "没有认证路线成功建立会话".into(),
                }),
        )
    } else {
        None
    }
}

fn aggregate_exit_code(
    outcome: &ubaa_core::domain::LoginOutcome,
    error: Option<&SafeError>,
) -> i32 {
    if outcome.readiness == LoginReadiness::NoneReady {
        error.map_or(ExitCode::Internal as i32, safe_error_exit_code)
    } else {
        ExitCode::Success as i32
    }
}

fn safe_error_exit_code(error: &SafeError) -> i32 {
    match error.code.as_str() {
        "invalid_input" => ExitCode::InvalidInput as i32,
        "authentication_required"
        | "invalid_credentials"
        | "password_risk_confirmation_failed"
        | "permission_denied" => ExitCode::Authentication as i32,
        "network_error" | "timeout" | "upstream_unavailable" => ExitCode::Network as i32,
        "upstream_changed" | "parse_error" => ExitCode::Upstream as i32,
        _ => ExitCode::Internal as i32,
    }
}

fn render_aggregate_input_error<O: Write, E: Write>(
    json_mode: bool,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    render_startup_error(json_mode, CliFeature::Auth, error, stdout, stderr)
}

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
    ) -> Result<FeatureResult<Vec<ubaa_core::domain::EvaluationResult>>> {
        self.evaluation_submit(payload).await
    }
    async fn evaluation_submit_courses(
        &mut self,
        courses: Vec<ubaa_core::domain::EvaluationCourse>,
    ) -> Result<FeatureResult<Vec<ubaa_core::domain::EvaluationResult>>> {
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

/// 使用 Core 所有的路由解析执行普通用户命令或只读命令。
#[allow(clippy::too_many_lines)]
pub async fn run_with_routed_backend<B, O, E>(
    cli: Cli,
    backend: &mut B,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    B: RoutedCliBackend + Send,
    O: Write,
    E: Write,
{
    let json_mode = cli.json;
    let (feature, result) = match cli.command {
        Command::User(UserArgs {
            command: UserCommand::Show,
        }) => (
            CliFeature::User,
            routed_map(backend.get_user_info().await, |profile| {
                CommandOutput::Profile(redacted_profile(profile))
            }),
        ),
        Command::Schedule(arguments) => (
            CliFeature::Schedule,
            run_routed_schedule(arguments, backend).await,
        ),
        Command::Exam(arguments) => (CliFeature::Exam, run_routed_exam(arguments, backend).await),
        Command::Grades(arguments) => (
            CliFeature::Grades,
            run_routed_grades(arguments, backend).await,
        ),
        Command::Classroom(arguments) => (
            CliFeature::Classroom,
            run_routed_classroom(arguments, backend).await,
        ),
        Command::Spoc(arguments) => (CliFeature::Spoc, run_routed_spoc(arguments, backend).await),
        Command::Judge(arguments) => (
            CliFeature::Judge,
            run_routed_judge(arguments, backend).await,
        ),
        Command::Signin(SigninArgs {
            command: SigninCommand::Today,
        }) => (
            CliFeature::Signin,
            routed_readonly(backend.signin_today().await, CliFeature::Signin),
        ),
        Command::Signin(SigninArgs {
            command:
                SigninCommand::Perform {
                    course_id,
                    confirm_write,
                },
        }) => {
            let result = if confirm_write {
                backend.signin_perform(&course_id).await
            } else {
                Err(RoutedError {
                    error: invalid_input("签到是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                })
            };
            (
                CliFeature::Signin,
                routed_readonly(result, CliFeature::Signin),
            )
        }
        Command::Libbook(arguments) => (
            CliFeature::LibBook,
            run_routed_libbook(arguments, backend).await,
        ),
        Command::Bykc(arguments) => (CliFeature::Bykc, run_routed_bykc(arguments, backend).await),
        Command::Cgyy(arguments) => (CliFeature::Cgyy, run_routed_cgyy(arguments, backend).await),
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Overview,
        }) => (
            CliFeature::Ygdk,
            routed_readonly(backend.ygdk_overview().await, CliFeature::Ygdk),
        ),
        Command::Evaluation(arguments) => (
            CliFeature::Evaluation,
            run_routed_evaluation(arguments, backend).await,
        ),
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Records { page, size },
        }) => (
            CliFeature::Ygdk,
            routed_readonly(backend.ygdk_records(page, size).await, CliFeature::Ygdk),
        ),
        Command::Ygdk(YgdkArgs {
            command:
                YgdkCommand::Submit {
                    item_id,
                    start_time,
                    end_time,
                    place,
                    photo,
                    share_to_square,
                    confirm_write,
                },
        }) => {
            let result = if confirm_write {
                match build_ygdk_request(
                    item_id,
                    start_time,
                    end_time,
                    place,
                    &photo,
                    share_to_square,
                ) {
                    Ok(request) => backend.ygdk_submit(request).await,
                    Err(error) => Err(RoutedError {
                        error,
                        resolution: None,
                    }),
                }
            } else {
                Err(RoutedError {
                    error: invalid_input("打卡是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                })
            };
            (CliFeature::Ygdk, routed_readonly(result, CliFeature::Ygdk))
        }
        Command::Auth(_) => (
            CliFeature::Auth,
            Err(RoutedError {
                error: invalid_input("普通路由执行不接受认证命令"),
                resolution: None,
            }),
        ),
    };

    render_routed_result(json_mode, feature, result, stdout, stderr)
}

async fn run_routed_schedule<B: RoutedCliBackend + Send>(
    arguments: ScheduleArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ScheduleCommand::Terms => {
            routed_readonly(backend.schedule_terms().await, CliFeature::Schedule)
        }
        ScheduleCommand::Weeks { term } => {
            routed_readonly(backend.schedule_weeks(&term).await, CliFeature::Schedule)
        }
        ScheduleCommand::Current { term, week } => routed_readonly(
            backend.schedule_week(&term, week).await,
            CliFeature::Schedule,
        ),
        ScheduleCommand::Today => {
            routed_readonly(backend.schedule_today().await, CliFeature::Schedule)
        }
    }
}

async fn run_routed_exam<B: RoutedCliBackend + Send>(
    arguments: ExamArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ExamCommand::List { term } => {
            routed_readonly(backend.exam_arrangement(&term).await, CliFeature::Exam)
        }
    }
}

async fn run_routed_grades<B: RoutedCliBackend + Send>(
    arguments: GradesArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        GradesCommand::List { term } => {
            routed_readonly(backend.grades(&term).await, CliFeature::Grades)
        }
    }
}

async fn run_routed_classroom<B: RoutedCliBackend + Send>(
    arguments: ClassroomArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ClassroomCommand::Search { campus, date } => routed_readonly(
            backend.classroom_search(campus, &date).await,
            CliFeature::Classroom,
        ),
    }
}

async fn run_routed_spoc<B: RoutedCliBackend + Send>(
    arguments: SpocArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        SpocCommand::Assignments => {
            routed_readonly(backend.spoc_assignments().await, CliFeature::Spoc)
        }
        SpocCommand::Diagnostics => routed_readonly(
            backend.spoc_assignments_diagnostics().await,
            CliFeature::Spoc,
        ),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => routed_readonly(backend.spoc_assignment(&id).await, CliFeature::Spoc),
    }
}

async fn run_routed_judge<B: RoutedCliBackend + Send>(
    arguments: JudgeArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        JudgeCommand::Assignments { include_expired } => routed_readonly(
            backend.judge_assignments(include_expired).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Diagnostics { include_expired } => routed_readonly(
            backend.judge_assignments_diagnostics(include_expired).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => routed_readonly(
            backend.judge_assignment(&course_id, &id).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("希冀详情键必须使用 course-id:assignment-id 格式")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "希冀详情键必须使用 course-id:assignment-id 格式",
                        ));
                    }
                    Ok(JudgeAssignmentKey {
                        course_id: course_id.into(),
                        assignment_id: assignment_id.into(),
                    })
                })
                .collect::<Result<Vec<_>>>()
                .map_err(|error| RoutedError {
                    error,
                    resolution: None,
                })?;
            routed_readonly(
                backend.judge_assignment_details(&parsed).await,
                CliFeature::Judge,
            )
        }
    }
}

async fn run_routed_libbook<B: RoutedCliBackend + Send>(
    arguments: LibBookArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        LibBookCommand::Libraries { day } => {
            routed_readonly(backend.libbook_libraries(&day).await, CliFeature::LibBook)
        }
        LibBookCommand::Areas {
            premises_id,
            storey_id,
            day,
        } => routed_readonly(
            backend
                .libbook_areas(&premises_id, storey_id.as_deref(), &day)
                .await,
            CliFeature::LibBook,
        ),
        LibBookCommand::AreaDetail { area_id } => routed_readonly(
            backend.libbook_area_detail(&area_id).await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Seats {
            area_id,
            day,
            start_time,
            end_time,
        } => routed_readonly(
            backend
                .libbook_seats(&area_id, &day, &start_time, &end_time)
                .await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Bookings { page, limit } => routed_readonly(
            backend.libbook_bookings(page, limit).await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Reserve {
            area_id,
            seat_id,
            day,
            segment,
            start_time,
            end_time,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend
                    .libbook_reserve(LibBookReserveRequest {
                        area_id,
                        seat_id,
                        day,
                        segment,
                        start_time,
                        end_time,
                    })
                    .await,
                CliFeature::LibBook,
            )
        }
        LibBookCommand::Cancel {
            booking_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("取消预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend.libbook_cancel_booking(&booking_id).await,
                CliFeature::LibBook,
            )
        }
    }
}

async fn run_routed_bykc<B: RoutedCliBackend + Send>(
    arguments: BykcArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        BykcCommand::Profile => routed_readonly(backend.bykc_profile().await, CliFeature::Bykc),
        BykcCommand::Courses { page, size, all } => routed_readonly(
            backend.bykc_courses(page, size, all).await,
            CliFeature::Bykc,
        ),
        BykcCommand::Course { id } => {
            routed_readonly(backend.bykc_course_detail(id).await, CliFeature::Bykc)
        }
        BykcCommand::Chosen => {
            routed_readonly(backend.bykc_chosen_courses().await, CliFeature::Bykc)
        }
        BykcCommand::Statistics => {
            routed_readonly(backend.bykc_statistics().await, CliFeature::Bykc)
        }
        BykcCommand::Select {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("选课是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend.bykc_select_course(course_id).await,
                CliFeature::Bykc,
            )
        }
        BykcCommand::Deselect {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("退选是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend.bykc_deselect_course(course_id).await,
                CliFeature::Bykc,
            )
        }
        BykcCommand::Sign {
            course_id,
            sign_type,
            lat,
            lng,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("签到是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend
                    .bykc_sign_course(BykcSignRequest {
                        course_id,
                        sign_type,
                        lat,
                        lng,
                    })
                    .await,
                CliFeature::Bykc,
            )
        }
    }
}

async fn run_routed_cgyy<B: RoutedCliBackend + Send>(
    arguments: CgyyArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        CgyyCommand::Sites => routed_readonly(backend.cgyy_sites().await, CliFeature::Cgyy),
        CgyyCommand::Purposes => routed_readonly(backend.cgyy_purposes().await, CliFeature::Cgyy),
        CgyyCommand::Day { site_id, date } => {
            routed_readonly(backend.cgyy_day(site_id, &date).await, CliFeature::Cgyy)
        }
        CgyyCommand::Orders { page, size } => {
            routed_readonly(backend.cgyy_orders(page, size).await, CliFeature::Cgyy)
        }
        CgyyCommand::Detail { id } => {
            routed_readonly(backend.cgyy_order_detail(id).await, CliFeature::Cgyy)
        }
        CgyyCommand::LockCode => {
            backend
                .cgyy_lock_code()
                .await
                .map(|Routed { data, resolution }| Routed {
                    data: CommandOutput::Readonly {
                        data: safe_lock_code_value(&data),
                        route: resolution.mode,
                        feature: CliFeature::Cgyy,
                    },
                    resolution,
                })
        }
        CgyyCommand::Cancel { id, confirm_write } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("取消预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(backend.cgyy_cancel_order(id).await, CliFeature::Cgyy)
        }
        CgyyCommand::Submit {
            request_stdin,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            if !request_stdin {
                return Err(RoutedError {
                    error: invalid_input("预约请求含敏感字段，必须显式指定 --request-stdin"),
                    resolution: None,
                });
            }
            let request = read_cgyy_request_stdin().map_err(|error| RoutedError {
                error,
                resolution: None,
            })?;
            routed_readonly(
                backend.cgyy_submit_reservation(request).await,
                CliFeature::Cgyy,
            )
        }
    }
}

fn routed_map<T>(
    result: RoutedResult<T>,
    map: impl FnOnce(T) -> CommandOutput,
) -> RoutedResult<CommandOutput> {
    result.map(|Routed { data, resolution }| Routed {
        data: map(data),
        resolution,
    })
}

fn routed_readonly<T: Serialize>(
    result: RoutedResult<T>,
    feature: CliFeature,
) -> RoutedResult<CommandOutput> {
    result.and_then(|Routed { data, resolution }| {
        let data = serde_json::to_value(data).map_err(|_| RoutedError {
            error: internal_error("无法序列化命令输出"),
            resolution: Some(resolution),
        })?;
        Ok(Routed {
            data: CommandOutput::Readonly {
                data,
                route: resolution.mode,
                feature,
            },
            resolution,
        })
    })
}

fn render_routed_result<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    result: RoutedResult<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(Routed { data, resolution }) => {
            if json_mode {
                let value = match command_output_value(data) {
                    Ok(value) => value,
                    Err(error) => {
                        return render_resolved_error(
                            true, feature, resolution, error, stdout, stderr,
                        );
                    }
                };
                let meta = ResolvedRoutedJsonMeta::from_resolution(feature, resolution);
                if write_json(stdout, &RoutedJsonEnvelope::success(value, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else {
                match data {
                    CommandOutput::Readonly {
                        data,
                        route,
                        feature,
                    } => {
                        if writeln!(stdout, "{} ({route:?}): {data}", feature.as_str()).is_err() {
                            return ExitCode::Internal as i32;
                        }
                    }
                    output => {
                        if render_human(output, stdout).is_err() {
                            return ExitCode::Internal as i32;
                        }
                    }
                }
            }
            ExitCode::Success as i32
        }
        Err(RoutedError {
            error,
            resolution: Some(resolution),
        }) => render_resolved_error(json_mode, feature, resolution, error, stdout, stderr),
        Err(RoutedError {
            error,
            resolution: None,
        }) => render_startup_error(json_mode, feature, error, stdout, stderr),
    }
}

fn routed_unavailable(message: impl Into<String>) -> RoutedError {
    RoutedError {
        error: internal_error(message),
        resolution: None,
    }
}

/// 使用宿主已验证的只读路由决策执行已解析命令。
#[allow(clippy::too_many_lines)]
pub async fn run_with_backend_with_route<B, R, O, E>(
    cli: Cli,
    backend: &mut B,
    route_context: ReadonlyRouteContext,
    input: &mut R,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    B: CliBackend + Send,
    R: BufRead,
    O: Write,
    E: Write,
{
    let mode = backend.mode();
    let feature = command_feature(&cli.command);
    let result = match cli.command {
        Command::Auth(AuthArgs {
            command: AuthCommand::Login(arguments),
        }) => run_login(cli.json, arguments, backend, input, stderr).await,
        Command::Auth(AuthArgs {
            command: AuthCommand::Status,
        }) => backend
            .auth_status()
            .await
            .map(|status| CommandOutput::Status(redacted_status(status))),
        Command::Auth(AuthArgs {
            command: AuthCommand::Logout,
        }) => backend
            .logout()
            .await
            .map(|()| CommandOutput::Logout(json!({ "loggedOut": true }))),
        Command::User(UserArgs {
            command: UserCommand::Show,
        }) => backend
            .get_user_info()
            .await
            .map(|profile| CommandOutput::Profile(redacted_profile(profile))),
        Command::Schedule(arguments) => run_schedule(arguments, backend).await,
        Command::Exam(arguments) => run_exam(arguments, backend).await,
        Command::Grades(arguments) => run_grades(arguments, backend).await,
        Command::Classroom(arguments) => run_classroom(arguments, backend).await,
        Command::Spoc(arguments) => run_spoc(arguments, backend).await,
        Command::Judge(arguments) => run_judge(arguments, backend).await,
        Command::Signin(SigninArgs {
            command: SigninCommand::Today,
        }) => backend
            .signin_today()
            .await
            .and_then(|data| readonly(data, CliFeature::Signin)),
        Command::Signin(SigninArgs {
            command:
                SigninCommand::Perform {
                    course_id,
                    confirm_write,
                },
        }) => {
            if confirm_write {
                backend
                    .signin_perform(&course_id)
                    .await
                    .and_then(|data| readonly(data, CliFeature::Signin))
            } else {
                Err(invalid_input("签到是写操作，必须显式指定 --confirm-write"))
            }
        }
        Command::Libbook(arguments) => run_libbook(arguments, backend).await,
        Command::Bykc(arguments) => run_bykc(arguments, backend).await,
        Command::Cgyy(arguments) => run_cgyy(arguments, backend).await,
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Overview,
        }) => backend
            .ygdk_overview()
            .await
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        Command::Evaluation(arguments) => run_evaluation(arguments, backend).await,
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Records { page, size },
        }) => backend
            .ygdk_records(page, size)
            .await
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        Command::Ygdk(YgdkArgs {
            command:
                YgdkCommand::Submit {
                    item_id,
                    start_time,
                    end_time,
                    place,
                    photo,
                    share_to_square,
                    confirm_write,
                },
        }) => {
            if confirm_write {
                match build_ygdk_request(
                    item_id,
                    start_time,
                    end_time,
                    place,
                    &photo,
                    share_to_square,
                ) {
                    Ok(request) => backend
                        .ygdk_submit(request)
                        .await
                        .and_then(|data| readonly(data, CliFeature::Ygdk)),
                    Err(error) => Err(error),
                }
            } else {
                Err(invalid_input("打卡是写操作，必须显式指定 --confirm-write"))
            }
        }
    };

    render_result(
        cli.json,
        mode,
        feature,
        route_context,
        result,
        stdout,
        stderr,
    )
}

async fn run_login<B, R, E>(
    json_mode: bool,
    arguments: LoginArgs,
    backend: &mut B,
    input: &mut R,
    stderr: &mut E,
) -> Result<CommandOutput>
where
    B: CliBackend + Send,
    R: BufRead,
    E: Write,
{
    let username = if arguments.username_stdin {
        if arguments.username.is_some() {
            return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
        }
        let username = read_secret_line(input, "标准输入中缺少用户名")?;
        if username.trim().is_empty() {
            return Err(invalid_input("用户名不能为空"));
        }
        username
    } else {
        match arguments.username {
            Some(username) if !username.trim().is_empty() => username,
            Some(_) if json_mode => return Err(invalid_input("用户名不能为空")),
            None if json_mode => return Err(invalid_input("JSON 模式必须提供 --username")),
            _ => prompt_line(input, stderr, "用户名：")?,
        }
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "标准输入中缺少密码")?
    } else if json_mode {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    } else {
        rpassword::prompt_password("密码：").map_err(|_| internal_error("无法安全读取密码"))?
    };

    backend
        .login(LoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
        .map(|profile| CommandOutput::Profile(redacted_profile(profile)))
}

async fn run_schedule<B: CliBackend + Send>(
    arguments: ScheduleArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ScheduleCommand::Terms => backend
            .schedule_terms()
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Weeks { term } => backend
            .schedule_weeks(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Current { term, week } => backend
            .schedule_week(&term, week)
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Today => backend
            .schedule_today()
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
    }
}

async fn run_exam<B: CliBackend + Send>(
    arguments: ExamArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ExamCommand::List { term } => backend
            .exam_arrangement(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Exam)),
    }
}

async fn run_grades<B: CliBackend + Send>(
    arguments: GradesArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        GradesCommand::List { term } => backend
            .grades(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Grades)),
    }
}

async fn run_classroom<B: CliBackend + Send>(
    arguments: ClassroomArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ClassroomCommand::Search { campus, date } => backend
            .classroom_search(campus, &date)
            .await
            .and_then(|result| readonly(result, CliFeature::Classroom)),
    }
}

async fn run_spoc<B: CliBackend + Send>(
    arguments: SpocArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        SpocCommand::Assignments => backend
            .spoc_assignments()
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
        SpocCommand::Diagnostics => backend
            .spoc_assignments_diagnostics()
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => backend
            .spoc_assignment(&id)
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
    }
}

async fn run_judge<B: CliBackend + Send>(
    arguments: JudgeArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        JudgeCommand::Assignments { include_expired } => backend
            .judge_assignments(include_expired)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Diagnostics { include_expired } => backend
            .judge_assignments_diagnostics(include_expired)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => backend
            .judge_assignment(&course_id, &id)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("希冀详情键必须使用 course-id:assignment-id 格式")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "希冀详情键必须使用 course-id:assignment-id 格式",
                        ));
                    }
                    Ok(JudgeAssignmentKey {
                        course_id: course_id.into(),
                        assignment_id: assignment_id.into(),
                    })
                })
                .collect::<Result<Vec<_>>>()?;
            backend
                .judge_assignment_details(&parsed)
                .await
                .and_then(|result| readonly(result, CliFeature::Judge))
        }
    }
}

async fn run_libbook<B: CliBackend + Send>(
    arguments: LibBookArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        LibBookCommand::Libraries { day } => backend
            .libbook_libraries(&day)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Areas {
            premises_id,
            storey_id,
            day,
        } => backend
            .libbook_areas(&premises_id, storey_id.as_deref(), &day)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::AreaDetail { area_id } => backend
            .libbook_area_detail(&area_id)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Seats {
            area_id,
            day,
            start_time,
            end_time,
        } => backend
            .libbook_seats(&area_id, &day, &start_time, &end_time)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Bookings { page, limit } => backend
            .libbook_bookings(page, limit)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Reserve {
            area_id,
            seat_id,
            day,
            segment,
            start_time,
            end_time,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("预约是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .libbook_reserve(LibBookReserveRequest {
                    area_id,
                    seat_id,
                    day,
                    segment,
                    start_time,
                    end_time,
                })
                .await
                .and_then(|result| readonly(result, CliFeature::LibBook))
        }
        LibBookCommand::Cancel {
            booking_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input(
                    "取消预约是写操作，必须显式指定 --confirm-write",
                ));
            }
            backend
                .libbook_cancel_booking(&booking_id)
                .await
                .and_then(|result| readonly(result, CliFeature::LibBook))
        }
    }
}

async fn run_routed_evaluation<B: RoutedCliBackend + Send>(
    arguments: EvaluationArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        EvaluationCommand::All => {
            routed_readonly(backend.evaluation_all().await, CliFeature::Evaluation)
        }
        EvaluationCommand::Pending => match backend.evaluation_all().await {
            Ok(value) => {
                let data = value
                    .data
                    .courses
                    .into_iter()
                    .filter(|course| !course.is_evaluated)
                    .collect::<Vec<_>>();
                Ok(Routed {
                    data: CommandOutput::Readonly {
                        data: serde_json::to_value(data).unwrap_or(serde_json::Value::Null),
                        route: value.resolution.mode,
                        feature: CliFeature::Evaluation,
                    },
                    resolution: value.resolution,
                })
            }
            Err(error) => Err(error),
        },
        EvaluationCommand::Submit {
            payload,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("评教是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            let payload = read_evaluation_payload(&payload).map_err(|error| RoutedError {
                error,
                resolution: None,
            })?;
            routed_readonly(
                backend.evaluation_submit(payload).await,
                CliFeature::Evaluation,
            )
        }
        EvaluationCommand::SubmitPending { confirm_write } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("评教是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            let value = backend.evaluation_all().await?;
            let courses = value
                .data
                .courses
                .into_iter()
                .filter(|course| !course.is_evaluated)
                .collect();
            routed_readonly(
                backend.evaluation_submit_courses(courses).await,
                CliFeature::Evaluation,
            )
        }
    }
}

async fn run_evaluation<B: CliBackend + Send>(
    arguments: EvaluationArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        EvaluationCommand::All => backend
            .evaluation_all()
            .await
            .and_then(|result| readonly(result, CliFeature::Evaluation)),
        EvaluationCommand::Pending => backend.evaluation_all().await.and_then(|result| {
            let pending: Vec<_> = result
                .data
                .courses
                .into_iter()
                .filter(|course| !course.is_evaluated)
                .collect();
            Ok(CommandOutput::Readonly {
                data: serde_json::to_value(pending)
                    .map_err(|_| internal_error("无法序列化评教输出"))?,
                route: result.resolved_route,
                feature: CliFeature::Evaluation,
            })
        }),
        EvaluationCommand::Submit {
            payload,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("评教是写操作，必须显式指定 --confirm-write"));
            }
            let payload = read_evaluation_payload(&payload)?;
            backend
                .evaluation_submit(payload)
                .await
                .and_then(|result| readonly(result, CliFeature::Evaluation))
        }
        EvaluationCommand::SubmitPending { confirm_write } => {
            if !confirm_write {
                return Err(invalid_input("评教是写操作，必须显式指定 --confirm-write"));
            }
            let result = backend.evaluation_all().await?;
            let courses = result
                .data
                .courses
                .into_iter()
                .filter(|course| !course.is_evaluated)
                .collect();
            backend
                .evaluation_submit_courses(courses)
                .await
                .and_then(|result| readonly(result, CliFeature::Evaluation))
        }
    }
}

async fn run_bykc<B: CliBackend + Send>(
    arguments: BykcArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        BykcCommand::Profile => backend
            .bykc_profile()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Courses { page, size, all } => backend
            .bykc_courses(page, size, all)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Course { id } => backend
            .bykc_course_detail(id)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Chosen => backend
            .bykc_chosen_courses()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Statistics => backend
            .bykc_statistics()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Select {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("选课是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .bykc_select_course(course_id)
                .await
                .and_then(|r| readonly(r, CliFeature::Bykc))
        }
        BykcCommand::Deselect {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("退选是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .bykc_deselect_course(course_id)
                .await
                .and_then(|r| readonly(r, CliFeature::Bykc))
        }
        BykcCommand::Sign {
            course_id,
            sign_type,
            lat,
            lng,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("签到是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .bykc_sign_course(BykcSignRequest {
                    course_id,
                    sign_type,
                    lat,
                    lng,
                })
                .await
                .and_then(|r| readonly(r, CliFeature::Bykc))
        }
    }
}

async fn run_cgyy<B: CliBackend + Send>(
    arguments: CgyyArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        CgyyCommand::Sites => backend
            .cgyy_sites()
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Purposes => backend
            .cgyy_purposes()
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Day { site_id, date } => backend
            .cgyy_day(site_id, &date)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Orders { page, size } => backend
            .cgyy_orders(page, size)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Detail { id } => backend
            .cgyy_order_detail(id)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::LockCode => {
            backend
                .cgyy_lock_code()
                .await
                .map(|result| CommandOutput::Readonly {
                    data: safe_lock_code_value(&result.data),
                    route: result.resolved_route,
                    feature: CliFeature::Cgyy,
                })
        }
        CgyyCommand::Cancel { id, confirm_write } => {
            if !confirm_write {
                return Err(invalid_input(
                    "取消预约是写操作，必须显式指定 --confirm-write",
                ));
            }
            backend
                .cgyy_cancel_order(id)
                .await
                .and_then(|result| readonly(result, CliFeature::Cgyy))
        }
        CgyyCommand::Submit {
            request_stdin,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("预约是写操作，必须显式指定 --confirm-write"));
            }
            if !request_stdin {
                return Err(invalid_input(
                    "预约请求含敏感字段，必须显式指定 --request-stdin",
                ));
            }
            let request = read_cgyy_request_stdin()?;
            backend
                .cgyy_submit_reservation(request)
                .await
                .and_then(|result| readonly(result, CliFeature::Cgyy))
        }
    }
}

fn render_result<O: Write, E: Write>(
    json_mode: bool,
    mode: ConnectionMode,
    feature: CliFeature,
    route_context: ReadonlyRouteContext,
    result: Result<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(output) => {
            let resolved_route = match &output {
                CommandOutput::Readonly { route, .. } => *route,
                _ => mode,
            };
            if json_mode {
                let value = match command_output_value(output) {
                    Ok(value) => value,
                    Err(error) => {
                        return render_resolved_error(
                            true,
                            feature,
                            route_context.resolution(resolved_route),
                            error,
                            stdout,
                            stderr,
                        );
                    }
                };
                let meta = route_context.meta(feature, resolved_route);
                if write_json(stdout, &RoutedJsonEnvelope::success(value, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if let CommandOutput::Readonly {
                data,
                route,
                feature,
            } = output
            {
                if writeln!(stdout, "{}（{route:?}）：{data}", feature.as_str()).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if render_human(output, stdout).is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_resolved_error(
            json_mode,
            feature,
            route_context.resolution(mode),
            error,
            stdout,
            stderr,
        ),
    }
}

fn render_resolved_error<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    resolution: RouteResolution,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit_code = error.code.exit_code() as i32;
    if json_mode {
        let error = project_cli_error(error, feature, resolution.mode);
        let meta = ResolvedRoutedJsonMeta::from_resolution(feature, resolution);
        let envelope = RoutedJsonEnvelope::<Value>::resolved_failure(error, meta);
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "错误：{error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

fn project_cli_error(
    error: UbaaError,
    _feature: CliFeature,
    _route: ConnectionMode,
) -> CliJsonError {
    CliJsonError::from_core(error)
}

/// 在后端构造前展示错误，并保持 JSON 标准输出约束。
pub fn render_startup_error<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit_code = error.code.exit_code() as i32;
    if json_mode {
        let envelope = RoutedJsonEnvelope::<Value>::unresolved_failure(
            CliJsonError::from_core(error),
            UnresolvedRoutedJsonMeta::new(feature),
        );
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "错误：{error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sensitive_mask_handles_unicode_without_byte_slicing() {
        assert_eq!(crate::render::mask_sensitive("ABCD1234"), "AB****34");
        assert_eq!(crate::render::mask_sensitive("北航用户甲乙"), "北航**甲乙");
    }

    #[test]
    fn lock_code_cli_projection_does_not_expose_opaque_payload() {
        let value = safe_lock_code_value(&CgyyLockCode { available: true });
        assert_eq!(value, json!({"available": true}));
    }
}
