//! UBAA 客户端的平台无关核心。
//!
//! 上游协议细节刻意不属于面向宿主的 API。
//!
//! ```compile_fail
//! use ubaa_core::upstream::SSO_LOGIN_URL;
//! ```

mod auth;
mod config;
mod connection;
pub(crate) mod connection_codec;
pub mod domain;
pub mod error;
pub mod facade;
mod features;
mod internal;
mod ports;
pub(crate) use internal::runtime;
mod session;
mod upstream;

/// 当前 Core 包版本。
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
