//! SPOC 当前学期、课程与全局作业分页读取。

use serde::Serialize;

use super::SpocCredential;
use super::auth::{check_business_response, resolve_required_spoc_result, with_spoc_auth_retry};
use super::calendar::normalize_datetime;
use super::crypto::encrypt_param;
use super::parser::{AssignmentPage, CourseRaw, CurrentTerm, parse_envelope, summary};

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
    let term_result = with_spoc_auth_retry(runtime, |runtime, credential| {
        Box::pin(fetch_current_term(runtime, credential))
    })
    .await;
    let term = resolve_required_spoc_result(runtime, term_result).await?;
    let term_code = term.mrxq.unwrap_or_default();
    if term_code.is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC 当前学期缺失",
        ));
    }
    let mut courses_url = url::Url::parse(&runtime.url(COURSES_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC 地址无效",
        )
    })?;
    courses_url
        .query_pairs_mut()
        .append_pair("kcmc", "")
        .append_pair("xnxq", &term_code);
    let courses_url = courses_url.to_string();
    let courses: Vec<CourseRaw> = with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_courses(runtime, courses_url.clone(), credential))
    })
    .await
    .unwrap_or_default();
    let courses = courses
        .into_iter()
        .map(|course| (course.kcid.clone(), course))
        .collect::<std::collections::HashMap<_, _>>();

    let mut assignments = Vec::new();
    let mut page_num = 1;
    let mut global_page_count = 0u32;
    loop {
        let page_term_code = term_code.clone();
        let page_result = with_spoc_auth_retry(runtime, move |runtime, credential| {
            Box::pin(fetch_assignment_page(
                runtime,
                page_term_code.clone(),
                page_num,
                credential,
            ))
        })
        .await;
        let page = resolve_required_spoc_result(runtime, page_result).await?;
        global_page_count = global_page_count.saturating_add(1);
        let page_empty = page.list.is_empty();
        for item in page.list {
            let course = item.sskcid.as_ref().and_then(|id| courses.get(id));
            let mut item_summary = summary(
                item.zyid,
                item.sskcid.unwrap_or_default(),
                item.kcmc
                    .or_else(|| course.map(|course| course.kcmc.clone()))
                    .unwrap_or_default(),
                item.zymc,
                item.tjzt.as_deref(),
                item.mf.as_deref(),
            );
            item_summary.teacher_name = course.and_then(|course| course.skjs.clone());
            item_summary.start_time = normalize_datetime(item.zykssj.as_deref());
            item_summary.due_time = normalize_datetime(item.zyjzsj.as_deref());
            assignments.push(item_summary);
        }
        if !page.has_next_page || page_num >= page.pages || page_empty {
            break;
        }
        page_num += 1;
    }
    assignments.sort_by(|left, right| {
        left.due_time
            .as_deref()
            .unwrap_or("9999-99-99 99:99:99")
            .cmp(right.due_time.as_deref().unwrap_or("9999-99-99 99:99:99"))
            .then_with(|| left.course_name.cmp(&right.course_name))
            .then_with(|| left.title.cmp(&right.title))
    });
    Ok(crate::domain::SpocAssignmentsDiagnostics {
        global_page_count,
        result: crate::domain::SpocAssignments {
            term_code,
            term_name: term.dqxq,
            assignments,
        },
    })
}

async fn fetch_current_term(
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

async fn fetch_courses(
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

async fn fetch_assignment_page(
    runtime: &mut crate::runtime::ClientRuntime,
    term_code: String,
    page_num: u32,
    credential: &SpocCredential,
) -> crate::error::Result<AssignmentPage> {
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
