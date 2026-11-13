//! 聚合客户端的唯一路线解析、运行时选择与操作收尾。

use crate::auth::AuthWorkflow;
use crate::config::FeatureRouteConfig;
use crate::connection::{RouteResolution, resolve_route};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

use super::client::UbaaClient;
use super::types::{CallerPinned, Operation, Routed, RoutedError, RoutedResult};
pub(super) mod domains;

/// 同一个只读表达式最多执行两次，每次使用独立路线运行时。
macro_rules! read_with_fallback {
    ($client:ident, $resolution:ident, $read:expr) => {{
        let mut $resolution = $resolution;
        let initial_resolution = $resolution;
        $client
            .runtime_for($resolution.mode)
            .reset_network_observation();
        let result = $read;
        match $client.prepare_read_fallback($resolution, &result).await {
            Ok(Some(domain)) => {
                $resolution.mode = crate::domain::ConnectionMode::WebVpn;
                $resolution.diagnostic.mode = $resolution.mode;
                $resolution.diagnostic.used_fallback = true;
                $client
                    .runtime_for($resolution.mode)
                    .reset_network_observation();
                let fallback_result = $read;
                if fallback_result.is_err() && result.is_ok() {
                    (initial_resolution, result)
                } else {
                    $client.remember_read_fallback(&domain, &fallback_result);
                    ($resolution, fallback_result)
                }
            }
            Ok(None) => ($resolution, result),
            Err(error) => {
                if result.is_ok() {
                    (initial_resolution, result)
                } else {
                    $resolution.mode = crate::domain::ConnectionMode::WebVpn;
                    $resolution.diagnostic.mode = $resolution.mode;
                    $resolution.diagnostic.used_fallback = true;
                    ($resolution, Err(error))
                }
            }
        }
    }};
}
pub(super) use read_with_fallback;

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
    pub(super) async fn prepare_read_fallback<T>(
        &mut self,
        resolution: RouteResolution,
        result: &Result<T>,
    ) -> Result<Option<String>> {
        if resolution.policy != RoutePolicy::Auto
            || resolution.diagnostic.network == crate::connection::NetworkState::Campus
            || resolution.mode != ConnectionMode::Direct
            || result.as_ref().is_err_and(|error| {
                !matches!(error.code, ErrorCode::NetworkError | ErrorCode::Timeout)
            })
        {
            return Ok(None);
        }
        let Some(domain) = self
            .direct_runtime
            .network_failure_domain
            .clone()
            .filter(|domain| domains::allowed(domain))
        else {
            return Ok(None);
        };
        self.domain_routes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .require_webvpn(domain.clone());
        self.guard_latest_session_ownership()?;
        if !self.webvpn_runtime.has_local_session() {
            return Err(authentication_required());
        }
        let expected = match self.direct_runtime.account_name() {
            Some(value) => value.to_owned(),
            None => self
                .auth_status_route(ConnectionMode::Direct)
                .await?
                .user
                .school_id
                .ok_or_else(authentication_required)?,
        };
        let actual = self.auth_status_route(ConnectionMode::WebVpn).await?;
        if actual.user.school_id.as_deref() != Some(expected.as_str()) {
            return Err(UbaaError::new(
                ErrorCode::PermissionDenied,
                ErrorKind::Authentication,
                false,
                "两条路线的账号不一致，请重新登录",
            ));
        }
        Ok(Some(domain))
    }

    pub(super) fn remember_read_fallback<T>(&mut self, domain: &str, result: &Result<T>) {
        if result.is_ok()
            && self.webvpn_runtime.reached_domains.contains(domain)
            && self.webvpn_runtime.network_failure_domain.as_deref() != Some(domain)
        {
            self.domain_routes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .remember(domain.to_owned(), self.route_now());
        }
    }

    fn route_now(&self) -> i64 {
        self.direct_runtime
            .now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |duration| {
                i64::try_from(duration.as_secs()).unwrap_or(i64::MAX)
            })
    }
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

    pub(super) fn resolve_recovery_operation(
        &mut self,
        operation: Operation,
    ) -> std::result::Result<RouteResolution, RoutedError> {
        let resolved = self.resolve_operation(operation);
        let resolution = match &resolved {
            Ok(value) => *value,
            Err(error) if error.error.code == ErrorCode::AuthenticationRequired => {
                let Some(value) = error.resolution else {
                    return resolved;
                };
                value
            }
            Err(_) => return resolved,
        };
        if resolution.policy == RoutePolicy::Auto
            && resolution.diagnostic.network == crate::connection::NetworkState::OffCampus
            && self
                .domain_routes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .needs_webvpn(operation)
        {
            let mut selected = resolution;
            selected.mode = ConnectionMode::WebVpn;
            selected.diagnostic.mode = ConnectionMode::WebVpn;
            selected.diagnostic.used_fallback = true;
            if !self.route_is_ready(ConnectionMode::WebVpn) {
                return Err(routed_error(authentication_required(), selected));
            }
            return Ok(selected);
        }
        resolved
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
        self.check_school_requests().map_err(|error| RoutedError {
            error,
            resolution: None,
        })?;
        let (policy, row) = match operation {
            Operation::Authentication
            | Operation::ConnectionRecovery
            | Operation::User
            | Operation::CloudPrint
            | Operation::Bhpan => (self.config.default, FeatureRouteConfig::SAFE_DEFAULT),
            Operation::Feature(feature) => (
                self.config.feature(feature),
                FeatureRouteConfig::for_feature(feature),
            ),
        };
        let mut resolution = resolve_route(policy, row, self.probe.as_ref());
        if policy == RoutePolicy::Auto {
            let mut domains = self
                .domain_routes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if resolution.diagnostic.network == crate::connection::NetworkState::Campus {
                domains.campus();
            } else if domains.prefers_webvpn(operation, self.route_now()) {
                resolution.mode = ConnectionMode::WebVpn;
                resolution.diagnostic.mode = ConnectionMode::WebVpn;
                resolution.diagnostic.used_fallback = true;
            }
        }
        if matches!(operation, Operation::ConnectionRecovery)
            && policy == RoutePolicy::Auto
            && resolution.diagnostic.network == crate::connection::NetworkState::OffCampus
        {
            resolution.mode = ConnectionMode::WebVpn;
            resolution.diagnostic.mode = ConnectionMode::WebVpn;
        }
        let initial_route = resolution.mode;
        if initial_route == ConnectionMode::Direct
            && !self.route_is_ready(initial_route)
            && policy == RoutePolicy::Auto
            && resolution.diagnostic.network != crate::connection::NetworkState::Campus
            && !matches!(operation, Operation::Bhpan)
        {
            let alternate = alternate_route(initial_route);
            if self.route_is_ready(alternate) {
                resolution.mode = alternate;
                resolution.diagnostic.mode = alternate;
                resolution.diagnostic.used_fallback = true;
            }
        }
        if matches!(operation, Operation::Bhpan) && resolution.mode != ConnectionMode::Direct {
            return Err(routed_error(
                crate::features::bhpan::auth::unavailable(),
                resolution,
            ));
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
        self.runtime_for(route).check_school_requests()?;
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
        *self.bhpan = super::bhpan::state::BhpanState::default();
        self.cloud_print = None;
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
