//! Platform-independent core for UBAA clients.
//!
//! Upstream protocol details are intentionally not part of the host-facing API.
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

/// Current core package version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
