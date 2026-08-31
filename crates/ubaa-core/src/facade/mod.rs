//! CLI 与未来绑定层使用的稳定 facade。
#![allow(clippy::missing_errors_doc, clippy::similar_names)]

use std::path::Path;
use std::time::Duration;

use crate::auth::AuthWorkflow;
use crate::config::{FeatureRouteConfig, RouteConfig};
use crate::connection::{CachingGatewayProbe, GatewayProbe, SystemGatewayProbe};
use crate::domain::{
    AuthStatus, BykcActionResult, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcSignRequest,
    BykcStatistics, BykcUserProfile, CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder,
    CgyyOrdersPage, CgyyPurposeType, CgyyPurposeTypes, CgyyReservationResult,
    CgyyReservationSubmitRequest, CgyyVenueSite, ClassroomQuery, ConnectionMode, DualLoginInput,
    DualLoginPreparation, EvaluationCourse, EvaluationCoursesResponse, EvaluationResult,
    ExamArrangement, FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey,
    JudgeAssignmentSummary, JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail,
    LibBookBookingsPage, LibBookCancelResult, LibBookLibrary, LibBookReserveRequest,
    LibBookReserveResult, LibBookSeat, LoginInput, LoginOutcome, LoginReadiness, ReadonlyFeature,
    RouteLoginResult, RouteLoginState, RoutePolicy, SigninActionResult, SigninClass,
    SpocAssignmentDetail, SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass,
    UserProfile, Week, WeeklySchedule, YgdkClockinSubmitRequest, YgdkClockinSubmitResult,
    YgdkOverview, YgdkRecordsPage,
};
use crate::error::{ErrorCode, Result};
use crate::features::user;
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore, SessionStore};

mod types;
use types::Operation;
pub use types::{Routed, RoutedError};
// 这些类型是宿主可见的安全路线诊断投影；其余 connection 实现仍属于 Core 内部。
pub use crate::connection::{NetworkState, RouteDiagnostic, RouteResolution};
mod aggregate_helpers;
use aggregate_helpers::{
    alternate_route, authentication_required, failed_preparation, failed_route,
    fixed_route_results, invalid_input, ready_route, routed_error, safe_error,
};
mod session_lifecycle;

/// 仅供诊断、测试和真实验证使用的单路线客户端。
#[doc(hidden)]
pub struct RouteClient {
    runtime: ClientRuntime,
    auth: AuthWorkflow,
    sessions: Option<DualSessionCoordinator>,
}

/// 面向宿主的聚合客户端，负责路由和相互独立的路线流程。
pub struct UbaaClient {
    config: RouteConfig,
    probe: Box<dyn GatewayProbe>,
    direct_runtime: ClientRuntime,
    webvpn_runtime: ClientRuntime,
    direct_auth: AuthWorkflow,
    webvpn_auth: AuthWorkflow,
    sessions: DualSessionCoordinator,
}

/// 普通路由 facade 操作返回的结果。
pub type RoutedResult<T> = std::result::Result<Routed<T>, RoutedError>;

impl UbaaClient {
    /// 基于一个双槽位会话文件打开生产 Direct 和 `WebVPN` 运行时。
    pub fn open(config_dir: impl AsRef<Path>) -> Result<Self> {
        let config_dir = config_dir.as_ref();
        let config = RouteConfig::load(config_dir)?;
        Self::with_routing(
            ReqwestTransport::new()?,
            ReqwestTransport::new()?,
            FileSessionStore::new(config_dir)?,
            config,
            SystemGatewayProbe,
        )
    }

    /// 使用可注入传输和默认路由构造聚合客户端。
    pub fn with_transports<TDirect, TWebVpn>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
    {
        Self::with_routing(
            direct_transport,
            webvpn_transport,
            store,
            RouteConfig::default(),
            SystemGatewayProbe,
        )
    }

    /// 使用可注入传输和路由输入构造聚合客户端。
    pub fn with_routing<TDirect, TWebVpn, P>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
        config: RouteConfig,
        probe: P,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
        P: GatewayProbe + 'static,
    {
        let sessions = DualSessionCoordinator::new(store)?;
        let direct_store = sessions.route_store(ConnectionMode::Direct);
        let webvpn_store = sessions.route_store(ConnectionMode::WebVpn);
        Ok(Self {
            config,
            probe: Box::new(CachingGatewayProbe::with_default_ttl(probe)),
            direct_runtime: ClientRuntime::new(
                ConnectionMode::Direct,
                direct_transport,
                direct_store,
            )?,
            webvpn_runtime: ClientRuntime::new(
                ConnectionMode::WebVpn,
                webvpn_transport,
                webvpn_store,
            )?,
            direct_auth: AuthWorkflow::default(),
            webvpn_auth: AuthWorkflow::default(),
            sessions,
        })
    }

    /// 返回当前客户端拥有的路线槽位。
    #[must_use]
    pub fn active_routes(&self) -> Vec<ConnectionMode> {
        self.sessions.active_routes()
    }

    /// 返回聚合认证操作使用的配置策略。
    #[must_use]
    pub const fn default_route_policy(&self) -> RoutePolicy {
        self.config.default
    }

    /// 按固定 Direct、`WebVPN` 顺序准备两条路线并返回安全路线状态。
    pub async fn prepare_login(&mut self) -> DualLoginPreparation {
        if let Err(error) = self.guard_latest_session_ownership() {
            return failed_preparation(&error);
        }
        let mut routes = Vec::with_capacity(2);
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let preparation = self.prepare_route(route).await;
            routes.push(match preparation {
                Ok(()) => ready_route(route),
                Err(error) => failed_route(route, &error),
            });
            if self.sessions.is_conflicted() {
                break;
            }
        }
        if let Err(error) = self.clear_on_session_conflict() {
            return failed_preparation(&error);
        }
        DualLoginPreparation {
            routes: fixed_route_results(routes),
        }
    }

    /// 分别向 Direct 和 `WebVPN` 提交凭据，并保留部分成功结果。
    pub async fn login(&mut self, input: DualLoginInput) -> Result<LoginOutcome> {
        self.guard_latest_session_ownership()?;
        let mut routes = Vec::with_capacity(2);
        let mut profile = None;
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let login = self
                .login_route(
                    route,
                    LoginInput {
                        username: input.username.clone(),
                        password: input.password.clone(),
                    },
                )
                .await;
            let (route_result, current) = Self::finish_route_login(route, login);
            if profile.is_none() {
                profile = current;
            }
            routes.push(route_result);
            if self.sessions.is_conflicted() {
                break;
            }
        }
        self.clear_on_session_conflict()?;
        let ready = routes
            .iter()
            .filter(|route| route.state == RouteLoginState::Ready)
            .count();
        let readiness = match ready {
            2 => LoginReadiness::AllReady,
            1 => LoginReadiness::Partial,
            _ => LoginReadiness::NoneReady,
        };
        Ok(LoginOutcome {
            readiness,
            routes: fixed_route_results(routes),
            profile,
        })
    }

    /// 清理两条路线流程及两个持久化槽位。
    pub async fn logout(&mut self) -> Result<()> {
        self.guard_latest_session_ownership()?;
        self.direct_auth
            .remote_logout(&mut self.direct_runtime)
            .await;
        self.webvpn_auth
            .remote_logout(&mut self.webvpn_runtime)
            .await;
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
        let revisions = self.sessions.clear_both()?;
        self.direct_runtime.set_session_revision(revisions.direct);
        self.webvpn_runtime.set_session_revision(revisions.webvpn);
        Ok(())
    }

    /// 校验两条持久化路线会话，并保留部分成功结果。
    pub async fn auth_status(&mut self) -> Result<LoginOutcome> {
        self.clear_on_session_conflict()?;
        let mut routes = Vec::with_capacity(2);
        let mut profile = None;
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            match self.auth_status_route(route).await {
                Ok(status) => {
                    if profile.is_none() {
                        profile = Some(status.user);
                    }
                    routes.push(RouteLoginResult {
                        route,
                        state: RouteLoginState::Ready,
                        error: None,
                    });
                }
                Err(error) => routes.push(RouteLoginResult {
                    route,
                    state: RouteLoginState::Failed,
                    error: Some(safe_error(&error)),
                }),
            }
            if self.sessions.is_conflicted() {
                break;
            }
        }
        self.clear_on_session_conflict()?;
        let ready = routes
            .iter()
            .filter(|route| route.state == RouteLoginState::Ready)
            .count();
        Ok(LoginOutcome {
            readiness: match ready {
                2 => LoginReadiness::AllReady,
                1 => LoginReadiness::Partial,
                _ => LoginReadiness::NoneReady,
            },
            routes: fixed_route_results(routes),
            profile,
        })
    }

    /// 通过默认路线策略获取用户中心资料。
    pub async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        let resolution = self.resolve_operation(Operation::User)?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                let mut clear_workflow = || self.direct_auth.clear();
                user::get_user_info(&mut self.direct_runtime, &mut clear_workflow).await
            }
            ConnectionMode::WebVpn => {
                let mut clear_workflow = || self.webvpn_auth.clear();
                user::get_user_info(&mut self.webvpn_runtime, &mut clear_workflow).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询博雅用户资料。
    pub async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::get_profile(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::get_profile(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询博雅课程分页。
    pub async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        if page <= 0 || size <= 0 {
            return Err(routed_error(
                invalid_input("页码和每页数量必须为正数"),
                resolution,
            ));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::get_courses(&mut self.direct_runtime, page, size, all).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::get_courses(&mut self.webvpn_runtime, page, size, all).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询博雅课程详情。
    pub async fn bykc_course_detail(&mut self, id: i64) -> RoutedResult<BykcCourse> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        if id <= 0 {
            return Err(routed_error(
                invalid_input("课程标识必须为正数"),
                resolution,
            ));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::get_course_detail(&mut self.direct_runtime, id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::get_course_detail(&mut self.webvpn_runtime, id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询博雅已选课程。
    pub async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::get_chosen_courses(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::get_chosen_courses(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询博雅修读统计。
    pub async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::get_statistics(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::get_statistics(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询全部评教课程。
    pub async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::evaluation::get_all(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::evaluation::get_all(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 提交由宿主构造的评教结果列表。
    pub async fn evaluation_submit(
        &mut self,
        pjjglist: Vec<serde_json::Value>,
    ) -> RoutedResult<Vec<EvaluationResult>> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::evaluation::submit_payload(
                    &mut self.direct_runtime,
                    pjjglist.clone(),
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::evaluation::submit_payload(&mut self.webvpn_runtime, pjjglist)
                    .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 按冻结问卷链自动构造并提交课程评教。
    pub async fn evaluation_submit_courses(
        &mut self,
        courses: Vec<EvaluationCourse>,
    ) -> RoutedResult<Vec<EvaluationResult>> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::evaluation::submit_courses(
                    &mut self.direct_runtime,
                    courses.clone(),
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::evaluation::submit_courses(&mut self.webvpn_runtime, courses).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn bykc_select_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::select_course(&mut self.direct_runtime, course_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::select_course(&mut self.webvpn_runtime, course_id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn bykc_deselect_course(&mut self, course_id: i64) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::deselect_course(&mut self.direct_runtime, course_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::deselect_course(&mut self.webvpn_runtime, course_id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> RoutedResult<BykcActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::bykc::sign_course(&mut self.direct_runtime, request.clone()).await
            }
            ConnectionMode::WebVpn => {
                crate::features::bykc::sign_course(&mut self.webvpn_runtime, request).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询场馆站点。
    pub async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "sites.list");
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_sites(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_sites(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询场馆用途类型。
    pub async fn cgyy_purpose_types(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "purposes.list");
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_purpose_types(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_purpose_types(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询场馆用途并保留上游或静态回退来源诊断。
    pub async fn cgyy_purpose_types_diagnostics(&mut self) -> RoutedResult<CgyyPurposeTypes> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_purpose_types_with_source(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_purpose_types_with_source(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(
            resolution,
            result.map(|(items, source)| CgyyPurposeTypes { items, source }),
        )
    }

    /// 查询场馆日期可用性。
    pub async fn cgyy_day_info(&mut self, site_id: i32, date: &str) -> RoutedResult<CgyyDayInfo> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "day.info");
        if site_id <= 0 || date.trim().is_empty() {
            return Err(routed_error(
                invalid_input("场馆站点和日期不能为空"),
                resolution,
            ));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_day_info(&mut self.direct_runtime, site_id, date).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_day_info(&mut self.webvpn_runtime, site_id, date).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询我的场馆订单。
    pub async fn cgyy_orders(&mut self, page: i32, size: i32) -> RoutedResult<CgyyOrdersPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.list");
        if page < 0 || size <= 0 {
            return Err(routed_error(invalid_input("分页参数无效"), resolution));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_orders(&mut self.direct_runtime, page, size).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_orders(&mut self.webvpn_runtime, page, size).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询场馆订单详情。
    pub async fn cgyy_order_detail(&mut self, id: i32) -> RoutedResult<CgyyOrder> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.detail");
        if id <= 0 {
            return Err(routed_error(
                invalid_input("订单标识必须为正数"),
                resolution,
            ));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_order_detail(&mut self.direct_runtime, id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_order_detail(&mut self.webvpn_runtime, id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.lock_code");
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::get_lock_code(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::get_lock_code(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 取消场馆预约订单。
    pub async fn cgyy_cancel_order(&mut self, id: i32) -> RoutedResult<CgyyActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.cancel");
        if id <= 0 {
            return Err(routed_error(
                invalid_input("订单标识必须为正数"),
                resolution,
            ));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::cancel_order(&mut self.direct_runtime, id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::cancel_order(&mut self.webvpn_runtime, id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 提交场馆预约；验证码材料可由调用方提供或由 Core 自动获取并校验。
    pub async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> RoutedResult<CgyyReservationResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "reservation.submit");
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::cgyy::submit_reservation(&mut self.direct_runtime, request).await
            }
            ConnectionMode::WebVpn => {
                crate::features::cgyy::submit_reservation(&mut self.webvpn_runtime, request).await
            }
        };
        self.finish_routed(resolution, result)
    }

    fn log_cgyy_route(&self, resolution: RouteResolution, operation: &str) {
        let runtime_mode = match resolution.mode {
            ConnectionMode::Direct => self.direct_runtime.mode(),
            ConnectionMode::WebVpn => self.webvpn_runtime.mode(),
        };
        tracing::debug!(
            target: "ubaa::cgyy",
            feature = "cgyy",
            operation,
            route_policy = ?resolution.policy,
            resolved_route = ?resolution.mode,
            selected_runtime = ?runtime_mode,
            "Cgyy 门面完成路线解析"
        );
    }

    /// 通过课表路线策略读取可用学期。
    pub async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::schedule::get_terms(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::schedule::get_terms(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过课表路线策略读取一个学期的教学周。
    pub async fn schedule_weeks(&mut self, term: &str) -> RoutedResult<Vec<Week>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::schedule::get_weeks(&mut self.direct_runtime, term).await
            }
            ConnectionMode::WebVpn => {
                crate::features::schedule::get_weeks(&mut self.webvpn_runtime, term).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过课表路线策略读取指定周课表。
    pub async fn schedule_week(&mut self, term: &str, week: i32) -> RoutedResult<WeeklySchedule> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        if term.trim().is_empty() || week <= 0 {
            return Err(routed_error(
                invalid_input("term and positive week are required"),
                resolution,
            ));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::schedule::get_week(&mut self.direct_runtime, term, week).await
            }
            ConnectionMode::WebVpn => {
                crate::features::schedule::get_week(&mut self.webvpn_runtime, term, week).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过课表路线策略读取今日课表。
    pub async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::schedule::get_today(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::schedule::get_today(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过考试路线策略读取一个学期的考试安排。
    pub async fn exam_arrangement(&mut self, term: &str) -> RoutedResult<ExamArrangement> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Exam))?;
        if term.trim().is_empty() {
            return Err(routed_error(invalid_input("term is required"), resolution));
        }
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::schedule::get_exam(&mut self.direct_runtime, term).await
            }
            ConnectionMode::WebVpn => {
                crate::features::schedule::get_exam(&mut self.webvpn_runtime, term).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过成绩路线策略读取一个学期的成绩。
    pub async fn grades(&mut self, term: &str) -> RoutedResult<GradeData> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Grades))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::grades::get_grades(&mut self.direct_runtime, term).await
            }
            ConnectionMode::WebVpn => {
                crate::features::grades::get_grades(&mut self.webvpn_runtime, term).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过空教室路线策略查询可用教室。
    pub async fn classroom_search(
        &mut self,
        campus_id: i32,
        date: &str,
    ) -> RoutedResult<ClassroomQuery> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Classroom))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::classroom::search(&mut self.direct_runtime, campus_id, date).await
            }
            ConnectionMode::WebVpn => {
                crate::features::classroom::search(&mut self.webvpn_runtime, campus_id, date).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过签到功能路由查询今日课堂签到状态。
    pub async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Signin))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::signin::get_today(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::signin::get_today(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 执行指定课程的课堂签到。
    pub async fn signin_perform(&mut self, course_id: &str) -> RoutedResult<SigninActionResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Signin))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::signin::perform_signin(&mut self.direct_runtime, course_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::signin::perform_signin(&mut self.webvpn_runtime, course_id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆楼馆列表。
    pub async fn libbook_libraries(&mut self, day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::get_libraries(&mut self.direct_runtime, day).await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::get_libraries(&mut self.webvpn_runtime, day).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆分区列表。
    pub async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::get_areas(
                    &mut self.direct_runtime,
                    premises_id,
                    storey_id,
                    day,
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::get_areas(
                    &mut self.webvpn_runtime,
                    premises_id,
                    storey_id,
                    day,
                )
                .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆分区详情。
    pub async fn libbook_area_detail(&mut self, area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::get_area_detail(&mut self.direct_runtime, area_id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::get_area_detail(&mut self.webvpn_runtime, area_id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆座位列表。
    pub async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::get_seats(
                    &mut self.direct_runtime,
                    area_id,
                    day,
                    start_time,
                    end_time,
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::get_seats(
                    &mut self.webvpn_runtime,
                    area_id,
                    day,
                    start_time,
                    end_time,
                )
                .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询当前用户的图书馆预约记录。
    pub async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::get_bookings(&mut self.direct_runtime, page, limit).await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::get_bookings(&mut self.webvpn_runtime, page, limit).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> RoutedResult<LibBookReserveResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::reserve(&mut self.direct_runtime, request.clone()).await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::reserve(&mut self.webvpn_runtime, request).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn libbook_cancel_booking(&mut self, id: &str) -> RoutedResult<LibBookCancelResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::libbook::cancel_booking(&mut self.direct_runtime, id).await
            }
            ConnectionMode::WebVpn => {
                crate::features::libbook::cancel_booking(&mut self.webvpn_runtime, id).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询阳光打卡概览。
    pub async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::ygdk::get_overview(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::ygdk::get_overview(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 查询阳光打卡历史记录。
    pub async fn ygdk_records(&mut self, page: i32, size: i32) -> RoutedResult<YgdkRecordsPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::ygdk::get_records(&mut self.direct_runtime, page, size).await
            }
            ConnectionMode::WebVpn => {
                crate::features::ygdk::get_records(&mut self.webvpn_runtime, page, size).await
            }
        };
        self.finish_routed(resolution, result)
    }

    pub async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> RoutedResult<YgdkClockinSubmitResult> {
        self.guard_latest_routed()?;
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::ygdk::submit_clockin(&mut self.direct_runtime, request.clone())
                    .await
            }
            ConnectionMode::WebVpn => {
                crate::features::ygdk::submit_clockin(&mut self.webvpn_runtime, request).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过 SPOC 路线策略读取当前作业列表。
    pub async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::spoc::get_assignments(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::spoc::get_assignments(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 读取当前 SPOC 列表，并返回安全的全局页面完成证据。
    pub async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> RoutedResult<SpocAssignmentsDiagnostics> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::spoc::get_assignments_diagnostics(&mut self.direct_runtime).await
            }
            ConnectionMode::WebVpn => {
                crate::features::spoc::get_assignments_diagnostics(&mut self.webvpn_runtime).await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过 SPOC 路线策略读取一项作业详情。
    pub async fn spoc_assignment(
        &mut self,
        assignment_id: &str,
    ) -> RoutedResult<SpocAssignmentDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Spoc))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::spoc::get_assignment_detail(
                    &mut self.direct_runtime,
                    assignment_id,
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::spoc::get_assignment_detail(
                    &mut self.webvpn_runtime,
                    assignment_id,
                )
                .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过希冀路线策略读取作业。
    pub async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::judge::get_assignments(&mut self.direct_runtime, include_expired)
                    .await
            }
            ConnectionMode::WebVpn => {
                crate::features::judge::get_assignments(&mut self.webvpn_runtime, include_expired)
                    .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过希冀路线策略读取作业，并返回安全解析计数。
    pub async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::judge::get_assignments_diagnostics(
                    &mut self.direct_runtime,
                    include_expired,
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::judge::get_assignments_diagnostics(
                    &mut self.webvpn_runtime,
                    include_expired,
                )
                .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过希冀路线策略读取一项作业详情。
    pub async fn judge_assignment(
        &mut self,
        course_id: &str,
        assignment_id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::judge::get_assignment_detail(
                    &mut self.direct_runtime,
                    course_id,
                    assignment_id,
                )
                .await
            }
            ConnectionMode::WebVpn => {
                crate::features::judge::get_assignment_detail(
                    &mut self.webvpn_runtime,
                    course_id,
                    assignment_id,
                )
                .await
            }
        };
        self.finish_routed(resolution, result)
    }

    /// 通过一次希冀路线策略决策读取多项作业详情。
    pub async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Judge))?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                crate::features::judge::get_assignment_details(&mut self.direct_runtime, keys).await
            }
            ConnectionMode::WebVpn => {
                crate::features::judge::get_assignment_details(&mut self.webvpn_runtime, keys).await
            }
        };
        self.finish_routed(resolution, result)
    }

    fn resolve_operation(
        &mut self,
        operation: Operation,
    ) -> std::result::Result<RouteResolution, RoutedError> {
        self.guard_latest_session_ownership()
            .map_err(|error| RoutedError {
                error,
                resolution: None,
            })?;
        let (policy, row) = match operation {
            Operation::User => (
                self.config.default,
                FeatureRouteConfig {
                    auto_route_override: None,
                    unknown_default: ConnectionMode::Direct,
                    allow_ready_route_fallback: false,
                    allow_network_fallback: false,
                },
            ),
            Operation::Feature(feature) => (
                self.config.feature(feature),
                FeatureRouteConfig::for_feature(feature),
            ),
        };
        let network = if policy == RoutePolicy::Auto {
            self.probe.probe(Duration::from_millis(500))
        } else {
            NetworkState::Unknown
        };
        let initial_route = match policy {
            RoutePolicy::Direct => ConnectionMode::Direct,
            RoutePolicy::WebVpn => ConnectionMode::WebVpn,
            RoutePolicy::Auto => row.auto_route_override.unwrap_or(match network {
                NetworkState::Campus => ConnectionMode::Direct,
                NetworkState::OffCampus => ConnectionMode::WebVpn,
                NetworkState::Unknown => row.unknown_default,
            }),
        };
        let mut resolution = RouteResolution {
            mode: initial_route,
            policy,
            diagnostic: RouteDiagnostic::new(network, initial_route),
        };
        if !self.route_is_ready(initial_route)
            && policy == RoutePolicy::Auto
            && row.allow_ready_route_fallback
        {
            let alternate = alternate_route(initial_route);
            if self.route_is_ready(alternate) {
                resolution.mode = alternate;
                resolution.diagnostic.mode = alternate;
                resolution.diagnostic.used_fallback = true;
            }
        }
        if !self.route_is_ready(resolution.mode) {
            return Err(routed_error(authentication_required(), resolution));
        }
        Ok(resolution)
    }

    fn guard_latest_session_ownership(&mut self) -> Result<()> {
        self.clear_on_session_conflict()?;
        if !self.direct_runtime.has_local_session() && !self.direct_auth.has_pending_login() {
            self.direct_runtime.sync_empty_session_revision()?;
        }
        if !self.webvpn_runtime.has_local_session() && !self.webvpn_auth.has_pending_login() {
            self.webvpn_runtime.sync_empty_session_revision()?;
        }
        if (self.direct_runtime.has_local_session() || self.direct_auth.has_pending_login())
            && let Err(error) = self.direct_runtime.ensure_session_revision()
        {
            self.clear_all_memory();
            return Err(error);
        }
        if (self.webvpn_runtime.has_local_session() || self.webvpn_auth.has_pending_login())
            && let Err(error) = self.webvpn_runtime.ensure_session_revision()
        {
            self.clear_all_memory();
            return Err(error);
        }
        Ok(())
    }

    fn guard_latest_routed(&mut self) -> std::result::Result<(), RoutedError> {
        self.guard_latest_session_ownership()
            .map_err(|error| RoutedError {
                error,
                resolution: None,
            })
    }

    fn route_is_ready(&self, route: ConnectionMode) -> bool {
        match route {
            ConnectionMode::Direct => self.direct_runtime.has_local_session(),
            ConnectionMode::WebVpn => self.webvpn_runtime.has_local_session(),
        }
    }

    fn finish_routed<T>(
        &mut self,
        resolution: RouteResolution,
        result: Result<T>,
    ) -> RoutedResult<T> {
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::AuthenticationRequired)
        {
            if self.route_is_ready(resolution.mode) {
                if let Err(error) = self.clear_invalidated_route(resolution.mode) {
                    return Err(routed_error(error, resolution));
                }
            } else {
                self.clear_invalidated_route_memory(resolution.mode);
            }
        }
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::InternalError)
            && !self.route_is_ready(resolution.mode)
        {
            self.clear_invalidated_route_memory(resolution.mode);
        }
        if let Err(error) = self.clear_on_session_conflict() {
            return Err(routed_error(error, resolution));
        }
        result
            .map(|data| Routed { data, resolution })
            .map_err(|error| routed_error(error, resolution))
    }

    fn clear_invalidated_route(&mut self, route: ConnectionMode) -> Result<()> {
        match route {
            ConnectionMode::Direct => {
                let auth = &mut self.direct_auth;
                self.direct_runtime.clear_with(|| auth.clear())
            }
            ConnectionMode::WebVpn => {
                let auth = &mut self.webvpn_auth;
                self.webvpn_runtime.clear_with(|| auth.clear())
            }
        }
    }

    fn clear_invalidated_route_memory(&mut self, route: ConnectionMode) {
        match route {
            ConnectionMode::Direct => {
                self.direct_runtime.clear_memory();
                self.direct_auth.clear();
            }
            ConnectionMode::WebVpn => {
                self.webvpn_runtime.clear_memory();
                self.webvpn_auth.clear();
            }
        }
    }

    fn clear_all_memory(&mut self) {
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
    }

    async fn prepare_route(&mut self, route: ConnectionMode) -> Result<()> {
        match route {
            ConnectionMode::Direct => {
                self.direct_auth
                    .prepare_login(&mut self.direct_runtime)
                    .await
            }
            ConnectionMode::WebVpn => {
                self.webvpn_auth
                    .prepare_login(&mut self.webvpn_runtime)
                    .await
            }
        }
    }

    fn finish_route_login(
        route: ConnectionMode,
        login: Result<UserProfile>,
    ) -> (RouteLoginResult, Option<UserProfile>) {
        match login {
            Ok(profile) => (ready_route(route), Some(profile)),
            Err(error) => (
                RouteLoginResult {
                    route,
                    state: RouteLoginState::Failed,
                    error: Some(safe_error(&error)),
                },
                None,
            ),
        }
    }

    async fn login_route(
        &mut self,
        route: ConnectionMode,
        input: LoginInput,
    ) -> Result<UserProfile> {
        match route {
            ConnectionMode::Direct => {
                self.direct_auth
                    .login(&mut self.direct_runtime, input)
                    .await
            }
            ConnectionMode::WebVpn => {
                self.webvpn_auth
                    .login(&mut self.webvpn_runtime, input)
                    .await
            }
        }
    }

    async fn auth_status_route(&mut self, route: ConnectionMode) -> Result<AuthStatus> {
        match route {
            ConnectionMode::Direct => {
                let mut clear_workflow = || self.direct_auth.clear();
                user::auth_status(&mut self.direct_runtime, &mut clear_workflow).await
            }
            ConnectionMode::WebVpn => {
                let mut clear_workflow = || self.webvpn_auth.clear();
                user::auth_status(&mut self.webvpn_runtime, &mut clear_workflow).await
            }
        }
    }

    fn clear_on_session_conflict(&mut self) -> Result<()> {
        if self.sessions.is_conflicted() {
            self.clear_all_memory();
            Err(DualSessionCoordinator::conflict_error())
        } else {
            Ok(())
        }
    }
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
        Ok(Some(Self {
            runtime: ClientRuntime::new(mode, ReqwestTransport::new()?, route_store)?,
            auth: AuthWorkflow::default(),
            sessions: Some(sessions),
        }))
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
        Ok(Self {
            runtime: ClientRuntime::new(mode, ReqwestTransport::new()?, route_store)?,
            auth: AuthWorkflow::default(),
            sessions: Some(sessions),
        })
    }

    /// 使用注入的传输和持久化端口构造客户端。
    ///
    /// # Errors
    ///
    /// 当无法加载已有会话时返回安全的持久化错误。
    pub fn with_transport<T, S>(mode: ConnectionMode, transport: T, store: S) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        Ok(Self {
            runtime: ClientRuntime::new(mode, transport, store)?,
            auth: AuthWorkflow::default(),
            sessions: None,
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
    pub async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        self.guard_session_ownership()?;
        let result = crate::features::bykc::get_profile(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆站点。
    pub async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_sites(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆用途类型；上游不可用时由 feature 保留冻结静态回退。
    pub async fn cgyy_purpose_types(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_purpose_types(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆用途并保留上游或静态回退来源诊断。
    pub async fn cgyy_purpose_types_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<CgyyPurposeTypes>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_purpose_types_with_source(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(
            &self.runtime,
            CgyyPurposeTypes {
                items: data.0,
                source: data.1,
            },
        ))
    }

    /// 查询场馆日期可用性。
    pub async fn cgyy_day_info(
        &mut self,
        site_id: i32,
        date: &str,
    ) -> Result<FeatureResult<CgyyDayInfo>> {
        self.guard_session_ownership()?;
        if site_id <= 0 || date.trim().is_empty() {
            return Err(invalid_input("场馆站点和日期不能为空"));
        }
        let result = crate::features::cgyy::get_day_info(&mut self.runtime, site_id, date).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆订单分页。
    pub async fn cgyy_orders(
        &mut self,
        page: i32,
        size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        self.guard_session_ownership()?;
        if page < 0 || size <= 0 {
            return Err(invalid_input("分页参数无效"));
        }
        let result = crate::features::cgyy::get_orders(&mut self.runtime, page, size).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询场馆订单详情。
    pub async fn cgyy_order_detail(&mut self, id: i32) -> Result<FeatureResult<CgyyOrder>> {
        self.guard_session_ownership()?;
        if id <= 0 {
            return Err(invalid_input("订单标识必须为正数"));
        }
        let result = crate::features::cgyy::get_order_detail(&mut self.runtime, id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    pub async fn cgyy_lock_code(&mut self) -> Result<FeatureResult<CgyyLockCode>> {
        self.guard_session_ownership()?;
        let result = crate::features::cgyy::get_lock_code(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 取消场馆预约订单。
    pub async fn cgyy_cancel_order(&mut self, id: i32) -> Result<FeatureResult<CgyyActionResult>> {
        self.guard_latest_session_ownership()?;
        if id <= 0 {
            return Err(invalid_input("订单标识必须为正数"));
        }
        let result = crate::features::cgyy::cancel_order(&mut self.runtime, id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 提交场馆预约；验证码材料可由调用方提供或由 Core 自动获取并校验。
    pub async fn cgyy_submit_reservation(
        &mut self,
        request: CgyyReservationSubmitRequest,
    ) -> Result<FeatureResult<CgyyReservationResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::cgyy::submit_reservation(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询博雅课程分页。
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
    pub async fn bykc_chosen_courses(&mut self) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        self.guard_session_ownership()?;
        let result = crate::features::bykc::get_chosen_courses(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询博雅修读统计。
    pub async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        self.guard_session_ownership()?;
        let result = crate::features::bykc::get_statistics(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询全部评教课程。
    pub async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        self.guard_session_ownership()?;
        let result = crate::features::evaluation::get_all(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 提交由宿主构造的评教结果列表。
    pub async fn evaluation_submit(
        &mut self,
        pjjglist: Vec<serde_json::Value>,
    ) -> Result<FeatureResult<Vec<EvaluationResult>>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::evaluation::submit_payload(&mut self.runtime, pjjglist).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 按冻结问卷链自动构造并提交课程评教。
    pub async fn evaluation_submit_courses(
        &mut self,
        courses: Vec<EvaluationCourse>,
    ) -> Result<FeatureResult<Vec<EvaluationResult>>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::evaluation::submit_courses(&mut self.runtime, courses).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    pub async fn bykc_select_course(
        &mut self,
        course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::bykc::select_course(&mut self.runtime, course_id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    pub async fn bykc_deselect_course(
        &mut self,
        course_id: i64,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::bykc::deselect_course(&mut self.runtime, course_id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
    pub async fn bykc_sign_course(
        &mut self,
        request: BykcSignRequest,
    ) -> Result<FeatureResult<BykcActionResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::bykc::sign_course(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取可用的学期列表。
    pub async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_terms(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定学期的教学周。
    pub async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_weeks(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定周次的课表。
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
    pub async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_today(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取指定学期的考试安排。
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
    pub async fn grades(&mut self, term: &str) -> Result<FeatureResult<GradeData>> {
        self.guard_session_ownership()?;
        let result = crate::features::grades::get_grades(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询可用教室。
    pub async fn classroom_search(
        &mut self,
        campus_id: i32,
        date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        self.guard_session_ownership()?;
        let result = crate::features::classroom::search(&mut self.runtime, campus_id, date).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询今日课堂签到状态。
    pub async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        self.guard_session_ownership()?;
        let result = crate::features::signin::get_today(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 执行指定课程的课堂签到。
    pub async fn signin_perform(
        &mut self,
        course_id: &str,
    ) -> Result<FeatureResult<SigninActionResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::signin::perform_signin(&mut self.runtime, course_id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询图书馆楼馆列表。
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

    pub async fn libbook_reserve(
        &mut self,
        request: LibBookReserveRequest,
    ) -> Result<FeatureResult<LibBookReserveResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::libbook::reserve(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    pub async fn libbook_cancel_booking(
        &mut self,
        id: &str,
    ) -> Result<FeatureResult<LibBookCancelResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::libbook::cancel_booking(&mut self.runtime, id).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询阳光打卡概览。
    pub async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        self.guard_session_ownership()?;
        let result = crate::features::ygdk::get_overview(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 查询阳光打卡历史记录。
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

    pub async fn ygdk_submit(
        &mut self,
        request: YgdkClockinSubmitRequest,
    ) -> Result<FeatureResult<YgdkClockinSubmitResult>> {
        self.guard_latest_session_ownership()?;
        let result = crate::features::ygdk::submit_clockin(&mut self.runtime, request).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取当前 SPOC 作业列表。
    pub async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取当前 SPOC 列表，并返回安全的全局页面完成证据。
    pub async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments_diagnostics(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 读取一项 SPOC 作业详情。
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
