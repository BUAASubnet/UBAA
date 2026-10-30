//! 分段只读复用原认证与请求编码，每次完整完成重试/主会话仲裁后才返回。
use super::{
    auth::{resolve_required_spoc_result, with_spoc_auth_retry},
    list::{
        assignment_summaries, course_map, current_term, fetch_assignment_page_as, page_finished,
        sort_assignments,
    },
    parser::{AssignmentPage, CourseRaw},
};
use crate::{
    domain::SpocAssignments,
    error::{ErrorCode, ErrorKind, Result, UbaaError},
    runtime::ClientRuntime,
};
use std::collections::HashMap;

#[derive(Default)]
pub(crate) struct Courses(HashMap<String, CourseRaw>);
pub(crate) struct Page {
    pub data: SpocAssignments,
    pub complete: bool,
    pub finished: bool,
    pub has_next: Option<bool>,
    pub pages: Option<u32>,
}
pub(crate) async fn term(runtime: &mut ClientRuntime) -> Result<SpocAssignments> {
    let term = current_term(runtime).await?;
    let code = term
        .mrxq
        .filter(|value| !value.trim().is_empty() && value.len() <= 1024)
        .ok_or_else(changed)?;
    Ok(SpocAssignments {
        term_code: code,
        term_name: term.dqxq,
        assignments: Vec::new(),
    })
}
pub(crate) async fn courses(runtime: &mut ClientRuntime, term: &str) -> Result<Courses> {
    let result = course_map(runtime, term).await;
    resolve_required_spoc_result(runtime, result)
        .await
        .map(Courses)
}

pub(crate) async fn page(
    runtime: &mut ClientRuntime,
    term: &SpocAssignments,
    page: u32,
    courses: &Courses,
) -> Result<Page> {
    let code = term.term_code.clone();
    let result = with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_assignment_page_as::<serde_json::Value>(
            runtime,
            code.clone(),
            page,
            credential,
        ))
    })
    .await;
    let raw = resolve_required_spoc_result(runtime, result).await?;
    // 缺失回显与明确错配不同：前者不完整，后者不可放进请求范围。
    for (name, expected) in [("pageNum", page), ("pageSize", 15)] {
        if raw
            .get(name)
            .is_some_and(|value| value.as_u64() != Some(u64::from(expected)))
        {
            return Err(changed());
        }
    }
    let observed = raw.get("pageNum").is_some()
        && raw.get("pageSize").is_some()
        && raw
            .get("pages")
            .and_then(serde_json::Value::as_u64)
            .is_some()
        && raw
            .get("hasNextPage")
            .and_then(serde_json::Value::as_bool)
            .is_some()
        && raw.get("list").is_some_and(serde_json::Value::is_array);
    let has_next = raw.get("hasNextPage").and_then(serde_json::Value::as_bool);
    let pages = raw
        .get("pages")
        .and_then(serde_json::Value::as_u64)
        .and_then(|value| u32::try_from(value).ok());
    let data: AssignmentPage = serde_json::from_value(raw).map_err(|_| changed())?;
    if data.list.iter().any(|item| {
        item.zyid.trim().is_empty()
            || item
                .xnxq
                .as_ref()
                .is_some_and(|code| code != &term.term_code)
    }) {
        return Err(changed());
    }
    let empty = data.list.is_empty();
    let finished = page_finished(&data, page);
    let complete = observed
        && (data.has_next_page || data.pages == page || (page == 1 && empty && data.pages == 0))
        && !(finished && data.has_next_page)
        && (data.pages >= page || (page == 1 && empty && data.pages == 0))
        && !(empty && page > 1);
    let result = SpocAssignments {
        assignments: assignment_summaries(data.list, &courses.0).collect(),
        ..term.clone()
    };
    Ok(Page {
        data: result,
        complete,
        finished,
        has_next,
        pages,
    })
}
pub(crate) fn sort(data: &mut SpocAssignments) {
    sort_assignments(&mut data.assignments);
}

fn changed() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "SPOC 学期或分页范围无法确认",
    )
}
