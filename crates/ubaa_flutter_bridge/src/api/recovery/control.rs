//! 按操作控制恢复锁等待与在途认证，不与普通共享注销耦合。

use super::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind,
    BridgeRecoveryFeature, BridgeRequiredSession, catch_panic, core, disposed_error, map_profile,
};

/// 一次所需路线校验或登录的控制柄，不能重复使用。
#[flutter_rust_bridge::frb(opaque)]
#[derive(Clone, Debug)]
pub struct BridgeRequiredRecoveryControl {
    inner: core::RequiredRecoveryControl,
}

impl BridgeRequiredRecoveryControl {
    /// 从当前单调时钟开始计算，最长 120000 毫秒，零立即到期。
    ///
    /// # Errors
    /// 超过两分钟时拒绝构造。
    #[flutter_rust_bridge::frb(sync)]
    pub fn new(timeout_millis: u32) -> Result<Self, BridgeError> {
        core::RequiredRecoveryControl::new(std::time::Duration::from_millis(u64::from(
            timeout_millis,
        )))
        .map(|inner| Self { inner })
        .map_err(|error| BridgeError::from_core(error, None))
    }

    /// 立即撤销本次操作，不等待 Core 锁，也不执行共享注销。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

impl BridgeClient {
    /// 在单次控制范围内校验任务所需路线。
    ///
    /// # Errors
    /// 原校验错误、取消、超时或重复使用均返回安全错误。
    pub async fn recover_required_session_controlled(
        &self,
        feature: BridgeRecoveryFeature,
        control: &BridgeRequiredRecoveryControl,
    ) -> Result<BridgeRequiredSession, BridgeError> {
        catch_panic(async {
            let operation = claim(control)?;
            let mut guard = tokio::select! {
                biased;
                error = control.inner.interrupted() => return Err(control_error(control, error, None)),
                guard = self.inner.lock() => guard,
            };
            self.check_required_control(control, None)?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            tokio::select! {
                biased;
                error = control.inner.interrupted() => return Err(control_error(control, error, None)),
                allowed = self.ensure_recovery_allowed() => allowed?,
            }
            let recovered = match feature {
                BridgeRecoveryFeature::Bhpan => client.recover_bhpan_session_controlled(operation).await,
                BridgeRecoveryFeature::Connection => client.recover_connection_session_controlled(operation).await,
                _ => match feature.feature() {
                Some(feature) => client.recover_required_session_controlled(feature, operation).await,
                None => client.recover_user_session_controlled(operation).await,
                },
            }.map_err(|error| {
                    let route = error.resolution.map(|resolution| resolution.mode.into());
                    control_error(control, error.error, route)
                })?;
            let route = Some(recovered.resolution.mode.into());
            self.check_required_control(control, route)?;
            Ok(BridgeRequiredSession { route: recovered.resolution.mode.into(), profile: map_profile(recovered.data.user) })
        }).await
    }

    /// 只向已明确的目标路线提交获准凭据，期限和取消覆盖锁排队。
    ///
    /// # Errors
    /// 保留原认证和写资格冲突，取消不重放或注销共享会话。
    pub async fn login_required_route_controlled(
        &self,
        route: BridgeConnectionMode,
        username: String,
        password: String,
        control: &BridgeRequiredRecoveryControl,
    ) -> Result<BridgeRequiredSession, BridgeError> {
        if username.trim().is_empty() || password.is_empty() {
            return Err(BridgeError::local(
                BridgeErrorCode::InvalidInput,
                BridgeErrorKind::Input,
                false,
                "用户名和密码不能为空",
            ));
        }
        catch_panic(async {
            let operation = claim(control)?;
            let mut guard = tokio::select! {
                biased;
                error = control.inner.interrupted() => return Err(control_error(control, error, Some(route))),
                guard = self.inner.lock() => guard,
            };
            self.check_required_control(control, Some(route))?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            tokio::select! {
                biased;
                error = control.inner.interrupted() => return Err(control_error(control, error, Some(route))),
                allowed = self.ensure_recovery_allowed() => allowed?,
            }
            let recovered = client.login_required_route_controlled(route.into(), core::LoginInput {
                username: username.trim().into(), password: core::SecretValue::new(password),
            }, operation).await.map_err(|error| control_error(control, error, Some(route)))?;
            self.check_required_control(control, Some(route))?;
            Ok(BridgeRequiredSession { route: recovered.pinned_route.into(), profile: map_profile(recovered.data) })
        }).await
    }

    fn check_required_control(
        &self,
        control: &BridgeRequiredRecoveryControl,
        route: Option<BridgeConnectionMode>,
    ) -> Result<(), BridgeError> {
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(disposed_error());
        }
        control
            .inner
            .check()
            .map_err(|error| control_error(control, error, route))
    }
}

fn claim(
    control: &BridgeRequiredRecoveryControl,
) -> Result<core::RequiredRecoveryOperation, BridgeError> {
    control.inner.claim().map_err(|error| {
        if control.inner.interruption_reason().is_some() {
            control_error(control, error, None)
        } else {
            BridgeError::local(
                BridgeErrorCode::OperationConflict,
                BridgeErrorKind::Input,
                false,
                "恢复控制柄已经使用",
            )
        }
    })
}

fn control_error(
    control: &BridgeRequiredRecoveryControl,
    error: core::UbaaError,
    route: Option<BridgeConnectionMode>,
) -> BridgeError {
    let mut error = match control.inner.interruption_reason() {
        Some(core::RequiredRecoveryInterruption::Cancelled) => BridgeError::local(
            BridgeErrorCode::OperationConflict,
            BridgeErrorKind::Input,
            false,
            "恢复已取消",
        ),
        Some(core::RequiredRecoveryInterruption::Deadline) => BridgeError::local(
            BridgeErrorCode::Timeout,
            BridgeErrorKind::Network,
            false,
            "恢复期限已到",
        ),
        None => BridgeError::from_core(error, route),
    };
    error.resolved_route = route;
    error
}

#[cfg(test)]
mod tests;
