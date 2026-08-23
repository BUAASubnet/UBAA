//! Stable facade consumed by CLI and future bindings.
#![allow(clippy::missing_errors_doc, clippy::similar_names)]

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use crate::auth::AuthWorkflow;
use crate::config::{FeatureRouteConfig, RouteConfig};
use crate::connection::{
    CachingGatewayProbe, GatewayProbe, NetworkState, RouteDiagnostic, RouteResolution,
    SystemGatewayProbe,
};
use crate::domain::{
    AuthStatus, CaptchaAnswer, ClassroomQuery, ConnectionMode, DualLoginInput,
    DualLoginPreparation, ExamArrangement, FeatureResult, GradeData, JudgeAssignmentDetail,
    JudgeAssignmentKey, JudgeAssignmentSummary, LoginChallenge, LoginInput, LoginOutcome,
    LoginReadiness, ReadonlyFeature, RouteLoginChallenge, RouteLoginResult, RouteLoginState,
    RoutePolicy, SafeError, SpocAssignmentDetail, SpocAssignments, Term, TodayClass, UserProfile,
    Week, WeeklySchedule,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::features::user;
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore, SessionStore};

static NEXT_PUBLIC_CAPTCHA_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Clone)]
struct CaptchaBinding {
    route: ConnectionMode,
    generation: u64,
    upstream_id: String,
    execution: String,
}

struct CaptchaAnswerBinding {
    route: ConnectionMode,
    value: String,
}

struct PreparedLoginRoute {
    route: ConnectionMode,
    challenge: Result<Option<LoginChallenge>>,
}

#[derive(Default)]
struct CaptchaRegistry {
    generation: u64,
    bindings: BTreeMap<String, CaptchaBinding>,
    direct_preparation: Option<Result<Option<LoginChallenge>>>,
    webvpn_preparation: Option<Result<Option<LoginChallenge>>>,
}

impl CaptchaRegistry {
    fn begin_generation(&mut self) {
        self.generation = self.generation.saturating_add(1).max(1);
        self.bindings.clear();
        self.direct_preparation = None;
        self.webvpn_preparation = None;
    }

    fn ensure_generation(&mut self) {
        if self.generation == 0 {
            self.begin_generation();
        }
    }

    fn issue(&mut self, route: ConnectionMode, challenge: &LoginChallenge) -> String {
        self.ensure_generation();
        let nonce = NEXT_PUBLIC_CAPTCHA_ID.fetch_add(1, Ordering::Relaxed);
        let public_id = format!("c{nonce:016x}");
        self.bindings.insert(
            public_id.clone(),
            CaptchaBinding {
                route,
                generation: self.generation,
                upstream_id: challenge.id.clone(),
                execution: challenge.execution.clone(),
            },
        );
        public_id
    }

    fn issue_if_missing(&mut self, route: ConnectionMode, challenge: &LoginChallenge) -> String {
        self.ensure_generation();
        if let Some((public_id, _)) = self.bindings.iter().find(|(_, binding)| {
            binding.route == route
                && binding.generation == self.generation
                && binding.upstream_id == challenge.id
                && binding.execution == challenge.execution
        }) {
            return public_id.clone();
        }
        self.issue(route, challenge)
    }

    fn validate_and_consume(
        &mut self,
        answers: &[CaptchaAnswer],
        prepared: &[PreparedLoginRoute],
    ) -> Result<Vec<CaptchaAnswerBinding>> {
        self.ensure_generation();
        let mut seen_ids = BTreeSet::new();
        let mut seen_routes = Vec::with_capacity(answers.len());
        let mut validated = Vec::with_capacity(answers.len());
        for answer in answers {
            let public_id = answer.challenge_id.trim();
            let value = answer.value.expose_secret().trim();
            if public_id.is_empty() || value.is_empty() {
                return Err(captcha_invalid("captcha answer id and value are required"));
            }
            if !seen_ids.insert(public_id.to_owned()) {
                return Err(captcha_invalid("captcha answer is duplicated"));
            }
            let Some(binding) = self.bindings.get(public_id) else {
                return Err(captcha_invalid("captcha answer is unknown or expired"));
            };
            if binding.generation != self.generation {
                return Err(captcha_invalid(
                    "captcha answer is from an expired generation",
                ));
            }
            let is_current = prepared.iter().any(|prepared| {
                prepared.route == binding.route
                    && prepared.challenge.as_ref().is_ok_and(|challenge| {
                        challenge.as_ref().is_some_and(|challenge| {
                            challenge.id == binding.upstream_id
                                && challenge.execution == binding.execution
                        })
                    })
            });
            if !is_current {
                return Err(captcha_invalid("captcha challenge is stale"));
            }
            if seen_routes.contains(&binding.route) {
                return Err(captcha_invalid("one route has multiple captcha answers"));
            }
            seen_routes.push(binding.route);
            validated.push(CaptchaAnswerBinding {
                route: binding.route,
                value: value.to_owned(),
            });
        }
        for answer in answers {
            self.bindings.remove(answer.challenge_id.trim());
        }
        Ok(validated)
    }

    fn remember_preparation(
        &mut self,
        route: ConnectionMode,
        preparation: &Result<Option<LoginChallenge>>,
    ) {
        let slot = match route {
            ConnectionMode::Direct => &mut self.direct_preparation,
            ConnectionMode::WebVpn => &mut self.webvpn_preparation,
        };
        *slot = Some(preparation.clone());
    }

    fn preparation(&self, route: ConnectionMode) -> Option<Result<Option<LoginChallenge>>> {
        match route {
            ConnectionMode::Direct => self.direct_preparation.clone(),
            ConnectionMode::WebVpn => self.webvpn_preparation.clone(),
        }
    }

    fn public_challenges(&self, prepared: &[PreparedLoginRoute]) -> Vec<RouteLoginChallenge> {
        prepared
            .iter()
            .filter_map(|prepared| {
                let challenge = prepared.challenge.as_ref().ok()?.as_ref()?;
                let (public_id, _) = self.bindings.iter().find(|(_, binding)| {
                    binding.route == prepared.route
                        && binding.generation == self.generation
                        && binding.upstream_id == challenge.id
                        && binding.execution == challenge.execution
                })?;
                Some(RouteLoginChallenge {
                    route: prepared.route,
                    challenge_id: public_id.clone(),
                    image_available: challenge.image_data_url.is_some(),
                    image_data_url: challenge.image_data_url.clone(),
                })
            })
            .collect()
    }

    fn clear_bindings_for_route(&mut self, route: ConnectionMode) {
        self.bindings.retain(|_, binding| binding.route != route);
    }

    fn clear_route(&mut self, route: ConnectionMode) {
        self.clear_bindings_for_route(route);
        match route {
            ConnectionMode::Direct => self.direct_preparation = None,
            ConnectionMode::WebVpn => self.webvpn_preparation = None,
        }
    }

    fn clear(&mut self) {
        self.bindings.clear();
        self.direct_preparation = None;
        self.webvpn_preparation = None;
    }
}

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
    captcha: CaptchaRegistry,
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
            captcha: CaptchaRegistry::default(),
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
        self.captcha.begin_generation();
        let mut routes = Vec::with_capacity(2);
        let mut challenges = Vec::with_capacity(2);
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let preparation = self.prepare_route(route, true).await;
            self.captcha.remember_preparation(route, &preparation);
            routes.push(match preparation {
                Ok(challenge) => {
                    if let Some(challenge) = challenge.as_ref() {
                        let public_id = self.captcha.issue_if_missing(route, challenge);
                        challenges.push(RouteLoginChallenge {
                            route,
                            challenge_id: public_id,
                            image_available: challenge.image_data_url.is_some(),
                            image_data_url: challenge.image_data_url.clone(),
                        });
                        RouteLoginResult {
                            route,
                            state: RouteLoginState::CaptchaRequired,
                            error: None,
                        }
                    } else {
                        RouteLoginResult {
                            route,
                            state: RouteLoginState::Ready,
                            error: None,
                        }
                    }
                }
                Err(error) => {
                    self.captcha.clear_bindings_for_route(route);
                    RouteLoginResult {
                        route,
                        state: RouteLoginState::Failed,
                        error: Some(safe_error(&error)),
                    }
                }
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
            challenges,
        }
    }

    /// Submit credentials independently to Direct and `WebVPN`, preserving partial success.
    pub async fn login(&mut self, input: DualLoginInput) -> Result<LoginOutcome> {
        self.clear_on_session_conflict()?;
        if self.captcha.generation == 0 {
            self.captcha.begin_generation();
        } else {
            self.captcha.ensure_generation();
        }
        let prepared = self.prepare_routes_for_login().await?;
        let mut challenges = self.captcha.public_challenges(&prepared);
        let answers = self
            .captcha
            .validate_and_consume(&input.captcha_answers, &prepared)?;
        let mut routes = Vec::with_capacity(2);
        let mut profile = None;
        for prepared_route in prepared {
            let (route_result, current) = self
                .submit_prepared_route(prepared_route, &input, &answers)
                .await?;
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
        challenges.retain(|challenge| {
            self.captcha.bindings.contains_key(&challenge.challenge_id)
                && routes.iter().any(|route| {
                    route.route == challenge.route
                        && route.state == RouteLoginState::CaptchaRequired
                })
        });
        Ok(LoginOutcome {
            readiness,
            routes: fixed_route_results(routes),
            profile,
            challenges,
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
        self.captcha.clear();
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
            challenges: Vec::new(),
        })
    }

    /// Fetch the User Center profile through the default route policy.
    pub async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        let resolution = self.resolve_operation(Operation::User)?;
        let result = match resolution.mode {
            ConnectionMode::Direct => {
                let auth = &mut self.direct_auth;
                let captcha = &mut self.captcha;
                let mut clear_workflow = || {
                    auth.clear();
                    captcha.clear_route(ConnectionMode::Direct);
                };
                user::get_user_info(&mut self.direct_runtime, &mut clear_workflow).await
            }
            ConnectionMode::WebVpn => {
                let auth = &mut self.webvpn_auth;
                let captcha = &mut self.captcha;
                let mut clear_workflow = || {
                    auth.clear();
                    captcha.clear_route(ConnectionMode::WebVpn);
                };
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
            && self.route_is_ready(resolution.mode)
            && let Err(error) = self.clear_invalidated_route(resolution.mode)
        {
            return Err(routed_error(error, resolution));
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
                let captcha = &mut self.captcha;
                self.direct_runtime.clear_with(|| {
                    auth.clear();
                    captcha.clear_route(route);
                })
            }
            ConnectionMode::WebVpn => {
                let auth = &mut self.webvpn_auth;
                let captcha = &mut self.captcha;
                self.webvpn_runtime.clear_with(|| {
                    auth.clear();
                    captcha.clear_route(route);
                })
            }
        }
    }

    fn clear_all_memory(&mut self) {
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
        self.captcha.clear();
    }

    async fn prepare_route(
        &mut self,
        route: ConnectionMode,
        force: bool,
    ) -> Result<Option<LoginChallenge>> {
        match route {
            ConnectionMode::Direct if !force && self.direct_auth.is_prepared() => {
                Ok(self.direct_auth.pending_challenge().cloned())
            }
            ConnectionMode::Direct => {
                self.direct_auth
                    .prepare_login(&mut self.direct_runtime)
                    .await
            }
            ConnectionMode::WebVpn if !force && self.webvpn_auth.is_prepared() => {
                Ok(self.webvpn_auth.pending_challenge().cloned())
            }
            ConnectionMode::WebVpn => {
                self.webvpn_auth
                    .prepare_login(&mut self.webvpn_runtime)
                    .await
            }
        }
    }

    async fn prepare_routes_for_login(&mut self) -> Result<Vec<PreparedLoginRoute>> {
        let mut prepared = Vec::with_capacity(2);
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let cached = self.captcha.preparation(route);
            let challenge = if cached
                .as_ref()
                .is_some_and(|preparation| preparation.is_err() || self.auth_is_prepared(route))
            {
                cached.expect("checked captcha preparation")
            } else {
                self.captcha.clear_route(route);
                let preparation = self.prepare_route(route, false).await;
                self.captcha.remember_preparation(route, &preparation);
                preparation
            };
            match &challenge {
                Ok(Some(challenge)) => {
                    self.captcha.issue_if_missing(route, challenge);
                }
                Ok(None) | Err(_) => self.captcha.clear_bindings_for_route(route),
            }
            prepared.push(PreparedLoginRoute { route, challenge });
            if self.sessions.is_conflicted() {
                break;
            }
        }
        self.clear_on_session_conflict()?;
        Ok(prepared)
    }

    async fn submit_prepared_route(
        &mut self,
        prepared: PreparedLoginRoute,
        input: &DualLoginInput,
        answers: &[CaptchaAnswerBinding],
    ) -> Result<(RouteLoginResult, Option<UserProfile>)> {
        let route = prepared.route;
        match prepared.challenge {
            Ok(_) => {}
            Err(error) => return Ok((failed_route(route, &error), None)),
        }
        let answer = answers.iter().find(|answer| answer.route == route);
        let captcha = answer.map(|answer| answer.value.clone());
        let supplied_answer = answer.is_some();
        let login = self
            .login_route(
                route,
                LoginInput {
                    username: input.username.clone(),
                    password: input.password.clone(),
                    captcha,
                },
            )
            .await;
        Ok(self.finish_route_login(route, login, supplied_answer))
    }

    fn finish_route_login(
        &mut self,
        route: ConnectionMode,
        login: Result<UserProfile>,
        supplied_answer: bool,
    ) -> (RouteLoginResult, Option<UserProfile>) {
        match login {
            Ok(profile) => {
                self.captcha.clear_route(route);
                (ready_route(route), Some(profile))
            }
            Err(error) => {
                if supplied_answer {
                    self.clear_auth_route(route);
                    self.captcha.clear_route(route);
                } else if !self.auth_is_prepared(route) {
                    self.captcha.clear_route(route);
                }
                let state = if error.code == crate::error::ErrorCode::CaptchaRequired {
                    RouteLoginState::CaptchaRequired
                } else {
                    RouteLoginState::Failed
                };
                (
                    RouteLoginResult {
                        route,
                        state,
                        error: Some(safe_error(&error)),
                    },
                    None,
                )
            }
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
                let auth = &mut self.direct_auth;
                let captcha = &mut self.captcha;
                let mut clear_workflow = || {
                    auth.clear();
                    captcha.clear_route(route);
                };
                user::auth_status(&mut self.direct_runtime, &mut clear_workflow).await
            }
            ConnectionMode::WebVpn => {
                let auth = &mut self.webvpn_auth;
                let captcha = &mut self.captcha;
                let mut clear_workflow = || {
                    auth.clear();
                    captcha.clear_route(route);
                };
                user::auth_status(&mut self.webvpn_runtime, &mut clear_workflow).await
            }
        }
    }

    fn clear_auth_route(&mut self, route: ConnectionMode) {
        match route {
            ConnectionMode::Direct => self.direct_auth.clear(),
            ConnectionMode::WebVpn => self.webvpn_auth.clear(),
        }
    }

    fn auth_is_prepared(&self, route: ConnectionMode) -> bool {
        match route {
            ConnectionMode::Direct => self.direct_auth.is_prepared(),
            ConnectionMode::WebVpn => self.webvpn_auth.is_prepared(),
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
        challenges: Vec::new(),
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

fn captcha_invalid(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        crate::error::ErrorCode::InvalidInput,
        crate::error::ErrorKind::Input,
        false,
        message,
    )
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

    /// Load the current SSO page and retain its execution/Cookie challenge in this client.
    ///
    /// # Errors
    ///
    /// Returns a safe network, authentication, or upstream protocol error.
    pub async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>> {
        self.guard_session_ownership()?;
        let result = self.auth.prepare_login(&mut self.runtime).await;
        self.finish_session_operation(result)
    }

    /// Submit one credential/captcha form, activate User Center, and return its parsed profile.
    ///
    /// # Errors
    ///
    /// Returns a stable input, captcha, authentication, network, or upstream error.
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

    /// Read the current SPOC assignment list.
    pub async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.guard_session_ownership()?;
        let result = crate::features::spoc::get_assignments(&mut self.runtime).await;
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
        self.finish_session_operation(result)
    }
}

#[cfg(test)]
mod captcha_registry_tests {
    use super::*;
    use crate::domain::SecretValue;
    use crate::error::ErrorCode;

    #[test]
    fn distinct_answers_for_one_route_are_rejected_as_a_complete_set() {
        let mut registry = CaptchaRegistry::default();
        registry.begin_generation();
        let challenge = LoginChallenge {
            id: "upstream-fixture".into(),
            execution: "execution-fixture".into(),
            image_data_url: None,
        };
        let first = registry.issue(ConnectionMode::Direct, &challenge);
        let second = registry.issue(ConnectionMode::Direct, &challenge);
        let prepared = [PreparedLoginRoute {
            route: ConnectionMode::Direct,
            challenge: Ok(Some(challenge)),
        }];
        let answers = [
            CaptchaAnswer {
                challenge_id: first.clone(),
                value: SecretValue::new("first"),
            },
            CaptchaAnswer {
                challenge_id: second.clone(),
                value: SecretValue::new("second"),
            },
        ];

        let Err(error) = registry.validate_and_consume(&answers, &prepared) else {
            panic!("two answers for one route were accepted");
        };

        assert_eq!(error.code, ErrorCode::InvalidInput);
        assert!(registry.bindings.contains_key(&first));
        assert!(registry.bindings.contains_key(&second));
    }
}
