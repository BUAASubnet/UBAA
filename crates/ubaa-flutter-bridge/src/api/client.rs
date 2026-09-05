use std::collections::HashMap;
use std::fmt;
use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};

use futures_util::FutureExt;
use ubaa_core::facade::{
    ConnectionMode, DualLoginPreparation, LoginOutcome, RouteLoginResult, RouteLoginState,
    RoutePolicy, SafeError, UserProfile,
};
use ubaa_core::facade::{
    ErrorCode, ErrorKind, NetworkState, RouteResolution, RoutedError, UbaaClient, UbaaError,
};

/// FRB 合同版本。
pub const BRIDGE_CONTRACT_VERSION: u32 = 9;

/// Core 与 bridge 共用的机器错误码。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeErrorCode {
    InvalidInput,
    AuthenticationRequired,
    InvalidCredentials,
    PasswordRiskConfirmationFailed,
    PermissionDenied,
    NetworkError,
    Timeout,
    UpstreamUnavailable,
    UpstreamChanged,
    ParseError,
    InternalError,
    ClientDisposed,
    ConfirmationRequired,
    IntentExpired,
    OperationConflict,
    OutcomeUnknown,
}

/// bridge 对外的安全错误类别。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeErrorKind {
    Input,
    Authentication,
    Network,
    Upstream,
    Parse,
    Internal,
}

/// Dart 可捕获的 typed 安全错误。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeError {
    pub code: BridgeErrorCode,
    pub kind: BridgeErrorKind,
    pub retryable: bool,
    pub message: String,
    pub resolved_route: Option<BridgeConnectionMode>,
}

impl fmt::Display for BridgeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.message.fmt(formatter)
    }
}

impl std::error::Error for BridgeError {}

impl BridgeError {
    pub(crate) fn local(
        code: BridgeErrorCode,
        kind: BridgeErrorKind,
        retryable: bool,
        message: impl Into<String>,
    ) -> Self {
        Self {
            code,
            kind,
            retryable,
            message: message.into(),
            resolved_route: None,
        }
    }

    pub(crate) fn from_core(
        error: UbaaError,
        resolved_route: Option<BridgeConnectionMode>,
    ) -> Self {
        Self {
            code: error.code.into(),
            kind: error.kind.into(),
            retryable: error.retryable,
            message: error.message,
            resolved_route,
        }
    }

    pub(crate) fn from_routed(error: RoutedError) -> Self {
        let route = error.resolution().map(|resolution| resolution.mode.into());
        Self::from_core(error.error, route)
    }
}

impl From<ErrorCode> for BridgeErrorCode {
    fn from(code: ErrorCode) -> Self {
        match code {
            ErrorCode::InvalidInput => Self::InvalidInput,
            ErrorCode::AuthenticationRequired => Self::AuthenticationRequired,
            ErrorCode::InvalidCredentials => Self::InvalidCredentials,
            ErrorCode::PasswordRiskConfirmationFailed => Self::PasswordRiskConfirmationFailed,
            ErrorCode::PermissionDenied => Self::PermissionDenied,
            ErrorCode::NetworkError => Self::NetworkError,
            ErrorCode::Timeout => Self::Timeout,
            ErrorCode::UpstreamUnavailable => Self::UpstreamUnavailable,
            ErrorCode::OutcomeUnknown => Self::OutcomeUnknown,
            ErrorCode::UpstreamChanged => Self::UpstreamChanged,
            ErrorCode::ParseError => Self::ParseError,
            ErrorCode::InternalError => Self::InternalError,
        }
    }
}

impl From<ErrorKind> for BridgeErrorKind {
    fn from(kind: ErrorKind) -> Self {
        match kind {
            ErrorKind::Input => Self::Input,
            ErrorKind::Authentication => Self::Authentication,
            ErrorKind::Network => Self::Network,
            ErrorKind::Upstream => Self::Upstream,
            ErrorKind::Parse => Self::Parse,
            ErrorKind::Internal => Self::Internal,
        }
    }
}

/// 当前连接路线。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeConnectionMode {
    Direct,
    WebVpn,
}

/// 用户选择的路线策略。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeRoutePolicy {
    Auto,
    Direct,
    WebVpn,
}

/// 网关探测三态结果。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeNetworkState {
    Campus,
    OffCampus,
    Unknown,
}

/// 一次 Core 路线决策的安全投影。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BridgeRouteDecision {
    pub policy: BridgeRoutePolicy,
    pub resolved_route: BridgeConnectionMode,
    pub network: BridgeNetworkState,
    pub initial_route: BridgeConnectionMode,
    pub used_fallback: bool,
}

/// 路线错误的安全投影。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeSafeError {
    pub code: String,
    pub kind: String,
    pub retryable: bool,
    pub message: String,
}

/// 单条路线登录结果。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeRouteLoginResult {
    pub route: BridgeConnectionMode,
    pub state: BridgeRouteLoginState,
    pub error: Option<BridgeSafeError>,
}

/// 路线登录状态。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeRouteLoginState {
    Ready,
    Failed,
}

/// 两条路线登录准备结果。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeLoginPreparation {
    pub routes: Vec<BridgeRouteLoginResult>,
}

/// 聚合登录状态。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeLoginReadiness {
    AllReady,
    Partial,
    NoneReady,
}

/// 用户资料白名单。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeUserProfile {
    pub username: Option<String>,
    pub name: Option<String>,
    pub school_id: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub id_card_type_name: Option<String>,
}

/// 聚合登录结果。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeLoginOutcome {
    pub readiness: BridgeLoginReadiness,
    pub routes: Vec<BridgeRouteLoginResult>,
    pub profile: Option<BridgeUserProfile>,
}

/// 当前路线设置。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeRouteSettings {
    pub default_policy: BridgeRoutePolicy,
    pub active_routes: Vec<BridgeConnectionMode>,
}

/// 带路线决策的用户资料。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BridgeRoutedUserProfile {
    pub data: BridgeUserProfile,
    pub route: BridgeRouteDecision,
}

/// FRB opaque client。内部 Core、Session 和路线 runtime 不对 Dart 可见。
pub struct BridgeClient {
    config_dir: PathBuf,
    pub(crate) inner: tokio::sync::Mutex<Option<UbaaClient>>,
    pub(crate) write_intents: tokio::sync::Mutex<HashMap<String, super::write::PendingEntry>>,
}

impl BridgeClient {
    /// 打开应用私有目录中的 Core client。
    #[flutter_rust_bridge::frb(sync)]
    pub fn open(config_dir: String) -> Result<Self, BridgeError> {
        let path = Path::new(&config_dir);
        if config_dir.trim().is_empty() || !path.is_absolute() {
            return Err(BridgeError::local(
                BridgeErrorCode::InvalidInput,
                BridgeErrorKind::Input,
                false,
                "config directory must be an absolute path",
            ));
        }
        let client = std::panic::catch_unwind(AssertUnwindSafe(|| UbaaClient::open(path)))
            .map_err(|_| panic_error())?
            .map_err(|error| BridgeError::from_core(error, None))?;
        Ok(Self {
            config_dir: path.to_path_buf(),
            inner: tokio::sync::Mutex::new(Some(client)),
            write_intents: tokio::sync::Mutex::new(HashMap::new()),
        })
    }

    /// 返回 bridge 合同版本。
    #[flutter_rust_bridge::frb(sync)]
    #[must_use]
    pub const fn contract_version(&self) -> u32 {
        BRIDGE_CONTRACT_VERSION
    }

    /// 幂等销毁 Core client。
    ///
    /// # Errors
    ///
    /// 当前实现不会返回错误；保留 `Result` 以便未来生命周期清理失败时维持稳定 ABI。
    pub async fn dispose(&self) -> Result<(), BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            *guard = None;
            self.write_intents.lock().await.clear();
            Ok(())
        })
        .await
    }

    /// 准备两条路线的登录页状态。
    ///
    /// # Errors
    ///
    /// 客户端已销毁或 Core 无法准备路线时返回安全错误。
    pub async fn prepare_login(&self) -> Result<BridgeLoginPreparation, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            Ok(map_preparation(client.prepare_login().await))
        })
        .await
    }

    /// 提交双路线账号密码。
    ///
    /// # Errors
    ///
    /// 输入为空、客户端已销毁或 Core 登录失败时返回安全错误。
    pub async fn login(
        &self,
        username: String,
        password: String,
    ) -> Result<BridgeLoginOutcome, BridgeError> {
        if username.trim().is_empty() || password.is_empty() {
            return Err(BridgeError::local(
                BridgeErrorCode::InvalidInput,
                BridgeErrorKind::Input,
                false,
                "username and password are required",
            ));
        }
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let input = ubaa_core::facade::DualLoginInput {
                username: username.trim().to_owned(),
                password: ubaa_core::facade::SecretValue::new(password),
            };
            let result = client
                .login(input)
                .await
                .map(map_login_outcome)
                .map_err(|error| BridgeError::from_core(error, None));
            if result.is_ok() {
                self.write_intents.lock().await.clear();
            }
            result
        })
        .await
    }

    /// 校验持久化认证状态。
    ///
    /// # Errors
    ///
    /// 客户端已销毁或 Core 无法读取认证状态时返回安全错误。
    pub async fn auth_status(&self) -> Result<BridgeLoginOutcome, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let result = client
                .auth_status()
                .await
                .map(map_login_outcome)
                .map_err(|error| BridgeError::from_core(error, None));
            // auth_status 会刷新或清理持久化 Session 修订；旧确认意图不得
            // 跨越该认证边界继续提交。
            self.write_intents.lock().await.clear();
            result
        })
        .await
    }

    /// 获取必要的用户资料。
    ///
    /// # Errors
    ///
    /// 客户端已销毁、未认证或 Core 读取资料失败时返回安全错误。
    pub async fn user_info(&self) -> Result<BridgeRoutedUserProfile, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            client
                .get_user_info()
                .await
                .map(|result| BridgeRoutedUserProfile {
                    data: map_profile(result.data),
                    route: map_route(result.resolution),
                })
                .map_err(BridgeError::from_routed)
        })
        .await
    }

    /// 清理 Core Session 并执行尽力远端注销。
    ///
    /// # Errors
    ///
    /// 客户端已销毁或 Core 注销失败时返回安全错误。
    pub async fn logout(&self) -> Result<(), BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let result = client
                .logout()
                .await
                .map_err(|error| BridgeError::from_core(error, None));
            self.write_intents.lock().await.clear();
            result
        })
        .await
    }

    /// 读取全局路线策略与已认证槽位。
    ///
    /// # Errors
    ///
    /// 客户端已销毁时返回安全错误。
    pub async fn route_settings(&self) -> Result<BridgeRouteSettings, BridgeError> {
        catch_panic(async {
            let guard = self.inner.lock().await;
            let client = guard.as_ref().ok_or_else(disposed_error)?;
            Ok(BridgeRouteSettings {
                default_policy: client.default_route_policy().into(),
                active_routes: client.active_routes().into_iter().map(Into::into).collect(),
            })
        })
        .await
    }

    /// 保存新的全局策略、清除 feature override 并重开 Core client。
    ///
    /// # Errors
    ///
    /// 另一个 bridge 操作占用客户端、客户端已销毁、配置保存失败或重开失败时返回安全错误。
    #[allow(clippy::unused_async)]
    pub async fn set_default_route_policy(
        &self,
        policy: BridgeRoutePolicy,
    ) -> Result<BridgeRouteSettings, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.try_lock().map_err(|_| {
                BridgeError::local(
                    BridgeErrorCode::OperationConflict,
                    BridgeErrorKind::Internal,
                    true,
                    "another bridge operation is in progress",
                )
            })?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            client
                .set_default_route_policy(policy.into())
                .map_err(|error| BridgeError::from_core(error, None))?;
            let reopened =
                std::panic::catch_unwind(AssertUnwindSafe(|| UbaaClient::open(&self.config_dir)))
                    .map_err(|_| panic_error())?
                    .map_err(|error| BridgeError::from_core(error, None))?;
            *guard = Some(reopened);
            self.write_intents.lock().await.clear();
            let client = guard.as_ref().ok_or_else(disposed_error)?;
            Ok(BridgeRouteSettings {
                default_policy: client.default_route_policy().into(),
                active_routes: client.active_routes().into_iter().map(Into::into).collect(),
            })
        })
        .await
    }
}

/// 将 Rust panic 归约为不含 panic 正文的稳定 bridge 错误。
pub(crate) async fn catch_panic<T, F>(future: F) -> Result<T, BridgeError>
where
    F: Future<Output = Result<T, BridgeError>>,
{
    AssertUnwindSafe(future)
        .catch_unwind()
        .await
        .unwrap_or_else(|_| Err(panic_error()))
}

pub(crate) fn panic_error() -> BridgeError {
    BridgeError::local(
        BridgeErrorCode::InternalError,
        BridgeErrorKind::Internal,
        false,
        "bridge operation failed internally",
    )
}

pub(crate) fn disposed_error() -> BridgeError {
    BridgeError::local(
        BridgeErrorCode::ClientDisposed,
        BridgeErrorKind::Internal,
        false,
        "bridge client is disposed",
    )
}

fn map_preparation(preparation: DualLoginPreparation) -> BridgeLoginPreparation {
    BridgeLoginPreparation {
        routes: preparation
            .routes
            .into_iter()
            .map(map_route_login)
            .collect(),
    }
}

fn map_login_outcome(outcome: LoginOutcome) -> BridgeLoginOutcome {
    BridgeLoginOutcome {
        readiness: match outcome.readiness {
            ubaa_core::facade::LoginReadiness::AllReady => BridgeLoginReadiness::AllReady,
            ubaa_core::facade::LoginReadiness::Partial => BridgeLoginReadiness::Partial,
            ubaa_core::facade::LoginReadiness::NoneReady => BridgeLoginReadiness::NoneReady,
        },
        routes: outcome.routes.into_iter().map(map_route_login).collect(),
        profile: outcome.profile.map(map_profile),
    }
}

fn map_route_login(result: RouteLoginResult) -> BridgeRouteLoginResult {
    BridgeRouteLoginResult {
        route: result.route.into(),
        state: match result.state {
            RouteLoginState::Ready => BridgeRouteLoginState::Ready,
            RouteLoginState::Failed => BridgeRouteLoginState::Failed,
        },
        error: result.error.map(map_safe_error),
    }
}

fn map_safe_error(error: SafeError) -> BridgeSafeError {
    BridgeSafeError {
        code: error.code,
        kind: error.kind,
        retryable: error.retryable,
        message: error.message,
    }
}

fn map_profile(profile: UserProfile) -> BridgeUserProfile {
    BridgeUserProfile {
        username: profile.username,
        name: profile.name,
        school_id: profile.school_id,
        email: profile.email,
        phone: profile.phone,
        id_card_type_name: profile.id_card_type_name,
    }
}

pub(crate) fn map_route(resolution: RouteResolution) -> BridgeRouteDecision {
    BridgeRouteDecision {
        policy: resolution.policy.into(),
        resolved_route: resolution.mode.into(),
        network: resolution.diagnostic.network.into(),
        initial_route: resolution.diagnostic.initial_route.into(),
        used_fallback: resolution.diagnostic.used_fallback,
    }
}

impl From<ConnectionMode> for BridgeConnectionMode {
    fn from(mode: ConnectionMode) -> Self {
        match mode {
            ConnectionMode::Direct => Self::Direct,
            ConnectionMode::WebVpn => Self::WebVpn,
        }
    }
}

impl From<BridgeConnectionMode> for ConnectionMode {
    fn from(mode: BridgeConnectionMode) -> Self {
        match mode {
            BridgeConnectionMode::Direct => Self::Direct,
            BridgeConnectionMode::WebVpn => Self::WebVpn,
        }
    }
}

impl From<RoutePolicy> for BridgeRoutePolicy {
    fn from(policy: RoutePolicy) -> Self {
        match policy {
            RoutePolicy::Auto => Self::Auto,
            RoutePolicy::Direct => Self::Direct,
            RoutePolicy::WebVpn => Self::WebVpn,
        }
    }
}

impl From<BridgeRoutePolicy> for RoutePolicy {
    fn from(policy: BridgeRoutePolicy) -> Self {
        match policy {
            BridgeRoutePolicy::Auto => Self::Auto,
            BridgeRoutePolicy::Direct => Self::Direct,
            BridgeRoutePolicy::WebVpn => Self::WebVpn,
        }
    }
}

impl From<NetworkState> for BridgeNetworkState {
    fn from(state: NetworkState) -> Self {
        match state {
            NetworkState::Campus => Self::Campus,
            NetworkState::OffCampus => Self::OffCampus,
            NetworkState::Unknown => Self::Unknown,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{BridgeClient, BridgeError, BridgeErrorCode, catch_panic};

    #[tokio::test]
    async fn panic_is_reduced_to_a_stable_internal_error_without_payload() {
        let error = catch_panic(async {
            panic!("sensitive panic payload");
            #[allow(unreachable_code)]
            Ok::<(), BridgeError>(())
        })
        .await
        .expect_err("panic must become a typed bridge error");
        assert_eq!(error.code, BridgeErrorCode::InternalError);
        assert_eq!(error.message, "bridge operation failed internally");
        assert!(!error.message.contains("sensitive"));
    }

    #[tokio::test]
    async fn client_lifecycle_rejects_relative_paths_and_disposes_idempotently() {
        let Err(error) = BridgeClient::open("relative-config".to_owned()) else {
            panic!("relative paths must be rejected");
        };
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);

        let path = std::env::temp_dir().join(format!("ubaa-bridge-client-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&path);
        let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
        assert_eq!(client.contract_version(), 9);
        client.dispose().await.expect("dispose client");
        client.dispose().await.expect("dispose client twice");
        let error = client.auth_status().await.expect_err("disposed client");
        assert_eq!(error.code, BridgeErrorCode::ClientDisposed);
        let _ = std::fs::remove_dir_all(path);
    }

    #[tokio::test]
    async fn disposed_handle_stays_terminal_while_a_rebuilt_client_can_reopen() {
        let path = std::env::temp_dir().join(format!(
            "ubaa-bridge-reopen-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&path);
        let config_dir = path.to_string_lossy().into_owned();
        let old = BridgeClient::open(config_dir.clone()).expect("open old client");
        old.dispose().await.expect("dispose old client");

        let rebuilt = BridgeClient::open(config_dir).expect("reopen after isolate rebuild");
        assert_eq!(rebuilt.contract_version(), 9);
        assert_eq!(
            old.route_settings()
                .await
                .expect_err("old handle stays terminal")
                .code,
            BridgeErrorCode::ClientDisposed
        );
        rebuilt.dispose().await.expect("dispose rebuilt client");
        let _ = std::fs::remove_dir_all(path);
    }
}
