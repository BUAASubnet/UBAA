//! 阳光打卡业务边界。
#![allow(clippy::missing_errors_doc)]

mod auth;
mod http;
mod parser;
mod read;
mod upload;
mod write;

use crate::error::UbaaError;
pub(crate) use crate::internal::route_state::YgdkCredential;

#[allow(unused_imports)]
pub use parser::{parse_envelope, parse_items, parse_overview, parse_records};
pub(crate) use read::{
    YgdkOverviewContext, get_overview, get_overview_context, get_overview_observed, get_records,
    get_records_in_context,
};
pub(crate) use write::{preflight_submit, submit_clockin, validate_submit_request};

const WRITE_OUTCOME_MESSAGE: &str = "阳光打卡提交结果未知，请刷新概览和记录后核对";

#[track_caller]
fn write_outcome_unknown() -> UbaaError {
    UbaaError::outcome_unknown(WRITE_OUTCOME_MESSAGE)
}

#[cfg(test)]
mod tests;
