//! Stable, serializable errors for hosts and bindings.

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::domain::LoginChallenge;

/// Machine-stable error code from the authentication contract.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// An argument or interactive value is missing or invalid.
    InvalidInput,
    /// No valid persisted authentication exists.
    AuthenticationRequired,
    /// SSO rejected the supplied credentials.
    InvalidCredentials,
    /// SSO requires a captcha answer.
    CaptchaRequired,
    /// SSO did not accept the one permitted password-risk continuation.
    PasswordRiskConfirmationFailed,
    /// The authenticated account lacks permission.
    PermissionDenied,
    /// A network operation failed.
    NetworkError,
    /// A bounded network operation timed out.
    Timeout,
    /// The upstream service is temporarily unavailable.
    UpstreamUnavailable,
    /// The upstream protocol no longer matches the verified contract.
    UpstreamChanged,
    /// A response could not be safely parsed.
    ParseError,
    /// An internal invariant failed.
    InternalError,
}

impl ErrorCode {
    /// Stable process exit category for CLI hosts.
    #[must_use]
    pub const fn exit_code(self) -> ExitCode {
        match self {
            Self::InvalidInput => ExitCode::InvalidInput,
            Self::AuthenticationRequired
            | Self::InvalidCredentials
            | Self::PasswordRiskConfirmationFailed
            | Self::PermissionDenied => ExitCode::Authentication,
            Self::CaptchaRequired => ExitCode::CaptchaRequired,
            Self::NetworkError | Self::Timeout | Self::UpstreamUnavailable => ExitCode::Network,
            Self::UpstreamChanged | Self::ParseError => ExitCode::Upstream,
            Self::InternalError => ExitCode::Internal,
        }
    }
}

/// Broad error category suitable for host presentation.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    /// Invalid caller input.
    Input,
    /// Authentication or authorization failure.
    Authentication,
    /// Network or timeout failure.
    Network,
    /// Upstream availability or protocol failure.
    Upstream,
    /// Response parsing failure.
    Parse,
    /// Internal invariant failure.
    Internal,
}

/// CLI exit codes fixed by the public contract.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(i32)]
pub enum ExitCode {
    /// Successful command.
    Success = 0,
    /// Invalid command argument or input.
    InvalidInput = 2,
    /// Authentication is absent or failed.
    Authentication = 3,
    /// Captcha input is required.
    CaptchaRequired = 4,
    /// Network, timeout, or temporary upstream failure.
    Network = 5,
    /// Upstream shape or parsing failure.
    Upstream = 6,
    /// Internal failure.
    Internal = 7,
}

/// Safe error payload returned by the core.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct UbaaError {
    /// Stable machine code.
    pub code: ErrorCode,
    /// Broad category.
    pub kind: ErrorKind,
    /// Whether repeating the non-secret operation may succeed later.
    pub retryable: bool,
    /// Human-readable message that contains no sensitive body or header data.
    pub message: String,
    /// Ephemeral captcha challenge, only for `captcha_required`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub challenge: Option<LoginChallenge>,
}

impl fmt::Debug for UbaaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UbaaError")
            .field("code", &self.code)
            .field("kind", &self.kind)
            .field("retryable", &self.retryable)
            .field("message", &"[REDACTED]")
            .field("challenge", &self.challenge.as_ref().map(|_| "[REDACTED]"))
            .finish()
    }
}

impl UbaaError {
    /// Construct a safe core error.
    pub fn new(
        code: ErrorCode,
        kind: ErrorKind,
        retryable: bool,
        message: impl Into<String>,
    ) -> Self {
        Self {
            code,
            kind,
            retryable,
            message: message.into(),
            challenge: None,
        }
    }

    /// Attach an ephemeral captcha challenge.
    #[must_use]
    pub fn with_challenge(mut self, challenge: LoginChallenge) -> Self {
        self.challenge = Some(challenge);
        self
    }
}

impl fmt::Display for UbaaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}", self.message)
    }
}

impl std::error::Error for UbaaError {}

/// Core result alias.
pub type Result<T> = std::result::Result<T, UbaaError>;
