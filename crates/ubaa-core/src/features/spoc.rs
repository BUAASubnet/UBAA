//! SPOC read-only parsing helpers and verified endpoint constants.
#![allow(
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::too_many_lines
)]

use std::future::Future;
use std::pin::Pin;

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use base64::Engine as _;
use serde::{Deserialize, Serialize};
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
        .replace("&#x27;", "'")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    (!text.is_empty()).then_some(text)
}

/// Normalize score text to the first numeric value, as in the frozen parser.
#[must_use]
pub fn normalize_score(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    if raw.is_empty() {
        return None;
    }
    Some(
        regex::Regex::new(r"-?\d+(?:\.\d+)?")
            .expect("static score regex")
            .find(raw)
            .map_or_else(|| raw.to_string(), |value| value.as_str().to_string()),
    )
}

/// Response envelope used by deterministic fixtures.
#[derive(Debug, Deserialize)]
pub struct Envelope<T> {
    /// Upstream status code.
    pub code: i64,
    /// Optional message.
    pub msg: Option<String>,
    /// Optional English message.
    #[serde(rename = "msg_en")]
    pub msg_en: Option<String>,
    /// Payload.
    pub content: Option<T>,
}

/// Decode one SPOC envelope without exposing raw body text.
pub fn parse_envelope<T: for<'de> Deserialize<'de>>(body: &str) -> crate::error::Result<T> {
    let envelope: Envelope<T> = parse_envelope_json(body)?;
    if envelope.code != 200 {
        return Err(classify_envelope_error(&envelope, body));
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
    let status = map_submission_status(
        raw_status,
        raw_status.is_some_and(|value| !value.trim().is_empty()),
    );
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
        submission_status_text: submission_status_text(status, raw_status),
    }
}

/// Build detail from a summary and verified HTML content.
#[must_use]
pub fn detail(summary: &SpocAssignmentSummary, html: Option<&str>) -> SpocAssignmentDetail {
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
        content_plain_text: html.and_then(to_plain_text),
        submitted_at: None,
    }
}

/// Fetch the current SPOC term and assignment list through the authenticated route.
pub(crate) async fn get_assignments(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<crate::domain::SpocAssignments> {
    let term = with_spoc_auth_retry(runtime, |runtime, credential| {
        Box::pin(fetch_current_term(runtime, credential))
    })
    .await?;
    let term_code = term.mrxq.unwrap_or_default();
    if term_code.is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC current term is missing",
        ));
    }
    let mut courses_url = url::Url::parse(&runtime.url(COURSES_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC URL is invalid",
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
    loop {
        let page_term_code = term_code.clone();
        let page = with_spoc_auth_retry(runtime, move |runtime, credential| {
            Box::pin(fetch_assignment_page(
                runtime,
                page_term_code.clone(),
                page_num,
                credential,
            ))
        })
        .await?;
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
    Ok(crate::domain::SpocAssignments {
        term_code,
        term_name: term.dqxq,
        assignments,
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
    let response = super::post_json(
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
    parse_envelope(&super::body(&response))
}

async fn fetch_courses(
    runtime: &mut crate::runtime::ClientRuntime,
    url: String,
    credential: &SpocCredential,
) -> crate::error::Result<Vec<CourseRaw>> {
    let token_header = credential.token_header();
    let response = super::get_with_headers(
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
    parse_envelope(&super::body(&response))
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
            "could not serialize the verified SPOC page request",
        )
    })?;
    let encrypted = encrypt_param(&plain);
    let token_header = credential.token_header();
    let response = super::post_json(
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
    parse_envelope(&super::body(&response))
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
    let detail_id = assignment_id.to_owned();
    let raw = with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_assignment_detail(
            runtime,
            detail_id.clone(),
            credential,
        ))
    })
    .await?;
    if raw.id != assignment_id {
        return Err(detail_id_mismatch());
    }
    let submission = fetch_optional_submission(runtime, assignment_id).await;
    merge_detail(assignment_id, &base, &raw, submission.as_ref())
}

async fn fetch_assignment_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: String,
    credential: &SpocCredential,
) -> crate::error::Result<DetailRaw> {
    let mut url = url::Url::parse(&runtime.url(ASSIGNMENT_DETAIL_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC URL is invalid",
        )
    })?;
    url.query_pairs_mut().append_pair("id", &assignment_id);
    let token_header = credential.token_header();
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_envelope(&super::body(&response))
}

async fn fetch_optional_submission(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: &str,
) -> Option<SubmissionRaw> {
    let assignment_id = assignment_id.to_owned();
    with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_submission(runtime, assignment_id.clone(), credential))
    })
    .await
    .ok()
    .flatten()
}

async fn fetch_submission(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: String,
    credential: &SpocCredential,
) -> crate::error::Result<Option<SubmissionRaw>> {
    let mut url = url::Url::parse(&runtime.url(SUBMISSION_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC URL is invalid",
        )
    })?;
    url.query_pairs_mut().append_pair("kczyid", &assignment_id);
    let token_header = credential.token_header();
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_optional_envelope(&super::body(&response))
}

const CURRENT_TERM_PARAM: &str =
    "YHrxtTavu6raCwC0/qdgYffB9evWHBkTng/XS4W6j3f/TPo02iEPSoegscDTRNzIPRG49o3RHl4JiFCXAiBkkA==";
const ASSIGNMENTS_PAGE_SQL_ID: &str = "1713252980496efac7d5d9985e81693116d3e8a52ebf2b";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AssignmentPageRequest<'a> {
    page_size: u32,
    page_num: u32,
    sqlid: &'static str,
    xnxq: &'a str,
    kcid: &'static str,
    yzwz: &'static str,
}

impl<'a> AssignmentPageRequest<'a> {
    const fn new(term_code: &'a str, page_num: u32) -> Self {
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

#[derive(Clone, Eq, PartialEq)]
pub(super) struct SpocCredential {
    token: String,
    role: String,
}

impl SpocCredential {
    fn token_header(&self) -> String {
        format!("Inco-{}", self.token)
    }
}

async fn login(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<SpocCredential> {
    let token = fetch_login_token(runtime).await?;
    let token_header = format!("Inco-{token}");
    let cas = super::post_json(
        runtime,
        runtime.url(CAS_LOGIN_URL)?,
        serde_json::json!({ "token": &token })
            .to_string()
            .into_bytes(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
        ],
    )
    .await?;
    super::check_response(&cas, "spoc")?;
    let content: Value = parse_envelope(&super::body(&cas))?;
    let role = resolve_role_code(&content).ok_or_else(spoc_auth_error)?;
    Ok(SpocCredential { token, role })
}

async fn ensure_credential(
    runtime: &mut crate::runtime::ClientRuntime,
    force_refresh: bool,
) -> crate::error::Result<SpocCredential> {
    let state = runtime.feature_state();
    if !force_refresh && let Some(credential) = state.spoc.credential() {
        return Ok(credential);
    }
    let _guard = state.spoc.login_guard().await;
    if force_refresh {
        state.spoc.clear_credential();
    } else if let Some(credential) = state.spoc.credential() {
        return Ok(credential);
    }
    let generation = state.spoc.generation();
    let credential = login(runtime).await?;
    state
        .spoc
        .store_credential(generation, credential.clone())
        .then_some(credential)
        .ok_or_else(spoc_auth_error)
}

type SpocOperationFuture<'a, T> =
    Pin<Box<dyn Future<Output = crate::error::Result<T>> + Send + 'a>>;

async fn with_spoc_auth_retry<T, F>(
    runtime: &mut crate::runtime::ClientRuntime,
    mut operation: F,
) -> crate::error::Result<T>
where
    T: Send,
    F: for<'a> FnMut(
            &'a mut crate::runtime::ClientRuntime,
            &'a SpocCredential,
        ) -> SpocOperationFuture<'a, T>
        + Send,
{
    let credential = ensure_credential(runtime, false).await?;
    match operation(runtime, &credential).await {
        Err(error) if is_authentication_error(&error) => {
            let credential = ensure_credential(runtime, true).await?;
            operation(runtime, &credential).await
        }
        result => result,
    }
}

async fn fetch_login_token(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<String> {
    let mut current = runtime.url(CAS_URL)?;
    for _ in 0..8 {
        if let Some(token) = extract_login_token(&current, runtime.mode()) {
            return Ok(token);
        }
        let response = super::get_with_headers(runtime, current.clone(), &[]).await?;
        if let Some(token) = extract_login_token(&response.final_url, runtime.mode()) {
            return Ok(token);
        }
        if response.status == 401 {
            return Err(spoc_auth_error());
        }
        if !(300..400).contains(&response.status) {
            super::check_response(&response, "spoc")?;
            return Err(spoc_auth_error());
        }
        let location = response
            .headers
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case("location"))
            .and_then(|(_, values)| values.first())
            .ok_or_else(spoc_auth_error)?;
        if let Some(token) = extract_login_token(location, runtime.mode()) {
            return Ok(token);
        }
        current = resolve_login_redirect(&response.final_url, location, runtime.mode())?;
    }
    Err(spoc_auth_error())
}

fn resolve_login_redirect(
    current: &str,
    location: &str,
    mode: crate::domain::ConnectionMode,
) -> crate::error::Result<String> {
    let routed_base = url::Url::parse(current).map_err(|_| spoc_auth_error())?;
    let routed_target = if location.starts_with("//") {
        url::Url::parse(&format!("{}:{location}", routed_base.scheme()))
            .map_err(|_| spoc_auth_error())?
    } else {
        routed_base.join(location).map_err(|_| spoc_auth_error())?
    };
    let routed_is_gateway = routed_target
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case("d.buaa.edu.cn"));
    if mode == crate::domain::ConnectionMode::Direct && routed_is_gateway {
        return Err(spoc_auth_error());
    }
    let direct = crate::connection::from_webvpn_url(routed_target.as_str())
        .map_err(|_| spoc_auth_error())?;
    let direct_target = url::Url::parse(&direct).map_err(|_| spoc_auth_error())?;
    if direct_target.scheme() != "https"
        || !direct_target.host_str().is_some_and(|host| {
            matches!(
                host.to_ascii_lowercase().as_str(),
                "spoc.buaa.edu.cn" | "sso.buaa.edu.cn"
            )
        })
    {
        return Err(spoc_auth_error());
    }
    if mode == crate::domain::ConnectionMode::WebVpn {
        if routed_is_gateway {
            Ok(routed_target.to_string())
        } else {
            crate::connection::to_webvpn_url(direct_target.as_str()).map_err(|_| spoc_auth_error())
        }
    } else {
        Ok(direct_target.to_string())
    }
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

fn is_authentication_error(error: &crate::error::UbaaError) -> bool {
    error.code == crate::error::ErrorCode::AuthenticationRequired
}

fn check_business_response(response: &crate::ports::HttpResponse) -> crate::error::Result<()> {
    if response_location_targets_sso(response) {
        return Err(spoc_auth_error());
    }
    super::check_response(response, "spoc")
}

fn response_location_targets_sso(response: &crate::ports::HttpResponse) -> bool {
    response
        .headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("location"))
        .and_then(|(_, values)| values.first())
        .is_some_and(|location| {
            let resolved = url::Url::parse(&response.final_url)
                .ok()
                .and_then(|base| base.join(location).ok())
                .map_or_else(|| location.clone(), |target| target.to_string());
            let direct =
                crate::connection::from_webvpn_url(&resolved).unwrap_or_else(|_| resolved.clone());
            url::Url::parse(&direct)
                .ok()
                .and_then(|target| target.host_str().map(str::to_ascii_lowercase))
                .is_some_and(|host| host == "sso.buaa.edu.cn")
        })
}

fn parse_optional_envelope<T: for<'de> Deserialize<'de>>(
    body: &str,
) -> crate::error::Result<Option<T>> {
    let envelope: Envelope<T> = parse_envelope_json(body)?;
    if envelope.code != 200 {
        return Err(classify_envelope_error(&envelope, body));
    }
    Ok(envelope.content)
}

fn parse_envelope_json<T: for<'de> Deserialize<'de>>(
    body: &str,
) -> crate::error::Result<Envelope<T>> {
    serde_json::from_str(body).map_err(|_| {
        if looks_like_authentication_failure(body) {
            spoc_auth_error()
        } else {
            crate::error::UbaaError::new(
                crate::error::ErrorCode::ParseError,
                crate::error::ErrorKind::Parse,
                false,
                "SPOC response is not valid JSON",
            )
        }
    })
}

fn classify_envelope_error<T>(envelope: &Envelope<T>, body: &str) -> crate::error::UbaaError {
    let messages = envelope
        .msg
        .iter()
        .chain(envelope.msg_en.iter())
        .map(String::as_str)
        .collect::<Vec<_>>()
        .join(" ");
    if looks_like_authentication_failure(&messages) || looks_like_authentication_failure(body) {
        spoc_auth_error()
    } else {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC response returned an unsuccessful code",
        )
    }
}

fn looks_like_authentication_failure(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    ["登录", "token", "未认证", "未登录"]
        .into_iter()
        .any(|marker| lower.contains(marker))
}

fn normalize_datetime(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    if raw.is_empty() {
        return None;
    }
    if let Some(converted) = normalize_offset_datetime(raw) {
        return Some(converted);
    }
    let normalized = raw.replace('T', " ");
    let normalized = normalized
        .split_once('.')
        .map_or(normalized.as_str(), |(value, _)| value);
    Some(normalized.to_string())
}

fn merge_detail(
    assignment_id: &str,
    base: &SpocAssignmentSummary,
    raw: &DetailRaw,
    submission: Option<&SubmissionRaw>,
) -> crate::error::Result<SpocAssignmentDetail> {
    if raw.id != assignment_id {
        return Err(detail_id_mismatch());
    }
    let raw_status = submission.and_then(|value| value.tjzt.as_deref());
    let status = map_submission_status(raw_status, submission.is_some());
    let detail_score = normalize_score(raw.zyfs.as_deref());
    let mut merged = summary(
        base.assignment_id.clone(),
        base.course_id.clone(),
        base.course_name.clone(),
        base.title.clone(),
        raw_status,
        detail_score.as_deref().or(base.score.as_deref()),
    );
    merged.teacher_name.clone_from(&base.teacher_name);
    merged.start_time =
        normalize_datetime(raw.zykssj.as_deref()).or_else(|| base.start_time.clone());
    merged.due_time = normalize_datetime(raw.zyjzsj.as_deref()).or_else(|| base.due_time.clone());
    merged.submission_status = status;
    merged.submission_status_text = submission_status_text(status, raw_status);
    let mut detail = detail(&merged, raw.zynr.as_deref());
    detail.submitted_at = submission.and_then(|value| normalize_datetime(value.tjsj.as_deref()));
    Ok(detail)
}

fn detail_id_mismatch() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "SPOC detail id does not match the requested assignment",
    )
}

fn submission_status_text(status: SpocSubmissionStatus, raw_status: Option<&str>) -> String {
    match status {
        SpocSubmissionStatus::Submitted => "已提交".into(),
        SpocSubmissionStatus::Unsubmitted => "未提交".into(),
        SpocSubmissionStatus::Unknown => raw_status
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map_or_else(|| "未知状态".into(), |value| format!("未知状态({value})")),
    }
}

fn normalize_offset_datetime(raw: &str) -> Option<String> {
    let bytes = raw.as_bytes();
    if bytes.len() < 20 || bytes.get(10) != Some(&b'T') {
        return None;
    }
    let year = parse_digits(bytes.get(0..4)?)?;
    let month = parse_digits(bytes.get(5..7)?)?;
    let day = parse_digits(bytes.get(8..10)?)?;
    let hour = parse_digits(bytes.get(11..13)?)?;
    let minute = parse_digits(bytes.get(14..16)?)?;
    let second = parse_digits(bytes.get(17..19)?)?;
    if bytes.get(4) != Some(&b'-')
        || bytes.get(7) != Some(&b'-')
        || bytes.get(13) != Some(&b':')
        || bytes.get(16) != Some(&b':')
        || month == 0
        || month > 12
        || day == 0
        || day > days_in_month(year, month)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return None;
    }
    let suffix = &raw[19..];
    let offset_seconds = if suffix.ends_with('Z') {
        0
    } else {
        let position = suffix
            .char_indices()
            .rev()
            .find(|(_, character)| matches!(character, '+' | '-'))?
            .0;
        let zone = &suffix[position..];
        let zone_bytes = zone.as_bytes();
        if zone_bytes.len() != 6 || zone_bytes[3] != b':' {
            return None;
        }
        let zone_hours = parse_digits(&zone_bytes[1..3])?;
        let zone_minutes = parse_digits(&zone_bytes[4..6])?;
        if zone_hours > 23 || zone_minutes > 59 {
            return None;
        }
        let seconds = i64::from(zone_hours * 3600 + zone_minutes * 60);
        if zone_bytes[0] == b'-' {
            -seconds
        } else if zone_bytes[0] == b'+' {
            seconds
        } else {
            return None;
        }
    };
    let utc_seconds = days_from_civil(year, month, day) * 86_400
        + i64::from(hour * 3600 + minute * 60 + second)
        - offset_seconds;
    let shanghai_seconds = utc_seconds + 8 * 60 * 60;
    let days = shanghai_seconds.div_euclid(86_400);
    let time = shanghai_seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    let hour = time / 3600;
    let minute = time % 3600 / 60;
    let second = time % 60;
    Some(format!(
        "{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}"
    ))
}

fn parse_digits(bytes: &[u8]) -> Option<u32> {
    bytes.iter().try_fold(0_u32, |value, byte| {
        byte.is_ascii_digit()
            .then(|| value * 10 + u32::from(*byte - b'0'))
    })
}

fn days_in_month(year: u32, month: u32) -> u32 {
    match month {
        2 if year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400)) => {
            29
        }
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

fn days_from_civil(year: u32, month: u32, day: u32) -> i64 {
    let year = i64::from(year) - i64::from(month <= 2);
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let month = i64::from(month);
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

fn civil_from_days(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = z.div_euclid(146_097);
    let day_of_era = z - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    (year + i64::from(month <= 2), month, day)
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
    id: String,
    #[serde(default)]
    zynr: Option<String>,
    #[serde(default)]
    zyfs: Option<String>,
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

fn extract_login_token(candidate: &str, mode: crate::domain::ConnectionMode) -> Option<String> {
    let raw = url::Url::parse(candidate).ok()?;
    let raw_is_gateway = raw
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case("d.buaa.edu.cn"));
    if (mode == crate::domain::ConnectionMode::Direct && raw_is_gateway)
        || (mode == crate::domain::ConnectionMode::WebVpn && !raw_is_gateway)
    {
        return None;
    }
    let direct = crate::connection::from_webvpn_url(candidate).ok()?;
    let parsed = url::Url::parse(&direct).ok()?;
    if parsed.scheme() != "https"
        || !parsed
            .host_str()
            .is_some_and(|host| host.eq_ignore_ascii_case("spoc.buaa.edu.cn"))
        || parsed.path() != "/spocnew/cas"
    {
        return None;
    }
    parsed
        .query_pairs()
        .find(|(key, _)| key == "token")
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.trim().is_empty())
}

fn resolve_role_code(content: &Value) -> Option<String> {
    ["jsdm", "rolecode", "jsdmList"]
        .into_iter()
        .find_map(|field| first_non_empty_string(content.get(field)))
}

fn first_non_empty_string(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(value) => non_empty(value),
        Value::Array(values) => values.iter().find_map(|value| match value {
            Value::String(value) => non_empty(value),
            primitive @ (Value::Number(_) | Value::Bool(_)) => non_empty(&primitive.to_string()),
            Value::Null | Value::Array(_) | Value::Object(_) => None,
        }),
        primitive @ (Value::Number(_) | Value::Bool(_)) => non_empty(&primitive.to_string()),
        Value::Null | Value::Object(_) => None,
    }
}

fn non_empty(value: &str) -> Option<String> {
    (!value.trim().is_empty()).then(|| value.to_string())
}

/// Keep JSON values opaque until the field mapping is proven.
#[allow(dead_code)]
fn _value_type_marker(value: Value) -> Value {
    value
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::{
        AssignmentPageRequest, DetailRaw, encrypt_param, extract_login_token, merge_detail,
        normalize_datetime, normalize_score, parse_envelope, resolve_role_code, summary,
    };

    #[test]
    fn frozen_crypto_and_mapping_vectors_are_preserved() {
        let plain = r#"{"pageSize":15,"pageNum":1,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"#;
        let encrypted = "hkJ9jAFVEMFUgJEjbOLv4eRZqXHIsmF+WbYaG1ipT1L1N+BbxRXtBj6Gcjri4Mo+y6q22/FkNm/isiC2+B+/hNejBx2cQJfNp9zoxorVJBa86sID0ROtPQ/2V07JCmVC3qsgIWBokL7EYyiPfilw+0ryJ6e61jRnLn90sQFosew=";

        assert_eq!(encrypt_param(plain), encrypted);
        assert_eq!(
            normalize_datetime(Some("2026-03-31T15:59:59.000+00:00")).as_deref(),
            Some("2026-03-31 23:59:59")
        );
        assert_eq!(
            normalize_datetime(Some("2026-03-24 16:00:00")).as_deref(),
            Some("2026-03-24 16:00:00")
        );
        assert_eq!(normalize_score(Some("Pass")).as_deref(), Some("Pass"));
        assert_eq!(
            normalize_datetime(Some("upstream-fixture")).as_deref(),
            Some("upstream-fixture")
        );
        let unknown = summary(
            "assignment-1".into(),
            "course-1".into(),
            "Fixture Course".into(),
            "Fixture Assignment".into(),
            Some("9"),
            None,
        );
        assert_eq!(unknown.submission_status_text, "未知状态(9)");
    }

    #[test]
    fn only_code_200_is_a_success_envelope() {
        let error = parse_envelope::<Value>(r#"{"code":0,"content":{}}"#)
            .expect_err("the frozen implementation accepts only code 200");

        assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
    }

    #[test]
    fn cas_token_requires_the_exact_landing_path() {
        assert_eq!(
            extract_login_token(
                "https://spoc.buaa.edu.cn/spocnew/cas?token=fixture-token",
                crate::domain::ConnectionMode::Direct,
            )
            .as_deref(),
            Some("fixture-token")
        );
        assert!(
            extract_login_token(
                "https://spoc.buaa.edu.cn/not-spocnew/cas?token=fixture-token",
                crate::domain::ConnectionMode::Direct,
            )
            .is_none()
        );
        assert!(
            extract_login_token(
                "https://spoc.buaa.edu.cn/spocnew/cas-extra?token=fixture-token",
                crate::domain::ConnectionMode::Direct,
            )
            .is_none()
        );
    }

    #[test]
    fn cas_token_is_bound_to_the_expected_host_and_route() {
        let direct = "https://spoc.buaa.edu.cn/spocnew/cas?token=fixture-token";
        let gateway = crate::connection::to_webvpn_url(direct).unwrap();
        let evil = "https://evil.example/spocnew/cas?token=fixture-token";
        let gateway_evil = crate::connection::to_webvpn_url(evil).unwrap();

        assert!(
            extract_login_token(evil, crate::domain::ConnectionMode::Direct).is_none(),
            "the path alone must not authorize a terminal host"
        );
        assert!(
            extract_login_token(&gateway, crate::domain::ConnectionMode::Direct).is_none(),
            "Direct must not consume a gateway-routed terminal"
        );
        assert!(
            extract_login_token(direct, crate::domain::ConnectionMode::WebVpn).is_none(),
            "WebVPN must not consume a direct terminal"
        );
        assert_eq!(
            extract_login_token(&gateway, crate::domain::ConnectionMode::WebVpn).as_deref(),
            Some("fixture-token")
        );
        assert!(
            extract_login_token(&gateway_evil, crate::domain::ConnectionMode::WebVpn).is_none()
        );
    }

    #[test]
    fn role_code_accepts_primitive_and_array_shapes() {
        for (body, expected) in [
            (r#"{"jsdm":"01"}"#, "01"),
            (r#"{"rolecode":"02"}"#, "02"),
            (r#"{"rolecode":["", "03"]}"#, "03"),
            (r#"{"jsdmList":"04"}"#, "04"),
            (r#"{"jsdmList":["05"]}"#, "05"),
            (r#"{"rolecode":6}"#, "6"),
            (r#"{"jsdmList":[false]}"#, "false"),
        ] {
            let value: Value = serde_json::from_str(body).unwrap();
            assert_eq!(resolve_role_code(&value).as_deref(), Some(expected));
        }
    }

    #[test]
    fn global_page_plaintext_has_the_frozen_field_order_and_empty_filters() {
        let request = AssignmentPageRequest::new("2025-20262", 1);

        assert_eq!(
            serde_json::to_string(&request).unwrap(),
            r#"{"pageSize":15,"pageNum":1,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"#
        );
    }

    #[test]
    fn aligned_plaintext_uses_the_frozen_no_extra_block_zero_padding() {
        assert_eq!(
            encrypt_param("1234567890abcdef"),
            "Df9tLndii11SqqHdmdu/fg=="
        );
    }

    #[test]
    fn detail_requires_its_upstream_id() {
        let error = parse_envelope::<DetailRaw>(
            r#"{"code":200,"content":{"zymc":"Fixture","zynr":"<p>safe</p>"}}"#,
        )
        .expect_err("a detail without its frozen id field is not valid");

        assert_eq!(error.code, crate::error::ErrorCode::ParseError);
    }

    #[test]
    fn public_detail_serialization_contains_plain_text_only() {
        let base = summary(
            "assignment-1".into(),
            "course-1".into(),
            "Fixture Course".into(),
            "Fixture Assignment".into(),
            None,
            Some("100"),
        );
        let value = serde_json::to_value(super::detail(
            &base,
            Some("<p>Fixture <strong>content</strong></p>"),
        ))
        .unwrap();

        assert_eq!(value["contentPlainText"], "Fixture content");
        assert!(value.get("contentHtml").is_none());
    }

    #[test]
    fn empty_submission_is_unknown_and_detail_fields_fall_back_to_summary() {
        let mut base = summary(
            "assignment-1".into(),
            "course-1".into(),
            "Fixture Course".into(),
            "Fixture Assignment".into(),
            Some("未做"),
            Some("80"),
        );
        base.start_time = Some("2026-03-01 08:00:00".into());
        base.due_time = Some("2026-03-31 23:59:59".into());
        let raw = DetailRaw {
            id: "assignment-1".into(),
            zynr: Some("<p>Fixture</p>".into()),
            zyfs: None,
            zykssj: None,
            zyjzsj: None,
        };
        let empty_submission = super::SubmissionRaw {
            tjzt: None,
            tjsj: None,
        };

        let detail = merge_detail("assignment-1", &base, &raw, Some(&empty_submission)).unwrap();

        assert_eq!(
            detail.submission_status,
            crate::domain::SpocSubmissionStatus::Unknown
        );
        assert_eq!(detail.submission_status_text, "未知状态");
        assert_eq!(detail.score.as_deref(), Some("80"));
        assert_eq!(detail.start_time.as_deref(), Some("2026-03-01 08:00:00"));
        assert_eq!(detail.due_time.as_deref(), Some("2026-03-31 23:59:59"));
    }

    #[test]
    fn blank_list_status_and_blank_detail_score_follow_frozen_fallbacks() {
        let mut base = summary(
            "assignment-1".into(),
            "course-1".into(),
            "Fixture Course".into(),
            "Fixture Assignment".into(),
            Some("  "),
            Some("80"),
        );
        assert_eq!(
            base.submission_status,
            crate::domain::SpocSubmissionStatus::Unsubmitted
        );
        let raw = DetailRaw {
            id: "assignment-1".into(),
            zynr: None,
            zyfs: Some("  ".into()),
            zykssj: None,
            zyjzsj: None,
        };
        base.score = Some("80".into());

        let detail = merge_detail("assignment-1", &base, &raw, None).unwrap();

        assert_eq!(detail.score.as_deref(), Some("80"));
    }

    #[test]
    fn detail_enrichment_cannot_replace_summary_identity_fields() {
        let base = summary(
            "assignment-1".into(),
            "summary-course".into(),
            "Fixture Course".into(),
            "Summary title".into(),
            None,
            None,
        );
        let raw = DetailRaw {
            id: "assignment-1".into(),
            zynr: None,
            zyfs: None,
            zykssj: None,
            zyjzsj: None,
        };

        let detail = merge_detail("assignment-1", &base, &raw, None).unwrap();

        assert_eq!(detail.assignment_id, "assignment-1");
        assert_eq!(detail.course_id, "summary-course");
        assert_eq!(detail.title, "Summary title");
    }

    #[test]
    fn envelope_auth_marker_outside_message_is_still_retryable_authentication() {
        let error = parse_envelope::<Value>(r#"{"code":401,"content":{"reason":"token expired"}}"#)
            .expect_err("the frozen classifier scans the complete response body");

        assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
    }

    #[test]
    fn invalidated_login_generation_cannot_repopulate_route_credentials() {
        let state = crate::features::state::RouteFeatureState::default();
        let generation = state.spoc.generation();
        state.clear();

        let stored = state.spoc.store_credential(
            generation,
            super::SpocCredential {
                token: "stale-token".into(),
                role: "01".into(),
            },
        );

        assert!(!stored);
        assert!(state.spoc.credential().is_none());
    }
}
