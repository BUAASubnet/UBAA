//! CLI 后端契约与默认不可用错误。

use ubaa_core::facade::{CampusMetrics, NetworkUsage, PortalProfile};

use async_trait::async_trait;
use ubaa_core::facade::{
    BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, CgyyCancelOrderRequest, CgyyCancelOrderResult, CgyyDayInfo,
    CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeType, CgyyReservationResult,
    CgyyReservationSubmitRequest, CgyyVenueSite, ClassroomQuery, ConnectionMode,
    EvaluationBatchResult, EvaluationCoursesResponse, EvaluationSubmitCoursesRequest,
    ExamArrangement, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary,
    JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail, LibBookBookingsPage,
    LibBookCancelRequest, LibBookCancelResult, LibBookLibrary, LibBookReserveRequest,
    LibBookReserveResult, LibBookSeat, SigninActionResult, SigninClass, SpocAssignmentDetail,
    SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass, UserProfile, Week,
    WeeklySchedule, YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkOverview,
    YgdkRecordsPage,
};
use ubaa_core::facade::{IhomeAppeal, IhomeConfig, IhomeNotice, IhomePage, IhomeQuery};
use ubaa_core::facade::{Result, RoutedResult};

use crate::io::input::internal_error;

/// 普通用户命令和只读命令所需的聚合 Core 门面。
///
/// Core 会把每个已完成的路由决策与操作结果一起返回。CLI 仅展示该决策，
/// 不自行选择或修复路由。
#[async_trait]
pub trait RoutedCliBackend {
    async fn finance_incomes(&mut self) -> RoutedResult<ubaa_core::facade::FinanceIncomes> {
        Err(ubaa_core::facade::RoutedError {
            error: internal_error("财务查询后端未接入"),
            resolution: None,
        })
    }
    async fn bhpan_execute(
        &mut self,
        _args: &crate::BhpanArgs,
        _input: &crate::bhpan::BhpanPreparedInput,
    ) -> RoutedResult<crate::bhpan::BhpanOutput> {
        Err(ubaa_core::facade::RoutedError {
            error: internal_error("当前后端未接入云盘命令"),
            resolution: None,
        })
    }

    async fn portal_profile(&mut self) -> RoutedResult<PortalProfile>;
    async fn campus_metrics(&mut self) -> RoutedResult<CampusMetrics>;
    async fn network_usage(&mut self) -> RoutedResult<NetworkUsage>;
    async fn ihome_page(&mut self, _query: IhomeQuery) -> RoutedResult<IhomePage>;
    async fn ihome_detail(&mut self, _id: i64, _mine: bool) -> RoutedResult<IhomeAppeal>;
    async fn ihome_config(&mut self) -> RoutedResult<IhomeConfig>;
    async fn ihome_notices(&mut self) -> RoutedResult<Vec<IhomeNotice>>;
    async fn ihome_notice(&mut self, _id: i64) -> RoutedResult<IhomeNotice>;

    /// 通过 Core 路由查询全部评教课程。
    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse>;
    /// 在调用方固定的原路线刷新评教课程，不重新执行路由策略。
    async fn evaluation_all_on_route(
        &mut self,
        _route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse>;
    /// 仅在 fresh commit 仍解析到调用方确认的路线时提交 typed 目标。
    async fn evaluation_submit_courses_if_route_matches(
        &mut self,
        _request: EvaluationSubmitCoursesRequest,
        _expected_route: ConnectionMode,
    ) -> RoutedResult<EvaluationBatchResult>;
    /// 查询今日课堂签到状态。
    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>>;
    async fn signin_perform(&mut self, _course_id: &str) -> RoutedResult<SigninActionResult>;
    /// 通过 Core 路由查询图书馆楼馆列表。
    async fn libbook_libraries(&mut self, _day: &str) -> RoutedResult<Vec<LibBookLibrary>>;
    /// 通过 Core 路由查询图书馆分区列表。
    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> RoutedResult<Vec<LibBookArea>>;
    /// 通过 Core 路由查询图书馆分区详情。
    async fn libbook_area_detail(&mut self, _area_id: &str) -> RoutedResult<LibBookAreaDetail>;
    /// 通过 Core 路由查询图书馆座位状态。
    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>>;
    /// 通过 Core 路由查询图书馆预约记录。
    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> RoutedResult<LibBookBookingsPage>;
    async fn libbook_reserve(
        &mut self,
        _request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult>;
    async fn libbook_cancel_booking(
        &mut self,
        _request: LibBookCancelRequest,
    ) -> RoutedResult<LibBookCancelResult>;
    /// 通过 Core 路由查询博雅用户资料。
    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile>;
    /// 通过 Core 路由分页查询博雅课程。
    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
        _all: bool,
    ) -> RoutedResult<BykcCoursePage>;
    /// 通过 Core 路由查询博雅课程详情。
    async fn bykc_course_detail(&mut self, _id: i64) -> RoutedResult<BykcCourse>;
    /// 通过 Core 路由查询博雅已选课程。
    async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>>;
    /// 通过 Core 路由查询博雅修读统计。
    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics>;
    async fn bykc_select_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult>;
    async fn bykc_deselect_course(&mut self, _course_id: i64) -> RoutedResult<BykcActionResult>;
    async fn bykc_sign_course(
        &mut self,
        _request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult>;
    /// 通过 Core 路由查询研讨室站点。
    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>>;
    async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode>;
    /// 通过 Core 路由查询预约用途。
    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>>;
    /// 通过 Core 路由查询日期预约信息。
    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> RoutedResult<CgyyDayInfo>;
    /// 通过 Core 路由查询当前用户订单。
    async fn cgyy_orders(&mut self, _page: i32, _size: i32) -> RoutedResult<CgyyOrdersPage>;
    /// 通过 Core 路由查询订单详情。
    async fn cgyy_order_detail(&mut self, _id: i32) -> RoutedResult<CgyyOrder>;
    /// 通过 Core 路由取消预约订单。
    async fn cgyy_cancel_order(
        &mut self,
        _request: CgyyCancelOrderRequest,
    ) -> RoutedResult<CgyyCancelOrderResult>;
    async fn cgyy_submit_reservation(
        &mut self,
        _request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult>;
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview>;
    async fn ygdk_records(&mut self, _page: i32, _size: i32) -> RoutedResult<YgdkRecordsPage>;
    async fn ygdk_submit(
        &mut self,
        _request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult>;
    /// 在调用方固定的已解析路线刷新阳光打卡概览。
    async fn ygdk_overview_on_route(&mut self, _route: ConnectionMode) -> Result<YgdkOverview>;
    /// 在调用方固定的已解析路线刷新阳光打卡记录。
    async fn ygdk_records_on_route(
        &mut self,
        _route: ConnectionMode,
        _page: i32,
        _size: i32,
    ) -> Result<YgdkRecordsPage>;
    /// 通过 Core 路由获取用户中心资料。
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile>;
    /// 通过 Core 路由查询学期。
    async fn exam_terms(&mut self) -> RoutedResult<Vec<Term>>;
    async fn grades_overview(&mut self) -> RoutedResult<ubaa_core::facade::GradeOverview>;
    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>>;
    /// 通过 Core 路由查询教学周。
    async fn schedule_weeks(&mut self, _term: &str) -> RoutedResult<Vec<Week>>;
    /// 通过 Core 路由查询指定教学周。
    async fn schedule_week(&mut self, _term: &str, _week: i32) -> RoutedResult<WeeklySchedule>;
    /// 通过 Core 路由查询今日课程。
    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>>;
    /// 通过 Core 路由查询考试。
    async fn exam_arrangement(&mut self, _term: &str) -> RoutedResult<ExamArrangement>;
    /// 通过 Core 路由查询成绩。
    async fn grades(&mut self, _term: &str) -> RoutedResult<GradeData>;
    /// 通过 Core 路由查询空闲教室。
    async fn classroom_search(&mut self, _campus: i32, _date: &str)
    -> RoutedResult<ClassroomQuery>;
    /// 通过 Core 路由查询 SPOC 作业。
    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments>;
    /// 通过 Core 路由查询安全的 SPOC 全局分页诊断。
    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics>;
    /// 通过 Core 路由查询一项 SPOC 作业。
    async fn spoc_assignment(&mut self, _id: &str) -> RoutedResult<SpocAssignmentDetail>;
    /// 通过 Core 路由查询希冀作业。
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>>;
    /// 通过 Core 路由查询安全的希冀解析诊断。
    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics>;
    /// 通过 Core 路由查询一项希冀作业。
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail>;
    /// 通过一次 Core 路由决策查询多项希冀作业详情。
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>>;
}

#[cfg(test)]
mod contract_tests {
    #[test]
    fn backend_trait不保留默认不可用实现() {
        let source = include_str!("contract.rs");
        let trait_source = source.split("#[cfg(test)]").next().unwrap_or(source);
        assert!(!trait_source.contains("Err(unavailable("));
        assert!(!trait_source.contains("Err(routed_unavailable("));
    }
}
