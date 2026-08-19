//! Judge (希冀) read-only HTML parsers.
#![allow(
    clippy::missing_errors_doc,
    clippy::missing_panics_doc,
    clippy::must_use_candidate
)]

use crate::domain::{
    JudgeAssignmentDetail, JudgeAssignmentSummary, JudgeProblem, JudgeSubmissionStatus,
};
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use tokio::sync::Semaphore;
use tokio::task::JoinSet;

/// Judge service login URL from the frozen implementation.
pub const LOGIN_URL: &str =
    "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F";
/// Judge service host.
pub const BASE_URL: &str = "https://judge.buaa.edu.cn";

const LIST_TTL: Duration = Duration::from_mins(5);
const DETAIL_TTL: Duration = Duration::from_mins(2);
const ASSIGNMENT_QUERY_CONCURRENCY: usize = 4;

type CacheScope = (crate::domain::ConnectionMode, u64);

#[derive(Default)]
struct JudgeCache {
    courses: HashMap<CacheScope, CacheEntry<Vec<Course>>>,
    assignments: HashMap<(CacheScope, String), CacheEntry<Vec<Assignment>>>,
    details: HashMap<(CacheScope, String, String), CacheEntry<JudgeAssignmentDetail>>,
    historical_courses: HashMap<CacheScope, HashSet<String>>,
}

struct CacheEntry<T> {
    value: T,
    cached_at: Instant,
}

static JUDGE_CACHE: OnceLock<Mutex<JudgeCache>> = OnceLock::new();

/// Parsed course link.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Course {
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
}

/// Parsed assignment link.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Assignment {
    /// Assignment ID.
    pub assignment_id: String,
    /// Course ID.
    pub course_id: String,
    /// Course name.
    pub course_name: String,
    /// Assignment title.
    pub title: String,
}

/// Extract course links while excluding the synthetic course 0 entry.
pub fn parse_courses(html: &str) -> Vec<Course> {
    let regex = regex::Regex::new(
        r#"(?is)<a\b[^>]*href\s*=\s*[\"']?[^\"' >]*courselist\.jsp\?courseID=(\d+)[^\"' >]*[\"']?[^>]*>(.*?)</a>"#,
    )
    .expect("static Judge course regex");
    let mut courses = Vec::new();
    for capture in regex.captures_iter(html) {
        let Some(id) = capture.get(1).map(|value| value.as_str()) else {
            continue;
        };
        if id == "0" || courses.iter().any(|course: &Course| course.course_id == id) {
            continue;
        }
        let name = clean_text(capture.get(2).map_or("", |value| value.as_str()));
        if !name.is_empty() {
            courses.push(Course {
                course_id: id.into(),
                course_name: name,
            });
        }
    }
    courses
}

/// Extract assignment links from a selected course page.
pub fn parse_assignments(html: &str, course: &Course) -> Vec<Assignment> {
    let regex = regex::Regex::new(
        r#"(?is)<a\b[^>]*href\s*=\s*[\"']?[^\"' >]*assignID=(\d+)[^\"' >]*[\"']?[^>]*>(.*?)</a>"#,
    )
    .expect("static Judge assignment regex");
    let mut assignments = Vec::new();
    for capture in regex.captures_iter(html) {
        let Some(id) = capture.get(1).map(|value| value.as_str()) else {
            continue;
        };
        if assignments
            .iter()
            .any(|assignment: &Assignment| assignment.assignment_id == id)
        {
            continue;
        }
        let title = clean_text(capture.get(2).map_or("", |value| value.as_str()));
        if !title.is_empty() {
            assignments.push(Assignment {
                assignment_id: id.into(),
                course_id: course.course_id.clone(),
                course_name: course.course_name.clone(),
                title,
            });
        }
    }
    assignments
}

/// Parse the evidence-backed summary fields from an assignment detail page.
pub fn parse_detail(
    html: &str,
    course_id: &str,
    course_name: &str,
    assignment_id: &str,
    title: &str,
) -> crate::error::Result<JudgeAssignmentDetail> {
    let plain = clean_text(html);
    let max_score = capture_number(&plain, r"作业满分[：:]\s*([\d.]+)");
    let total = capture_number(&plain, r"共\s*(\d+)\s*道")
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    let (start_time, due_time) = capture_window(&plain);
    let unsubmitted = plain.contains("未提交") || plain.contains("未作答");
    let status = if unsubmitted {
        JudgeSubmissionStatus::Unsubmitted
    } else {
        JudgeSubmissionStatus::Unknown
    };
    Ok(JudgeAssignmentDetail {
        course_id: course_id.into(),
        course_name: course_name.into(),
        assignment_id: assignment_id.into(),
        title: title.into(),
        start_time,
        due_time,
        max_score,
        my_score: None,
        total_problems: total,
        submitted_count: if unsubmitted { 0 } else { total },
        submission_status: status,
        submission_status_text: if unsubmitted {
            "未提交".into()
        } else {
            "未知状态".into()
        },
        problems: Vec::<JudgeProblem>::new(),
        content_plain_text: (!plain.is_empty()).then_some(plain),
    })
}

/// Convert one detail to its stable list summary.
#[must_use]
pub fn to_summary(detail: &JudgeAssignmentDetail) -> JudgeAssignmentSummary {
    JudgeAssignmentSummary {
        course_id: detail.course_id.clone(),
        course_name: detail.course_name.clone(),
        assignment_id: detail.assignment_id.clone(),
        title: detail.title.clone(),
        start_time: detail.start_time.clone(),
        due_time: detail.due_time.clone(),
        max_score: detail.max_score.clone(),
        my_score: detail.my_score.clone(),
        total_problems: detail.total_problems,
        submitted_count: detail.submitted_count,
        submission_status: detail.submission_status,
        submission_status_text: detail.submission_status_text.clone(),
    }
}

/// Fetch Judge assignment links for the current authenticated route.
pub(crate) async fn get_assignments(
    runtime: &mut crate::runtime::ClientRuntime,
    include_expired: bool,
) -> crate::error::Result<Vec<JudgeAssignmentSummary>> {
    let scope = cache_scope(runtime);
    let courses = get_courses_cached(runtime, scope).await?;
    let skipped = if include_expired {
        HashSet::new()
    } else {
        cache()
            .lock()
            .expect("Judge cache mutex")
            .historical_courses
            .get(&scope)
            .cloned()
            .unwrap_or_default()
    };
    let courses = courses
        .into_iter()
        .filter(|course| !skipped.contains(&course.course_id))
        .collect::<Vec<_>>();
    let cutoff = six_month_cutoff();
    let limiter = Arc::new(Semaphore::new(ASSIGNMENT_QUERY_CONCURRENCY));
    let mut workers = JoinSet::new();
    for (index, course) in courses.into_iter().enumerate() {
        let mut worker = fork_judge_worker(runtime);
        let cutoff = cutoff.clone();
        let limiter = Arc::clone(&limiter);
        workers.spawn(async move {
            let permit = limiter.acquire_owned().await.map_err(|_| worker_error())?;
            let result =
                summarize_course(&mut worker, scope, course, include_expired, &cutoff).await;
            drop(permit);
            result.map(|summary| (index, summary))
        });
    }

    let mut summaries = Vec::new();
    while let Some(joined) = workers.join_next().await {
        match joined {
            Ok(Ok((index, summary))) => summaries.push((index, summary)),
            Ok(Err(error)) => {
                workers.abort_all();
                return Err(error);
            }
            Err(_) => {
                workers.abort_all();
                return Err(worker_error());
            }
        }
    }

    summaries.sort_by_key(|(index, _)| *index);
    let mut result = Vec::new();
    for (_, summary) in summaries {
        if summary.historical {
            cache()
                .lock()
                .expect("Judge cache mutex")
                .historical_courses
                .entry(scope)
                .or_default()
                .insert(summary.course_id.clone());
        }
        result.extend(summary.summaries);
    }
    result.sort_by(|left, right| {
        left.due_time
            .as_deref()
            .unwrap_or("9999-99-99 99:99:99")
            .cmp(right.due_time.as_deref().unwrap_or("9999-99-99 99:99:99"))
            .then_with(|| left.course_name.cmp(&right.course_name))
            .then_with(|| left.title.cmp(&right.title))
    });
    Ok(result)
}

/// Fetch one Judge assignment detail.
pub(crate) async fn get_assignment_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: &str,
    assignment_id: &str,
) -> crate::error::Result<JudgeAssignmentDetail> {
    if course_id.trim().is_empty() || assignment_id.trim().is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::InvalidInput,
            crate::error::ErrorKind::Input,
            false,
            "course id and assignment id are required",
        ));
    }
    let scope = cache_scope(runtime);
    let courses = get_courses_cached(runtime, scope).await?;
    let course = courses
        .into_iter()
        .find(|course| course.course_id == course_id)
        .ok_or_else(not_found)?;
    let assignments = get_course_assignments_cached(runtime, scope, &course).await?;
    let assignment = assignments
        .into_iter()
        .find(|assignment| assignment.assignment_id == assignment_id)
        .ok_or_else(not_found)?;
    get_detail_cached(runtime, scope, &assignment).await
}

/// Fetch multiple Judge details, preserving input order and rejecting empty input.
pub(crate) async fn get_assignment_details(
    runtime: &mut crate::runtime::ClientRuntime,
    keys: &[crate::domain::JudgeAssignmentKey],
) -> crate::error::Result<Vec<JudgeAssignmentDetail>> {
    if keys.is_empty() {
        return Ok(Vec::new());
    }
    let mut normalized = Vec::with_capacity(keys.len());
    let mut seen = HashSet::new();
    for key in keys {
        if key.course_id.trim().is_empty()
            || key.assignment_id.trim().is_empty()
            || !seen.insert((key.course_id.clone(), key.assignment_id.clone()))
        {
            continue;
        }
        normalized.push(key.clone());
    }
    if normalized.is_empty() {
        return Ok(Vec::new());
    }

    let scope = cache_scope(runtime);
    let courses = get_courses_cached(runtime, scope).await?;
    let limiter = Arc::new(Semaphore::new(ASSIGNMENT_QUERY_CONCURRENCY));
    let mut workers = JoinSet::new();
    for (index, key) in normalized.into_iter().enumerate() {
        let course = courses
            .iter()
            .find(|course| course.course_id == key.course_id)
            .cloned()
            .ok_or_else(not_found)?;
        let mut worker = fork_judge_worker(runtime);
        let limiter = Arc::clone(&limiter);
        workers.spawn(async move {
            let permit = limiter.acquire_owned().await.map_err(|_| worker_error())?;
            let result = async {
                activate(&mut worker).await?;
                let assignments =
                    get_course_assignments_cached(&mut worker, scope, &course).await?;
                let assignment = assignments
                    .into_iter()
                    .find(|assignment| assignment.assignment_id == key.assignment_id)
                    .ok_or_else(not_found)?;
                get_detail_cached(&mut worker, scope, &assignment).await
            }
            .await;
            drop(permit);
            result.map(|detail| (index, detail))
        });
    }

    let mut ordered = Vec::new();
    while let Some(joined) = workers.join_next().await {
        match joined {
            Ok(Ok((index, detail))) => ordered.push((index, detail)),
            Ok(Err(error)) => {
                workers.abort_all();
                return Err(error);
            }
            Err(_) => {
                workers.abort_all();
                return Err(worker_error());
            }
        }
    }
    ordered.sort_by_key(|(index, _)| *index);
    let result = ordered.into_iter().map(|(_, detail)| detail).collect();
    Ok(result)
}

struct CourseSummary {
    course_id: String,
    summaries: Vec<JudgeAssignmentSummary>,
    historical: bool,
}

async fn summarize_course(
    runtime: &mut crate::runtime::ClientRuntime,
    scope: CacheScope,
    course: Course,
    include_expired: bool,
    cutoff: &str,
) -> crate::error::Result<CourseSummary> {
    activate(runtime).await?;
    let assignments = get_course_assignments_cached(runtime, scope, &course).await?;
    let mut summaries = Vec::new();
    let mut historical = false;
    for assignment in assignments {
        let detail = get_detail_cached(runtime, scope, &assignment).await?;
        if detail
            .start_time
            .as_deref()
            .is_some_and(|start| start < cutoff)
        {
            historical = true;
            if !include_expired {
                break;
            }
        }
        summaries.push(to_summary(&detail));
    }
    Ok(CourseSummary {
        course_id: course.course_id,
        summaries,
        historical,
    })
}

fn worker_error() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::InternalError,
        crate::error::ErrorKind::Internal,
        true,
        "Judge read worker failed",
    )
}

fn cache() -> &'static Mutex<JudgeCache> {
    JUDGE_CACHE.get_or_init(|| Mutex::new(JudgeCache::default()))
}

fn cache_scope(runtime: &crate::runtime::ClientRuntime) -> CacheScope {
    (runtime.mode(), runtime.cache_scope_key())
}

fn fork_judge_worker(runtime: &crate::runtime::ClientRuntime) -> crate::runtime::ClientRuntime {
    let mode = runtime.mode();
    runtime.fork_for_readonly_with_cookie_filter(|cookie| !is_judge_scoped_cookie(cookie, mode))
}

fn is_judge_scoped_cookie(
    cookie: &crate::session::StoredCookie,
    mode: crate::domain::ConnectionMode,
) -> bool {
    match mode {
        crate::domain::ConnectionMode::Direct => {
            let domain = cookie.domain.trim_start_matches('.');
            domain.eq_ignore_ascii_case("judge.buaa.edu.cn")
                || domain.to_ascii_lowercase().ends_with(".judge.buaa.edu.cn")
        }
        crate::domain::ConnectionMode::WebVpn => {
            cookie.domain.eq_ignore_ascii_case("d.buaa.edu.cn")
                && webvpn_cookie_path_targets_judge(&cookie.path)
        }
    }
}

fn webvpn_cookie_path_targets_judge(path: &str) -> bool {
    let normalized_path = if path.starts_with('/') {
        path.to_string()
    } else {
        format!("/{path}")
    };
    let gateway_url = format!("https://d.buaa.edu.cn{normalized_path}");
    crate::connection::from_webvpn_url(&gateway_url)
        .ok()
        .and_then(|url| url::Url::parse(&url).ok())
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
        .is_some_and(|host| host == "judge.buaa.edu.cn" || host.ends_with(".judge.buaa.edu.cn"))
}

async fn activate(runtime: &mut crate::runtime::ClientRuntime) -> crate::error::Result<()> {
    let response =
        super::get_with_redirects(runtime, runtime.url(LOGIN_URL)?, judge_headers(), "judge")
            .await?;
    super::check_response(&response, "judge")
}

async fn get_courses_cached(
    runtime: &mut crate::runtime::ClientRuntime,
    scope: CacheScope,
) -> crate::error::Result<Vec<Course>> {
    if let Some(courses) = cache()
        .lock()
        .expect("Judge cache mutex")
        .courses
        .get(&scope)
        .filter(|entry| entry.cached_at.elapsed() < LIST_TTL)
        .map(|entry| entry.value.clone())
    {
        return Ok(courses);
    }
    activate(runtime).await?;
    let mut url =
        url::Url::parse(&format!("{BASE_URL}/courselist.jsp")).map_err(|_| invalid_url())?;
    url.query_pairs_mut().append_pair("courseID", "0");
    let response = get_html(runtime, runtime.url(url.as_str())?).await?;
    let courses = parse_courses(&super::body(&response));
    if !courses.is_empty() {
        cache().lock().expect("Judge cache mutex").courses.insert(
            scope,
            CacheEntry {
                value: courses.clone(),
                cached_at: Instant::now(),
            },
        );
    }
    Ok(courses)
}

async fn get_course_assignments_cached(
    runtime: &mut crate::runtime::ClientRuntime,
    scope: CacheScope,
    course: &Course,
) -> crate::error::Result<Vec<Assignment>> {
    let key = (scope, course.course_id.clone());
    if let Some(assignments) = cache()
        .lock()
        .expect("Judge cache mutex")
        .assignments
        .get(&key)
        .filter(|entry| entry.cached_at.elapsed() < LIST_TTL)
        .map(|entry| entry.value.clone())
    {
        return Ok(assignments);
    }
    let mut select_url =
        url::Url::parse(&format!("{BASE_URL}/courselist.jsp")).map_err(|_| invalid_url())?;
    select_url
        .query_pairs_mut()
        .append_pair("courseID", &course.course_id);
    get_html(runtime, runtime.url(select_url.as_str())?).await?;
    let index_url = runtime.url(&format!("{BASE_URL}/assignment/index.jsp"))?;
    let response = get_html(runtime, index_url).await?;
    let assignments = parse_assignments(&super::body(&response), course);
    let mut cache = cache().lock().expect("Judge cache mutex");
    if assignments.is_empty() {
        cache.assignments.remove(&key);
    } else {
        cache.assignments.insert(
            key,
            CacheEntry {
                value: assignments.clone(),
                cached_at: Instant::now(),
            },
        );
    }
    Ok(assignments)
}

async fn get_detail_cached(
    runtime: &mut crate::runtime::ClientRuntime,
    scope: CacheScope,
    assignment: &Assignment,
) -> crate::error::Result<JudgeAssignmentDetail> {
    let key = (
        scope,
        assignment.course_id.clone(),
        assignment.assignment_id.clone(),
    );
    if let Some(detail) = cache()
        .lock()
        .expect("Judge cache mutex")
        .details
        .get(&key)
        .filter(|entry| entry.cached_at.elapsed() < DETAIL_TTL)
        .map(|entry| entry.value.clone())
    {
        return Ok(detail);
    }
    let mut select_url =
        url::Url::parse(&format!("{BASE_URL}/courselist.jsp")).map_err(|_| invalid_url())?;
    select_url
        .query_pairs_mut()
        .append_pair("courseID", &assignment.course_id);
    get_html(runtime, runtime.url(select_url.as_str())?).await?;
    let mut detail_url =
        url::Url::parse(&format!("{BASE_URL}/assignment/index.jsp")).map_err(|_| invalid_url())?;
    detail_url
        .query_pairs_mut()
        .append_pair("assignID", &assignment.assignment_id);
    let response = get_html(runtime, runtime.url(detail_url.as_str())?).await?;
    let detail = parse_detail(
        &super::body(&response),
        &assignment.course_id,
        &assignment.course_name,
        &assignment.assignment_id,
        &assignment.title,
    )?;
    cache().lock().expect("Judge cache mutex").details.insert(
        key,
        CacheEntry {
            value: detail.clone(),
            cached_at: Instant::now(),
        },
    );
    Ok(detail)
}

fn judge_headers() -> &'static [(&'static str, &'static str)] {
    &[
        (
            "Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        ),
        ("Accept-Language", "zh-CN,zh;q=0.9"),
        (
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3",
        ),
    ]
}

async fn get_html(
    runtime: &mut crate::runtime::ClientRuntime,
    url: String,
) -> crate::error::Result<crate::ports::HttpResponse> {
    let response =
        super::get_with_redirects(runtime, url.clone(), judge_headers(), "judge").await?;
    match super::check_response(&response, "judge") {
        Ok(()) => Ok(response),
        Err(error) if error.code == crate::error::ErrorCode::AuthenticationRequired => {
            activate(runtime).await?;
            let response = super::get_with_headers(runtime, url, judge_headers()).await?;
            super::check_response(&response, "judge")?;
            Ok(response)
        }
        Err(error) => Err(error),
    }
}

fn six_month_cutoff() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
        + 8 * 60 * 60;
    let days = i64::try_from(seconds / 86_400).unwrap_or(i64::MAX);
    let (mut year, mut month, day) = civil_date(days);
    if month <= 6 {
        year -= 1;
        month += 6;
    } else {
        month -= 6;
    }
    format!("{year:04}-{month:02}-{day:02} 00:00:00")
}

fn civil_date(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    (year + i64::from(month <= 2), month, day)
}

fn invalid_url() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "Judge URL is invalid",
    )
}

fn not_found() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "Judge assignment was not found",
    )
}

fn capture_number(text: &str, pattern: &str) -> Option<String> {
    regex::Regex::new(pattern)
        .expect("static Judge number regex")
        .captures(text)
        .and_then(|capture| capture.get(1).map(|value| value.as_str().to_string()))
}

fn capture_window(text: &str) -> (Option<String>, Option<String>) {
    let regex = regex::Regex::new(
        r"作业时间[：:]\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}:\d{2})?)\s*至\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}:\d{2})?)",
    )
    .expect("static Judge date regex");
    let Some(capture) = regex.captures(text) else {
        return (None, None);
    };
    (
        capture.get(1).map(|value| value.as_str().replace('T', " ")),
        capture.get(2).map(|value| value.as_str().replace('T', " ")),
    )
}

fn clean_text(value: &str) -> String {
    regex::Regex::new(r"(?is)<[^>]+>")
        .expect("static Judge HTML regex")
        .replace_all(value, " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
