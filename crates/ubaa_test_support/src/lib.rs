//! 工作区各 crate 共享的脱敏夹具与确定性 HTTP 支持。

mod fixtures;
mod http;
mod session;

pub use fixtures::{assert_fixture_is_sanitized, auth_fixture, readonly_fixture};
pub use http::{ExpectedRequest, MockTransport};
pub use session::MemorySessionStore;
pub use ubaa_core::facade::testing::{
    DualSessionMutation, DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpMethod,
    HttpRequest, HttpResponse, HttpTransport, RouteConfig, RouteSessionSnapshot, RouteSessions,
    SessionMutation, SessionSnapshot, SessionStore, StoredCookie, VersionedDualSession,
    VersionedSession, from_webvpn_url, to_webvpn_url,
};
pub use ubaa_core::facade::{ConnectionMode, ErrorCode, ErrorKind, Result, UbaaError};
