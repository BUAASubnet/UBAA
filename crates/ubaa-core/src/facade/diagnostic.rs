//! 单路线诊断、测试与真实只读验证客户端。

use std::path::Path;
#[cfg(feature = "test-contract")]
use std::time::SystemTime;

use crate::auth::AuthWorkflow;
use crate::domain::{
    AuthStatus, BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, ClassroomQuery, ConnectionMode, ExamArrangement,
    FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary,
    JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail, LibBookBookingsPage,
    LibBookCancelPreflight, LibBookCancelRequest, LibBookCancelResult, LibBookLibrary,
    LibBookReservePreflight, LibBookReserveRequest, LibBookReserveResult, LibBookSeat, LoginInput,
    SigninActionResult, SigninClass, SpocAssignmentDetail, SpocAssignments,
    SpocAssignmentsDiagnostics, Term, TodayClass, UserProfile, Week, WeeklySchedule,
    YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkOverview, YgdkRecordsPage,
};
use crate::error::{ErrorCode, Result};
use crate::features::user;
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore, SessionStore};

use super::routing::invalid_input;

mod cgyy;
mod evaluation;

/// 仅供诊断、测试和真实验证使用的单路线客户端。
#[doc(hidden)]
pub struct RouteClient {
    runtime: ClientRuntime,
    auth: AuthWorkflow,
    sessions: Option<DualSessionCoordinator>,
}

impl RouteClient {
    /// 使用显式或持久化的连接模式打开诊断客户端。
    ///
    /// 当连接模式和持久化会话均不存在时返回 `None`，宿主可据此呈现命令级缺少会话提示，
    /// 无需读取持久化实现细节。
    ///
    /// # Errors
    ///
    /// 返回安全的传输或持久化错误。
    pub fn open(
        mode: Option<ConnectionMode>,
        config_dir: impl AsRef<Path>,
    ) -> Result<Option<Self>> {
        let store = FileSessionStore::new(config_dir)?;
        let sessions = DualSessionCoordinator::new(store)?;
        let Some(mode) = mode.or_else(|| sessions.active_routes().into_iter().next()) else {
            return Ok(None);
        };
        let route_store = sessions.route_store(mode);
        Self::build(mode, ReqwestTransport::new()?, route_store, Some(sessions)).map(Some)
    }

    /// 在宿主选定的配置目录下构造生产客户端。
    ///
    /// # Errors
    ///
    /// 返回安全的传输或持久化错误。
    pub fn new(mode: ConnectionMode, config_dir: impl AsRef<Path>) -> Result<Self> {
        let store = FileSessionStore::new(config_dir)?;
        let sessions = DualSessionCoordinator::new(store)?;
        let route_store = sessions.route_store(mode);
        Self::build(mode, ReqwestTransport::new()?, route_store, Some(sessions))
    }

    /// 使用注入的传输和持久化端口构造客户端。
    ///
    /// # Errors
    ///
    /// 当无法加载已有会话时返回安全的持久化错误。
    #[cfg(feature = "test-contract")]
    #[doc(hidden)]
    pub fn with_transport<T, S>(mode: ConnectionMode, transport: T, store: S) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        Self::build(mode, transport, store, None)
    }

    /// 使用注入的固定时钟构造测试客户端。
    ///
    /// # Errors
    ///
    /// 当无法加载已有会话时返回安全的持久化错误。
    #[cfg(feature = "test-contract")]
    #[doc(hidden)]
    pub fn with_transport_at<T, S>(
        mode: ConnectionMode,
        transport: T,
        store: S,
        now: SystemTime,
    ) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        Ok(Self {
            runtime: ClientRuntime::new_at(mode, transport, store, now)?,
            auth: AuthWorkflow::default(),
            sessions: None,
        })
    }

    fn build<T, S>(
        mode: ConnectionMode,
        transport: T,
        store: S,
        sessions: Option<DualSessionCoordinator>,
    ) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        Ok(Self {
            runtime: ClientRuntime::new(mode, transport, store)?,
            auth: AuthWorkflow::default(),
            sessions,
        })
    }

    /// 返回此客户端固定的连接模式。
    #[must_use]
    pub const fn mode(&self) -> ConnectionMode {
        self.runtime.mode()
    }

    /// 加载并校验当前客户端的 SSO 登录页。
    ///
    /// # Errors
    ///
    /// 返回安全的网络、认证或上游协议错误。
    pub async fn prepare_login(&mut self) -> Result<()> {
        self.guard_latest_session_ownership()?;
        let result = self.auth.prepare_login(&mut self.runtime).await;
        self.finish_session_operation(result)
    }

    /// 提交一份凭据表单、激活用户中心并返回解析后的资料。
    ///
    /// # Errors
    ///
    /// 返回稳定的输入、认证、网络或上游错误。
    pub async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        // 登录会发送凭据 POST，同样必须在任何网络副作用前确认修订仍归当前运行时所有。
        self.guard_latest_session_ownership()?;
        let result = self.auth.login(&mut self.runtime, input).await;
        self.finish_session_operation(result)
    }

    /// 校验当前用户中心会话并刷新最近活动时间。
    ///
    /// # Errors
    ///
    /// 显式失效时返回需要认证；超时或 5xx 时保留现有状态。
    pub async fn auth_status(&mut self) -> Result<AuthStatus> {
        self.guard_session_ownership()?;
        let mut clear_workflow = || self.auth.clear();
        let result = user::auth_status(&mut self.runtime, &mut clear_workflow).await;
        self.finish_session_operation(result)
    }

    /// 获取并解析最新的用户中心资料。
    ///
    /// # Errors
    ///
    /// 返回稳定的认证、网络、可用性或解析错误。
    pub async fn get_user_info(&mut self) -> Result<UserProfile> {
        self.guard_session_ownership()?;
        let mut clear_workflow = || self.auth.clear();
        let result = user::get_user_info(&mut self.runtime, &mut clear_workflow).await;
        self.finish_session_operation(result)
    }

    /// 尽力执行远程注销，然后无条件清理客户端内存。
    ///
    /// # Errors
    ///
    /// 返回持久化或修订版本错误；远程注销失败会被有意忽略。
    pub async fn logout(&mut self) -> Result<()> {
        self.guard_latest_session_ownership()?;
        let result = self.auth.logout(&mut self.runtime).await;
        self.finish_session_operation(result)
    }

    /// 查询博雅用户资料。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        self.guard_session_ownership()?;
        let result = crate::features::bykc::get_profile(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询博雅课程分页。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        self.guard_session_ownership()?;
        if page <= 0 || size <= 0 {
            return Err(invalid_input("页码和每页数量必须为正数"));
        }
        let result = crate::features::bykc::get_courses(&mut self.runtime, page, size, all).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询博雅课程详情。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn bykc_course_detail(&mut self, id: i64) -> Result<FeatureResult<BykcCourse>> {
        self.guard_session_ownership()?;
        if id <= 0 {
            return Err(invalid_input("课程标识必须为正数"));
        }
        let result = crate::features::bykc::get_course_detail(&mut self.runtime, id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询博雅已选课程。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        self.guard_session_ownership()?;
        let result = crate::features::bykc::get_chosen_courses(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询博雅修读统计。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        self.guard_session_ownership()?;
        let result = crate::features::bykc::get_statistics(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 选择一门博雅课程。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn bykc_select_course(
        &mut self,
        course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::bykc::select_course(&mut self.runtime, course_id).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    /// 退选一门博雅课程。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn bykc_deselect_course(
        &mut self,
        course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::bykc::deselect_course(&mut self.runtime, course_id).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    /// 提交博雅课程签到。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::bykc::sign_course(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取可用的学期列表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_terms(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定学期的教学周。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_weeks(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定周次的课表。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn schedule_week(
        &mut self,
        term: &str,
        week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        self.guard_session_ownership()?;
        if term.trim().is_empty() || week <= 0 {
            return Err(crate::error::UbaaError::new(
                crate::error::ErrorCode::InvalidInput,
                crate::error::ErrorKind::Input,
                false,
                "学期不能为空且周次必须为正数",
            ));
        }
        let result = crate::features::schedule::get_week(&mut self.runtime, term, week).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取今日课表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_today(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定学期的考试安排。
    ///
    /// # Errors
    ///
    /// 参数无效、会话校验失败、网络请求失败或上游响应处理失败时返回错误。
    pub async fn exam_arrangement(&mut self, term: &str) -> Result<FeatureResult<ExamArrangement>> {
        self.guard_session_ownership()?;
        if term.trim().is_empty() {
            return Err(crate::error::UbaaError::new(
                crate::error::ErrorCode::InvalidInput,
                crate::error::ErrorKind::Input,
                false,
                "学期不能为空",
            ));
        }
        let result = crate::features::schedule::get_exam(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定学期的成绩。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn grades(&mut self, term: &str) -> Result<FeatureResult<GradeData>> {
        self.guard_session_ownership()?;
        let result = crate::features::grades::get_grades(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询可用教室。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn classroom_search(
        &mut self,
        campus_id: i32,
        date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        self.guard_session_ownership()?;
        let result = crate::features::classroom::search(&mut self.runtime, campus_id, date).await;
        let classrooms = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, classrooms))
    }

    /// 查询今日课堂签到状态。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        self.guard_session_ownership()?;
        let result = crate::features::signin::get_today(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 执行指定课程的课堂签到。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn signin_perform(
        &mut self,
        course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::signin::perform_signin(&mut self.runtime, course_id).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询图书馆楼馆列表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn libbook_libraries(
        &mut self,
        day: &str,
    ) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        self.guard_session_ownership()?;
        let result = crate::features::libbook::get_libraries(&mut self.runtime, day).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询图书馆分区列表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        self.guard_session_ownership()?;
        let result =
            crate::features::libbook::get_areas(&mut self.runtime, premises_id, storey_id, day)
                .await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询图书馆分区详情。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn libbook_area_detail(
        &mut self,
        area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        self.guard_session_ownership()?;
        let result = crate::features::libbook::get_area_detail(&mut self.runtime, area_id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询图书馆座位列表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        self.guard_session_ownership()?;
        let result = crate::features::libbook::get_seats(
            &mut self.runtime,
            area_id,
            day,
            start_time,
            end_time,
        )
        .await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询当前用户的图书馆预约记录。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        self.guard_session_ownership()?;
        let result = crate::features::libbook::get_bookings(&mut self.runtime, page, limit).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 只读复核图书馆预约的当前日期、时段和唯一座位资格。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、路线读取失败、目标不唯一或资格不足时返回错误。
    pub async fn preflight_libbook_reserve(
        &mut self,
        request: &LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReservePreflight>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::libbook::preflight_reserve(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 提交图书馆座位预约。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::libbook::reserve(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 只读复核 action 所属分页内唯一 active 的图书馆预约。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、路线读取失败、目标不唯一或取消资格不足时返回错误。
    pub async fn preflight_libbook_cancel(
        &mut self,
        request: &LibBookCancelRequest,
    ) -> Result<FeatureResult<LibBookCancelPreflight>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::libbook::preflight_cancel(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 取消图书馆预约。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn libbook_cancel_booking(
        &mut self,
        request: LibBookCancelRequest,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        self.guard_latest_session_ownership()?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::libbook::cancel_booking(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询阳光打卡概览。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        self.guard_session_ownership()?;
        let result = crate::features::ygdk::get_overview(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询阳光打卡历史记录。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn ygdk_records(
        &mut self,
        page: i32,
        size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        self.guard_session_ownership()?;
        let result = crate::features::ygdk::get_records(&mut self.runtime, page, size).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 提交阳光打卡记录。
    ///
    /// # Errors
    ///
    /// 会话所有权校验、网络写请求或上游响应处理失败时返回错误。
    pub async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        self.guard_latest_session_ownership()?;
        crate::features::ygdk::validate_submit_request(&request)?;
        self.runtime.begin_non_idempotent_operation();
        let result = crate::features::ygdk::submit_clockin(&mut self.runtime, request).await;
        let data = self.finish_write_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取当前 SPOC 作业列表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取当前 SPOC 列表，并返回安全的全局页面完成证据。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments_diagnostics(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取一项 SPOC 作业详情。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn spoc_assignment(
        &mut self,
        assignment_id: &str,
    ) -> Result<FeatureResult<SpocAssignmentDetail>> {
        self.guard_session_ownership()?;
        let result =
            crate::features::spoc::get_assignment_detail(&mut self.runtime, assignment_id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取希冀作业列表。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        self.guard_session_ownership()?;
        let result =
            crate::features::judge::get_assignments(&mut self.runtime, include_expired).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取希冀作业列表，并返回安全的解析计数。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        self.guard_session_ownership()?;
        let result =
            crate::features::judge::get_assignments_diagnostics(&mut self.runtime, include_expired)
                .await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取一项希冀作业详情。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn judge_assignment(
        &mut self,
        course_id: &str,
        assignment_id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        self.guard_session_ownership()?;
        let result = crate::features::judge::get_assignment_detail(
            &mut self.runtime,
            course_id,
            assignment_id,
        )
        .await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取多项希冀作业详情。
    ///
    /// # Errors
    ///
    /// 会话校验或清理、网络请求或上游响应处理失败时返回错误。
    pub async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        self.guard_session_ownership()?;
        let result = crate::features::judge::get_assignment_details(&mut self.runtime, keys).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
}
impl RouteClient {
    fn guard_session_ownership(&mut self) -> Result<()> {
        if self
            .sessions
            .as_ref()
            .is_some_and(DualSessionCoordinator::is_conflicted)
        {
            self.runtime.clear_memory();
            self.auth.clear();
            return Err(DualSessionCoordinator::conflict_error());
        }
        if !self.runtime.has_local_session() && !self.auth.has_pending_login() {
            self.runtime.sync_empty_session_revision()?;
            return Ok(());
        }
        match self.runtime.ensure_session_revision() {
            Ok(()) => Ok(()),
            Err(error) => {
                self.runtime.clear_memory();
                self.auth.clear();
                Err(error)
            }
        }
    }

    /// 在会产生网络副作用的入口前确认当前运行时仍拥有最新会话修订。
    fn guard_latest_session_ownership(&mut self) -> Result<()> {
        self.guard_session_ownership()?;
        if !self.runtime.has_local_session() && !self.auth.has_pending_login() {
            self.runtime.sync_empty_session_revision()?;
            return Ok(());
        }
        match self.runtime.ensure_session_revision() {
            Ok(()) => Ok(()),
            Err(error) => {
                self.runtime.clear_memory();
                self.auth.clear();
                Err(error)
            }
        }
    }

    fn finish_session_operation<T>(&mut self, result: Result<T>) -> Result<T> {
        self.guard_session_ownership()?;
        result
    }

    fn cleanup_operation_result<T>(&mut self, result: &Result<T>) -> Result<()> {
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::AuthenticationRequired)
        {
            if self.runtime.has_local_session() {
                self.runtime.clear_with(|| self.auth.clear())?;
            } else {
                self.runtime.clear_memory();
                self.auth.clear();
            }
        }
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::InternalError)
            && !self.runtime.has_local_session()
        {
            self.auth.clear();
        }
        Ok(())
    }

    fn finish_readonly_operation<T>(&mut self, result: Result<T>) -> Result<T> {
        self.cleanup_operation_result(&result)?;
        self.finish_session_operation(result)
    }

    /// 写请求跨越发送边界后，收尾检查只负责使失效会话进入安全状态，不能覆盖写结果。
    fn finish_write_operation<T>(&mut self, result: Result<T>) -> Result<T> {
        if !self.runtime.take_non_idempotent_boundary_crossed() {
            return self.finish_readonly_operation(result);
        }
        let _ = self.cleanup_operation_result(&result);
        let _ = self.guard_session_ownership();
        result
    }
}
