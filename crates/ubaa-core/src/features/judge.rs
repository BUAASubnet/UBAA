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
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use scraper::{ElementRef, Html, Selector};
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
const BUSINESS_REACTIVATION_LIMIT: usize = 3;

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

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct AssignmentList {
    pub(crate) assignments: Vec<Assignment>,
    pub(crate) raw_anchor_count: usize,
}

impl AssignmentList {
    fn filtered_unique_count(&self) -> usize {
        self.assignments.len()
    }
}

/// Extract course links while excluding the synthetic course 0 entry.
pub fn parse_courses(html: &str) -> Vec<Course> {
    let document = Html::parse_document(html);
    let anchors = selector("a[href]");
    let course_id = regex::Regex::new(r"(?i)courselist\.jsp\?courseID=(\d+)")
        .expect("static Judge course id regex");
    let mut courses = Vec::new();
    for anchor in document.select(&anchors) {
        let Some(id) = anchor
            .attr("href")
            .and_then(|href| course_id.captures(href))
            .and_then(|capture| capture.get(1).map(|value| value.as_str()))
        else {
            continue;
        };
        if id == "0" || courses.iter().any(|course: &Course| course.course_id == id) {
            continue;
        }
        let name = element_text(anchor, None);
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
    parse_assignment_list(html, course).assignments
}

fn parse_assignment_list(html: &str, course: &Course) -> AssignmentList {
    let document = Html::parse_document(html);
    let anchors = selector("a[href]");
    let assignment_id =
        regex::Regex::new(r"(?i)assignID=(\d+)").expect("static Judge assignment id regex");
    let mut assignments = Vec::new();
    let mut raw_anchor_count = 0;
    for anchor in document.select(&anchors) {
        let Some(href) = anchor.attr("href") else {
            continue;
        };
        let Some(id) = assignment_id
            .captures(href)
            .and_then(|capture| capture.get(1).map(|value| value.as_str()))
        else {
            continue;
        };
        raw_anchor_count += 1;
        if href.contains("problemContent") || href.contains("judgeDetails") {
            continue;
        }
        if assignments
            .iter()
            .any(|assignment: &Assignment| assignment.assignment_id == id)
        {
            continue;
        }
        let title = element_text(anchor, None);
        if !title.is_empty() {
            assignments.push(Assignment {
                assignment_id: id.into(),
                course_id: course.course_id.clone(),
                course_name: course.course_name.clone(),
                title,
            });
        }
    }
    AssignmentList {
        assignments,
        raw_anchor_count,
    }
}

/// Parse the evidence-backed summary fields from an assignment detail page.
pub fn parse_detail(
    html: &str,
    course_id: &str,
    course_name: &str,
    assignment_id: &str,
    title: &str,
) -> crate::error::Result<JudgeAssignmentDetail> {
    let document = Html::parse_document(html);
    let body_selector = selector("body");
    let root = document
        .select(&body_selector)
        .next()
        .unwrap_or_else(|| document.root_element());
    let plain = element_text(root, None);
    let max_score = capture_number(&plain, r"作业满分[：:]\s*([\d.]+)");
    let total = capture_number(&plain, r"共\s*(\d+)\s*道")
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    let (start_time, due_time) = capture_window(&plain);
    let parsed_problems = parse_problems(&document);
    let earned_scores = parsed_problems
        .iter()
        .filter_map(|problem| problem.earned_score)
        .collect::<Vec<_>>();
    let problems = parsed_problems
        .into_iter()
        .map(|problem| problem.problem)
        .collect::<Vec<_>>();
    let submitted_count = if problems.is_empty() {
        estimate_submitted_count(&plain)
    } else {
        i32::try_from(
            problems
                .iter()
                .filter(|problem| problem.status != JudgeSubmissionStatus::Unsubmitted)
                .count(),
        )
        .unwrap_or(i32::MAX)
    };
    let total_problems = if total == 0 && !problems.is_empty() {
        i32::try_from(problems.len()).unwrap_or(i32::MAX)
    } else {
        total
    };
    let explicit_my_score = capture_number(&plain, r"总分[：:]\s*([\d.]+)");
    let my_score = explicit_my_score
        .or_else(|| (!earned_scores.is_empty()).then(|| format_score(earned_scores.iter().sum())));
    let status = resolve_status(total_problems, submitted_count);
    let normalized_max_score = normalize_score(max_score.as_deref());
    let normalized_my_score = normalize_score(my_score.as_deref());
    Ok(JudgeAssignmentDetail {
        course_id: course_id.into(),
        course_name: course_name.into(),
        assignment_id: assignment_id.into(),
        title: title.into(),
        start_time,
        due_time,
        max_score: normalized_max_score,
        my_score: normalized_my_score,
        total_problems,
        submitted_count,
        submission_status: status,
        submission_status_text: submission_status_text(
            status,
            submitted_count,
            total_problems,
            my_score.as_deref(),
            max_score.as_deref(),
        ),
        problems,
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
    Ok(get_assignments_diagnostics(runtime, include_expired)
        .await?
        .summaries)
}

pub(crate) async fn get_assignments_diagnostics(
    runtime: &mut crate::runtime::ClientRuntime,
    include_expired: bool,
) -> crate::error::Result<crate::domain::JudgeAssignmentsDiagnostics> {
    let result = get_assignments_diagnostics_inner(runtime, include_expired).await;
    resolve_required_judge_result(runtime, result).await
}

async fn get_assignments_diagnostics_inner(
    runtime: &mut crate::runtime::ClientRuntime,
    include_expired: bool,
) -> crate::error::Result<crate::domain::JudgeAssignmentsDiagnostics> {
    let state = runtime.feature_state();
    let generation = state.judge.generation();
    let courses = get_courses_cached(runtime, &state, generation).await?;
    let course_count = courses.len();
    let skipped = if include_expired {
        HashSet::new()
    } else {
        state.judge.historical_courses(generation)
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
        let state = Arc::clone(&state);
        let cutoff = cutoff.clone();
        let limiter = Arc::clone(&limiter);
        workers.spawn(async move {
            let permit = limiter.acquire_owned().await.map_err(|_| worker_error())?;
            let result = summarize_course(
                &mut worker,
                &state,
                generation,
                course,
                include_expired,
                &cutoff,
            )
            .await;
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
                while workers.join_next().await.is_some() {}
                return Err(error);
            }
            Err(_) => {
                workers.abort_all();
                while workers.join_next().await.is_some() {}
                return Err(worker_error());
            }
        }
    }

    summaries.sort_by_key(|(index, _)| *index);
    let mut result = Vec::new();
    let mut raw_anchor_count = 0usize;
    let mut filtered_unique_count = 0usize;
    for (_, summary) in summaries {
        raw_anchor_count = raw_anchor_count.saturating_add(summary.raw_anchor_count);
        filtered_unique_count = filtered_unique_count.saturating_add(summary.filtered_unique_count);
        if summary.historical {
            state
                .judge
                .mark_historical(generation, &summary.course_id, Instant::now());
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
    Ok(crate::domain::JudgeAssignmentsDiagnostics {
        course_count,
        raw_anchor_count,
        filtered_unique_count,
        summaries: result,
    })
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
    get_assignment_details(
        runtime,
        &[crate::domain::JudgeAssignmentKey {
            course_id: course_id.into(),
            assignment_id: assignment_id.into(),
        }],
    )
    .await?
    .into_iter()
    .next()
    .ok_or_else(not_found)
}

/// Fetch multiple Judge details, preserving input order and rejecting empty input.
pub(crate) async fn get_assignment_details(
    runtime: &mut crate::runtime::ClientRuntime,
    keys: &[crate::domain::JudgeAssignmentKey],
) -> crate::error::Result<Vec<JudgeAssignmentDetail>> {
    let result = get_assignment_details_inner(runtime, keys).await;
    resolve_required_judge_result(runtime, result).await
}

async fn get_assignment_details_inner(
    runtime: &mut crate::runtime::ClientRuntime,
    keys: &[crate::domain::JudgeAssignmentKey],
) -> crate::error::Result<Vec<JudgeAssignmentDetail>> {
    super::require_session(runtime)?;
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

    let state = runtime.feature_state();
    let generation = state.judge.generation();
    let courses = get_courses_cached(runtime, &state, generation).await?;
    let courses_by_id = courses
        .into_iter()
        .map(|course| (course.course_id.clone(), course))
        .collect::<HashMap<_, _>>();
    for key in &normalized {
        if !courses_by_id.contains_key(&key.course_id) {
            return Err(not_found());
        }
    }

    let mut grouped = Vec::<(Course, Vec<(usize, crate::domain::JudgeAssignmentKey)>)>::new();
    let mut group_indexes = HashMap::<String, usize>::new();
    for (index, key) in normalized.into_iter().enumerate() {
        let group_index = if let Some(index) = group_indexes.get(&key.course_id) {
            *index
        } else {
            let index = grouped.len();
            let course = courses_by_id
                .get(&key.course_id)
                .expect("courses were validated before grouping")
                .clone();
            grouped.push((course, Vec::new()));
            group_indexes.insert(key.course_id.clone(), index);
            index
        };
        grouped[group_index].1.push((index, key));
    }

    let limiter = Arc::new(Semaphore::new(ASSIGNMENT_QUERY_CONCURRENCY));
    let mut workers = JoinSet::new();
    for (course, course_keys) in grouped {
        let mut worker = fork_judge_worker(runtime);
        let state = Arc::clone(&state);
        let limiter = Arc::clone(&limiter);
        workers.spawn(async move {
            let first_index = course_keys[0].0;
            let permit = limiter
                .acquire_owned()
                .await
                .map_err(|_| (first_index, worker_error()))?;
            let result =
                fetch_course_details(&mut worker, &state, generation, &course, course_keys).await;
            drop(permit);
            result
        });
    }

    let mut ordered = Vec::new();
    let mut failures = Vec::new();
    while let Some(joined) = workers.join_next().await {
        match joined {
            Ok(Ok(details)) => ordered.extend(details),
            Ok(Err(failure)) => failures.push(failure),
            Err(_) => {
                workers.abort_all();
                while workers.join_next().await.is_some() {}
                return Err(worker_error());
            }
        }
    }
    if let Some((_, error)) = failures.into_iter().min_by_key(|(index, _)| *index) {
        return Err(error);
    }
    ordered.sort_by_key(|(index, _)| *index);
    let result = ordered.into_iter().map(|(_, detail)| detail).collect();
    Ok(result)
}

async fn fetch_course_details(
    runtime: &mut crate::runtime::ClientRuntime,
    state: &crate::features::state::RouteFeatureState,
    generation: u64,
    course: &Course,
    keys: Vec<(usize, crate::domain::JudgeAssignmentKey)>,
) -> Result<Vec<(usize, JudgeAssignmentDetail)>, (usize, crate::error::UbaaError)> {
    let first_index = keys[0].0;
    let mut activated = false;
    let assignments =
        get_course_assignments_cached(runtime, state, generation, course, &mut activated)
            .await
            .map_err(|error| (first_index, error))?
            .assignments
            .into_iter()
            .map(|assignment| (assignment.assignment_id.clone(), assignment))
            .collect::<HashMap<_, _>>();
    let mut details = Vec::with_capacity(keys.len());
    for (index, key) in keys {
        let assignment = assignments
            .get(&key.assignment_id)
            .ok_or_else(|| (index, not_found()))?;
        let detail = get_detail_cached(runtime, state, generation, assignment, &mut activated)
            .await
            .map_err(|error| (index, error))?;
        details.push((index, detail));
    }
    Ok(details)
}

struct CourseSummary {
    course_id: String,
    summaries: Vec<JudgeAssignmentSummary>,
    raw_anchor_count: usize,
    filtered_unique_count: usize,
    historical: bool,
}

async fn resolve_required_judge_result<T>(
    runtime: &mut crate::runtime::ClientRuntime,
    result: crate::error::Result<T>,
) -> crate::error::Result<T> {
    match result {
        Err(error) if is_authentication_error(&error) && runtime.has_local_session() => {
            resolve_judge_business_authentication_failure(runtime).await
        }
        result => result,
    }
}

async fn resolve_judge_business_authentication_failure<T>(
    runtime: &mut crate::runtime::ClientRuntime,
) -> crate::error::Result<T> {
    let mut preserve_primary_workflow = || {};
    match crate::features::user::validate_status(runtime, &mut preserve_primary_workflow).await {
        Err(error) if is_authentication_error(&error) => Err(error),
        Err(error) if error.code == crate::error::ErrorCode::InternalError => Err(error),
        Ok(_) | Err(_) => Err(judge_business_authentication_error()),
    }
}

async fn summarize_course(
    runtime: &mut crate::runtime::ClientRuntime,
    state: &crate::features::state::RouteFeatureState,
    generation: u64,
    course: Course,
    include_expired: bool,
    cutoff: &str,
) -> crate::error::Result<CourseSummary> {
    let mut activated = false;
    let assignment_list =
        get_course_assignments_cached(runtime, state, generation, &course, &mut activated).await?;
    let raw_anchor_count = assignment_list.raw_anchor_count;
    let filtered_unique_count = assignment_list.filtered_unique_count();
    let mut summaries = Vec::new();
    let mut historical = false;
    for assignment in assignment_list.assignments {
        let detail =
            get_detail_cached(runtime, state, generation, &assignment, &mut activated).await?;
        if detail
            .start_time
            .as_deref()
            .is_some_and(|start| started_before_cutoff(start, cutoff))
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
        raw_anchor_count,
        filtered_unique_count,
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

fn judge_business_authentication_error() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamUnavailable,
        crate::error::ErrorKind::Upstream,
        true,
        "Judge business authentication failed without explicit primary-session invalidation",
    )
}

fn is_authentication_error(error: &crate::error::UbaaError) -> bool {
    error.code == crate::error::ErrorCode::AuthenticationRequired
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
    state: &crate::features::state::RouteFeatureState,
    generation: u64,
) -> crate::error::Result<Vec<Course>> {
    if let Some(courses) = state.judge.courses(generation, Instant::now(), LIST_TTL) {
        return Ok(courses);
    }
    activate(runtime).await?;
    let mut url =
        url::Url::parse(&format!("{BASE_URL}/courselist.jsp")).map_err(|_| invalid_url())?;
    url.query_pairs_mut().append_pair("courseID", "0");
    let response = get_html(runtime, runtime.url(url.as_str())?).await?;
    let courses = parse_courses(&super::body(&response));
    state
        .judge
        .store_courses(generation, courses.clone(), Instant::now());
    Ok(courses)
}

async fn get_course_assignments_cached(
    runtime: &mut crate::runtime::ClientRuntime,
    state: &crate::features::state::RouteFeatureState,
    generation: u64,
    course: &Course,
    activated: &mut bool,
) -> crate::error::Result<AssignmentList> {
    if let Some(assignments) =
        state
            .judge
            .assignments(generation, &course.course_id, Instant::now(), LIST_TTL)
    {
        return Ok(assignments);
    }
    ensure_worker_activated(runtime, activated).await?;
    let mut select_url =
        url::Url::parse(&format!("{BASE_URL}/courselist.jsp")).map_err(|_| invalid_url())?;
    select_url
        .query_pairs_mut()
        .append_pair("courseID", &course.course_id);
    get_html(runtime, runtime.url(select_url.as_str())?).await?;
    let index_url = runtime.url(&format!("{BASE_URL}/assignment/index.jsp"))?;
    let response = get_html(runtime, index_url).await?;
    let assignments = parse_assignment_list(&super::body(&response), course);
    state.judge.store_assignments(
        generation,
        &course.course_id,
        assignments.clone(),
        Instant::now(),
    );
    Ok(assignments)
}

async fn get_detail_cached(
    runtime: &mut crate::runtime::ClientRuntime,
    state: &crate::features::state::RouteFeatureState,
    generation: u64,
    assignment: &Assignment,
    activated: &mut bool,
) -> crate::error::Result<JudgeAssignmentDetail> {
    if let Some(detail) = state.judge.detail(
        generation,
        &assignment.course_id,
        &assignment.assignment_id,
        Instant::now(),
        DETAIL_TTL,
    ) {
        return Ok(detail);
    }
    ensure_worker_activated(runtime, activated).await?;
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
    state.judge.store_detail(
        generation,
        &assignment.course_id,
        &assignment.assignment_id,
        detail.clone(),
        Instant::now(),
    );
    Ok(detail)
}

async fn ensure_worker_activated(
    runtime: &mut crate::runtime::ClientRuntime,
    activated: &mut bool,
) -> crate::error::Result<()> {
    if !*activated {
        activate(runtime).await?;
        *activated = true;
    }
    Ok(())
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
    for reactivations in 0..=BUSINESS_REACTIVATION_LIMIT {
        let checked =
            match super::get_with_redirects(runtime, url.clone(), judge_headers(), "judge").await {
                Ok(response) => super::check_response(&response, "judge").map(|()| response),
                Err(error) => Err(error),
            };
        match checked {
            Ok(response) => return Ok(response),
            Err(error)
                if error.code == crate::error::ErrorCode::AuthenticationRequired
                    && reactivations < BUSINESS_REACTIVATION_LIMIT =>
            {
                activate(runtime).await?;
            }
            Err(error) => return Err(error),
        }
    }
    unreachable!("the bounded Judge retry loop always returns")
}

fn six_month_cutoff() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
        + 8 * 60 * 60;
    let days = i64::try_from(seconds / 86_400).unwrap_or(i64::MAX);
    let seconds_of_day = seconds % 86_400;
    let hour = seconds_of_day / 3_600;
    let minute = seconds_of_day % 3_600 / 60;
    let second = seconds_of_day % 60;
    let (year, month, day) = civil_date(days);
    six_month_cutoff_from_shanghai(&format!(
        "{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}"
    ))
    .expect("the current Shanghai date is valid")
}

fn six_month_cutoff_from_shanghai(value: &str) -> Option<String> {
    let (mut year, mut month, day, hour, minute, second) = parse_judge_datetime(value)?;
    if month <= 6 {
        year -= 1;
        month += 6;
    } else {
        month -= 6;
    }
    let target_day = day.min(days_in_month(year, month));
    Some(format!(
        "{year:04}-{month:02}-{target_day:02} {hour:02}:{minute:02}:{second:02}"
    ))
}

fn started_before_cutoff(start: &str, cutoff: &str) -> bool {
    parse_judge_datetime(start)
        .zip(parse_judge_datetime(cutoff))
        .is_some_and(|(start, cutoff)| start < cutoff)
}

fn parse_judge_datetime(value: &str) -> Option<(i64, i64, i64, i64, i64, i64)> {
    let capture = regex::Regex::new(r"^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$")
        .expect("static Judge datetime regex")
        .captures(value)?;
    let year = capture.get(1)?.as_str().parse::<i64>().ok()?;
    let month = capture.get(2)?.as_str().parse::<i64>().ok()?;
    let day = capture.get(3)?.as_str().parse::<i64>().ok()?;
    let hour = capture.get(4)?.as_str().parse::<i64>().ok()?;
    let minute = capture.get(5)?.as_str().parse::<i64>().ok()?;
    let second = capture.get(6)?.as_str().parse::<i64>().ok()?;
    if !(1..=12).contains(&month)
        || !(1..=days_in_month(year, month)).contains(&day)
        || !(0..=23).contains(&hour)
        || !(0..=59).contains(&minute)
        || !(0..=59).contains(&second)
    {
        return None;
    }
    Some((year, month, day, hour, minute, second))
}

fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => unreachable!("month is validated before calculating its length"),
    }
}

fn is_leap_year(year: i64) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
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
        r"作业时间[：:]\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)\s*至\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)",
    )
    .expect("static Judge date regex");
    let Some(capture) = regex.captures(text) else {
        return (None, None);
    };
    (
        capture
            .get(1)
            .map(|value| normalize_datetime(value.as_str())),
        capture
            .get(2)
            .map(|value| normalize_datetime(value.as_str())),
    )
}

fn normalize_datetime(value: &str) -> String {
    if value.matches(':').count() == 1 {
        format!("{value}:00")
    } else {
        value.to_string()
    }
}

struct ParsedProblem {
    problem: JudgeProblem,
    earned_score: Option<f64>,
}

fn parse_problems(document: &Html) -> Vec<ParsedProblem> {
    let table_selector = selector("table");
    let row_selector = selector("tr");
    let mut problems = Vec::new();
    for table in document.select(&table_selector).filter(|table| {
        !table
            .ancestors()
            .filter_map(ElementRef::wrap)
            .any(|ancestor| ancestor.value().name() == "table")
    }) {
        for row in table
            .select(&row_selector)
            .filter(|row| nearest_ancestor_table(*row).is_some_and(|owner| owner == table))
        {
            let cells = row
                .child_elements()
                .filter(|cell| matches!(cell.value().name(), "th" | "td"))
                .map(|cell| element_text(cell, Some(table)))
                .collect::<Vec<_>>();
            if let Some(problem) = parse_problem_from_cells(&cells) {
                problems.push(problem);
            }
        }
    }
    problems
}

fn nearest_ancestor_table(element: ElementRef<'_>) -> Option<ElementRef<'_>> {
    element
        .ancestors()
        .filter_map(ElementRef::wrap)
        .find(|ancestor| ancestor.value().name() == "table")
}

fn parse_problem_from_cells(cells: &[String]) -> Option<ParsedProblem> {
    if cells.len() >= 4 {
        let max_score = parse_number(&cells[2])?;
        let status_text = cells[3..].join(" ");
        let status = detect_problem_status(&status_text)?;
        let earned_score = parse_earned_score(&status_text);
        let score = earned_score
            .or((status == JudgeSubmissionStatus::Submitted).then_some(max_score))
            .map(format_score);
        return Some(ParsedProblem {
            problem: JudgeProblem {
                name: cells[1].clone(),
                score,
                max_score: Some(format_score(max_score)),
                status,
                status_text: problem_status_text(status).into(),
            },
            earned_score,
        });
    }

    if cells.len() == 2 {
        let status = detect_problem_status(&cells[1])?;
        let earned_score = parse_earned_score(&cells[1]);
        let index = cells[0].trim().trim_end_matches('.');
        return Some(ParsedProblem {
            problem: JudgeProblem {
                name: if index.is_empty() {
                    "题目".into()
                } else {
                    format!("第{index}题")
                },
                score: earned_score.map(format_score),
                max_score: earned_score.map(format_score),
                status,
                status_text: problem_status_text(status).into(),
            },
            earned_score,
        });
    }

    None
}

fn estimate_submitted_count(text: &str) -> i32 {
    let first_section = ["填空题", "编程题", "文件上传题"]
        .iter()
        .filter_map(|section| text.find(section))
        .min()
        .unwrap_or(text.len());
    let choice_count = count_matches(&text[..first_section], r"得分[：:]\s*[\d.]+");

    let fill_answer_count = text.find("填空题").map_or(0, |start| {
        let after_heading = start + "填空题".len();
        let next_section = ["编程题", "文件上传题"]
            .iter()
            .filter_map(|section| {
                text[after_heading..]
                    .find(section)
                    .map(|offset| after_heading + offset)
            })
            .min()
            .unwrap_or(text.len());
        count_matches(&text[start..next_section], r"得分[：:]\s*[\d.]+")
    });
    let programming_count = text.find("编程题").map_or(0, |start| {
        count_matches(&text[start..], r"最后一次提交时间")
    });
    let file_upload_count = text
        .find("文件上传题")
        .map_or(0, |start| count_matches(&text[start..], r"初次提交时间"));
    i32::try_from(choice_count + fill_answer_count + programming_count + file_upload_count)
        .unwrap_or(i32::MAX)
}

fn count_matches(text: &str, pattern: &str) -> usize {
    regex::Regex::new(pattern)
        .expect("static Judge fallback regex")
        .find_iter(text)
        .count()
}

fn detect_problem_status(text: &str) -> Option<JudgeSubmissionStatus> {
    const UNSUBMITTED: &[&str] = &[
        "还未提交代码",
        "未提交文件",
        "未提交答案",
        "未作答",
        "未提交",
    ];
    const SUBMITTED: &[&str] = &[
        "初次提交时间",
        "首次提交时间",
        "最近一次提交时间",
        "最后一次提交时间",
        "最后一次修改时间",
        "已提交",
        "得分",
        "Accepted",
        "Accept",
    ];
    let normalized = normalize_text(text);
    if UNSUBMITTED.iter().any(|marker| normalized.contains(marker)) {
        return Some(JudgeSubmissionStatus::Unsubmitted);
    }
    let lowercase = normalized.to_lowercase();
    SUBMITTED
        .iter()
        .any(|marker| lowercase.contains(&marker.to_lowercase()))
        .then_some(JudgeSubmissionStatus::Submitted)
}

fn resolve_status(total_problems: i32, submitted_count: i32) -> JudgeSubmissionStatus {
    if total_problems <= 0 {
        JudgeSubmissionStatus::Unknown
    } else if submitted_count <= 0 {
        JudgeSubmissionStatus::Unsubmitted
    } else if submitted_count < total_problems {
        JudgeSubmissionStatus::Partial
    } else {
        JudgeSubmissionStatus::Submitted
    }
}

fn submission_status_text(
    status: JudgeSubmissionStatus,
    submitted_count: i32,
    total_problems: i32,
    my_score: Option<&str>,
    max_score: Option<&str>,
) -> String {
    match status {
        JudgeSubmissionStatus::Submitted => match (my_score, max_score) {
            (Some(my_score), Some(max_score)) if !my_score.is_empty() && !max_score.is_empty() => {
                format!("已完成 {my_score}/{max_score}")
            }
            _ => "已完成".into(),
        },
        JudgeSubmissionStatus::Partial => {
            format!("进行中({submitted_count}/{total_problems})")
        }
        JudgeSubmissionStatus::Unsubmitted => "未提交".into(),
        JudgeSubmissionStatus::Unknown => "未知状态".into(),
    }
}

fn problem_status_text(status: JudgeSubmissionStatus) -> &'static str {
    match status {
        JudgeSubmissionStatus::Submitted => "已提交",
        JudgeSubmissionStatus::Partial => "部分提交",
        JudgeSubmissionStatus::Unsubmitted => "未提交",
        JudgeSubmissionStatus::Unknown => "未知状态",
    }
}

fn parse_number(value: &str) -> Option<f64> {
    let value = normalize_text(value);
    regex::Regex::new(r"^\d+(?:\.\d+)?$")
        .expect("static Judge numeric regex")
        .is_match(&value)
        .then(|| value.parse().ok())
        .flatten()
}

fn parse_earned_score(value: &str) -> Option<f64> {
    capture_number(&normalize_text(value), r"得分[：:]\s*([\d.]+)")?
        .parse()
        .ok()
}

fn normalize_score(value: Option<&str>) -> Option<String> {
    value.map(|value| {
        value
            .parse::<f64>()
            .map_or_else(|_| value.to_string(), format_score)
    })
}

fn format_score(value: f64) -> String {
    if value.fract() == 0.0 {
        format!("{value:.0}")
    } else {
        value.to_string()
    }
}

fn selector(query: &str) -> Selector {
    Selector::parse(query).expect("static Judge selector")
}

fn element_text(element: ElementRef<'_>, owning_table: Option<ElementRef<'_>>) -> String {
    let mut pieces = Vec::new();
    for node in element.descendants() {
        let Some(text) = node.value().as_text() else {
            continue;
        };
        let allowed = node
            .ancestors()
            .take_while(|ancestor| ancestor.id() != element.id())
            .filter_map(ElementRef::wrap)
            .all(|ancestor| match ancestor.value().name() {
                "script" | "style" => false,
                "table" => owning_table.is_none() || owning_table == Some(ancestor),
                _ => true,
            });
        if allowed {
            pieces.push(text.to_string());
        }
    }
    normalize_text(&pieces.join(" "))
}

fn normalize_text(value: &str) -> String {
    value
        .replace('\u{00a0}', " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture_course() -> Course {
        Course {
            course_id: "12".into(),
            course_name: "Fixture Course".into(),
        }
    }

    #[test]
    fn assignments_filter_internal_links_before_deduplication() {
        let parsed = parse_assignment_list(
            r#"
            <a href="problemContent.jsp?assignID=7">Internal problem</a>
            <a href="assignment/index.jsp?assignID=7">Fixture &amp; Review</a>
            <a href="judgeDetails.jsp?assignID=8">Internal details</a>
            <a href="assignment/index.jsp?assignID=8">Second task</a>
            <a href="assignment/index.jsp?ASSIGNid=9">Case insensitive task</a>
            <a href="assignment/index.jsp?assignID=not-a-number">Invalid task</a>
            "#,
            &fixture_course(),
        );

        assert_eq!(parsed.raw_anchor_count, 5);
        assert_eq!(parsed.filtered_unique_count(), 3);
        assert_eq!(
            parsed
                .assignments
                .iter()
                .map(|assignment| (assignment.assignment_id.as_str(), assignment.title.as_str()))
                .collect::<Vec<_>>(),
            vec![
                ("7", "Fixture & Review"),
                ("8", "Second task"),
                ("9", "Case insensitive task")
            ]
        );
    }

    #[test]
    fn assignments_keep_raw_count_when_every_numeric_anchor_is_filtered() {
        let parsed = parse_assignment_list(
            r#"
            <a href="problemContent.jsp?assignID=7">Internal problem</a>
            <a href="judgeDetails.jsp?assignID=8">Internal details</a>
            <a href="assignment/index.jsp?assignID=9"><span> </span></a>
            "#,
            &fixture_course(),
        );

        assert_eq!(parsed.raw_anchor_count, 3);
        assert_eq!(parsed.filtered_unique_count(), 0);
        assert!(parsed.assignments.is_empty());
    }

    #[test]
    fn detail_parses_four_cell_rows_without_nested_table_or_script_noise() {
        let detail = parse_detail(
            r#"
            <html>
              <head>
              </head>
              <body>
                <style>.score::after { content: "总分：999"; }</style>
                <script>const fake = "作业满分：999 总分：999";</script>
                作业时间：2026-04-20 19:00 至 2026-05-03 23:00
                作业满分：20.00，共 2 道题
                <table>
                  <thead><tr><th>#</th><th>题目</th><th>分值</th><th>状态</th></tr></thead>
                  <tbody>
                    <tr>
                      <th>1.</th><td>程序 &amp; 设计</td><td>10.00</td>
                      <td>最后一次提交时间：2026-04-17 12:00:00 得分：8.00
                        <table>
                          <tr><th>name</th><th>verdict</th></tr>
                          <tr><td>TestCase1</td><td>Accept</td></tr>
                        </table>
                      </td>
                    </tr>
                    <tr><th>2.</th><td>报告</td><td>10.00</td><td>未提交答案</td></tr>
                  </tbody>
                </table>
              </body>
            </html>
            "#,
            "12",
            "Fixture Course",
            "7",
            "Fixture Task",
        )
        .unwrap();

        assert_eq!(detail.start_time.as_deref(), Some("2026-04-20 19:00:00"));
        assert_eq!(detail.due_time.as_deref(), Some("2026-05-03 23:00:00"));
        assert_eq!(detail.max_score.as_deref(), Some("20"));
        assert_eq!(detail.my_score.as_deref(), Some("8"));
        assert_eq!(detail.total_problems, 2);
        assert_eq!(detail.submitted_count, 1);
        assert_eq!(detail.submission_status, JudgeSubmissionStatus::Partial);
        assert_eq!(detail.submission_status_text, "进行中(1/2)");
        assert_eq!(detail.problems.len(), 2);
        assert_eq!(detail.problems[0].name, "程序 & 设计");
        assert_eq!(detail.problems[0].score.as_deref(), Some("8"));
        assert_eq!(detail.problems[0].max_score.as_deref(), Some("10"));
        assert_eq!(detail.problems[0].status, JudgeSubmissionStatus::Submitted);
        assert_eq!(
            detail.problems[1].status,
            JudgeSubmissionStatus::Unsubmitted
        );
        let content = detail.content_plain_text.as_deref().unwrap();
        assert!(content.contains("程序 & 设计"));
        assert!(content.contains("TestCase1"));
        assert!(!content.contains("const fake"));
        assert!(!content.contains("content:"));
    }

    #[test]
    fn detail_parses_two_cell_rows_and_normalizes_scores() {
        let detail = parse_detail(
            r"
            作业满分：2.00，共 2 道题
            <table><tbody>
              <tr><th>1.</th><td>已提交 最后一次提交时间：2026-04-14 19:38:39 题干 得分：1.00</td></tr>
              <tr><th>2.</th><td>未作答 题干</td></tr>
            </tbody></table>
            ",
            "12",
            "Fixture Course",
            "8",
            "Choice Task",
        )
        .unwrap();

        assert_eq!(detail.max_score.as_deref(), Some("2"));
        assert_eq!(detail.my_score.as_deref(), Some("1"));
        assert_eq!(detail.submission_status, JudgeSubmissionStatus::Partial);
        assert_eq!(
            detail
                .problems
                .iter()
                .map(|problem| problem.name.as_str())
                .collect::<Vec<_>>(),
            vec!["第1题", "第2题"]
        );
        assert_eq!(detail.problems[0].max_score.as_deref(), Some("1"));
        assert_eq!(detail.problems[1].max_score, None);
    }

    #[test]
    fn detail_uses_frozen_fallback_and_status_rules() {
        let partial = parse_detail(
            "作业满分：4，共 4 道题 选择题 得分：1 填空题 得分：1 编程题 最后一次提交时间：2026-01-01 12:00:00",
            "12",
            "Fixture Course",
            "9",
            "Fallback Task",
        )
        .unwrap();
        assert_eq!(partial.submitted_count, 3);
        assert_eq!(partial.submission_status, JudgeSubmissionStatus::Partial);
        assert_eq!(partial.submission_status_text, "进行中(3/4)");

        let unknown = parse_detail(
            "<p>No verified assignment fields</p>",
            "12",
            "Fixture Course",
            "10",
            "Unknown",
        )
        .unwrap();
        assert_eq!(unknown.total_problems, 0);
        assert_eq!(unknown.submission_status, JudgeSubmissionStatus::Unknown);
        assert_eq!(unknown.submission_status_text, "未知状态");
    }

    #[test]
    fn detail_prefers_explicit_score_and_resolves_terminal_statuses() {
        let submitted = parse_detail(
            r"
            作业满分：10.00，共 1 道题，总分：7.00
            <table><tbody>
              <tr><th>1.</th><td>Fixture</td><td>10.00</td><td>已提交 得分：8.00</td></tr>
            </tbody></table>
            ",
            "12",
            "Fixture Course",
            "11",
            "Submitted",
        )
        .unwrap();
        assert_eq!(submitted.my_score.as_deref(), Some("7"));
        assert_eq!(submitted.max_score.as_deref(), Some("10"));
        assert_eq!(submitted.submitted_count, 1);
        assert_eq!(
            submitted.submission_status,
            JudgeSubmissionStatus::Submitted
        );
        assert_eq!(submitted.submission_status_text, "已完成 7.00/10.00");

        let unsubmitted = parse_detail(
            "作业满分：10，共 1 道题 未提交",
            "12",
            "Fixture Course",
            "12",
            "Unsubmitted",
        )
        .unwrap();
        assert_eq!(unsubmitted.submitted_count, 0);
        assert_eq!(
            unsubmitted.submission_status,
            JudgeSubmissionStatus::Unsubmitted
        );
        assert_eq!(unsubmitted.submission_status_text, "未提交");
    }

    #[test]
    fn six_month_cutoff_preserves_time_and_clamps_month_end() {
        assert_eq!(
            six_month_cutoff_from_shanghai("2024-08-31 12:34:56").as_deref(),
            Some("2024-02-29 12:34:56")
        );
        assert_eq!(
            six_month_cutoff_from_shanghai("2023-08-31 01:02:03").as_deref(),
            Some("2023-02-28 01:02:03")
        );
        assert_eq!(
            six_month_cutoff_from_shanghai("2026-03-31 23:59:58").as_deref(),
            Some("2025-09-30 23:59:58")
        );
        assert_eq!(six_month_cutoff_from_shanghai("invalid"), None);
    }

    #[test]
    fn historical_start_requires_a_valid_datetime_and_full_time_ordering() {
        let cutoff = "2026-02-24 12:34:56";

        assert!(!started_before_cutoff("0000-00-00 00:00:00", cutoff));
        assert!(!started_before_cutoff("2026-02-30 12:34:55", cutoff));
        assert!(!started_before_cutoff("2026-02-24 24:00:00", cutoff));
        assert!(started_before_cutoff("2026-02-24 12:34:55", cutoff));
        assert!(!started_before_cutoff("2026-02-24 12:34:56", cutoff));
    }
}
