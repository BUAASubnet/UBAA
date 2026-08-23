//! Stable facade consumed by CLI and future bindings.
#![allow(clippy::missing_errors_doc, clippy::similar_names)]

use std::path::Path;

use crate::auth::AuthWorkflow;
use crate::domain::{
    AuthStatus, ClassroomQuery, ConnectionMode, DualLoginInput, DualLoginPreparation,
    ExamArrangement, FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey,
    JudgeAssignmentSummary, LoginChallenge, LoginInput, LoginOutcome, LoginReadiness,
    RouteLoginChallenge, RouteLoginResult, RouteLoginState, SafeError, SpocAssignmentDetail,
    SpocAssignments, Term, TodayClass, UserProfile, Week, WeeklySchedule,
};
use crate::error::{Result, UbaaError};
use crate::features::user;
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, FileSessionStore, SessionStore};

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
        let mut routes = Vec::with_capacity(2);
        let mut challenges = Vec::with_capacity(2);
        for (route, runtime, auth) in [
            (
                ConnectionMode::Direct,
                &mut self.direct_runtime,
                &mut self.direct_auth,
            ),
            (
                ConnectionMode::WebVpn,
                &mut self.webvpn_runtime,
                &mut self.webvpn_auth,
            ),
        ] {
            routes.push(match auth.prepare_login(runtime).await {
                Ok(challenge) => {
                    if let Some(challenge) = challenge {
                        challenges.push(RouteLoginChallenge {
                            route,
                            challenge_id: challenge.id,
                            image_data_url: challenge.image_data_url,
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
                Err(error) => RouteLoginResult {
                    route,
                    state: RouteLoginState::Failed,
                    error: Some(safe_error(&error)),
                },
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
        let mut routes = Vec::with_capacity(2);
        let mut profile = None;
        let answers = input.captcha_answers;
        for (route, runtime, auth) in [
            (
                ConnectionMode::Direct,
                &mut self.direct_runtime,
                &mut self.direct_auth,
            ),
            (
                ConnectionMode::WebVpn,
                &mut self.webvpn_runtime,
                &mut self.webvpn_auth,
            ),
        ] {
            let challenge = if auth.is_prepared() {
                auth.pending_challenge().cloned()
            } else {
                match auth.prepare_login(runtime).await {
                    Ok(challenge) => challenge,
                    Err(error) => {
                        routes.push(RouteLoginResult {
                            route,
                            state: RouteLoginState::Failed,
                            error: Some(safe_error(&error)),
                        });
                        if self.sessions.is_conflicted() {
                            break;
                        }
                        continue;
                    }
                }
            };
            let captcha = challenge.as_ref().and_then(|current| {
                answers
                    .iter()
                    .find(|answer| answer.challenge_id == current.id)
                    .map(|answer| answer.value.expose_secret().to_owned())
            });
            match auth
                .login(
                    runtime,
                    LoginInput {
                        username: input.username.clone(),
                        password: input.password.clone(),
                        captcha,
                    },
                )
                .await
            {
                Ok(current) => {
                    if profile.is_none() {
                        profile = Some(current);
                    }
                    routes.push(RouteLoginResult {
                        route,
                        state: RouteLoginState::Ready,
                        error: None,
                    });
                }
                Err(error) if error.code == crate::error::ErrorCode::CaptchaRequired => {
                    routes.push(RouteLoginResult {
                        route,
                        state: RouteLoginState::CaptchaRequired,
                        error: Some(safe_error(&error)),
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
        let readiness = match ready {
            2 => LoginReadiness::AllReady,
            1 => LoginReadiness::Partial,
            _ => LoginReadiness::NoneReady,
        };
        Ok(LoginOutcome {
            readiness,
            routes,
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
        for (route, runtime, auth) in [
            (
                ConnectionMode::Direct,
                &mut self.direct_runtime,
                &mut self.direct_auth,
            ),
            (
                ConnectionMode::WebVpn,
                &mut self.webvpn_runtime,
                &mut self.webvpn_auth,
            ),
        ] {
            let mut clear_workflow = || auth.clear();
            match user::auth_status(runtime, &mut clear_workflow).await {
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
        })
    }

    fn clear_all_memory(&mut self) {
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
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
