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
use crate::session::{FileSessionStore, RouteSessionStore, SessionStore};

/// One independent Direct or `WebVPN` session and login state machine.
pub struct UbaaClient {
    runtime: ClientRuntime,
    auth: AuthWorkflow,
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
    active_routes: Vec<ConnectionMode>,
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
        let active_routes = store
            .load_dual()?
            .map(|snapshot| {
                [
                    (ConnectionMode::Direct, snapshot.sessions.direct.is_some()),
                    (ConnectionMode::WebVpn, snapshot.sessions.webvpn.is_some()),
                ]
                .into_iter()
                .filter_map(|(mode, active)| active.then_some(mode))
                .collect()
            })
            .unwrap_or_default();
        let direct_store = RouteSessionStore::new(store.clone(), ConnectionMode::Direct);
        let webvpn_store = RouteSessionStore::new(store, ConnectionMode::WebVpn);
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
            active_routes,
        })
    }

    /// Return the route slots that were populated when this client opened.
    #[must_use]
    pub fn active_routes(&self) -> &[ConnectionMode] {
        &self.active_routes
    }

    /// Prepare both routes in fixed Direct, `WebVPN` order and return safe route states.
    pub async fn prepare_login(&mut self) -> DualLoginPreparation {
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
        }
        DualLoginPreparation { routes, challenges }
    }

    /// Submit credentials independently to Direct and `WebVPN`, preserving partial success.
    pub async fn login(&mut self, input: DualLoginInput) -> Result<LoginOutcome> {
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
            if let Err(error) = runtime.refresh_revision() {
                routes.push(RouteLoginResult {
                    route,
                    state: RouteLoginState::Failed,
                    error: Some(safe_error(&error)),
                });
                continue;
            }
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
        }
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
        let direct = self.direct_auth.logout(&mut self.direct_runtime).await;
        let _ = self.webvpn_runtime.refresh_revision();
        let webvpn = self.webvpn_auth.logout(&mut self.webvpn_runtime).await;
        match direct {
            Err(error) => {
                let _ = webvpn;
                Err(error)
            }
            Ok(()) => webvpn,
        }
    }

    /// Validate both persisted route sessions and preserve partial success.
    pub async fn auth_status(&mut self) -> Result<LoginOutcome> {
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
            if let Err(error) = runtime.refresh_revision() {
                routes.push(RouteLoginResult {
                    route,
                    state: RouteLoginState::Failed,
                    error: Some(safe_error(&error)),
                });
                continue;
            }
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
        }
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
        let dual = store.load_dual()?;
        let Some(mode) = mode.or_else(|| {
            dual.as_ref().and_then(|snapshot| {
                if snapshot.sessions.direct.is_some() {
                    Some(ConnectionMode::Direct)
                } else if snapshot.sessions.webvpn.is_some() {
                    Some(ConnectionMode::WebVpn)
                } else {
                    None
                }
            })
        }) else {
            return Ok(None);
        };
        let route_store = RouteSessionStore::new(store, mode);
        let persisted = route_store.load_versioned()?;
        Ok(Some(Self {
            runtime: ClientRuntime::from_versioned(
                mode,
                ReqwestTransport::new()?,
                route_store,
                persisted,
            )?,
            auth: AuthWorkflow::default(),
        }))
    }

    /// Construct a production client rooted at a host-selected configuration directory.
    ///
    /// # Errors
    ///
    /// Returns a safe transport or persistence error.
    pub fn new(mode: ConnectionMode, config_dir: impl AsRef<Path>) -> Result<Self> {
        let store = FileSessionStore::new(config_dir)?;
        let route_store = RouteSessionStore::new(store, mode);
        Ok(Self {
            runtime: ClientRuntime::new(mode, ReqwestTransport::new()?, route_store)?,
            auth: AuthWorkflow::default(),
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
        self.auth.prepare_login(&mut self.runtime).await
    }

    /// Submit one credential/captcha form, activate User Center, and return its parsed profile.
    ///
    /// # Errors
    ///
    /// Returns a stable input, captcha, authentication, network, or upstream error.
    pub async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        self.auth.login(&mut self.runtime, input).await
    }

    /// Validate the current User Center session and refresh last activity.
    ///
    /// # Errors
    ///
    /// Returns authentication-required for explicit invalidation while preserving state on timeout/5xx.
    pub async fn auth_status(&mut self) -> Result<AuthStatus> {
        let mut clear_workflow = || self.auth.clear();
        user::auth_status(&mut self.runtime, &mut clear_workflow).await
    }

    /// Fetch and parse the latest User Center profile.
    ///
    /// # Errors
    ///
    /// Returns a stable authentication, network, availability, or parsing error.
    pub async fn get_user_info(&mut self) -> Result<UserProfile> {
        let mut clear_workflow = || self.auth.clear();
        user::get_user_info(&mut self.runtime, &mut clear_workflow).await
    }

    /// Best-effort remote logout followed by unconditional cleanup of this client's memory.
    ///
    /// # Errors
    ///
    /// Returns a persistence/revision error; remote logout failures are intentionally ignored.
    pub async fn logout(&mut self) -> Result<()> {
        self.auth.logout(&mut self.runtime).await
    }

    /// Read the available academic terms.
    pub async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        let data = crate::features::schedule::get_terms(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read teaching weeks for a term.
    pub async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        let data = crate::features::schedule::get_weeks(&mut self.runtime, term).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one numbered week's schedule.
    pub async fn schedule_week(
        &mut self,
        term: &str,
        week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
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
        let data = crate::features::schedule::get_today(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one term's exam arrangement.
    pub async fn exam_arrangement(&mut self, term: &str) -> Result<FeatureResult<ExamArrangement>> {
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
        let data = crate::features::grades::get_grades(&mut self.runtime, term).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Search available classrooms.
    pub async fn classroom_search(
        &mut self,
        campus_id: i32,
        date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        let data = crate::features::classroom::search(&mut self.runtime, campus_id, date).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read the current SPOC assignment list.
    pub async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        let data = crate::features::spoc::get_assignments(&mut self.runtime).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read one SPOC assignment detail.
    pub async fn spoc_assignment(
        &mut self,
        assignment_id: &str,
    ) -> Result<FeatureResult<SpocAssignmentDetail>> {
        let data =
            crate::features::spoc::get_assignment_detail(&mut self.runtime, assignment_id).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// Read Judge assignments.
    pub async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
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
        let data = crate::features::judge::get_assignment_details(&mut self.runtime, keys).await?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
}
