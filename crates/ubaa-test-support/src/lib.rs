//! 工作区各 crate 共享的脱敏夹具与确定性 HTTP 支持。

mod fixtures;
mod http;
mod session;

pub use fixtures::{assert_fixture_is_sanitized, auth_fixture, readonly_fixture};
pub use http::{ExpectedRequest, MockTransport};
pub use session::MemorySessionStore;
