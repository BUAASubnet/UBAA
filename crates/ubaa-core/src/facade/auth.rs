//! 聚合认证、状态与注销流程。

use crate::domain::{
    AuthStatus, ConnectionMode, DualLoginInput, DualLoginPreparation, LoginInput, LoginOutcome,
    LoginReadiness, RouteLoginResult, RouteLoginState, SafeError, UserProfile,
};
use crate::error::{Result, UbaaError};
use crate::features::user;
use crate::session::DualSessionCoordinator;

use super::client::UbaaClient;

impl UbaaClient {
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
    ///
    /// # Errors
    ///
    /// 双路线会话所有权或协调状态发生冲突时返回错误；单路线认证失败保留在返回结果中。
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
    ///
    /// # Errors
    ///
    /// 会话所有权已失效或无法原子清理持久化槽位时返回错误。
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
    ///
    /// # Errors
    ///
    /// 双路线协调器已进入冲突终态时返回错误；单路线校验失败保留在返回结果中。
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

    pub(super) fn clear_on_session_conflict(&mut self) -> Result<()> {
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
