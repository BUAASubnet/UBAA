//! Stable facade consumed by CLI and future bindings.
#![allow(clippy::missing_errors_doc, clippy::similar_names)]

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::auth::AuthWorkflow;
use crate::domain::{
    AuthStatus, CaptchaAnswer, ClassroomQuery, ConnectionMode, DualLoginInput,
    DualLoginPreparation, ExamArrangement, FeatureResult, GradeData, JudgeAssignmentDetail,
    JudgeAssignmentKey, JudgeAssignmentSummary, LoginChallenge, LoginInput, LoginOutcome,
    LoginReadiness, RouteLoginChallenge, RouteLoginResult, RouteLoginState, SafeError,
    SpocAssignmentDetail, SpocAssignments, Term, TodayClass, UserProfile, Week, WeeklySchedule,
};
use crate::error::{Result, UbaaError};
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

/// One independent Direct or `WebVPN` session and login state machine.
pub struct UbaaClient {
    runtime: ClientRuntime,
    auth: AuthWorkflow,
    sessions: Option<DualSessionCoordinator>,
}

/// A host-facing aggregate client that owns independent Direct and `WebVPN` workflows.
///
/// The existing [`UbaaClient`] remains the route-locked diagnostic client used by compatibility
/// callers. New hosts can use this type when one login operation must attempt both routes.
pub struct DualUbaaClient {
    direct_runtime: ClientRuntime,
    webvpn_runtime: ClientRuntime,
    direct_auth: AuthWorkflow,
    webvpn_auth: AuthWorkflow,
    sessions: DualSessionCoordinator,
    captcha: CaptchaRegistry,
}

impl DualUbaaClient {
    /// Open production Direct and `WebVPN` runtimes over one dual-slot session file.
    pub fn open(config_dir: impl AsRef<Path>) -> Result<Self> {
        Self::with_transports(
            ReqwestTransport::new()?,
            ReqwestTransport::new()?,
            FileSessionStore::new(config_dir)?,
        )
    }

    /// Construct a dual client with independent injectable transports.
    pub fn with_transports<TDirect, TWebVpn>(
        direct_transport: TDirect,
        webvpn_transport: TWebVpn,
        store: FileSessionStore,
    ) -> Result<Self>
    where
        TDirect: HttpTransport + 'static,
        TWebVpn: HttpTransport + 'static,
    {
        let sessions = DualSessionCoordinator::new(store)?;
        let direct_store = sessions.route_store(ConnectionMode::Direct);
        let webvpn_store = sessions.route_store(ConnectionMode::WebVpn);
        Ok(Self {
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
        DualLoginPreparation { routes, challenges }
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
            routes,
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
            routes,
            profile,
            challenges: Vec::new(),
        })
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
        routes: [ConnectionMode::Direct, ConnectionMode::WebVpn]
            .into_iter()
            .map(|route| RouteLoginResult {
                route,
                state: RouteLoginState::Failed,
                error: Some(error.clone()),
            })
            .collect(),
        challenges: Vec::new(),
    }
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

impl UbaaClient {
    /// Open a production client using an explicit or persisted connection mode.
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
        let data = crate::features::schedule::get_terms(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read teaching weeks for a term.
    pub async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        self.guard_session_ownership()?;
        let data = crate::features::schedule::get_weeks(&mut self.runtime, term).await?;
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
        let data = crate::features::schedule::get_week(&mut self.runtime, term, week).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read today's schedule.
    pub async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        self.guard_session_ownership()?;
        let data = crate::features::schedule::get_today(&mut self.runtime).await?;
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
        let data = crate::features::schedule::get_exam(&mut self.runtime, term).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one term's grades.
    pub async fn grades(&mut self, term: &str) -> Result<FeatureResult<GradeData>> {
        self.guard_session_ownership()?;
        let data = crate::features::grades::get_grades(&mut self.runtime, term).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Search available classrooms.
    pub async fn classroom_search(
        &mut self,
        campus_id: i32,
        date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        self.guard_session_ownership()?;
        let data = crate::features::classroom::search(&mut self.runtime, campus_id, date).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read the current SPOC assignment list.
    pub async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.guard_session_ownership()?;
        let data = crate::features::spoc::get_assignments(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one SPOC assignment detail.
    pub async fn spoc_assignment(
        &mut self,
        assignment_id: &str,
    ) -> Result<FeatureResult<SpocAssignmentDetail>> {
        self.guard_session_ownership()?;
        let data =
            crate::features::spoc::get_assignment_detail(&mut self.runtime, assignment_id).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read Judge assignments.
    pub async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        self.guard_session_ownership()?;
        let data =
            crate::features::judge::get_assignments(&mut self.runtime, include_expired).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one Judge assignment detail.
    pub async fn judge_assignment(
        &mut self,
        course_id: &str,
        assignment_id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        self.guard_session_ownership()?;
        let data = crate::features::judge::get_assignment_detail(
            &mut self.runtime,
            course_id,
            assignment_id,
        )
        .await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read multiple Judge assignment details.
    pub async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        self.guard_session_ownership()?;
        let data = crate::features::judge::get_assignment_details(&mut self.runtime, keys).await?;
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
