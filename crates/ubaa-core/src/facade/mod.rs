//! CLI 与未来绑定层使用的稳定 facade。
mod auth;
mod client;
mod diagnostic;
mod read;
mod routing;
mod types;
mod write;

pub use client::UbaaClient;
pub use diagnostic::RouteClient;
pub use types::{Routed, RoutedError, RoutedResult};

// 这些类型是宿主可见的安全路线诊断投影；其余 connection 实现仍属于 Core 内部。
pub use crate::connection::{NetworkState, RouteDiagnostic, RouteResolution};
