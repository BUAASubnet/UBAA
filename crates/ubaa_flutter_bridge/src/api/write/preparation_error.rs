use crate::api::client::{BridgeError, BridgeErrorCode as B, BridgeErrorKind as K, panic_error};
use futures_util::FutureExt;
use ubaa_core::facade as core;

pub(crate) struct PreparationError {
    bridge: BridgeError,
    original: Option<core::RoutedError>,
}
impl PreparationError {
    pub(crate) fn from_routed(error: core::RoutedError) -> Self {
        Self {
            bridge: BridgeError::from_routed(error.clone()),
            original: Some(error),
        }
    }
    pub(crate) fn mapped(
        error: core::RoutedError,
        map: impl FnOnce(core::RoutedError) -> BridgeError,
    ) -> Self {
        Self {
            bridge: map(error.clone()),
            original: Some(error),
        }
    }
    pub(crate) fn into_bridge(self) -> BridgeError {
        self.bridge
    }
    pub(crate) fn into_routed(self) -> core::RoutedError {
        self.original
            .unwrap_or_else(|| routed_bridge_error(self.bridge))
    }
}
impl From<BridgeError> for PreparationError {
    fn from(bridge: BridgeError) -> Self {
        Self {
            bridge,
            original: None,
        }
    }
}
pub(crate) fn routed_bridge_error(error: BridgeError) -> core::RoutedError {
    let code = match error.code {
        B::AuthenticationRequired | B::CaptchaRequired => core::ErrorCode::AuthenticationRequired,
        B::InvalidCredentials => core::ErrorCode::InvalidCredentials,
        B::PasswordRiskConfirmationFailed => core::ErrorCode::PasswordRiskConfirmationFailed,
        B::PermissionDenied | B::CacheIdentityMismatch => core::ErrorCode::PermissionDenied,
        B::NetworkError => core::ErrorCode::NetworkError,
        B::Timeout => core::ErrorCode::Timeout,
        B::UpstreamUnavailable => core::ErrorCode::UpstreamUnavailable,
        B::UpstreamChanged => core::ErrorCode::UpstreamChanged,
        B::ParseError => core::ErrorCode::ParseError,
        B::OutcomeUnknown => core::ErrorCode::OutcomeUnknown,
        B::InvalidInput | B::ConfirmationRequired | B::IntentExpired => {
            core::ErrorCode::InvalidInput
        }
        B::InternalError | B::ClientDisposed | B::OperationConflict => {
            core::ErrorCode::InternalError
        }
    };
    let kind = match error.kind {
        K::Input => core::ErrorKind::Input,
        K::Authentication => core::ErrorKind::Authentication,
        K::Network => core::ErrorKind::Network,
        K::Upstream => core::ErrorKind::Upstream,
        K::Parse => core::ErrorKind::Parse,
        K::Internal => core::ErrorKind::Internal,
    };
    core::RoutedError {
        error: core::UbaaError::new(code, kind, error.retryable, error.message),
        resolution: None,
    }
}
pub(crate) async fn catch_preparation_panic<T>(
    future: impl std::future::Future<Output = Result<T, PreparationError>>,
) -> Result<T, PreparationError> {
    std::panic::AssertUnwindSafe(future)
        .catch_unwind()
        .await
        .unwrap_or_else(|_| Err(panic_error().into()))
}
