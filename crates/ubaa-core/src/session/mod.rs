//! Cookie 容器与受限的磁盘会话持久化。

mod cookies;
mod coordinator;
mod file_safety;
mod file_store;
mod ports;
mod storage;
mod types;

pub use cookies::{CookieJar, StoredCookie};
pub(crate) use coordinator::DualSessionCoordinator;
pub use file_store::FileSessionStore;
pub use ports::SessionStore;
#[cfg(feature = "test-contract")]
pub use types::{
    DualSessionMutation, DualSessionSnapshot, RouteSessionSnapshot, RouteSessions,
    VersionedDualSession,
};
pub use types::{SessionMutation, SessionSnapshot, VersionedSession};
