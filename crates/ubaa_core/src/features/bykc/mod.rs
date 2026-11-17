//! 博雅课程领域入口。

mod auth;
mod catalog;
mod crypto;
mod parser;
mod read;
mod write;

pub(crate) use crate::internal::route_state::BykcCredential;
#[allow(unused_imports)]
pub(crate) use auth::ensure_login;
#[allow(unused_imports)]
pub(crate) use crypto::{EncryptedRequest, decrypt_response, encrypt_request};
pub(crate) use read::{
    get_chosen_courses, get_chosen_courses_observed, get_course_catalog, get_course_detail,
    get_course_full_detail, get_courses, get_profile, get_statistics,
};
pub(crate) use write::{deselect_course, preflight_sign_course, select_course, sign_course};

use crate::error::UbaaError;

/// 博雅上游时间是不带时区的北京时间；资格判定不依赖设备时区。
fn campus_now() -> chrono::NaiveDateTime {
    crate::time::shanghai_datetime(std::time::SystemTime::now())
}

#[track_caller]
fn error(message: &str) -> UbaaError {
    UbaaError::upstream_changed(message).with_diagnostic("parse", "response_shape_invalid")
}

#[cfg(test)]
mod tests;
