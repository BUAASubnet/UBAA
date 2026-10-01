//! Bridge v38 专用验证码通路；不向普通 DTO 或诊断投影敏感材料。

use std::fmt;
use std::sync::atomic::Ordering;

use ubaa_core::facade::{
    CaptchaAnswer, CaptchaChallenge, DualLoginInput, InteractiveLoginHandle,
    InteractiveLoginOutcome, InteractiveRouteState, LoginReadiness, SecretValue,
};

use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeLoginOutcome, BridgeLoginReadiness,
    BridgeRouteSettings, BridgeSafeError, BridgeUserProfile, catch_panic, disposed_error,
    map_login_outcome, map_profile, map_safe_error,
};

/// Core 绑定到客户端和账号代次的 opaque 登录上下文。
#[flutter_rust_bridge::frb(opaque)]
#[derive(Clone, Debug)]
pub struct BridgeInteractiveLogin {
    pub(crate) inner: InteractiveLoginHandle,
}

/// Core 绑定到路线、当前准备代次和期限的 opaque 挑战。
#[flutter_rust_bridge::frb(opaque)]
#[derive(Clone, Debug)]
pub struct BridgeCaptchaChallenge {
    pub(crate) inner: CaptchaChallenge,
}

impl BridgeCaptchaChallenge {
    /// 立即撤销当前挑战；不等待客户端网络锁。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.inner.cancel();
    }
}

/// 只在当前页面内存中存在的受限 RGBA 帧。
pub struct BridgeCaptchaFrame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

impl fmt::Debug for BridgeCaptchaFrame {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("BridgeCaptchaFrame([REDACTED])")
    }
}

/// 带句柄的一次答案；不实现 serde，也没有 JSON 或普通登录入口。
#[flutter_rust_bridge::frb(non_opaque)]
pub struct BridgeCaptchaAnswer {
    pub challenge: BridgeCaptchaChallenge,
    pub answer: String,
}

impl fmt::Debug for BridgeCaptchaAnswer {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("BridgeCaptchaAnswer([REDACTED])")
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeInteractiveRouteState {
    Prepared,
    CaptchaRequired,
    Ready,
    Failed,
}

/// 每路线状态；revision 是本地帧替换标识，与上游 id 无关。
pub struct BridgeInteractiveRouteResult {
    pub route: BridgeConnectionMode,
    pub state: BridgeInteractiveRouteState,
    pub challenge: Option<BridgeCaptchaChallenge>,
    pub revision: u64,
    pub valid_for_millis: u32,
    pub frame: Option<BridgeCaptchaFrame>,
    pub error: Option<BridgeSafeError>,
}

impl fmt::Debug for BridgeInteractiveRouteResult {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("BridgeInteractiveRouteResult")
            .field("route", &self.route)
            .field("state", &self.state)
            .finish_non_exhaustive()
    }
}

#[flutter_rust_bridge::frb(non_opaque)]
pub struct BridgeInteractiveLoginOutcome {
    pub login: BridgeInteractiveLogin,
    pub routes: Vec<BridgeInteractiveRouteResult>,
    pub readiness: BridgeLoginReadiness,
    pub profile: Option<BridgeUserProfile>,
}

impl fmt::Debug for BridgeInteractiveLoginOutcome {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("BridgeInteractiveLoginOutcome")
            .field("readiness", &self.readiness)
            .finish_non_exhaustive()
    }
}

/// 继续成功时在同一 Core 锁内取得的身份与实际策略。
pub struct BridgeInteractiveLoginCompletion {
    pub outcome: BridgeLoginOutcome,
    pub settings: BridgeRouteSettings,
}

impl fmt::Debug for BridgeInteractiveLoginCompletion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("BridgeInteractiveLoginCompletion")
    }
}

impl BridgeClient {
    /// 同步登记用户的新手动登录，取消动作可在异步准备排队期间撤销它。
    ///
    /// # Errors
    ///
    /// 已销毁或账号为空时返回安全错误。
    #[flutter_rust_bridge::frb(sync)]
    pub fn begin_interactive_login(
        &self,
        username: String,
    ) -> Result<BridgeInteractiveLogin, BridgeError> {
        if self.is_disposed.load(Ordering::SeqCst) {
            return Err(disposed_error());
        }
        let control = self
            .auth_control
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        control
            .begin(&username)
            .map(|inner| BridgeInteractiveLogin { inner })
            .map_err(|error| BridgeError::from_core(error, None))
    }

    /// 立即撤销当前交互，永不排队等待 Core 网络锁。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel_interactive_login(&self) {
        self.auth_control
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cancel();
        if let Ok(mut guard) = self.inner.try_lock() {
            if let Some(client) = guard.as_mut() {
                client.discard_cancelled_interactive_login();
            }
        }
    }

    /// 准备同步登记的两路验证状态。
    ///
    /// # Errors
    ///
    /// 失效句柄、会话冲突、已销毁或准备失败时返回安全错误。
    pub async fn prepare_interactive_login(
        &self,
        login: &BridgeInteractiveLogin,
    ) -> Result<BridgeInteractiveLoginOutcome, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let result = client
                .prepare_interactive_login_for(&login.inner)
                .await
                .map(map_interactive_outcome)
                .map_err(|error| BridgeError::from_core(error, None));
            self.write_intents.lock().await.clear();
            client.discard_cancelled_interactive_login();
            if !login.inner.is_active() {
                return Err(cancelled_login_error());
            }
            result
        })
        .await
    }

    /// 按各路线独立句柄提交答案；成功路线不会再次收到凭据。
    ///
    /// # Errors
    ///
    /// 无效或已消费句柄在网络前拒绝，认证错误保持安全分类。
    pub async fn submit_interactive_login(
        &self,
        login: &BridgeInteractiveLogin,
        username: String,
        password: String,
        answers: Vec<BridgeCaptchaAnswer>,
    ) -> Result<BridgeInteractiveLoginOutcome, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let input = DualLoginInput {
                username,
                password: SecretValue::new(password),
            };
            let answers = answers
                .into_iter()
                .map(|value| CaptchaAnswer {
                    challenge: value.challenge.inner,
                    answer: SecretValue::new(value.answer),
                })
                .collect();
            let result = client
                .submit_interactive_login(&login.inner, input, answers)
                .await
                .map(map_interactive_outcome)
                .map_err(|error| BridgeError::from_core(error, None));
            self.write_intents.lock().await.clear();
            client.discard_cancelled_interactive_login();
            if !login.inner.is_active() {
                return Err(cancelled_login_error());
            }
            result
        })
        .await
    }

    /// 只刷新所选路线的当前挑战，不使用密码。
    ///
    /// # Errors
    ///
    /// 失效句柄、已完成路线或会话冲突在网络前拒绝。
    pub async fn refresh_interactive_captcha(
        &self,
        login: &BridgeInteractiveLogin,
        route: BridgeConnectionMode,
    ) -> Result<BridgeInteractiveLoginOutcome, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let result = client
                .refresh_interactive_captcha(&login.inner, route.into())
                .await
                .map(map_interactive_outcome)
                .map_err(|error| BridgeError::from_core(error, Some(route)));
            client.discard_cancelled_interactive_login();
            if !login.inner.is_active() {
                return Err(cancelled_login_error());
            }
            result
        })
        .await
    }

    /// 明确进入已就绪路线；Core 原子保存所需策略，保留真实认证槽位。
    ///
    /// # Errors
    ///
    /// 未就绪、失效、配置保存失败时不销毁可恢复交互。
    pub async fn continue_interactive_login(
        &self,
        login: &BridgeInteractiveLogin,
        selected_route: BridgeConnectionMode,
        pin_ready_route: bool,
    ) -> Result<BridgeInteractiveLoginCompletion, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let outcome = client
                .continue_interactive_login(&login.inner, selected_route.into(), pin_ready_route)
                .map(map_login_outcome)
                .map_err(|error| BridgeError::from_core(error, None))?;
            Ok(BridgeInteractiveLoginCompletion {
                outcome,
                settings: BridgeRouteSettings {
                    default_policy: client.default_route_policy().into(),
                    active_routes: client.active_routes().into_iter().map(Into::into).collect(),
                },
            })
        })
        .await
    }
}

fn map_interactive_outcome(outcome: InteractiveLoginOutcome) -> BridgeInteractiveLoginOutcome {
    BridgeInteractiveLoginOutcome {
        login: BridgeInteractiveLogin {
            inner: outcome.login,
        },
        routes: outcome
            .routes
            .into_iter()
            .map(|route| BridgeInteractiveRouteResult {
                route: route.route.into(),
                state: match route.state {
                    InteractiveRouteState::Prepared => BridgeInteractiveRouteState::Prepared,
                    InteractiveRouteState::CaptchaRequired => {
                        BridgeInteractiveRouteState::CaptchaRequired
                    }
                    InteractiveRouteState::Ready => BridgeInteractiveRouteState::Ready,
                    InteractiveRouteState::Failed => BridgeInteractiveRouteState::Failed,
                },
                revision: route
                    .challenge
                    .as_ref()
                    .map_or(0, CaptchaChallenge::revision),
                challenge: route
                    .challenge
                    .map(|inner| BridgeCaptchaChallenge { inner }),
                valid_for_millis: route.valid_for_millis,
                frame: route.frame.map(|frame| BridgeCaptchaFrame {
                    width: frame.width,
                    height: frame.height,
                    rgba: frame.rgba,
                }),
                error: route.error.map(map_safe_error),
            })
            .collect(),
        readiness: match outcome.readiness {
            LoginReadiness::AllReady => BridgeLoginReadiness::AllReady,
            LoginReadiness::Partial => BridgeLoginReadiness::Partial,
            LoginReadiness::NoneReady => BridgeLoginReadiness::NoneReady,
        },
        profile: outcome.profile.map(map_profile),
    }
}

fn cancelled_login_error() -> BridgeError {
    BridgeError::local(
        super::client::BridgeErrorCode::InvalidInput,
        super::client::BridgeErrorKind::Input,
        false,
        "当前验证已失效，请重新准备",
    )
}

#[cfg(test)]
mod tests;
