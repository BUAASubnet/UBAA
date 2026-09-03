//! Judge 批量查询、worker 隔离、排序与错误仲裁。

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Instant;

use tokio::sync::Semaphore;
use tokio::task::JoinSet;

use crate::domain::{Course, JudgeAssignmentDetail, JudgeAssignmentSummary};

use super::calendar::{six_month_cutoff, started_before_cutoff};
use super::parser::to_summary;
use super::service::{get_course_assignments_cached, get_courses_cached, get_detail_cached};

const ASSIGNMENT_QUERY_CONCURRENCY: usize = 4;

/// 通过当前认证路线获取 Judge 作业链接。
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

/// 获取一项 Judge 作业详情。
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

/// 获取多项 Judge 详情，保持输入顺序并拒绝空输入。
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
    crate::features::require_session(runtime)?;
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
        "希冀读取任务失败",
    )
}

fn judge_business_authentication_error() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamUnavailable,
        crate::error::ErrorKind::Upstream,
        true,
        "希冀业务认证失败，但未明确要求使主会话失效",
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

fn not_found() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "未找到希冀作业",
    )
}
