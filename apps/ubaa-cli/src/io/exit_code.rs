//! CLI 进程退出码及错误到退出策略的映射。

use ubaa_core::facade::ErrorCode;
use ubaa_core::facade::SafeError;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(i32)]
pub(crate) enum ExitCode {
    Success = 0,
    InvalidInput = 2,
    Authentication = 3,
    Network = 5,
    Upstream = 6,
    Internal = 7,
}

pub(crate) const fn exit_code(code: ErrorCode) -> ExitCode {
    match code {
        ErrorCode::InvalidInput => ExitCode::InvalidInput,
        ErrorCode::AuthenticationRequired
        | ErrorCode::InvalidCredentials
        | ErrorCode::PasswordRiskConfirmationFailed
        | ErrorCode::PermissionDenied => ExitCode::Authentication,
        ErrorCode::NetworkError | ErrorCode::Timeout | ErrorCode::UpstreamUnavailable => {
            ExitCode::Network
        }
        ErrorCode::UpstreamChanged | ErrorCode::ParseError => ExitCode::Upstream,
        ErrorCode::InternalError => ExitCode::Internal,
    }
}

pub(crate) fn safe_error_exit_code(error: &SafeError) -> i32 {
    match error.code.as_str() {
        "invalid_input" => ExitCode::InvalidInput as i32,
        "authentication_required"
        | "invalid_credentials"
        | "password_risk_confirmation_failed"
        | "permission_denied" => ExitCode::Authentication as i32,
        "network_error" | "timeout" | "upstream_unavailable" => ExitCode::Network as i32,
        "upstream_changed" | "parse_error" => ExitCode::Upstream as i32,
        _ => ExitCode::Internal as i32,
    }
}
