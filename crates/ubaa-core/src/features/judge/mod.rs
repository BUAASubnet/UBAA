//! Judge（希冀）课程、作业、详情与批量读取。
#![allow(
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::must_use_candidate
)]

mod batch;
mod calendar;
mod parser;
mod service;

#[cfg(test)]
mod tests;

#[allow(unused_imports)]
pub use crate::domain::{Assignment, Course};
pub(crate) use crate::internal::route_state::AssignmentList;

pub(crate) use batch::{
    get_assignment_detail, get_assignment_details, get_assignments, get_assignments_diagnostics,
};
#[allow(unused_imports)]
pub use parser::{parse_courses, parse_detail, to_summary};
#[allow(unused_imports)]
pub use service::{BASE_URL, LOGIN_URL};
