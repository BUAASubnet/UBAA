//! CLI JSON 错误载荷与稳定名称映射。

use std::fmt;

use serde::Serialize;
use ubaa_core::facade::SafeError;
use ubaa_core::facade::{ErrorCode, ErrorKind, Result, UbaaError};

pub(crate) const CGYY_CANCEL_OUTCOME_UNKNOWN_MESSAGE: &str =
    "场馆订单取消结果未知，请刷新订单列表与详情核对后再操作";
pub(crate) const CGYY_RESERVATION_OUTCOME_UNKNOWN_MESSAGE: &str =
    "场馆写入结果未知，请稍后查询预约记录确认";

/// 安全的 CLI 错误载荷。
#[derive(Clone, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CliJsonError {
    code: String,
    kind: String,
    message: String,
    retryable: bool,
}

impl CliJsonError {
    /// 将 Core 错误转换为稳定的宿主载荷。
    #[must_use]
    pub fn from_core(error: UbaaError) -> Self {
        Self {
            code: error_code_name(error.code).to_owned(),
            kind: error_kind_name(error.kind).to_owned(),
            message: error.message,
            retryable: error.retryable,
        }
    }

    /// 转换经过校验的聚合错误投影。
    ///
    /// # Errors
    ///
    /// 投影包含未知代码或类别时返回内部错误。
    pub fn try_from_safe(error: SafeError) -> Result<Self> {
        if !is_error_code(&error.code) || !is_error_kind(&error.kind) {
            return Err(output_invariant_error(
                "aggregate error projection has an unsupported code or kind",
            ));
        }
        Ok(Self {
            code: error.code,
            kind: error.kind,
            message: error.message,
            retryable: error.retryable,
        })
    }
}

impl From<UbaaError> for CliJsonError {
    fn from(error: UbaaError) -> Self {
        Self::from_core(error)
    }
}

impl fmt::Debug for CliJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CliJsonError")
            .field("code", &self.code)
            .field("kind", &self.kind)
            .field("message", &"[REDACTED]")
            .field("retryable", &self.retryable)
            .finish()
    }
}
pub(super) fn output_invariant_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

const fn error_code_name(code: ErrorCode) -> &'static str {
    match code {
        ErrorCode::InvalidInput => "invalid_input",
        ErrorCode::AuthenticationRequired => "authentication_required",
        ErrorCode::InvalidCredentials => "invalid_credentials",
        ErrorCode::PasswordRiskConfirmationFailed => "password_risk_confirmation_failed",
        ErrorCode::PermissionDenied => "permission_denied",
        ErrorCode::NetworkError => "network_error",
        ErrorCode::Timeout => "timeout",
        ErrorCode::UpstreamUnavailable => "upstream_unavailable",
        ErrorCode::OutcomeUnknown => "outcome_unknown",
        ErrorCode::UpstreamChanged => "upstream_changed",
        ErrorCode::ParseError => "parse_error",
        ErrorCode::InternalError => "internal_error",
    }
}

const fn error_kind_name(kind: ErrorKind) -> &'static str {
    match kind {
        ErrorKind::Input => "input",
        ErrorKind::Authentication => "authentication",
        ErrorKind::Network => "network",
        ErrorKind::Upstream => "upstream",
        ErrorKind::Parse => "parse",
        ErrorKind::Internal => "internal",
    }
}

fn is_error_code(code: &str) -> bool {
    matches!(
        code,
        "invalid_input"
            | "authentication_required"
            | "invalid_credentials"
            | "password_risk_confirmation_failed"
            | "permission_denied"
            | "network_error"
            | "timeout"
            | "upstream_unavailable"
            | "outcome_unknown"
            | "upstream_changed"
            | "parse_error"
            | "internal_error"
    )
}

fn is_error_kind(kind: &str) -> bool {
    matches!(
        kind,
        "input" | "authentication" | "network" | "upstream" | "parse" | "internal"
    )
}
