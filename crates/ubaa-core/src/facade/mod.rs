//! Stable facade consumed by CLI and future bindings.
#![allow(clippy::missing_errors_doc, clippy::similar_names)]

use std::path::Path;
use std::time::Duration;

use crate::auth::AuthWorkflow;
use crate::config::{FeatureRouteConfig, RouteConfig};
use crate::connection::{
    CachingGatewayProbe, GatewayProbe, NetworkState, RouteDiagnostic, RouteResolution,
    SystemGatewayProbe,
};
use crate::domain::{
    AuthStatus, ClassroomQuery, ConnectionMode, DualLoginInput, DualLoginPreparation,
    ExamArrangement, FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey,
    JudgeAssignmentSummary, JudgeAssignmentsDiagnostics, LibBookArea, LibBookAreaDetail,
    LibBookBookingsPage, LibBookLibrary, LibBookSeat, LoginInput, LoginOutcome, LoginReadiness,
    ReadonlyFeature, RouteLoginResult, RouteLoginState, RoutePolicy, SafeError, SigninClass,
    SpocAssignmentDetail, SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass,
    UserProfile, Week, WeeklySchedule, YgdkOverview, YgdkRecordsPage,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::features::user;
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore, SessionStore};

/// One route-locked client used only by diagnostics, tests, and live verification.
pub struct RouteClient {
    runtime: ClientRuntime,
    auth: AuthWorkflow,
    sessions: Option<DualSessionCoordinator>,
}

/// A host-facing aggregate client that owns routing and independent route workflows.
pub struct UbaaClient {
    config: RouteConfig,
    probe: Box<dyn GatewayProbe>,
    direct_runtime: ClientRuntime,
    webvpn_runtime: ClientRuntime,
    direct_auth: AuthWorkflow,
    webvpn_auth: AuthWorkflow,
    sessions: DualSessionCoordinator,
}

/// Successful ordinary operation plus the route decision made by Core.
#[derive(Clone, Debug)]
pub struct Routed<T> {
    /// Stable operation result.
    pub data: T,
    /// Immutable routing metadata for this operation.
    pub resolution: RouteResolution,
}

/// Ordinary operation failure, with routing metadata when resolution completed.
#[derive(Clone, Debug)]
pub struct RoutedError {
    /// Stable Core error.
    pub error: UbaaError,
    /// Route decision, absent only for failures that precede route resolution.
    pub resolution: Option<RouteResolution>,
}

/// Result returned by ordinary routed facade operations.
pub type RoutedResult<T> = std::result::Result<Routed<T>, RoutedError>;

impl RoutedError {
    /// Return routing metadata when Core reached a route decision.
    #[must_use]
    pub const fn resolution(&self) -> Option<&RouteResolution> {
        self.resolution.as_ref()
    }
}

impl std::fmt::Display for RoutedError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.error.fmt(formatter)
    }
}

impl std::error::Error for RoutedError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.error)
    }
}

#[derive(Clone, Copy)]
enum Operation {
    User,
    Feature(ReadonlyFeature),
}

impl UbaaClient {
    /// Open production Direct and `WebVPN` runtimes over one dual-slot session file.
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

    /// Construct an aggregate client with injectable transports and default routing.
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

    /// Construct an aggregate client with injectable transports and routing inputs.
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

    /// Return the route slots currently owned by this client.
    #[must_use]
    pub fn active_routes(&self) -> Vec<ConnectionMode> {
        self.sessions.active_routes()
    }

    /// Return the configured policy used by aggregate authentication operations.
    #[must_use]
    pub const fn default_route_policy(&self) -> RoutePolicy {
        self.config.default
    }

    /// Prepare both routes in fixed Direct, `WebVPN` order and return safe route states.
    pub async fn prepare_login(&mut self) -> DualLoginPreparation {
        if let Err(error) = self.clear_on_session_conflict() {
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

    /// Submit credentials independently to Direct and `WebVPN`, preserving partial success.
    pub async fn login(&mut self, input: DualLoginInput) -> Result<LoginOutcome> {
        self.clear_on_session_conflict()?;
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

    /// Clear both route workflows and both persisted slots.
    pub async fn logout(&mut self) -> Result<()> {
        self.clear_on_session_conflict()?;
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

    /// Validate both persisted route sessions and preserve partial success.
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

    /// Fetch the User Center profile through the default route policy.
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

    /// Read the available academic terms through the Schedule route policy.
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

    /// Read teaching weeks for a term through the Schedule route policy.
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

    /// Read one numbered week's schedule through the Schedule route policy.
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

    /// Read today's schedule through the Schedule route policy.
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

    /// Read one term's exam arrangement through the Exam route policy.
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

    /// Read one term's grades through the Grades route policy.
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

    /// Search available classrooms through the Classroom route policy.
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

    /// Read the current SPOC assignment list through the SPOC route policy.
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

    /// Read the current SPOC list with safe global-page completion evidence.
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

    /// Read one SPOC assignment detail through the SPOC route policy.
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

    /// Read Judge assignments through the Judge route policy.
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

    /// Read Judge assignments with safe parser counts through the Judge route policy.
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

    /// Read one Judge assignment detail through the Judge route policy.
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

    /// Read multiple Judge details through one Judge route policy decision.
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
        self.clear_on_session_conflict()
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

fn failed_preparation(error: &UbaaError) -> DualLoginPreparation {
    let error = safe_error(error);
    DualLoginPreparation {
        routes: [ConnectionMode::Direct, ConnectionMode::WebVpn].map(|route| RouteLoginResult {
            route,
            state: RouteLoginState::Failed,
            error: Some(error.clone()),
        }),
    }
}

fn fixed_route_results(routes: Vec<RouteLoginResult>) -> [RouteLoginResult; 2] {
    routes
        .try_into()
        .expect("completed aggregate operations always produce Direct and WebVPN results")
}

fn ready_route(route: ConnectionMode) -> RouteLoginResult {
    RouteLoginResult {
        route,
        state: RouteLoginState::Ready,
        error: None,
    }
}

fn failed_route(route: ConnectionMode, error: &UbaaError) -> RouteLoginResult {
    RouteLoginResult {
        route,
        state: RouteLoginState::Failed,
        error: Some(safe_error(error)),
    }
}

fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "authentication is required",
    )
}

fn invalid_input(message: impl Into<String>) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

fn routed_error(error: UbaaError, resolution: RouteResolution) -> RoutedError {
    RoutedError {
        error,
        resolution: Some(resolution),
    }
}

const fn alternate_route(route: ConnectionMode) -> ConnectionMode {
    match route {
        ConnectionMode::Direct => ConnectionMode::WebVpn,
        ConnectionMode::WebVpn => ConnectionMode::Direct,
    }
}

fn safe_error(error: &UbaaError) -> SafeError {
    let code = serde_json::to_string(&error.code)
        .unwrap_or_else(|_| "\"internal_error\"".into())
        .trim_matches('"')
        .to_owned();
    let kind = serde_json::to_string(&error.kind)
        .unwrap_or_else(|_| "\"internal\"".into())
        .trim_matches('"')
        .to_owned();
    SafeError {
        code,
        kind,
        retryable: error.retryable,
        message: error.message.clone(),
    }
}

impl RouteClient {
    /// Open a diagnostic client using an explicit or persisted connection mode.
    ///
    /// Returns `None` when neither a mode nor a persisted session exists, allowing a host to
    /// render command-specific missing-session behavior without inspecting persistence internals.
    ///
    /// # Errors
    ///
    /// Returns a safe transport or persistence error.
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

    /// Construct a production client rooted at a host-selected configuration directory.
    ///
    /// # Errors
    ///
    /// Returns a safe transport or persistence error.
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

    /// Construct a client with injected transport and persistence ports.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when an existing session cannot be loaded.
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

    /// Return this client's fixed connection mode.
    #[must_use]
    pub const fn mode(&self) -> ConnectionMode {
        self.runtime.mode()
    }

    /// Load and validate the current SSO login page in this client.
    ///
    /// # Errors
    ///
    /// Returns a safe network, authentication, or upstream protocol error.
    pub async fn prepare_login(&mut self) -> Result<()> {
        self.guard_session_ownership()?;
        let result = self.auth.prepare_login(&mut self.runtime).await;
        self.finish_session_operation(result)
    }

    /// Submit one credential form, activate User Center, and return its parsed profile.
    ///
    /// # Errors
    ///
    /// Returns a stable input, authentication, network, or upstream error.
    pub async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        self.guard_session_ownership()?;
        let result = self.auth.login(&mut self.runtime, input).await;
        self.finish_session_operation(result)
    }

    /// Validate the current User Center session and refresh last activity.
    ///
    /// # Errors
    ///
    /// Returns authentication-required for explicit invalidation while preserving state on timeout/5xx.
    pub async fn auth_status(&mut self) -> Result<AuthStatus> {
        self.guard_session_ownership()?;
        let mut clear_workflow = || self.auth.clear();
        let result = user::auth_status(&mut self.runtime, &mut clear_workflow).await;
        self.finish_session_operation(result)
    }

    /// Fetch and parse the latest User Center profile.
    ///
    /// # Errors
    ///
    /// Returns a stable authentication, network, availability, or parsing error.
    pub async fn get_user_info(&mut self) -> Result<UserProfile> {
        self.guard_session_ownership()?;
        let mut clear_workflow = || self.auth.clear();
        let result = user::get_user_info(&mut self.runtime, &mut clear_workflow).await;
        self.finish_session_operation(result)
    }

    /// Best-effort remote logout followed by unconditional cleanup of this client's memory.
    ///
    /// # Errors
    ///
    /// Returns a persistence/revision error; remote logout failures are intentionally ignored.
    pub async fn logout(&mut self) -> Result<()> {
        self.guard_session_ownership()?;
        let result = self.auth.logout(&mut self.runtime).await;
        self.finish_session_operation(result)
    }

    /// Read the available academic terms.
    pub async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_terms(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read teaching weeks for a term.
    pub async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_weeks(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one numbered week's schedule.
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
                "term and positive week are required",
            ));
        }
        let result = crate::features::schedule::get_week(&mut self.runtime, term, week).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read today's schedule.
    pub async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        self.guard_session_ownership()?;
        let result = crate::features::schedule::get_today(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one term's exam arrangement.
    pub async fn exam_arrangement(&mut self, term: &str) -> Result<FeatureResult<ExamArrangement>> {
        self.guard_session_ownership()?;
        if term.trim().is_empty() {
            return Err(crate::error::UbaaError::new(
                crate::error::ErrorCode::InvalidInput,
                crate::error::ErrorKind::Input,
                false,
                "term is required",
            ));
        }
        let result = crate::features::schedule::get_exam(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one term's grades.
    pub async fn grades(&mut self, term: &str) -> Result<FeatureResult<GradeData>> {
        self.guard_session_ownership()?;
        let result = crate::features::grades::get_grades(&mut self.runtime, term).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Search available classrooms.
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

    /// Read the current SPOC assignment list.
    pub async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read the current SPOC list with safe global-page completion evidence.
    pub async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments_diagnostics(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one SPOC assignment detail.
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

    /// Read Judge assignments.
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

    /// Read Judge assignments with safe parser counts.
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

    /// Read one Judge assignment detail.
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

    /// Read multiple Judge assignment details.
    pub async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        self.guard_session_ownership()?;
        let result = crate::features::judge::get_assignment_details(&mut self.runtime, keys).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    fn guard_session_ownership(&mut self) -> Result<()> {
        if self
            .sessions
            .as_ref()
            .is_some_and(DualSessionCoordinator::is_conflicted)
        {
            self.runtime.clear_memory();
            self.auth.clear();
            Err(DualSessionCoordinator::conflict_error())
        } else {
            Ok(())
        }
    }

    fn finish_session_operation<T>(&mut self, result: Result<T>) -> Result<T> {
        self.guard_session_ownership()?;
        result
    }

    fn finish_readonly_operation<T>(&mut self, result: Result<T>) -> Result<T> {
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
        self.finish_session_operation(result)
    }
}
