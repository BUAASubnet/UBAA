use super::RoutedError;
use crate::connection::RouteResolution;
use crate::domain::{
    ConnectionMode, DualLoginPreparation, RouteLoginResult, RouteLoginState, SafeError,
};
use crate::error::{ErrorCode, ErrorKind, UbaaError};

pub(super) fn failed_preparation(error: &UbaaError) -> DualLoginPreparation {
    let error = safe_error(error);
    DualLoginPreparation {
        routes: [ConnectionMode::Direct, ConnectionMode::WebVpn].map(|route| RouteLoginResult {
            route,
            state: RouteLoginState::Failed,
            error: Some(error.clone()),
        }),
    }
}

pub(super) fn fixed_route_results(routes: Vec<RouteLoginResult>) -> [RouteLoginResult; 2] {
    routes
        .try_into()
        .expect("completed aggregate operations always produce Direct and WebVPN results")
}

pub(super) fn ready_route(route: ConnectionMode) -> RouteLoginResult {
    RouteLoginResult {
        route,
        state: RouteLoginState::Ready,
        error: None,
    }
}

pub(super) fn failed_route(route: ConnectionMode, error: &UbaaError) -> RouteLoginResult {
    RouteLoginResult {
        route,
        state: RouteLoginState::Failed,
        error: Some(safe_error(error)),
    }
}

pub(super) fn authentication_required() -> UbaaError {
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

pub(super) const fn alternate_route(route: ConnectionMode) -> ConnectionMode {
    match route {
        ConnectionMode::Direct => ConnectionMode::WebVpn,
        ConnectionMode::WebVpn => ConnectionMode::Direct,
    }
}

pub(super) fn safe_error(error: &UbaaError) -> SafeError {
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
