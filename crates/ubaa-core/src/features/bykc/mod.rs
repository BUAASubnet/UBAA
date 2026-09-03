//! 博雅课程领域入口。

mod auth;
mod crypto;
mod parser;
mod read;
mod write;

pub(crate) use crate::internal::route_state::BykcCredential;
#[allow(unused_imports)]
pub(crate) use auth::ensure_login;
#[allow(unused_imports)]
pub(crate) use crypto::{EncryptedRequest, decrypt_response, encrypt_request};
#[allow(unused_imports)]
pub(crate) use parser::{
    parse_chosen_courses, parse_course_detail, parse_courses, parse_profile, parse_statistics,
};
pub(crate) use read::{
    get_chosen_courses, get_course_detail, get_courses, get_profile, get_statistics,
};
pub(crate) use write::{deselect_course, select_course, sign_course};

use crate::error::{ErrorCode, ErrorKind, UbaaError};

fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[cfg(test)]
mod tests;
