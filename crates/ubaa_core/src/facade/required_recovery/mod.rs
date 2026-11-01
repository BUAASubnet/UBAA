//! 在所需路线恢复期间安装控制范围，并负责中断收尾。

use super::{
    AuthStatus, CallerPinned, ConnectionMode, LoginInput, ReadonlyFeature, RequiredRecoveryControl,
    RequiredRecoveryOperation, RoutedResult, UbaaClient, UserProfile,
};
use crate::error::Result;

impl UbaaClient {
    /// 在单次控制范围内校验任务所需路线。
    ///
    /// # Errors
    /// 原校验错误、取消及期限到达均返回带已知路线的安全错误。
    pub async fn recover_required_session_controlled(
        &mut self,
        feature: ReadonlyFeature,
        operation: RequiredRecoveryOperation,
    ) -> RoutedResult<AuthStatus> {
        let control = operation.control;
        control.check().map_err(|error| super::RoutedError {
            error,
            resolution: None,
        })?;
        let resolved = self.resolve_operation(super::types::Operation::Feature(feature));
        let known_resolution = match &resolved {
            Ok(resolution) => Some(*resolution),
            Err(error) => error.resolution,
        };
        control.check().map_err(|error| super::RoutedError {
            error,
            resolution: known_resolution,
        })?;
        let resolution = resolved?;
        let mut scope = InstalledRecovery::new(self, resolution.mode, control.clone());
        let result = tokio::select! {
            biased;
            error = control.interrupted() => Err(super::RoutedError { error, resolution: Some(resolution) }),
            result = scope.client.recover_resolved_session(resolution) => result,
        };
        let result = control
            .check()
            .map_err(|error| super::RoutedError {
                error,
                resolution: Some(resolution),
            })
            .and(result);
        scope.completed = control.interruption_reason().is_none();
        result
    }

    /// 在单次控制范围内只登录明确指定的路线。
    ///
    /// # Errors
    /// 保留原认证错误，不自动重试凭据或注销共享会话。
    pub async fn login_required_route_controlled(
        &mut self,
        route: ConnectionMode,
        input: LoginInput,
        operation: RequiredRecoveryOperation,
    ) -> Result<CallerPinned<UserProfile>> {
        let control = operation.control;
        control.check()?;
        let mut scope = InstalledRecovery::new(self, route, control.clone());
        let result = tokio::select! {
            biased;
            error = control.interrupted() => Err(error),
            result = scope.client.login_required_route(route, input) => result,
        };
        let result = control.check().and(result);
        scope.completed = control.interruption_reason().is_none();
        result
    }
}

/// 即使调用 future 被宿主直接丢弃，也必须解除范围并收尾准备状态。
struct InstalledRecovery<'a> {
    client: &'a mut UbaaClient,
    route: ConnectionMode,
    completed: bool,
}

impl<'a> InstalledRecovery<'a> {
    fn new(
        client: &'a mut UbaaClient,
        route: ConnectionMode,
        control: RequiredRecoveryControl,
    ) -> Self {
        client
            .runtime_for(route)
            .set_required_recovery_scope(Some(control));
        Self {
            client,
            route,
            completed: false,
        }
    }
}

impl Drop for InstalledRecovery<'_> {
    fn drop(&mut self) {
        // 自身取消不能干扰收尾的所有权检查。先解除范围，再检查仍保留的 pending。
        self.client
            .runtime_for(self.route)
            .set_required_recovery_scope(None);
        if !self.completed {
            if let Err(error) = self.client.guard_latest_session_ownership() {
                tracing::debug!(code = ?error.code, kind = ?error.kind, "恢复中断收尾的会话所有权检查失败");
            }
            self.client.verified_login = None;
            self.client.verified_login_generations = None;
            let (runtime, auth) = self.client.route_parts_for(self.route);
            auth.clear();
            runtime.clear_feature_state();
        }
    }
}

#[cfg(all(test, feature = "test-contract"))]
mod tests;
