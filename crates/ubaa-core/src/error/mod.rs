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
}

impl fmt::Debug for UbaaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UbaaError")
            .field("code", &self.code)
            .field("kind", &self.kind)
            .field("retryable", &self.retryable)
            .field("message", &"[REDACTED]")
            .finish()
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
        }
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
