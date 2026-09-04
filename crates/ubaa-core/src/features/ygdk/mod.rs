//! 阳光打卡业务边界。
#![allow(clippy::missing_errors_doc)]

mod auth;
mod http;
mod parser;
mod read;
mod upload;
mod write;

use crate::error::{ErrorCode, ErrorKind, UbaaError};
pub(crate) use crate::internal::route_state::YgdkCredential;

#[allow(unused_imports)]
pub use parser::{parse_envelope, parse_items, parse_overview, parse_records};
pub(crate) use read::{get_overview, get_records};
pub(crate) use write::{preflight_submit, submit_clockin, validate_submit_request};

fn write_outcome_unknown() -> UbaaError {
    UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        "阳光打卡提交结果未知，请刷新概览和记录后核对",
    )
}

#[cfg(test)]
mod tests;
