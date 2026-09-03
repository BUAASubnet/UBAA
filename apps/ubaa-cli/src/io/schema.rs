//! CLI JSON 架构、路线信封与命令结果模型。

use std::fmt;

use serde::Serialize;

use serde_json::Value;
use ubaa_core::domain::{
    AuthStatus, ConnectionMode, FeatureResult, LoginOutcome, LoginReadiness, RouteLoginState,
    RoutePolicy, SafeError, UserProfile,
};
use ubaa_core::error::{Result as CoreResult, UbaaError};
use ubaa_core::facade::{NetworkState, RouteResolution};

use crate::io::error::{CliJsonError, output_invariant_error};
use crate::io::input::internal_error;

/// CLI 唯一支持的 JSON 架构版本。
pub const CLI_JSON_SCHEMA_VERSION: u32 = 2;

/// CLI JSON 元数据使用的封闭功能名称集合。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum CliFeature {
    /// 参数解析和进程启动。
    Cli,
    /// 认证、状态和登出。
    Auth,
    /// 用户资料查询。
    User,
    /// 课表和教学周查询。
    Schedule,
    /// 考试安排查询。
    Exam,
    /// 成绩查询。
    Grades,
    /// 空闲教室查询。
    Classroom,
    /// SPOC 作业查询。
    Spoc,
    /// 希冀作业查询。
    Judge,
    /// 课堂签到查询。
    Signin,
    /// 图书馆座位与预约查询。
    LibBook,
    /// 博雅课程查询。
    Bykc,
    /// 阳光打卡查询。
    Ygdk,
    /// 场馆预约查询。
    Cgyy,
    /// 教学评教查询。
    Evaluation,
}

impl CliFeature {
    /// 返回稳定的 JSON 拼写。
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Cli => "cli",
            Self::Auth => "auth",
            Self::User => "user",
            Self::Schedule => "schedule",
            Self::Exam => "exam",
            Self::Grades => "grades",
            Self::Classroom => "classroom",
            Self::Spoc => "spoc",
            Self::Judge => "judge",
            Self::Signin => "signin",
            Self::LibBook => "libbook",
            Self::Bykc => "bykc",
            Self::Ygdk => "ygdk",
            Self::Cgyy => "cgyy",
            Self::Evaluation => "evaluation",
        }
    }
}

/// Core 解析路线后输出的完整路线元数据。
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedRoutedJsonMeta {
    route_policy: RoutePolicy,
    network_state: NetworkState,
    initial_route: ConnectionMode,
    resolved_route: ConnectionMode,
    used_fallback: bool,
    feature: CliFeature,
}

impl ResolvedRoutedJsonMeta {
    /// 将 Core 路线决策投影为稳定 CLI 元数据。
    #[must_use]
    pub const fn from_resolution(feature: CliFeature, resolution: RouteResolution) -> Self {
        Self {
            route_policy: resolution.policy,
            network_state: resolution.diagnostic.network,
            initial_route: resolution.diagnostic.initial_route,
            resolved_route: resolution.mode,
            used_fallback: resolution.diagnostic.used_fallback,
            feature,
        }
    }

    /// 为未执行探测的显式诊断路线构造元数据。
    #[must_use]
    pub const fn explicit(feature: CliFeature, mode: ConnectionMode) -> Self {
        Self {
            route_policy: match mode {
                ConnectionMode::Direct => RoutePolicy::Direct,
                ConnectionMode::WebVpn => RoutePolicy::WebVpn,
            },
            network_state: NetworkState::Unknown,
            initial_route: mode,
            resolved_route: mode,
            used_fallback: false,
            feature,
        }
    }
}

/// 路线解析前发生失败时使用的最小元数据。
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UnresolvedRoutedJsonMeta {
    feature: CliFeature,
}

impl UnresolvedRoutedJsonMeta {
    /// 标识操作，但不擅自编造路线诊断。
    #[must_use]
    pub const fn new(feature: CliFeature) -> Self {
        Self { feature }
    }
}

#[derive(Clone, Copy, Debug, Serialize)]
#[serde(untagged)]
enum RoutedJsonMeta {
    Resolved(ResolvedRoutedJsonMeta),
    Unresolved(UnresolvedRoutedJsonMeta),
}

/// 一项路线命令的 JSON 信封。
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoutedJsonEnvelope<T> {
    schema_version: u32,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<CliJsonError>,
    meta: RoutedJsonMeta,
}

impl<T> RoutedJsonEnvelope<T> {
    /// 路线解析后构造成功响应。
    #[must_use]
    pub const fn success(data: T, meta: ResolvedRoutedJsonMeta) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
            meta: RoutedJsonMeta::Resolved(meta),
        }
    }
}

impl RoutedJsonEnvelope<serde_json::Value> {
    /// 路线解析后构造失败响应。
    #[must_use]
    pub fn resolved_failure(error: impl Into<CliJsonError>, meta: ResolvedRoutedJsonMeta) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error.into()),
            meta: RoutedJsonMeta::Resolved(meta),
        }
    }

    /// 在不虚构路线元数据的情况下构造失败响应。
    #[must_use]
    pub fn unresolved_failure(
        error: impl Into<CliJsonError>,
        meta: UnresolvedRoutedJsonMeta,
    ) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error.into()),
            meta: RoutedJsonMeta::Unresolved(meta),
        }
    }
}

impl<T> fmt::Debug for RoutedJsonEnvelope<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RoutedJsonEnvelope")
            .field("schema_version", &self.schema_version)
            .field("ok", &self.ok)
            .field("data_present", &self.data.is_some())
            .field("error_present", &self.error.is_some())
            .field("meta", &self.meta)
            .finish()
    }
}

/// 使用固定 Direct、`WebVPN` 路线对的聚合认证元数据。
#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateJsonMeta {
    route_policy: RoutePolicy,
    resolved_routes: [ConnectionMode; 2],
    feature: CliFeature,
}

impl AggregateJsonMeta {
    /// 构造认证元数据，不接受调用方提供的路线。
    #[must_use]
    pub const fn auth(route_policy: RoutePolicy) -> Self {
        Self {
            route_policy,
            resolved_routes: [ConnectionMode::Direct, ConnectionMode::WebVpn],
            feature: CliFeature::Auth,
        }
    }
}

/// 只能通过合同构造函数创建状态的聚合 JSON 信封。
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateJsonEnvelope<T> {
    schema_version: u32,
    ok: bool,
    data: T,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<CliJsonError>,
    meta: AggregateJsonMeta,
}

impl AggregateJsonEnvelope<LoginOutcome> {
    /// 构造成功的聚合认证响应。
    ///
    /// # Errors
    ///
    /// 当路线对不是 Direct、`WebVPN` 顺序时返回内部错误。
    pub fn auth_success(
        outcome: LoginOutcome,
        route_policy: RoutePolicy,
    ) -> Result<Self, UbaaError> {
        validate_auth_outcome(&outcome, true)?;
        Ok(Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: true,
            data: outcome,
            error: None,
            meta: AggregateJsonMeta::auth(route_policy),
        })
    }

    /// 构造失败的聚合认证响应。
    ///
    /// # Errors
    ///
    /// 当路线对或安全错误投影无效时返回内部错误。
    pub fn auth_failure(
        outcome: LoginOutcome,
        error: SafeError,
        route_policy: RoutePolicy,
    ) -> Result<Self, UbaaError> {
        validate_auth_outcome(&outcome, false)?;
        let error = CliJsonError::try_from_safe(error)?;
        Ok(Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: false,
            data: outcome,
            error: Some(error),
            meta: AggregateJsonMeta::auth(route_policy),
        })
    }
}

impl<T> fmt::Debug for AggregateJsonEnvelope<T> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AggregateJsonEnvelope")
            .field("schema_version", &self.schema_version)
            .field("ok", &self.ok)
            .field("data", &"[REDACTED]")
            .field("error_present", &self.error.is_some())
            .field("meta", &self.meta)
            .finish()
    }
}

/// 聚合退出时输出的固定路线状态。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum AggregateLogoutRouteState {
    LoggedOut,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
struct AggregateLogoutRoute {
    route: ConnectionMode,
    state: AggregateLogoutRouteState,
}

/// 成功聚合退出的数据，明确命名两条路线槽位。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AggregateLogoutData {
    logged_out: bool,
    routes: [AggregateLogoutRoute; 2],
}

impl AggregateLogoutData {
    /// 构造唯一有效的聚合注销结果。
    #[must_use]
    pub const fn new() -> Self {
        Self {
            logged_out: true,
            routes: [
                AggregateLogoutRoute {
                    route: ConnectionMode::Direct,
                    state: AggregateLogoutRouteState::LoggedOut,
                },
                AggregateLogoutRoute {
                    route: ConnectionMode::WebVpn,
                    state: AggregateLogoutRouteState::LoggedOut,
                },
            ],
        }
    }
}

impl Default for AggregateLogoutData {
    fn default() -> Self {
        Self::new()
    }
}

impl AggregateJsonEnvelope<AggregateLogoutData> {
    /// 为两个会话槽位构造成功的聚合注销响应。
    #[must_use]
    pub const fn logout_success(route_policy: RoutePolicy) -> Self {
        Self {
            schema_version: CLI_JSON_SCHEMA_VERSION,
            ok: true,
            data: AggregateLogoutData::new(),
            error: None,
            meta: AggregateJsonMeta::auth(route_policy),
        }
    }
}

fn validate_auth_outcome(outcome: &LoginOutcome, success: bool) -> Result<(), UbaaError> {
    if outcome.routes[0].route != ConnectionMode::Direct
        || outcome.routes[1].route != ConnectionMode::WebVpn
    {
        return Err(output_invariant_error(
            "aggregate authentication routes must be Direct then WebVPN",
        ));
    }
    for route in &outcome.routes {
        let state_matches_error = match route.state {
            RouteLoginState::Ready => route.error.is_none(),
            RouteLoginState::Failed => route.error.is_some(),
        };
        if !state_matches_error {
            return Err(output_invariant_error(
                "aggregate authentication route state does not match its error",
            ));
        }
    }
    let ready_count = outcome
        .routes
        .iter()
        .filter(|route| route.state == RouteLoginState::Ready)
        .count();
    let expected_readiness = match ready_count {
        2 => LoginReadiness::AllReady,
        1 => LoginReadiness::Partial,
        _ => LoginReadiness::NoneReady,
    };
    if outcome.readiness != expected_readiness {
        return Err(output_invariant_error(
            "aggregate authentication readiness does not match route states",
        ));
    }
    if (ready_count > 0) != outcome.profile.is_some() {
        return Err(output_invariant_error(
            "aggregate authentication profile presence does not match route readiness",
        ));
    }
    let requires_failure = ready_count == 0;
    if success == requires_failure {
        return Err(output_invariant_error(
            "aggregate authentication ok flag does not match route states",
        ));
    }
    Ok(())
}

pub(crate) fn readonly<T: Serialize>(
    result: FeatureResult<T>,
    feature: CliFeature,
) -> CoreResult<CommandOutput> {
    let data =
        serde_json::to_value(result.data).map_err(|_| internal_error("无法序列化命令输出"))?;
    Ok(CommandOutput::Readonly {
        data,
        route: result.resolved_route,
        feature,
    })
}

pub(crate) enum CommandOutput {
    Profile(UserProfile),
    Status(AuthStatus),
    Logout(Value),
    Readonly {
        data: Value,
        route: ConnectionMode,
        feature: CliFeature,
    },
}

pub(crate) fn command_output_value(output: CommandOutput) -> CoreResult<Value> {
    match output {
        CommandOutput::Profile(profile) => serde_json::to_value(profile),
        CommandOutput::Status(status) => serde_json::to_value(status),
        CommandOutput::Logout(value) | CommandOutput::Readonly { data: value, .. } => Ok(value),
    }
    .map_err(|_| internal_error("无法序列化命令输出"))
}
