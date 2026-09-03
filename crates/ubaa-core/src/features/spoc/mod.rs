//! SPOC 认证、作业列表与详情的领域边界。
#![allow(clippy::missing_errors_doc, clippy::missing_panics_doc)]

mod auth;
mod calendar;
mod crypto;
mod detail;
mod list;
mod parser;

#[allow(unused_imports)]
pub use auth::{CAS_LOGIN_URL, CAS_URL};
#[allow(unused_imports)]
pub use detail::{ASSIGNMENT_DETAIL_URL, SUBMISSION_URL};
#[allow(unused_imports)]
pub use list::{ASSIGNMENTS_URL, COURSES_URL, CURRENT_TERM_URL};
#[allow(unused_imports)]
pub use parser::{
    Envelope, detail, map_submission_status, normalize_score, parse_envelope, summary,
    to_plain_text,
};

pub(super) use crate::internal::route_state::SpocCredential;
pub(crate) use detail::get_assignment_detail;
pub(crate) use list::{get_assignments, get_assignments_diagnostics};

#[cfg(test)]
mod tests;
