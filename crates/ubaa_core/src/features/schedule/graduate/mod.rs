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
pub(super) async fn fetch(
    runtime: &mut ClientRuntime,
    term: Option<&str>,
) -> Result<GraduateSchedule> {
    transport::fetch(runtime, term).await
}

#[cfg(all(test, feature = "test-contract"))]
mod network_tests;
