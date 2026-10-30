//! SPOC 当前学期、课程与全局作业分页读取。

use serde::Serialize;
use std::collections::HashMap;

use super::SpocCredential;
use super::auth::{check_business_response, resolve_required_spoc_result, with_spoc_auth_retry};
use super::calendar::normalize_datetime;
use super::crypto::encrypt_param;
use super::parser::{
    AssignmentPage, AssignmentRaw, CourseRaw, CurrentTerm, parse_envelope, summary,
};

/// 当前学期查询地址。
pub const CURRENT_TERM_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
/// 课程列表地址。
pub const COURSES_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb";
/// 加密作业页面地址。
pub const ASSIGNMENTS_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";

const CURRENT_TERM_PARAM: &str =
    "YHrxtTavu6raCwC0/qdgYffB9evWHBkTng/XS4W6j3f/TPo02iEPSoegscDTRNzIPRG49o3RHl4JiFCXAiBkkA==";
const ASSIGNMENTS_PAGE_SQL_ID: &str = "1713252980496efac7d5d9985e81693116d3e8a52ebf2b";

/// 通过已认证路线获取当前 SPOC 学期和作业列表。
pub(crate) async fn get_assignments(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<crate::domain::SpocAssignments> {
    Ok(get_assignments_diagnostics(runtime).await?.result)
}

/// 获取当前 SPOC 列表，并返回全局页面已解析的安全证明。
pub(crate) async fn get_assignments_diagnostics(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<crate::domain::SpocAssignmentsDiagnostics> {
    let term = current_term(runtime).await?;
    let term_code = term.mrxq.unwrap_or_default();
    if term_code.is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC 当前学期缺失",
        ));
    }
    let courses = course_map(runtime, &term_code).await.unwrap_or_default();

    let mut assignments = Vec::new();
    let mut page_num = 1;
    let mut global_page_count = 0u32;
    loop {
        let page_term_code = term_code.clone();
        let page_result = with_spoc_auth_retry(runtime, move |runtime, credential| {
            Box::pin(fetch_assignment_page_as::<AssignmentPage>(
                runtime,
                page_term_code.clone(),
                page_num,
                credential,
            ))
        })
        .await;
        let page = resolve_required_spoc_result(runtime, page_result).await?;
        global_page_count = global_page_count.saturating_add(1);
        let finished = page_finished(&page, page_num);
        assignments.extend(assignment_summaries(page.list, &courses));
        if finished {
            break;
        }
        page_num += 1;
    }
    sort_assignments(&mut assignments);
    Ok(crate::domain::SpocAssignmentsDiagnostics {
        global_page_count,
        result: crate::domain::SpocAssignments {
            term_code,
            term_name: term.dqxq,
            assignments,
        },
    })
}

pub(super) async fn current_term(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<CurrentTerm> {
    let result = with_spoc_auth_retry(runtime, |runtime, credential| {
        Box::pin(fetch_current_term(runtime, credential))
    })
    .await;
    resolve_required_spoc_result(runtime, result).await
}

pub(super) async fn course_map(
    runtime: &mut crate::runtime::ClientRuntime,
    term: &str,
) -> crate::error::Result<HashMap<String, CourseRaw>> {
    let mut url = url::Url::parse(&runtime.url(COURSES_URL)?)
        .map_err(|_| crate::error::UbaaError::upstream_changed("SPOC 地址无效"))?;
    url.query_pairs_mut()
        .append_pair("kcmc", "")
        .append_pair("xnxq", term);
    let url = url.to_string();
    with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_courses(runtime, url.clone(), credential))
    })
    .await
    .map(|courses| {
        courses
            .into_iter()
            .map(|course| (course.kcid.clone(), course))
            .collect()
    })
}

pub(super) fn page_finished(page: &AssignmentPage, number: u32) -> bool {
    !page.has_next_page || number >= page.pages || page.list.is_empty()
}

pub(super) fn assignment_summaries(
    items: Vec<AssignmentRaw>,
    courses: &HashMap<String, CourseRaw>,
) -> impl Iterator<Item = crate::domain::SpocAssignmentSummary> + '_ {
    items.into_iter().map(|item| {
        let course = item.sskcid.as_ref().and_then(|id| courses.get(id));
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
        value
    })
}

pub(super) fn sort_assignments(assignments: &mut [crate::domain::SpocAssignmentSummary]) {
    assignments.sort_by(|left, right| {
        left.due_time
            .as_deref()
            .unwrap_or("9999-99-99 99:99:99")
            .cmp(right.due_time.as_deref().unwrap_or("9999-99-99 99:99:99"))
            .then_with(|| left.course_name.cmp(&right.course_name))
            .then_with(|| left.title.cmp(&right.title))
    });
}

pub(super) async fn fetch_current_term(
    runtime: &mut crate::runtime::ClientRuntime,
    credential: &SpocCredential,
) -> crate::error::Result<CurrentTerm> {
    let term_url = runtime.url(CURRENT_TERM_URL)?;
    let term_body = serde_json::json!({ "param": CURRENT_TERM_PARAM })
        .to_string()
        .into_bytes();
    let response = crate::features::post_json(
        runtime,
        term_url,
        term_body,
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &credential.token_header()),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_envelope(&crate::features::body(&response))
}

pub(super) async fn fetch_courses(
    runtime: &mut crate::runtime::ClientRuntime,
    url: String,
    credential: &SpocCredential,
) -> crate::error::Result<Vec<CourseRaw>> {
    let token_header = credential.token_header();
    let response = crate::features::get_with_headers(
        runtime,
        url,
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_envelope(&crate::features::body(&response))
}

pub(super) async fn fetch_assignment_page_as<T: serde::de::DeserializeOwned>(
    runtime: &mut crate::runtime::ClientRuntime,
    term_code: String,
    page_num: u32,
    credential: &SpocCredential,
) -> crate::error::Result<T> {
    let request = AssignmentPageRequest::new(&term_code, page_num);
    let plain = serde_json::to_string(&request).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::InternalError,
            crate::error::ErrorKind::Internal,
            false,
            "无法序列化已校验的 SPOC 页面请求",
        )
    })?;
    let encrypted = encrypt_param(&plain);
    let token_header = credential.token_header();
    let response = crate::features::post_json(
        runtime,
        runtime.url(ASSIGNMENTS_URL)?,
        serde_json::json!({ "param": encrypted })
            .to_string()
            .into_bytes(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_envelope(&crate::features::body(&response))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct AssignmentPageRequest<'a> {
    page_size: u32,
    page_num: u32,
    sqlid: &'static str,
    xnxq: &'a str,
    kcid: &'static str,
    yzwz: &'static str,
}

impl<'a> AssignmentPageRequest<'a> {
    pub(super) const fn new(term_code: &'a str, page_num: u32) -> Self {
        Self {
            page_size: 15,
            page_num,
            sqlid: ASSIGNMENTS_PAGE_SQL_ID,
            xnxq: term_code,
            kcid: "",
            yzwz: "",
        }
    }
}
