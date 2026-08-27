//! UBAA 客户端的平台无关核心。
//!
//! 上游协议细节刻意不属于面向宿主的 API。
//!
//! ```compile_fail
//! use ubaa_core::upstream::SSO_LOGIN_URL;
//! ```

pub mod auth;
pub mod config;
pub mod connection;
pub mod domain;
pub mod error;
pub mod facade;
pub mod features;
pub mod output;
pub mod ports;
mod runtime;
pub mod session;
mod upstream;

/// 当前 Core 包版本。
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
