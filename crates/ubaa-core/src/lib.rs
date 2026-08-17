//! Platform-independent core for UBAA clients.

pub mod domain;
pub mod error;
pub mod output;
pub mod ports;

/// Current core package version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
