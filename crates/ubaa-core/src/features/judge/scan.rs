//! 每批保留完整选课上下文，仅在请求收尾后向宿主让位。
use crate::{
    domain::{Assignment, Course, JudgeAssignmentDetail},
    error::{ErrorCode, Result},
    runtime::ClientRuntime,
};

pub(crate) struct ScanRead<T> {
    pub(crate) result: Result<T>,
    pub(crate) fatal: bool,
}
async fn finish<T>(runtime: &mut ClientRuntime, result: Result<T>) -> ScanRead<T> {
    let fatal = result.as_ref().is_err_and(|error| {
        matches!(
            error.code,
            ErrorCode::AuthenticationRequired | ErrorCode::InternalError
        )
    });
    let result = super::batch::resolve_required_judge_result(runtime, result).await;
    ScanRead {
        fatal: fatal
            || result
                .as_ref()
                .is_err_and(|error| error.code == ErrorCode::InternalError),
        result,
    }
}
pub(crate) async fn courses(
    runtime: &mut ClientRuntime,
    activated: &mut bool,
    force_fresh: bool,
) -> ScanRead<Vec<Course>> {
    let state = runtime.feature_state();
    let result = super::service::get_courses_cached(
        runtime,
        &state,
        state.judge.generation(),
        activated,
        force_fresh,
    )
    .await;
    finish(runtime, result).await
}
pub(crate) async fn assignments(
    runtime: &mut ClientRuntime,
    course: &Course,
    activated: &mut bool,
    force_fresh: bool,
) -> ScanRead<Vec<Assignment>> {
    let state = runtime.feature_state();
    let result = super::service::get_course_assignments_cached(
        runtime,
        &state,
        state.judge.generation(),
        course,
        activated,
        force_fresh,
    )
    .await
    .map(|list| list.assignments);
    finish(runtime, result).await
}
pub(crate) async fn detail(
    runtime: &mut ClientRuntime,
    assignment: &Assignment,
    activated: &mut bool,
    force_fresh: bool,
) -> ScanRead<JudgeAssignmentDetail> {
    let state = runtime.feature_state();
    let result = super::service::get_detail_cached(
        runtime,
        &state,
        state.judge.generation(),
        assignment,
        activated,
        force_fresh,
    )
    .await;
    finish(runtime, result).await
}
