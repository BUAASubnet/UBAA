//! Judge 服务激活、请求构造与路线状态缓存。

use std::time::{Duration, Instant};

use crate::domain::{Assignment, Course, JudgeAssignmentDetail};

use super::AssignmentList;
use super::parser::{parse_assignment_list, parse_courses, parse_detail};

/// 冻结实现中的 Judge 服务登录地址。
pub const LOGIN_URL: &str =
    "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F";
/// Judge 服务主机。
pub const BASE_URL: &str = "https://judge.buaa.edu.cn";

const LIST_TTL: Duration = Duration::from_mins(5);
const DETAIL_TTL: Duration = Duration::from_mins(2);
const BUSINESS_REACTIVATION_LIMIT: usize = 3;

async fn activate(runtime: &mut crate::runtime::ClientRuntime) -> crate::error::Result<()> {
    let response = crate::features::get_with_redirects(
        runtime,
        runtime.url(LOGIN_URL)?,
        judge_headers(),
        "judge",
    )
    .await?;
    crate::features::check_response(&response, "judge")
}

pub(super) async fn get_courses_cached(
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
    let courses = parse_courses(&crate::features::body(&response));
    state
        .judge
        .store_courses(generation, courses.clone(), Instant::now());
    Ok(courses)
}

pub(super) async fn get_course_assignments_cached(
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
    let assignments = parse_assignment_list(&crate::features::body(&response), course);
    state.judge.store_assignments(
        generation,
        &course.course_id,
        assignments.clone(),
        Instant::now(),
    );
    Ok(assignments)
}

pub(super) async fn get_detail_cached(
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
        &crate::features::body(&response),
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
        let checked = match crate::features::get_with_redirects(
            runtime,
            url.clone(),
            judge_headers(),
            "judge",
        )
        .await
        {
            Ok(response) => crate::features::check_response(&response, "judge").map(|()| response),
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

fn invalid_url() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "希冀地址无效",
    )
}
