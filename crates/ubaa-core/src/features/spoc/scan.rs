//! 分段只读复用原认证与请求编码，每次完整完成重试/主会话仲裁后才返回。
use super::{
    auth::{resolve_required_spoc_result, with_spoc_auth_retry},
    calendar::normalize_datetime,
    list::{COURSES_URL, fetch_assignment_page_as, fetch_courses, fetch_current_term},
    parser::{AssignmentPage, CourseRaw, summary},
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
    let result = with_spoc_auth_retry(runtime, |runtime, credential| {
        Box::pin(fetch_current_term(runtime, credential))
    })
    .await;
    let term = resolve_required_spoc_result(runtime, result).await?;
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
    let mut url = url::Url::parse(&runtime.url(COURSES_URL)?).map_err(|_| changed())?;
    url.query_pairs_mut()
        .append_pair("kcmc", "")
        .append_pair("xnxq", term);
    let url = url.to_string();
    let result = with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_courses(runtime, url.clone(), credential))
    })
    .await;
    resolve_required_spoc_result(runtime, result)
        .await
        .map(|rows| {
            Courses(
                rows.into_iter()
                    .map(|row| (row.kcid.clone(), row))
                    .collect(),
            )
        })
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
    let finished = !data.has_next_page || page >= data.pages || empty;
    let complete = observed
        && (data.has_next_page || data.pages == page || (page == 1 && empty && data.pages == 0))
        && !(finished && data.has_next_page)
        && (data.pages >= page || (page == 1 && empty && data.pages == 0))
        && !(empty && page > 1);
    let mut result = SpocAssignments {
        assignments: Vec::new(),
        ..term.clone()
    };
    for item in data.list {
        let course = item.sskcid.as_ref().and_then(|id| courses.0.get(id));
        let mut value = summary(
            item.zyid,
            item.sskcid.unwrap_or_default(),
            item.kcmc
                .or_else(|| course.map(|course| course.kcmc.clone()))
                .unwrap_or_default(),
            item.zymc,
            item.tjzt.as_deref(),
            item.mf.as_deref(),
        );
        value.teacher_name = course.and_then(|course| course.skjs.clone());
        value.start_time = normalize_datetime(item.zykssj.as_deref());
        value.due_time = normalize_datetime(item.zyjzsj.as_deref());
        result.assignments.push(value);
    }
    Ok(Page {
        data: result,
        complete,
        finished,
        has_next,
        pages,
    })
}
pub(crate) fn sort(data: &mut SpocAssignments) {
    data.assignments.sort_by(|left, right| {
        left.due_time
            .as_deref()
            .unwrap_or("9999-99-99 99:99:99")
            .cmp(right.due_time.as_deref().unwrap_or("9999-99-99 99:99:99"))
            .then_with(|| left.course_name.cmp(&right.course_name))
            .then_with(|| left.title.cmp(&right.title))
    });
}
fn changed() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "SPOC 学期或分页范围无法确认",
    )
}
