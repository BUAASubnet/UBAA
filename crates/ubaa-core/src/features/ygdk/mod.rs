//! 阳光打卡业务边界。
#![allow(clippy::missing_errors_doc)]

mod auth;
mod http;
mod parser;
mod read;
mod upload;
mod write;

pub(crate) use crate::internal::route_state::YgdkCredential;

#[allow(unused_imports)]
pub use parser::{parse_envelope, parse_items, parse_overview, parse_records};
pub(crate) use read::{get_overview, get_records};
pub(crate) use write::submit_clockin;

#[cfg(test)]
mod tests;
