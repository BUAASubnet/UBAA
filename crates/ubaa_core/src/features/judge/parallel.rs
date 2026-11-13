//! 同课程详情复用父会话，整组收尾后才交还宿主。
use crate::{
    domain::{Assignment, JudgeAssignmentDetail},
    error::Result,
    runtime::ClientRuntime,
};

pub(crate) struct PreparedDetail {
    pub(crate) key: (String, String),
    route: crate::domain::ConnectionMode,
    result: Result<JudgeAssignmentDetail>,
    pub(crate) source_at: i64,
    failure_domain: Option<String>,
    reached_domains: std::collections::BTreeSet<String>,
}
impl PreparedDetail {
    pub(crate) fn from_index(
        detail: JudgeAssignmentDetail,
        route: crate::domain::ConnectionMode,
        source_at: i64,
    ) -> Self {
        Self {
            key: (detail.course_id.clone(), detail.assignment_id.clone()),
            route,
            result: Ok(detail),
            source_at,
            failure_domain: None,
            reached_domains: std::collections::BTreeSet::default(),
        }
    }
    pub(crate) fn matches(
        &self,
        route: crate::domain::ConnectionMode,
        assignment: &Assignment,
    ) -> bool {
        self.route == route
            && self.key.0 == assignment.course_id
            && self.key.1 == assignment.assignment_id
    }

    pub(crate) async fn finish(
        self,
        runtime: &mut ClientRuntime,
    ) -> super::scan::ScanRead<JudgeAssignmentDetail> {
        runtime.network_failure_domain = self.failure_domain;
        runtime.reached_domains = self.reached_domains;
        super::scan::finish(runtime, self.result).await
    }
}

/// 两条路线共用已选课程，只并发发送详情，不在子请求中认证或选课。
pub(crate) async fn read_same_course_details(
    runtime: &mut ClientRuntime,
    assignments: &[Assignment],
) -> Result<Vec<PreparedDetail>> {
    let responses = match request_same_course_details(runtime, assignments).await {
        Ok(responses) => responses,
        Err(error) => vec![Err(error); assignments.len()],
    };
    let state = runtime.feature_state();
    let mut results = Vec::with_capacity(assignments.len());
    for (assignment, response) in assignments.iter().zip(responses) {
        let checked = response.and_then(|response| {
            if (300..400).contains(&response.status) {
                return Err(crate::error::UbaaError::new(
                    crate::error::ErrorCode::AuthenticationRequired,
                    crate::error::ErrorKind::Authentication,
                    false,
                    "希冀详情需要串行处理重定向",
                ));
            }
            super::service::check_judge_response(&response)?;
            super::parse_detail(
                &crate::features::body(&response),
                &assignment.course_id,
                &assignment.course_name,
                &assignment.assignment_id,
                &assignment.title,
            )
        });
        let result = match checked {
            Err(error) if error.code == crate::error::ErrorCode::AuthenticationRequired => {
                // 全部并发请求已收尾，恢复流程才可改变共享选课状态。
                runtime.judge_selected_course = None;
                super::service::get_detail_cached(
                    runtime,
                    &state,
                    state.judge.generation(),
                    assignment,
                    &mut true,
                    true,
                )
                .await
            }
            other => other,
        };
        if let Ok(detail) = &result {
            state.judge.store_detail(
                state.judge.generation(),
                &assignment.course_id,
                &assignment.assignment_id,
                detail.clone(),
                std::time::Instant::now(),
            );
        } else {
            runtime.judge_selected_course = None;
        }
        results.push(PreparedDetail {
            key: (
                assignment.course_id.clone(),
                assignment.assignment_id.clone(),
            ),
            route: runtime.mode(),
            result,
            source_at: chrono::Utc::now().timestamp(),
            failure_domain: runtime.network_failure_domain.clone(),
            reached_domains: runtime.reached_domains.clone(),
        });
    }
    Ok(results)
}

async fn request_same_course_details(
    runtime: &mut ClientRuntime,
    assignments: &[Assignment],
) -> Result<Vec<Result<crate::ports::HttpResponse>>> {
    let Some(first) = assignments.first() else {
        return Ok(Vec::new());
    };
    super::service::select_course(runtime, &first.course_id).await?;
    let requests = assignments
        .iter()
        .map(|assignment| {
            let mut url = url::Url::parse(&format!("{}/assignment/index.jsp", super::BASE_URL))
                .expect("静态希冀地址有效");
            url.query_pairs_mut()
                .append_pair("assignID", &assignment.assignment_id);
            let mut request = crate::ports::HttpRequest::get(runtime.url(url.as_str())?);
            for (key, value) in super::service::judge_headers() {
                request.headers.insert((*key).into(), (*value).into());
            }
            Ok(request)
        })
        .collect::<Result<Vec<_>>>()?;
    runtime.reset_network_observation();
    runtime.request_judge_details(requests).await
}
