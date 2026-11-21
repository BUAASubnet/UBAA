//! 供宿主与绑定层使用的稳定、可序列化错误。

mod auth_diagnostic;
mod diagnostic;
pub use auth_diagnostic::{AuthDiagnostic, AuthReason, AuthStage};
pub use diagnostic::{ErrorDiagnostic, safe_upstream_message};

use std::fmt;

use serde::{Deserialize, Serialize};

/// 认证合同定义的机器稳定错误码。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    /// 参数或交互输入缺失或无效。
    InvalidInput,
    /// 当前身份或业务明细尚不支持。
    Unsupported,
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
    /// 上游业务当前不在可用时段或状态。
    BusinessUnavailable,
    /// 上游已明确拒绝业务请求。
    BusinessRejected,
    /// 非幂等写请求可能已到达上游，但无法确定最终业务结果。
    OutcomeUnknown,
    /// 上游协议不再符合已验证合同。
    UpstreamChanged,
    /// 无法安全解析响应。
    ParseError,
    /// 需要更新应用才能继续访问学校服务。
    UpdateRequired,
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
#[derive(Clone, Deserialize, Eq, Serialize)]
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
    #[serde(skip)]
    diagnostic: Box<ErrorDiagnostic>,
    #[serde(skip)]
    auth_diagnostic: Option<AuthDiagnostic>,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum ErrorCause {
    NetworkChanged,
    SessionConflict,
    SharedAccountConflict,
    ClientClosed,
    AgendaCreationRouteChanged,
    BhpanRouteUnverified,
    CaptchaRequired,
    Initialization(InitializationFailure),
}

/// 本地初始化失败的白名单原因；不包含路径或原始异常正文。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InitializationFailure {
    /// 配置无法安全读取或解析。
    Configuration,
    /// 会话无法安全读取或解析。
    Session,
    /// 其他实例占用本地会话资源。
    ResourceBusy,
    /// 本地传输或运行组件无法创建。
    ComponentUnavailable,
}

// 诊断位置随调用点变化，不参与业务错误的相等判断。
impl PartialEq for UbaaError {
    fn eq(&self, other: &Self) -> bool {
        self.code == other.code
            && self.kind == other.kind
            && self.retryable == other.retryable
            && self.message == other.message
            && self.cause == other.cause
            && self.auth_diagnostic == other.auth_diagnostic
    }
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
    pub(crate) fn campus_network_required(status: u16) -> Self {
        Self::new(
            ErrorCode::NetworkError,
            ErrorKind::Network,
            false,
            "该服务当前仅限校园网访问，可切换到 WebVPN 后重试",
        )
        .with_diagnostic("network", "campus_network_required")
        .with_http_status(status)
    }

    pub(crate) fn campus_network_unattempted(status: u16) -> Self {
        Self::new(
            ErrorCode::NetworkError,
            ErrorKind::Network,
            false,
            "未发送：该服务当前仅限校园网访问，可切换到 WebVPN 后重试",
        )
        .with_diagnostic("network", "campus_network_required")
        .with_http_status(status)
    }

    pub(crate) fn write_unattempted() -> Self {
        Self::new(
            ErrorCode::NetworkError,
            ErrorKind::Network,
            false,
            "未尝试：前一项结果待核对，本批次已停止",
        )
        .with_diagnostic("write", "operation_not_attempted")
    }

    pub(crate) fn campus_network_write_unknown(status: u16) -> Self {
        Self::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            "结果未知，请先刷新核对；该服务当前仅限校园网访问",
        )
        .with_diagnostic("network", "campus_network_required")
        .with_http_status(status)
    }

    pub(crate) fn is_campus_network_required(&self) -> bool {
        self.diagnostic.reason.as_deref() == Some("campus_network_required")
    }

    pub(crate) fn facade_retryable(&self) -> bool {
        self.retryable && !self.is_campus_network_required()
    }

    pub(crate) fn for_facade(mut self) -> Self {
        self.retryable = self.facade_retryable();
        self
    }

    /// 返回与展示文案分离的安全诊断信息。
    #[must_use]
    pub fn diagnostic(&self) -> &ErrorDiagnostic {
        &self.diagnostic
    }

    pub(crate) fn with_diagnostic(mut self, stage: &'static str, reason: &'static str) -> Self {
        self.diagnostic.stage = Some(stage.into());
        self.diagnostic.reason = Some(reason.into());
        self
    }

    /// 字段名必须来自源码常量，只导出预期类型与实际类型，不保留字段值。
    pub(crate) fn with_json_field(
        mut self,
        field: &'static str,
        expected: &'static str,
        value: Option<&serde_json::Value>,
    ) -> Self {
        use serde_json::Value;
        let actual = match value {
            None => "missing",
            Some(Value::Null) => "null",
            Some(Value::Bool(_)) => "boolean",
            Some(Value::Number(_)) => "number",
            Some(Value::String(s)) if s.is_empty() => "empty_string",
            Some(Value::String(_)) => "string",
            Some(Value::Array(_)) => "array",
            Some(Value::Object(_)) => "object",
        };
        self.diagnostic.stage.get_or_insert_with(|| "parse".into());
        self.diagnostic.reason = Some(format!(
            "{}_expected_{expected}_got_{actual}",
            field.to_ascii_lowercase()
        ));
        self
    }

    pub(crate) fn with_http_status(mut self, status: u16) -> Self {
        self.diagnostic.status = Some(status);
        self
    }

    pub(crate) fn with_upstream_code(mut self, code: i64) -> Self {
        self.diagnostic.upstream_code = diagnostic::bounded_upstream_code(code);
        self
    }

    pub(crate) fn with_write_outcome_unknown(mut self, message: &'static str) -> Self {
        self.code = ErrorCode::OutcomeUnknown;
        self.kind = ErrorKind::Upstream;
        self.retryable = false;
        self.message = message.into();
        self.cause = None;
        self.with_diagnostic_default("confirmation", "outcome_unknown")
    }

    pub(crate) fn with_diagnostic_default(
        mut self,
        stage: &'static str,
        reason: &'static str,
    ) -> Self {
        self.diagnostic.stage.get_or_insert_with(|| stage.into());
        self.diagnostic.reason.get_or_insert_with(|| reason.into());
        self
    }

    pub(crate) fn with_response(mut self, body: &[u8], status: Option<u16>) -> Self {
        self.diagnostic.response(body, status, None);
        self
    }

    pub(crate) fn with_business_response(
        mut self,
        body: &[u8],
        status: Option<u16>,
        code_field: &'static str,
    ) -> Self {
        self.diagnostic.response(body, status, Some(code_field));
        self
    }

    /// 返回不含用户数据的本地登录诊断。
    #[must_use]
    pub const fn auth_diagnostic(&self) -> Option<AuthDiagnostic> {
        self.auth_diagnostic
    }

    pub(crate) fn with_auth_reason(mut self, reason: AuthReason) -> Self {
        self.diagnostic.stage = Some(reason.diagnostic().stage.wire_name().into());
        self.diagnostic.reason = Some(reason.wire_name().into());
        self.auth_diagnostic = Some(reason.diagnostic());
        self
    }

    pub(crate) fn with_auth_stage(mut self, stage: AuthStage) -> Self {
        if self.auth_diagnostic.is_none() {
            self.diagnostic
                .stage
                .get_or_insert_with(|| stage.wire_name().into());
            self.auth_diagnostic = Some(AuthDiagnostic {
                stage,
                reason: None,
            });
        }
        self
    }

    #[track_caller]
    pub(crate) fn network_changed() -> Self {
        Self {
            cause: Some(ErrorCause::NetworkChanged),
            ..Self::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                false,
                "网络已变化，读取已取消",
            )
            .with_diagnostic("network", "network_revision_changed")
        }
    }

    /// 本机换网取消，与学校认证失败区分。
    #[must_use]
    pub const fn is_network_changed(&self) -> bool {
        matches!(self.cause, Some(ErrorCause::NetworkChanged))
    }
    /// 构造不可重试的输入错误。
    #[track_caller]
    pub fn invalid_input(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
    }

    /// 构造不可重试的上游协议变化错误。
    #[track_caller]
    pub fn upstream_changed(message: impl Into<String>) -> Self {
        Self::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            message,
        )
    }

    /// 构造不可重试的解析错误。
    #[track_caller]
    pub fn parse_error(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::ParseError, ErrorKind::Parse, false, message)
    }

    #[track_caller]
    pub(crate) fn json_error(
        error: &serde_json::Error,
        message: &'static str,
        body: &[u8],
    ) -> Self {
        let result = if error.is_data() {
            Self::upstream_changed(message)
        } else {
            Self::parse_error(message)
        };
        result.with_json_error(error, body)
    }

    /// 为已有错误补充 JSON 解码上下文，保留调用方的错误码与重试语义。
    pub(crate) fn with_json_error(mut self, error: &serde_json::Error, body: &[u8]) -> Self {
        self = self
            .with_diagnostic(
                "parse",
                if error.is_data() {
                    "response_shape_invalid"
                } else {
                    "json_invalid"
                },
            )
            .with_response(body, None);
        self.diagnostic.json_line = Some(error.line());
        self.diagnostic.json_column = Some(error.column());
        self
    }

    /// 构造认证要求错误。
    #[track_caller]
    pub fn authentication_required(message: impl Into<String>) -> Self {
        Self::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            message,
        )
    }

    pub(crate) fn captcha_required() -> Self {
        Self {
            cause: Some(ErrorCause::CaptchaRequired),
            ..Self::authentication_required("请填写验证码完成登录")
        }
    }

    /// 当前认证已转交专用人工验证码流程，不表示保存的密码已被判定无效。
    #[must_use]
    pub const fn is_captcha_required(&self) -> bool {
        matches!(self.cause, Some(ErrorCause::CaptchaRequired))
    }

    /// 构造可重试的上游不可用错误。
    #[track_caller]
    pub fn upstream_unavailable(message: impl Into<String>) -> Self {
        Self::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            message,
        )
    }

    /// 构造可重试的上游业务不可用错误。
    #[track_caller]
    pub fn business_unavailable(message: impl Into<String>) -> Self {
        Self::new(
            ErrorCode::BusinessUnavailable,
            ErrorKind::Upstream,
            true,
            message,
        )
    }

    #[track_caller]
    pub(crate) fn business_rejected(message: impl Into<String>) -> Self {
        Self::new(
            ErrorCode::BusinessRejected,
            ErrorKind::Upstream,
            false,
            message,
        )
        .with_diagnostic("response", "business_rejected")
    }

    /// 构造学校请求被更新门控拒绝的错误。
    #[must_use]
    pub fn update_required() -> Self {
        Self::new(
            ErrorCode::UpdateRequired,
            ErrorKind::Upstream,
            false,
            "请更新应用后再使用学校功能",
        )
    }

    /// 构造不可重试的结果未知错误。
    #[track_caller]
    pub fn outcome_unknown(message: impl Into<String>) -> Self {
        Self::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            message,
        )
        .with_diagnostic("confirmation", "outcome_unknown")
    }

    pub(crate) fn with_initialization_failure(mut self, failure: InitializationFailure) -> Self {
        if self.initialization_failure().is_none() {
            self.cause = Some(ErrorCause::Initialization(failure));
        }
        self
    }

    /// 返回本进程建立的初始化分类，不从外部字符串推断。
    #[must_use]
    pub fn initialization_failure(&self) -> Option<InitializationFailure> {
        match self.cause {
            Some(ErrorCause::Initialization(failure)) => Some(failure),
            _ => None,
        }
    }

    pub(crate) fn resource_busy() -> Self {
        Self::new(
            ErrorCode::Timeout,
            ErrorKind::Internal,
            true,
            "本地会话资源忙，请稍后重试",
        )
        .with_initialization_failure(InitializationFailure::ResourceBusy)
    }

    /// 构造由本地缓存锁占用导致的可重试错误。
    #[track_caller]
    #[must_use]
    pub fn cache_busy() -> Self {
        Self::new(
            ErrorCode::Timeout,
            ErrorKind::Internal,
            true,
            crate::cache::CacheError::Busy.to_string(),
        )
        .with_diagnostic("cache", "cache_busy")
    }

    /// 构造安全的 Core 错误。
    #[track_caller]
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
            diagnostic: Box::new(ErrorDiagnostic::at(std::panic::Location::caller())),
            cause: None,
            auth_diagnostic: None,
        }
    }

    #[track_caller]
    pub(crate) fn agenda_creation_route_changed() -> Self {
        let mut error = Self::invalid_input("日程同步路线已变化，请重新拉取并确认");
        error.cause = Some(ErrorCause::AgendaCreationRouteChanged);
        error.with_diagnostic("route", "route_revision_changed")
    }

    pub(crate) const fn is_agenda_creation_route_changed(&self) -> bool {
        matches!(self.cause, Some(ErrorCause::AgendaCreationRouteChanged))
    }

    #[track_caller]
    pub(crate) fn bhpan_route_unverified() -> Self {
        Self {
            cause: Some(ErrorCause::BhpanRouteUnverified),
            ..Self::new(
                ErrorCode::PermissionDenied,
                ErrorKind::Input,
                false,
                "云盘 WebVPN 完整链路尚缺协议证据，请选择 Direct 路线",
            )
            .with_diagnostic("route", "route_unverified")
        }
    }

    pub(crate) const fn is_bhpan_route_unverified(&self) -> bool {
        matches!(self.cause, Some(ErrorCause::BhpanRouteUnverified))
    }

    #[track_caller]
    pub(crate) fn session_conflict() -> Self {
        Self {
            cause: Some(ErrorCause::SessionConflict),
            ..Self::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                true,
                "local session changed in another process",
            )
            .with_diagnostic("session", "session_revision_changed")
        }
    }

    #[track_caller]
    pub(crate) fn client_closed() -> Self {
        Self {
            cause: Some(ErrorCause::ClientClosed),
            ..Self::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "client handle is closed",
            )
            .with_diagnostic("lifecycle", "client_closed")
        }
    }
    /// 此错误是否由本进程句柄普通关闭产生。
    #[must_use]
    pub fn is_client_closed(&self) -> bool {
        self.cause == Some(ErrorCause::ClientClosed)
    }
    #[track_caller]
    pub(crate) fn shared_account_conflict() -> Self {
        Self {
            cause: Some(ErrorCause::SharedAccountConflict),
            ..Self::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "shared account authority was revoked",
            )
            .with_diagnostic("session", "shared_account_conflict")
        }
    }
    /// 此错误是否由本机共享身份的固定版本检查产生。
    #[must_use]
    pub fn is_shared_account_conflict(&self) -> bool {
        self.cause == Some(ErrorCause::SharedAccountConflict)
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
    fn 校园网提示按发送边界区分确定失败与未知结果() {
        let before_send = UbaaError::campus_network_required(200);
        assert_eq!(before_send.code, ErrorCode::NetworkError);
        assert!(!before_send.retryable);
        assert_eq!(
            before_send.diagnostic().reason.as_deref(),
            Some("campus_network_required")
        );
        let after_send = UbaaError::campus_network_write_unknown(200);
        assert_eq!(after_send.code, ErrorCode::OutcomeUnknown);
        assert!(!after_send.retryable);
        assert_eq!(
            after_send.diagnostic().reason.as_deref(),
            Some("campus_network_required")
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

    #[test]
    fn 便捷构造器保持错误合同字段() {
        assert_eq!(
            UbaaError::invalid_input("x"),
            UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, "x")
        );
        assert_eq!(
            UbaaError::upstream_changed("x"),
            UbaaError::new(ErrorCode::UpstreamChanged, ErrorKind::Upstream, false, "x")
        );
        assert_eq!(
            UbaaError::parse_error("x"),
            UbaaError::new(ErrorCode::ParseError, ErrorKind::Parse, false, "x")
        );
        assert_eq!(
            UbaaError::authentication_required("x"),
            UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "x",
            )
        );
        assert_eq!(
            UbaaError::upstream_unavailable("x"),
            UbaaError::new(
                ErrorCode::UpstreamUnavailable,
                ErrorKind::Upstream,
                true,
                "x"
            )
        );
        assert_eq!(
            UbaaError::business_unavailable("x"),
            UbaaError::new(
                ErrorCode::BusinessUnavailable,
                ErrorKind::Upstream,
                true,
                "x"
            )
        );
        assert_eq!(
            UbaaError::outcome_unknown("x"),
            UbaaError::new(ErrorCode::OutcomeUnknown, ErrorKind::Upstream, false, "x")
        );
    }
}
