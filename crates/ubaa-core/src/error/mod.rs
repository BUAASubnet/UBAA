//! 供宿主与绑定层使用的稳定、可序列化错误。

use std::fmt;

use serde::{Deserialize, Serialize};

/// 认证合同定义的机器稳定错误码。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// 参数或交互输入缺失或无效。
    InvalidInput,
    /// 不存在有效的持久化认证。
    AuthenticationRequired,
    /// SSO 拒绝了提供的凭据。
    InvalidCredentials,
    /// SSO 未接受唯一允许的密码风险继续操作。
    PasswordRiskConfirmationFailed,
    /// 已认证账号缺少权限。
    PermissionDenied,
    /// 网络操作失败。
    NetworkError,
    /// 有界网络操作超时。
    Timeout,
    /// 上游服务暂时不可用。
    UpstreamUnavailable,
    /// 非幂等写请求可能已到达上游，但无法确定最终业务结果。
    OutcomeUnknown,
    /// 上游协议不再符合已验证合同。
    UpstreamChanged,
    /// 无法安全解析响应。
    ParseError,
    /// 内部不变量失效。
    InternalError,
}

/// 适合宿主展示的宽泛错误类别。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    /// 调用方输入无效。
    Input,
    /// 认证或授权失败。
    Authentication,
    /// 网络或超时失败。
    Network,
    /// 上游可用性或协议失败。
    Upstream,
    /// 响应解析失败。
    Parse,
    /// 内部不变量失败。
    Internal,
}

/// Core 返回的安全错误载荷。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct UbaaError {
    /// 稳定机器码。
    pub code: ErrorCode,
    /// 宽泛类别。
    pub kind: ErrorKind,
    /// 稍后重试非敏感操作是否可能成功。
    pub retryable: bool,
    /// 不包含敏感响应体或请求头数据的人类可读消息。
    pub message: String,
    /// 仅本进程的可信控制流使用，不属于公开 wire 错误合同。
    #[serde(skip)]
    cause: Option<ErrorCause>,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum ErrorCause {
    SessionConflict,
}

impl fmt::Debug for UbaaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UbaaError")
            .field("code", &self.code)
            .field("kind", &self.kind)
            .field("retryable", &self.retryable)
            .field("message", &"[REDACTED]")
            .finish_non_exhaustive()
    }
}

impl UbaaError {
    /// 构造安全的 Core 错误。
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
            cause: None,
        }
    }

    pub(crate) fn session_conflict() -> Self {
        Self {
            cause: Some(ErrorCause::SessionConflict),
            ..Self::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                true,
                "local session changed in another process",
            )
        }
    }

    /// 此错误是否由当前 Core 的 Session 修订冲突产生。
    ///
    /// 原因不从消息或序列化数据恢复；外部输入不能伪造本进程的冲突证明。
    #[must_use]
    pub fn is_session_conflict(&self) -> bool {
        self.cause == Some(ErrorCause::SessionConflict)
    }
}

impl fmt::Display for UbaaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}", self.message)
    }
}

impl std::error::Error for UbaaError {}

/// Core 结果别名。
pub type Result<T> = std::result::Result<T, UbaaError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 冲突原因随内存错误传播而不依赖文案() {
        let mut error = UbaaError::session_conflict();
        error.message = "新的安全展示文案".into();
        assert!(error.clone().is_session_conflict());
        assert!(
            !UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                true,
                "local session changed in another process",
            )
            .is_session_conflict()
        );
    }

    #[test]
    fn 错误序列化保持四字段且外部数据不能伪造内部原因() {
        let error = UbaaError::session_conflict();
        let value = serde_json::to_value(&error).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "code": "internal_error", "kind": "internal", "retryable": true,
                "message": "local session changed in another process",
            })
        );
        let mut forged = value;
        forged["cause"] = serde_json::json!("SessionConflict");
        let projected: UbaaError = serde_json::from_value(forged).unwrap();
        assert!(!projected.is_session_conflict());
        assert_eq!(projected.code, error.code);
        assert_eq!(projected.kind, error.kind);
        assert_eq!(projected.retryable, error.retryable);
        assert_eq!(projected.message, error.message);
    }
}
