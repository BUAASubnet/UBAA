use std::fmt;

use serde::{Deserialize, Serialize, Serializer};

use super::ConnectionMode;

/// 只读操作结果及 Core 内部实际使用的具体路线。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FeatureResult<T> {
    /// 解析后的稳定 DTO。
    pub data: T,
    /// 本次请求使用的具体路线。
    pub resolved_route: ConnectionMode,
}

/// 在普通格式化和序列化中都会遮盖内容的值。
#[derive(Clone, Eq, PartialEq)]
pub struct SecretValue(String);

impl SecretValue {
    /// 包装秘密值，避免格式化 trait 暴露内容。
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// 仅在上游请求的有限范围内显式借用秘密值。
    #[must_use]
    pub fn expose_secret(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SecretValue([REDACTED])")
    }
}

impl fmt::Display for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("[REDACTED]")
    }
}

impl Serialize for SecretValue {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str("[REDACTED]")
    }
}

/// 一次登录提交使用的凭据。
#[derive(Clone)]
pub struct LoginInput {
    /// SSO 账号名称。
    pub username: String,
    /// SSO 密码，在请求边界之外始终遮盖。
    pub password: SecretValue,
}

impl fmt::Debug for LoginInput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LoginInput")
            .field("username", &"[REDACTED]")
            .field("password", &self.password)
            .finish()
    }
}

/// 两条独立路线会话的登录就绪状态。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LoginReadiness {
    /// 两条路线均已就绪。
    AllReady,
    /// 恰有一条路线就绪。
    Partial,
    /// 两条路线均未就绪。
    NoneReady,
}

/// 聚合登录期间单条路线的安全状态。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RouteLoginState {
    /// 该路线拥有已认证会话。
    Ready,
    /// 该路线失败，但不暴露协议细节。
    Failed,
}

/// 聚合认证公开且不含敏感信息的错误投影。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SafeError {
    /// 稳定的机器错误代码。
    pub code: String,
    /// 稳定的错误类别。
    pub kind: String,
    /// 重试是否可能成功。
    pub retryable: bool,
    /// 可安全展示给用户的消息。
    pub message: String,
}

/// 聚合登录操作中单条路线的结果。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteLoginResult {
    /// 实际尝试的路线。
    pub route: ConnectionMode,
    /// 安全的路线状态。
    pub state: RouteLoginState,
    /// 路线未就绪时的脱敏失败信息。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<SafeError>,
}

/// 按固定 Direct、`WebVPN` 顺序排列的聚合登录结果。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginOutcome {
    /// 聚合就绪状态。
    pub readiness: LoginReadiness,
    /// 恰有两条路线记录，顺序为 Direct、`WebVPN`。
    pub routes: [RouteLoginResult; 2],
    /// 任一认证成功路线返回的资料。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile: Option<UserProfile>,
}

/// 准备两条路线登录页的结果。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DualLoginPreparation {
    /// 固定 Direct、`WebVPN` 状态顺序。
    pub routes: [RouteLoginResult; 2],
}

/// 聚合登录凭据。
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DualLoginInput {
    /// 两条路线尝试共用的 SSO 账号名称。
    pub username: String,
    /// 仅在本次操作内存中保存的密码。
    pub password: SecretValue,
}

impl fmt::Debug for DualLoginInput {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DualLoginInput")
            .field("username", &"[REDACTED]")
            .field("password", &self.password)
            .finish()
    }
}

/// 从旧版 `UserInfo` DTO 映射的用户中心资料。
#[derive(Clone, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserProfile {
    /// 证件类型代码。
    pub id_card_type: Option<String>,
    /// 供用户阅读的证件类型。
    pub id_card_type_name: Option<String>,
    /// 用户中心返回的手机号。
    pub phone: Option<String>,
    /// 学校标识。上游字段拼写为 `schoolid`。
    #[serde(alias = "schoolid")]
    pub school_id: Option<String>,
    /// 显示姓名。
    pub name: Option<String>,
    /// 证件号码。
    pub id_card_number: Option<String>,
    /// 电子邮箱地址。
    pub email: Option<String>,
    /// 用户中心账号名称。
    pub username: Option<String>,
}

impl fmt::Debug for UserProfile {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserProfile")
            .field(
                "id_card_type",
                &redacted_option(self.id_card_type.as_deref()),
            )
            .field(
                "id_card_type_name",
                &redacted_option(self.id_card_type_name.as_deref()),
            )
            .field("phone", &redacted_option(self.phone.as_deref()))
            .field("school_id", &redacted_option(self.school_id.as_deref()))
            .field("name", &redacted_option(self.name.as_deref()))
            .field(
                "id_card_number",
                &redacted_option(self.id_card_number.as_deref()),
            )
            .field("email", &redacted_option(self.email.as_deref()))
            .field("username", &redacted_option(self.username.as_deref()))
            .finish()
    }
}

/// 状态和资料接口共用的用户中心 JSON 包装。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct UserInfoResponse {
    /// 上游结果代码；冻结实现中零表示成功。
    pub code: i64,
    /// 可选的资料载荷。
    pub data: Option<UserProfile>,
}

/// 返回给宿主的已验证认证状态。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatus {
    /// 用户中心身份摘要。
    pub user: UserProfile,
    /// 当前会话完成认证时的 Unix 时间戳。
    pub authenticated_at: i64,
    /// 最近一次成功检查状态时的 Unix 时间戳。
    pub last_activity: i64,
}

impl fmt::Debug for UserInfoResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UserInfoResponse")
            .field("code", &self.code)
            .field("data_present", &self.data.is_some())
            .finish()
    }
}

impl fmt::Debug for AuthStatus {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AuthStatus")
            .field("user", &self.user)
            .field("authenticated_at", &self.authenticated_at)
            .field("last_activity", &self.last_activity)
            .finish()
    }
}

fn redacted_option(value: Option<&str>) -> Option<&'static str> {
    value.map(|_| "[REDACTED]")
}
