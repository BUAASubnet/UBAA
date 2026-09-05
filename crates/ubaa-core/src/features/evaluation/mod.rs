//! SPOC 教学评教的 fresh typed 读取与批量提交边界。
#![allow(clippy::missing_errors_doc)]

mod parser;
mod payload;
mod read;
mod write;

use crate::error::{ErrorCode, ErrorKind, UbaaError};

#[cfg(test)]
pub use parser::parse_courses;
pub(crate) use read::get_all;
pub(crate) use write::{preflight_submit_courses, submit_courses, validate_submit_courses_request};

pub(super) const CAS_URL: &str = "https://spoc.buaa.edu.cn/pjxt/cas";
pub(super) const TASKS_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks";
pub(super) const QUESTIONNAIRES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireListToTask";
pub(super) const COURSES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData";
pub(super) const REVISE_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/reviseQuestionnairePattern";
pub(super) const TOPIC_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireTopic";
pub(super) const SUBMIT_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/submitSaveEvaluation";

pub(super) fn upstream_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

pub(super) fn authority_error() -> UbaaError {
    upstream_error("评教提交资格核对响应无效")
}

pub(super) fn invalid_input(message: &'static str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

pub(super) fn is_authentication_error(error: &UbaaError) -> bool {
    matches!(
        error.code,
        ErrorCode::AuthenticationRequired
            | ErrorCode::InvalidCredentials
            | ErrorCode::PermissionDenied
    )
}

#[cfg(test)]
mod tests;
