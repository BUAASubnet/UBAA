//! 聚合客户端的唯一路线解析、运行时选择与操作收尾。

use crate::auth::AuthWorkflow;
use crate::config::FeatureRouteConfig;
use crate::connection::{RouteResolution, resolve_route};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

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

    pub(super) fn log_cgyy_route(&mut self, resolution: RouteResolution, operation: &str) {
        let runtime_mode = self.runtime_for(resolution.mode).mode();
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
            Operation::User => (self.config.default, FeatureRouteConfig::SAFE_DEFAULT),
            Operation::Feature(feature) => (
                self.config.feature(feature),
                FeatureRouteConfig::for_feature(feature),
            ),
        };
        let mut resolution = resolve_route(policy, row, self.probe.as_ref());
        let initial_route = resolution.mode;
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

    pub(super) fn runtime_for(&mut self, route: ConnectionMode) -> &mut ClientRuntime {
        self.route_parts_for(route).0
    }

    pub(super) fn route_parts_for(
        &mut self,
        route: ConnectionMode,
    ) -> (&mut ClientRuntime, &mut AuthWorkflow) {
        match route {
            ConnectionMode::Direct => (&mut self.direct_runtime, &mut self.direct_auth),
            ConnectionMode::WebVpn => (&mut self.webvpn_runtime, &mut self.webvpn_auth),
        }
    }

    fn route_is_ready(&mut self, route: ConnectionMode) -> bool {
        self.runtime_for(route).has_local_session()
    }

    pub(super) fn finish_routed<T>(
        &mut self,
        resolution: RouteResolution,
        result: Result<T>,
    ) -> RoutedResult<T> {
        if should_clear_invalidated_route(&result) {
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
        let (runtime, auth) = self.route_parts_for(route);
        runtime.clear_with(|| auth.clear())
    }

    fn clear_invalidated_route_memory(&mut self, route: ConnectionMode) {
        let (runtime, auth) = self.route_parts_for(route);
        runtime.clear_memory();
        auth.clear();
    }

    pub(super) fn clear_all_memory(&mut self) {
        self.direct_runtime.clear_memory();
        self.webvpn_runtime.clear_memory();
        self.direct_auth.clear();
        self.webvpn_auth.clear();
    }
}

fn should_clear_invalidated_route<T>(result: &Result<T>) -> bool {
    result
        .as_ref()
        .is_err_and(|error| error.code == ErrorCode::AuthenticationRequired)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_invalidation_clears_but_timeout_and_server_errors_preserve_session() {
        let valid: Result<()> = Ok(());
        let invalid: Result<()> = Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "需要认证",
        ));
        let timeout: Result<()> = Err(UbaaError::new(
            ErrorCode::Timeout,
            ErrorKind::Network,
            true,
            "请求超时",
        ));
        let server_error: Result<()> = Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "上游服务暂时不可用",
        ));

        assert!(!should_clear_invalidated_route(&valid));
        assert!(should_clear_invalidated_route(&invalid));
        assert!(!should_clear_invalidated_route(&timeout));
        assert!(!should_clear_invalidated_route(&server_error));
    }
}
