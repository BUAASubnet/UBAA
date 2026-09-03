//! SPOC 响应包装、分页、详情与提交状态解析。

use serde::Deserialize;
use serde_json::Value;

use super::calendar::normalize_datetime;
use crate::domain::{SpocAssignmentDetail, SpocAssignmentSummary, SpocSubmissionStatus};

/// 映射已验证的 SPOC 状态值，不擅自创造新状态。
#[must_use]
pub fn map_submission_status(raw_status: Option<&str>, has_content: bool) -> SpocSubmissionStatus {
    match raw_status.map(str::trim) {
        Some("1" | "已做" | "已提交") => SpocSubmissionStatus::Submitted,
        Some("0" | "未做" | "未提交") => SpocSubmissionStatus::Unsubmitted,
        _ if !has_content => SpocSubmissionStatus::Unsubmitted,
        _ => SpocSubmissionStatus::Unknown,
    }
}

/// 将已知 HTML 标记转换为安全的纯文本描述。
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

/// 按冻结解析器规则，将成绩文本规范化为第一个数字值。
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

/// 确定性 fixture 使用的响应包装。
#[derive(Debug, Deserialize)]
pub struct Envelope<T> {
    /// 上游状态代码。
    pub code: i64,
    /// 可选消息。
    pub msg: Option<String>,
    /// 可选英文消息。
    #[serde(rename = "msg_en")]
    pub msg_en: Option<String>,
    /// 载荷。
    pub content: Option<T>,
}

/// 解码一个 SPOC 包装，不暴露原始响应体文本。
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
            "SPOC 响应缺少内容",
        )
    })
}

/// 根据观察到的原始字段构造稳定摘要。
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

/// 根据摘要和已验证的 HTML 内容构造详情。
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

pub(super) fn parse_optional_envelope<T: for<'de> Deserialize<'de>>(
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
        crate::error::UbaaError::new(
            crate::error::ErrorCode::ParseError,
            crate::error::ErrorKind::Parse,
            false,
            "SPOC 响应不是有效 JSON",
        )
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
            "SPOC 响应返回失败状态码",
        )
    }
}

pub(super) fn spoc_auth_error() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::AuthenticationRequired,
        crate::error::ErrorKind::Authentication,
        false,
        "SPOC 功能需要认证",
    )
}

fn looks_like_authentication_failure(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    ["登录", "token", "未认证", "未登录"]
        .into_iter()
        .any(|marker| lower.contains(marker))
}

pub(super) fn merge_detail(
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

pub(super) fn detail_id_mismatch() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "SPOC 详情标识与请求的作业不一致",
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

#[derive(Debug, Deserialize)]
pub(super) struct CurrentTerm {
    #[serde(default)]
    pub(super) dqxq: Option<String>,
    #[serde(default)]
    pub(super) mrxq: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct CourseRaw {
    pub(super) kcid: String,
    pub(super) kcmc: String,
    #[serde(default)]
    pub(super) skjs: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct AssignmentPage {
    // 保留此字段，使 serde 校验冻结线协议类型，宿主不对外暴露分页信息。
    #[allow(dead_code)]
    #[serde(default)]
    pub(super) total: u32,
    #[allow(dead_code)]
    #[serde(rename = "pageNum", default = "default_page_num")]
    pub(super) page_num: u32,
    #[allow(dead_code)]
    #[serde(rename = "pageSize", default = "default_page_size")]
    pub(super) page_size: u32,
    #[serde(default = "default_page_num")]
    pub(super) pages: u32,
    #[serde(rename = "hasNextPage", default)]
    pub(super) has_next_page: bool,
    #[serde(default)]
    pub(super) list: Vec<AssignmentRaw>,
}

const fn default_page_num() -> u32 {
    1
}

const fn default_page_size() -> u32 {
    15
}

#[derive(Debug, Deserialize)]
pub(super) struct AssignmentRaw {
    pub(super) zyid: String,
    pub(super) zymc: String,
    #[serde(default)]
    pub(super) sskcid: Option<String>,
    // 为严格解析冻结线协议而保留；外层响应已提供 term_code。
    #[allow(dead_code)]
    #[serde(default)]
    pub(super) xnxq: Option<String>,
    #[serde(default)]
    pub(super) tjzt: Option<String>,
    #[serde(default)]
    pub(super) mf: Option<String>,
    #[serde(default)]
    pub(super) kcmc: Option<String>,
    #[serde(default)]
    pub(super) zykssj: Option<String>,
    #[serde(default)]
    pub(super) zyjzsj: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct DetailRaw {
    pub(super) id: String,
    // 线协议要求该字段，但权威列表摘要仍是公开身份信息。
    #[allow(dead_code)]
    pub(super) zymc: String,
    #[serde(default)]
    pub(super) zynr: Option<String>,
    #[serde(default)]
    pub(super) zyfs: Option<String>,
    #[serde(default)]
    pub(super) zykssj: Option<String>,
    #[serde(default)]
    pub(super) zyjzsj: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    pub(super) sskcid: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct SubmissionRaw {
    #[serde(default)]
    pub(super) tjzt: Option<String>,
    #[serde(default)]
    pub(super) tjsj: Option<String>,
}

pub(super) fn resolve_role_code(content: &Value) -> Option<String> {
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

/// 在字段映射得到证明前保持 JSON 值不透明。
#[allow(dead_code)]
fn _value_type_marker(value: Value) -> Value {
    value
}
