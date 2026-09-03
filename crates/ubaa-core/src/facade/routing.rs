//! 聚合客户端的唯一路线解析、运行时选择与操作收尾。

use std::time::Duration;

use crate::config::FeatureRouteConfig;
use crate::connection::{NetworkState, RouteDiagnostic, RouteResolution};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

use super::client::UbaaClient;
use super::types::{Operation, Routed, RoutedError, RoutedResult};

impl UbaaClient {
    /// 为 typed 读取/写入准备解析本次实际路线，不发起业务请求。
    ///
    /// # Errors
    ///
    /// 会话所有权已失效或解析出的路线尚未认证时返回错误。
    pub fn resolve_route_for_feature(
        &mut self,
        feature: ReadonlyFeature,
    ) -> Result<RouteResolution> {
        self.resolve_operation(Operation::Feature(feature))
            .map_err(|error| error.error)
    }

    pub(super) fn log_cgyy_route(&self, resolution: RouteResolution, operation: &str) {
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
    pub(super) fn resolve_operation(
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

    pub(super) fn guard_latest_session_ownership(&mut self) -> Result<()> {
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

    pub(super) fn guard_latest_routed(&mut self) -> std::result::Result<(), RoutedError> {
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

    pub(super) fn finish_routed<T>(
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

    pub(super) fn clear_all_memory(&mut self) {
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
    }
}
fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "需要认证",
    )
}

pub(super) fn invalid_input(message: impl Into<String>) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

pub(super) fn routed_error(error: UbaaError, resolution: RouteResolution) -> RoutedError {
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
