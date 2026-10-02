//! 当前冻结GSMIS网络协议和校历转换，不使用历史选课系统网络地址。
mod parser;
mod projection;
#[cfg(test)]
mod tests;
mod transport;
use crate::domain::{CourseClass, SectionTime, Term};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;
use chrono::NaiveDate;
#[cfg(test)]
pub(super) use parser::parse_terms;

pub(super) struct GraduateSchedule {
    terms: Vec<Term>,
    term: String,
    rows: Vec<Row>,
    sections: Vec<SectionTime>,
    monday: Option<NaiveDate>,
}
struct Row {
    course: CourseClass,
    mask: String,
    scheme: Option<String>,
    teachers: Option<String>,
}
fn error() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "研究生课表字段或校历无法一致核对",
    )
}
pub(super) fn active(runtime: &ClientRuntime) -> bool {
    let state = runtime.feature_state();
    state
        .graduate_schedule
        .load(std::sync::atomic::Ordering::Acquire)
        == state.lifecycle_generation().saturating_add(1)
}
pub(super) async fn fetch(
    runtime: &mut ClientRuntime,
    term: Option<&str>,
) -> Result<GraduateSchedule> {
    runtime.ensure_session_revision()?;
    let owner = runtime.feature_state();
    let generation = owner.lifecycle_generation();
    let result = transport::fetch(runtime, term).await?;
    runtime.ensure_session_revision()?;
    // 存储观察到的代次，clear之后的旧请求不能让新会话跳过本科分支。
    if owner.lifecycle_generation() == generation {
        owner.graduate_schedule.store(
            generation.saturating_add(1),
            std::sync::atomic::Ordering::Release,
        );
    }
    Ok(result)
}

#[cfg(all(test, feature = "test-contract"))]
mod network_tests;
