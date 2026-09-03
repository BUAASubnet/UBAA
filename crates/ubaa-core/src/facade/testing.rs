//! 仅供 workspace 测试支持使用的最小注入合同。

pub use crate::config::RouteConfig;
pub use crate::connection::{GatewayProbe, from_webvpn_url, to_webvpn_url};
pub use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
pub use crate::session::{
    DualSessionMutation, DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot,
    RouteSessions, SessionMutation, SessionSnapshot, SessionStore, StoredCookie,
    VersionedDualSession, VersionedSession,
};
