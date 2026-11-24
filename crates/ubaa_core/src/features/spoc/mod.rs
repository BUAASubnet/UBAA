//! SPOC 认证、作业列表与详情的领域边界。
#![allow(clippy::missing_errors_doc, clippy::missing_panics_doc)]

mod auth;
mod calendar;
pub(crate) mod course_files;
mod crypto;
mod detail;
pub(crate) mod files;
mod list;
mod parser;
pub(crate) mod scan;
pub(crate) mod submit;

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
pub(crate) use detail::{get_assignment_detail, get_assignment_detail_for_base};
pub(crate) use list::{get_assignments, get_assignments_diagnostics};

#[cfg(test)]
mod tests;
