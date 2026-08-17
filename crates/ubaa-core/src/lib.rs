//! Platform-independent core for UBAA clients.

pub mod auth;
pub mod connection;
pub mod domain;
pub mod error;
pub mod facade;
pub mod features;
pub mod output;
pub mod ports;
pub mod session;
pub mod upstream;

/// Current core package version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
