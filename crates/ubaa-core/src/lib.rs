//! Platform-independent core for UBAA clients.

pub mod connection;
pub mod domain;
pub mod error;
pub mod output;
pub mod ports;
pub mod session;

/// Current core package version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
