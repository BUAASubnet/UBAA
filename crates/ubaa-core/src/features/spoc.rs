//! SPOC read-only parsing helpers and verified endpoint constants.
#![allow(
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::too_many_lines
)]

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use base64::Engine as _;
use serde::Deserialize;
use serde_json::Value;

use crate::domain::{SpocAssignmentDetail, SpocAssignmentSummary, SpocSubmissionStatus};

/// Current-term query endpoint.
pub const CURRENT_TERM_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne";
/// No-follow CAS token bootstrap endpoint.
pub const CAS_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/cas";
/// CAS role/token activation endpoint.
pub const CAS_LOGIN_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/sys/casLogin";
/// Course list endpoint.
pub const COURSES_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb";
/// Encrypted assignment page endpoint.
pub const ASSIGNMENTS_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage";
/// Assignment detail endpoint.
pub const ASSIGNMENT_DETAIL_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid";
/// Submission status endpoint used for read-only detail enrichment.
pub const SUBMISSION_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo";

/// Map verified SPOC status values without inventing a new state.
#[must_use]
pub fn map_submission_status(raw_status: Option<&str>, has_content: bool) -> SpocSubmissionStatus {
    match raw_status.map(str::trim) {
        Some("1" | "已做" | "已提交") => SpocSubmissionStatus::Submitted,
        Some("0" | "未做" | "未提交") => SpocSubmissionStatus::Unsubmitted,
        _ if !has_content => SpocSubmissionStatus::Unsubmitted,
        _ => SpocSubmissionStatus::Unknown,
    }
}

/// Convert known HTML markup to a safe plain-text description.
#[must_use]
pub fn to_plain_text(html: &str) -> Option<String> {
    let text = regex::Regex::new(r"(?is)<br\s*/?>|<[^>]+>")
        .expect("static HTML regex")
        .replace_all(html, " ")
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    (!text.is_empty()).then_some(text)
}

/// Normalize score text to the first numeric value, as in the frozen parser.
#[must_use]
pub fn normalize_score(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    regex::Regex::new(r"-?\d+(?:\.\d+)?")
        .expect("static score regex")
        .find(raw)
        .map(|value| value.as_str().to_string())
}

/// Response envelope used by deterministic fixtures.
#[derive(Debug, Deserialize)]
pub struct Envelope<T> {
    /// Upstream status code.
    pub code: i64,
    /// Optional message.
    pub msg: Option<String>,
    /// Payload.
    pub content: Option<T>,
}

/// Decode one SPOC envelope without exposing raw body text.
pub fn parse_envelope<T: for<'de> Deserialize<'de>>(body: &str) -> crate::error::Result<T> {
    let envelope: Envelope<T> = serde_json::from_str(body).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::ParseError,
            crate::error::ErrorKind::Parse,
            false,
            "SPOC response is not valid JSON",
        )
    })?;
    if envelope.code != 0 && envelope.code != 200 {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC response returned a nonzero code",
        ));
    }
    envelope.content.ok_or_else(|| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC response is missing content",
        )
    })
}

/// Build a stable summary from observed raw fields.
#[must_use]
pub fn summary(
    assignment_id: String,
    course_id: String,
    course_name: String,
    title: String,
    raw_status: Option<&str>,
    score: Option<&str>,
) -> SpocAssignmentSummary {
    let status = map_submission_status(raw_status, raw_status.is_some());
    SpocAssignmentSummary {
        assignment_id,
        course_id,
        course_name,
        teacher_name: None,
        title,
        start_time: None,
        due_time: None,
        score: normalize_score(score),
        submission_status: status,
        submission_status_text: match status {
            SpocSubmissionStatus::Submitted => "已提交".into(),
            SpocSubmissionStatus::Unsubmitted => "未提交".into(),
            SpocSubmissionStatus::Unknown => "未知状态".into(),
        },
    }
}

/// Build detail from a summary and verified HTML content.
#[must_use]
pub fn detail(summary: &SpocAssignmentSummary, html: Option<String>) -> SpocAssignmentDetail {
    SpocAssignmentDetail {
        assignment_id: summary.assignment_id.clone(),
        course_id: summary.course_id.clone(),
        course_name: summary.course_name.clone(),
        teacher_name: summary.teacher_name.clone(),
        title: summary.title.clone(),
        start_time: summary.start_time.clone(),
        due_time: summary.due_time.clone(),
        score: summary.score.clone(),
        submission_status: summary.submission_status,
        submission_status_text: summary.submission_status_text.clone(),
        content_plain_text: html.as_deref().and_then(to_plain_text),
        content_html: html,
        submitted_at: None,
    }
}

/// Fetch the current SPOC term and assignment list through the authenticated route.
pub(crate) async fn get_assignments(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<crate::domain::SpocAssignments> {
    let (token, role) = login(runtime).await?;
    let term_url = runtime.url(CURRENT_TERM_URL)?;
    let term_body = serde_json::json!({ "param": CURRENT_TERM_PARAM })
        .to_string()
        .into_bytes();
    let term_response = super::post_json(
        runtime,
        term_url,
        term_body,
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &format!("Inco-{token}")),
            ("RoleCode", &role),
        ],
    )
    .await?;
    super::check_response(&term_response, "spoc")?;
    let term: CurrentTerm = parse_envelope(&super::body(&term_response))?;
    let term_code = term.mrxq.unwrap_or_default();
    if term_code.is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC current term is missing",
        ));
    }
    let mut url = url::Url::parse(&runtime.url(COURSES_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC URL is invalid",
        )
    })?;
    url.query_pairs_mut()
        .append_pair("kcmc", "")
        .append_pair("xnxq", &term_code);
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &format!("Inco-{token}")),
            ("RoleCode", &role),
        ],
    )
    .await?;
    super::check_response(&response, "spoc")?;
    let courses: Vec<CourseRaw> = parse_envelope(&super::body(&response))?;
    let mut assignments = Vec::new();
    for course in courses {
        let course_name = course.kcmc;
        let teacher_name = course.skjs;
        let mut page_num = 1;
        loop {
            let plain = serde_json::json!({
                "pageSize": 15,
                "pageNum": page_num,
                "sqlid": ASSIGNMENTS_PAGE_SQL_ID,
                "xnxq": term_code,
                "kcid": course.kcid,
                "yzwz": ""
            });
            let encrypted = encrypt_param(&plain.to_string());
            let token_header = format!("Inco-{token}");
            let page_response = super::post_json(
                runtime,
                runtime.url(ASSIGNMENTS_URL)?,
                serde_json::json!({ "param": encrypted })
                    .to_string()
                    .into_bytes(),
                &[
                    ("X-Requested-With", "XMLHttpRequest"),
                    ("Token", &token_header),
                    ("RoleCode", &role),
                ],
            )
            .await?;
            super::check_response(&page_response, "spoc")?;
            let page: AssignmentPage = parse_envelope(&super::body(&page_response))?;
            let page_empty = page.list.is_empty();
            for item in page.list {
                let mut item_summary = summary(
                    item.zyid,
                    item.sskcid.unwrap_or_default(),
                    item.kcmc.unwrap_or_else(|| course_name.clone()),
                    item.zymc,
                    item.tjzt.as_deref(),
                    item.mf.as_deref(),
                );
                item_summary.teacher_name.clone_from(&teacher_name);
                item_summary.start_time = normalize_datetime(item.zykssj.as_deref());
                item_summary.due_time = normalize_datetime(item.zyjzsj.as_deref());
                assignments.push(item_summary);
            }
            if !page.has_next_page || page_num >= page.pages || page_empty {
                break;
            }
            page_num += 1;
        }
    }
    assignments.sort_by(|left, right| {
        left.due_time
            .as_deref()
            .unwrap_or("9999-99-99 99:99:99")
            .cmp(right.due_time.as_deref().unwrap_or("9999-99-99 99:99:99"))
            .then_with(|| left.course_name.cmp(&right.course_name))
            .then_with(|| left.title.cmp(&right.title))
    });
    Ok(crate::domain::SpocAssignments {
        term_code,
        term_name: term.dqxq,
        assignments,
    })
}

/// Fetch one read-only SPOC assignment detail.
pub(crate) async fn get_assignment_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: &str,
) -> crate::error::Result<crate::domain::SpocAssignmentDetail> {
    if assignment_id.trim().is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::InvalidInput,
            crate::error::ErrorKind::Input,
            false,
            "assignment id is required",
        ));
    }
    let assignments = get_assignments(runtime).await?;
    let base = assignments
        .assignments
        .into_iter()
        .find(|assignment| assignment.assignment_id == assignment_id)
        .ok_or_else(|| {
            crate::error::UbaaError::new(
                crate::error::ErrorCode::UpstreamChanged,
                crate::error::ErrorKind::Upstream,
                false,
                "SPOC assignment was not found",
            )
        })?;
    let (token, role) = login(runtime).await?;
    let mut url = url::Url::parse(&runtime.url(ASSIGNMENT_DETAIL_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC URL is invalid",
        )
    })?;
    url.query_pairs_mut().append_pair("id", assignment_id);
    let token_header = format!("Inco-{token}");
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &role),
        ],
    )
    .await?;
    super::check_response(&response, "spoc")?;
    let raw: DetailRaw = parse_envelope(&super::body(&response))?;
    let submission = fetch_submission(runtime, assignment_id, &token, &role).await?;
    let mut summary = summary(
        base.assignment_id.clone(),
        raw.sskcid.unwrap_or_else(|| base.course_id.clone()),
        base.course_name.clone(),
        non_empty_or(raw.zymc.clone(), base.title.clone()),
        submission.as_ref().and_then(|value| value.tjzt.as_deref()),
        raw.zyfs.as_deref(),
    );
    summary.teacher_name = base.teacher_name;
    summary.start_time = normalize_datetime(raw.zykssj.as_deref()).or(base.start_time);
    summary.due_time = normalize_datetime(raw.zyjzsj.as_deref()).or(base.due_time);
    let mut detail = detail(&summary, raw.zynr);
    detail.start_time = normalize_datetime(raw.zykssj.as_deref());
    detail.due_time = normalize_datetime(raw.zyjzsj.as_deref());
    detail.submitted_at = submission
        .as_ref()
        .and_then(|value| normalize_datetime(value.tjsj.as_deref()));
    Ok(detail)
}

async fn fetch_submission(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: &str,
    token: &str,
    role: &str,
) -> crate::error::Result<Option<SubmissionRaw>> {
    let mut url = url::Url::parse(&runtime.url(SUBMISSION_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC URL is invalid",
        )
    })?;
    url.query_pairs_mut().append_pair("kczyid", assignment_id);
    let token_header = format!("Inco-{token}");
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", role),
        ],
    )
    .await?;
    super::check_response(&response, "spoc")?;
    parse_optional_envelope(&super::body(&response))
}

const CURRENT_TERM_PARAM: &str =
    "YHrxtTavu6raCwC0/qdgYffB9evWHBkTng/XS4W6j3f/TPo02iEPSoegscDTRNzIPRG49o3RHl4JiFCXAiBkkA==";
const ASSIGNMENTS_PAGE_SQL_ID: &str = "1713252980496efac7d5d9985e81693116d3e8a52ebf2b";

#[derive(Debug, Deserialize)]
struct AssignmentPage {
    #[serde(default)]
    pages: u32,
    #[serde(rename = "hasNextPage", default)]
    has_next_page: bool,
    #[serde(default)]
    list: Vec<AssignmentRaw>,
}

#[derive(Debug, Deserialize)]
struct AssignmentRaw {
    zyid: String,
    zymc: String,
    #[serde(default)]
    sskcid: Option<String>,
    #[serde(default)]
    tjzt: Option<String>,
    #[serde(default)]
    mf: Option<String>,
    #[serde(default)]
    kcmc: Option<String>,
    #[serde(default)]
    zykssj: Option<String>,
    #[serde(default)]
    zyjzsj: Option<String>,
}

async fn login(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<(String, String)> {
    let response = super::get_with_redirects(
        runtime,
        runtime.url(CAS_URL)?,
        &[("Accept", "text/html,application/xhtml+xml")],
        "spoc",
    )
    .await?;
    let location = response.final_url.clone();
    let parsed = url::Url::parse(&location).map_err(|_| spoc_auth_error())?;
    let token = parsed
        .query_pairs()
        .find(|(key, _)| key == "token")
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.is_empty())
        .ok_or_else(spoc_auth_error)?;
    let cas = super::post_json(
        runtime,
        runtime.url(CAS_LOGIN_URL)?,
        serde_json::json!({ "token": token })
            .to_string()
            .into_bytes(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &format!("Inco-{token}")),
        ],
    )
    .await?;
    super::check_response(&cas, "spoc")?;
    let value: Value = serde_json::from_str(&super::body(&cas)).map_err(|_| spoc_auth_error())?;
    let role = value
        .pointer("/content/jsdm")
        .and_then(Value::as_str)
        .or_else(|| value.pointer("/content/rolecode/0").and_then(Value::as_str))
        .or_else(|| value.pointer("/content/jsdmList/0").and_then(Value::as_str))
        .filter(|value| !value.is_empty())
        .ok_or_else(spoc_auth_error)?
        .to_owned();
    Ok((token, role))
}

fn encrypt_param(plain: &str) -> String {
    let mut bytes = plain.as_bytes().to_vec();
    let padding = (16 - bytes.len() % 16) % 16;
    bytes.resize(bytes.len() + padding, 0);
    let cipher = Aes128::new_from_slice(b"inco12345678ocni").expect("static AES key");
    let mut previous = *b"ocni12345678inco";
    for chunk in bytes.chunks_exact_mut(16) {
        for (byte, prior) in chunk.iter_mut().zip(previous) {
            *byte ^= prior;
        }
        let mut block = GenericArray::clone_from_slice(chunk);
        cipher.encrypt_block(&mut block);
        chunk.copy_from_slice(&block);
        previous.copy_from_slice(&block);
    }
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

fn spoc_auth_error() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::AuthenticationRequired,
        crate::error::ErrorKind::Authentication,
        false,
        "SPOC authentication is required",
    )
}

fn parse_optional_envelope<T: for<'de> Deserialize<'de>>(
    body: &str,
) -> crate::error::Result<Option<T>> {
    let envelope: Envelope<T> = serde_json::from_str(body).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::ParseError,
            crate::error::ErrorKind::Parse,
            false,
            "SPOC response is not valid JSON",
        )
    })?;
    if envelope.code != 0 && envelope.code != 200 {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC response returned a nonzero code",
        ));
    }
    Ok(envelope.content)
}

fn normalize_datetime(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    if raw.is_empty() {
        return None;
    }
    let (date, time) = raw.split_once('T').or_else(|| raw.split_once(' '))?;
    let time = time
        .split_once('.')
        .map_or(time, |(value, _)| value)
        .trim_end_matches('Z');
    let time = time
        .split_once('+')
        .map_or(time, |(value, _)| value)
        .split_once('-')
        .map_or(time, |(value, _)| value);
    (date.len() == 10 && time.len() >= 8).then(|| format!("{date} {}", &time[..8]))
}

fn non_empty_or(value: String, fallback: String) -> String {
    if value.trim().is_empty() {
        fallback
    } else {
        value
    }
}

#[derive(Debug, Deserialize)]
struct CurrentTerm {
    #[serde(default)]
    dqxq: Option<String>,
    #[serde(default)]
    mrxq: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CourseRaw {
    kcid: String,
    kcmc: String,
    #[serde(default)]
    skjs: Option<String>,
}

#[derive(Debug, Deserialize)]
struct DetailRaw {
    zymc: String,
    #[serde(default)]
    zynr: Option<String>,
    #[serde(default)]
    zyfs: Option<String>,
    #[serde(default)]
    sskcid: Option<String>,
    #[serde(default)]
    zykssj: Option<String>,
    #[serde(default)]
    zyjzsj: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SubmissionRaw {
    #[serde(default)]
    tjzt: Option<String>,
    #[serde(default)]
    tjsj: Option<String>,
}

/// Keep JSON values opaque until the field mapping is proven.
#[allow(dead_code)]
fn _value_type_marker(value: Value) -> Value {
    value
}
