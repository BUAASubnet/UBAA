//! 会话持久化快照和比较交换类型。

use std::ops::Deref;

use serde::{Deserialize, Serialize};

use crate::domain::ConnectionMode;

use super::StoredCookie;

/// 可跨 CLI 进程持久化的会话快照。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct SessionSnapshot {
    /// 此会话使用的连接策略。
    pub mode: ConnectionMode,
    /// 过滤后的上游 Cookie。
    pub cookies: Vec<StoredCookie>,
    /// 认证成功时的 Unix 时间戳。
    pub authenticated_at: i64,
    /// 最近一次成功校验的 Unix 时间戳。
    pub last_activity: i64,
}

/// schema-v2 会话文件中的一个持久化路线槽位。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteSessionSnapshot {
    /// 作用域限定在此路线的过滤后上游 Cookie。
    pub cookies: Vec<StoredCookie>,
    /// 认证成功时的 Unix 时间戳。
    pub authenticated_at: i64,
    /// 最近一次成功校验的 Unix 时间戳。
    pub last_activity: i64,
}

impl RouteSessionSnapshot {
    /// 转换已有旧版快照，不修改或复制其中的 Cookie。
    #[must_use]
    pub fn from_legacy(snapshot: &SessionSnapshot) -> Self {
        Self {
            cookies: snapshot.cookies.clone(),
            authenticated_at: snapshot.authenticated_at,
            last_activity: snapshot.last_activity,
        }
    }

    /// 将此槽位转换为旧版路线范围运行时值。
    #[must_use]
    pub fn into_legacy(self, mode: ConnectionMode) -> SessionSnapshot {
        SessionSnapshot {
            mode,
            cookies: self.cookies,
            authenticated_at: self.authenticated_at,
            last_activity: self.last_activity,
        }
    }
}

/// 在 schema 版本 2 中原子持久化的 Direct 与 `WebVPN` 槽位。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DualSessionSnapshot {
    /// 架构判别字段。
    pub schema_version: u32,
    /// 按路线隔离的会话。
    pub sessions: RouteSessions,
}

/// 双路线快照及用于比较交换的版本号。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VersionedDualSession {
    /// 当前 schema-v2 快照（如果存在）。
    pub snapshot: Option<DualSessionSnapshot>,
    /// 与快照使用同一把锁保护的单调版本号。
    pub revision: u64,
}

/// schema-v2 会话文件中的路线槽位。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct RouteSessions {
    /// Direct 路线会话。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub direct: Option<RouteSessionSnapshot>,
    /// `WebVPN` 路线会话。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub webvpn: Option<RouteSessionSnapshot>,
}

impl DualSessionSnapshot {
    /// 构造 schema-v2 快照。
    #[must_use]
    pub const fn new(
        direct: Option<RouteSessionSnapshot>,
        webvpn: Option<RouteSessionSnapshot>,
    ) -> Self {
        Self {
            schema_version: 2,
            sessions: RouteSessions { direct, webvpn },
        }
    }

    /// Direct 路线槽位。
    #[must_use]
    pub fn direct(&self) -> Option<&RouteSessionSnapshot> {
        self.sessions.direct.as_ref()
    }

    /// `WebVPN` 路线槽位。
    #[must_use]
    pub fn webvpn(&self) -> Option<&RouteSessionSnapshot> {
        self.sessions.webvpn.as_ref()
    }
}

impl Deref for DualSessionSnapshot {
    type Target = RouteSessions;

    fn deref(&self) -> &Self::Target {
        &self.sessions
    }
}

impl std::fmt::Debug for SessionSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SessionSnapshot")
            .field("mode", &self.mode)
            .field("cookie_count", &self.cookies.len())
            .field("authenticated_at", &self.authenticated_at)
            .field("last_activity", &self.last_activity)
            .finish()
    }
}

/// 校验持久化会话的结果。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionValidation {
    /// 上游确认会话有效。
    Valid,
    /// 上游明确拒绝会话或将其重定向。
    Invalid,
    /// 上游返回临时服务器错误。
    ServerError,
    /// 请求超时，尚未得出结论。
    Timeout,
}

impl SessionValidation {
    /// 是否必须清理本地认证状态。
    #[must_use]
    pub const fn should_clear(self) -> bool {
        matches!(self, Self::Invalid)
    }
}

/// 原子加载的持久化快照及其变更版本号。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VersionedSession {
    /// 持久化会话（如果存在）。
    pub snapshot: Option<SessionSnapshot>,
    /// 用于拒绝过期写入方的本地单调修订。
    pub revision: u64,
}

/// 会话变更比较交换的结果。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionMutation {
    /// 变更已应用，并产生此版本号。
    Applied { revision: u64 },
    /// 调用方加载后，另一个进程修改了会话。
    Conflict,
}

/// schema-v2 双路线会话比较交换的结果。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DualSessionMutation {
    /// 变更已应用，版本号已前进。
    Applied { revision: u64 },
    /// 另一进程修改了某个路线槽位。
    Conflict,
}
