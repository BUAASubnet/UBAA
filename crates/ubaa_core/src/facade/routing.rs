//! 聚合客户端的唯一路线解析、运行时选择与操作收尾。

use crate::auth::AuthWorkflow;
use crate::config::FeatureRouteConfig;
use crate::connection::{RouteResolution, resolve_route};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

use super::client::UbaaClient;
use super::types::{CallerPinned, Operation, Routed, RoutedError, RoutedResult};

/// 已选定路线的会话检查与操作收尾，两种 facade 共用此实现。
pub(super) struct RouteExecution<'a> {
    runtime: &'a mut ClientRuntime,
    auth: &'a mut AuthWorkflow,
}

impl<'a> RouteExecution<'a> {
    pub(super) fn new(runtime: &'a mut ClientRuntime, auth: &'a mut AuthWorkflow) -> Self {
        Self { runtime, auth }
    }

    pub(super) fn guard_session_ownership(&mut self) -> Result<()> {
        if !self.runtime.has_local_session() && !self.auth.has_pending_login() {
            return self.runtime.sync_empty_session_revision();
        }
        if let Err(error) = self.runtime.ensure_session_revision() {
            self.runtime.clear_memory();
            self.auth.clear();
            return Err(error);
        }
        Ok(())
    }

    pub(super) fn cleanup_result<T>(&mut self, result: &Result<T>) -> Result<()> {
        if should_clear_invalidated_route(result) {
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
            self.runtime.clear_memory();
            self.auth.clear();
        }
        Ok(())
    }

    /// 发送后的清理不能覆盖学校写入结果，未发送的操作交回普通收尾。
    pub(super) fn cleanup_sent_write<T>(&mut self, result: &Result<T>) -> bool {
        if !self.runtime.take_non_idempotent_boundary_crossed() {
            return false;
        }
        let _ = self.cleanup_result(result);
        true
    }
}

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

    pub(super) fn log_cgyy_pinned_route(&mut self, pinned_route: ConnectionMode, operation: &str) {
        let runtime_mode = self.runtime_for(pinned_route).mode();
        tracing::debug!(
            target: "ubaa::cgyy",
            feature = "cgyy",
            operation,
            route_source = "caller_pinned",
            ?pinned_route,
            selected_runtime = ?runtime_mode,
            "Cgyy 门面使用调用方固定路线"
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

    /// 写入的确认路线与运行时选择共享同一次解析，不能在校验后再次探测。
    pub(super) fn resolve_write_route(
        &mut self,
        feature: ReadonlyFeature,
        expected_route: Option<ConnectionMode>,
    ) -> std::result::Result<RouteResolution, RoutedError> {
        let resolution = self.resolve_operation(Operation::Feature(feature))?;
        if expected_route.is_some_and(|expected| expected != resolution.mode) {
            return Err(routed_error(
                invalid_input("写入路线已变化，请重新确认"),
                resolution,
            ));
        }
        Ok(resolution)
    }

    pub(super) fn guard_latest_session_ownership(&mut self) -> Result<()> {
        self.clear_on_session_conflict()?;
        for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let (runtime, auth) = self.route_parts_for(route);
            if let Err(error) = RouteExecution::new(runtime, auth).guard_session_ownership() {
                self.clear_all_memory();
                return Err(error);
            }
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

    pub(super) fn guard_caller_pinned_route(&mut self, route: ConnectionMode) -> Result<()> {
        self.guard_latest_session_ownership()?;
        if !self.route_is_ready(route) {
            return Err(authentication_required());
        }
        Ok(())
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
        if let Err(error) = self.cleanup_route_result(resolution.mode, &result) {
            return Err(routed_error(error, resolution));
        }
        if let Err(error) = self.clear_on_session_conflict() {
            return Err(routed_error(error, resolution));
        }
        result
            .map(|data| Routed { data, resolution })
            .map_err(|error| routed_error(error, resolution))
    }

    pub(super) fn finish_caller_pinned<T>(
        &mut self,
        pinned_route: ConnectionMode,
        result: Result<T>,
    ) -> Result<CallerPinned<T>> {
        self.cleanup_route_result(pinned_route, &result)?;
        self.clear_on_session_conflict()?;
        result.map(|data| CallerPinned { data, pinned_route })
    }

    /// 写请求跨越发送边界后，收尾检查只清理失效状态，不得覆盖确定或未知结果。
    pub(super) fn finish_routed_write<T>(
        &mut self,
        resolution: RouteResolution,
        result: Result<T>,
    ) -> RoutedResult<T> {
        let (runtime, auth) = self.route_parts_for(resolution.mode);
        if !RouteExecution::new(runtime, auth).cleanup_sent_write(&result) {
            return self.finish_routed(resolution, result);
        }
        let _ = self.guard_latest_session_ownership();
        result
            .map(|data| Routed { data, resolution })
            .map_err(|error| routed_error(error, resolution))
    }

    fn cleanup_route_result<T>(&mut self, route: ConnectionMode, result: &Result<T>) -> Result<()> {
        let (runtime, auth) = self.route_parts_for(route);
        RouteExecution::new(runtime, auth).cleanup_result(result)
    }

    pub(super) fn clear_all_memory(&mut self) {
        self.clear_interactive_context();
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
