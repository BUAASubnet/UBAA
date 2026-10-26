//! 评教 typed preflight、fresh commit 与不可重放最终提交。

use std::collections::HashSet;

use rand::Rng;
use serde_json::{Map, Value};

use crate::domain::{
    EvaluationBatchResult, EvaluationCourseOutcome, EvaluationCourseResult,
    EvaluationSubmitCoursesRequest, EvaluationSubmitPreflight, EvaluationSubmitTarget,
};
use crate::error::{ErrorCode, Result};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

use super::parser::{EvaluationCourseAuthority, result_value};
use super::payload::{build_evaluation_payload, build_submit_body};
use super::read::read_authority;
use super::{
    REVISE_URL, SUBMIT_URL, TOPIC_URL, authority_error, invalid_input, is_authentication_error,
    upstream_error,
};

pub(crate) fn validate_submit_courses_request(
    request: &EvaluationSubmitCoursesRequest,
) -> Result<()> {
    if request.targets.is_empty() {
        return Err(invalid_input("评教提交目标不能为空"));
    }
    let mut unique = HashSet::new();
    for target in &request.targets {
        if [
            target.rwid.as_str(),
            target.wjid.as_str(),
            target.kcdm.as_str(),
        ]
        .into_iter()
        .any(|value| value.is_empty() || value != value.trim())
            || target
                .bpdm
                .as_deref()
                .is_some_and(|value| value.is_empty() || value != value.trim())
        {
            return Err(invalid_input("评教提交目标无效"));
        }
        if !unique.insert(target.clone()) {
            return Err(invalid_input("评教提交目标不能重复"));
        }
    }
    Ok(())
}

pub(crate) async fn preflight_submit_courses(
    runtime: &mut ClientRuntime,
    request: &EvaluationSubmitCoursesRequest,
) -> Result<EvaluationSubmitPreflight> {
    validate_submit_courses_request(request)?;
    let snapshot = read_authority(runtime, true).await?;
    let courses = request
        .targets
        .iter()
        .map(|target| {
            snapshot
                .unique_allowed(target)
                .map(|(course, _)| course.clone())
                .ok_or_else(authority_error)
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(EvaluationSubmitPreflight {
        targets: request.targets.clone(),
        courses,
    })
}

pub(crate) async fn submit_courses(
    runtime: &mut ClientRuntime,
    request: EvaluationSubmitCoursesRequest,
) -> Result<EvaluationBatchResult> {
    validate_submit_courses_request(&request)?;
    let snapshot = read_authority(runtime, true).await?;
    let mut items = Vec::with_capacity(request.targets.len());
    let mut stopped = false;

    for target in &request.targets {
        if stopped {
            items.push(course_result(
                target,
                snapshot.course_name_for(target),
                EvaluationCourseOutcome::Unattempted,
            ));
            continue;
        }
        let Some((course, authority)) = snapshot.unique_allowed(target) else {
            items.push(course_result(
                target,
                snapshot.course_name_for(target),
                EvaluationCourseOutcome::Failure,
            ));
            continue;
        };
        let course_name = course.kcmc.clone();
        let authority = authority.clone();
        let outcome = submit_one_course(runtime, &authority).await?;
        stopped = outcome == EvaluationCourseOutcome::OutcomeUnknown;
        items.push(course_result(target, Some(course_name), outcome));
    }

    let success = items
        .iter()
        .all(|item| item.outcome == EvaluationCourseOutcome::Success);
    let outcome_unknown = items
        .iter()
        .any(|item| item.outcome == EvaluationCourseOutcome::OutcomeUnknown);
    Ok(EvaluationBatchResult {
        items,
        success,
        outcome_unknown,
    })
}

async fn submit_one_course(
    runtime: &mut ClientRuntime,
    course: &EvaluationCourseAuthority,
) -> Result<EvaluationCourseOutcome> {
    revise_questionnaire_pattern(runtime, course).await?;
    let topic = match fetch_questionnaire_topic(runtime, course).await {
        Ok(topic) => topic,
        Err(error) if is_authentication_error(&error) => return Err(error),
        Err(_) => return Ok(EvaluationCourseOutcome::Failure),
    };
    let question_index = rand::thread_rng().r#gen::<usize>();
    let Ok(payload) = build_evaluation_payload(course, &topic, question_index) else {
        return Ok(EvaluationCourseOutcome::Failure);
    };
    Ok(submit_final(runtime, &payload).await)
}

async fn revise_questionnaire_pattern(
    runtime: &mut ClientRuntime,
    course: &EvaluationCourseAuthority,
) -> Result<()> {
    let body = serde_json::to_vec(&serde_json::json!({
        "rwid": course.target.rwid,
        "wjid": course.target.wjid,
        "msid": course.msid,
    }))
    .map_err(|_| upstream_error("评教模式切换正文无法编码"))?;
    let request = HttpRequest::post(runtime.url(REVISE_URL)?, body)
        .with_header("Content-Type", "application/json");
    let expected = request.url.clone();
    let result = async {
        let response = runtime.request(request).await?;
        super::super::check_response(&response, "评教")?;
        if response.final_url != expected {
            return Err(upstream_error("评教模式切换终点无效"));
        }
        Ok(())
    }
    .await;
    match result {
        Err(error) if is_authentication_error(&error) => Err(error),
        Err(_) | Ok(()) => Ok(()),
    }
}

async fn fetch_questionnaire_topic(
    runtime: &mut ClientRuntime,
    course: &EvaluationCourseAuthority,
) -> Result<Map<String, Value>> {
    let mut url = url::Url::parse(&runtime.url(TOPIC_URL)?)
        .map_err(|_| upstream_error("评教题目地址无效"))?;
    let params = [
        ("id", String::new()),
        ("rwid", course.target.rwid.clone()),
        ("wjid", course.target.wjid.clone()),
        ("zdmc", course.zdmc.clone()),
        ("ypjcs", course.ypjcs.to_string()),
        ("xypjcs", course.xypjcs.to_string()),
        ("sxz", course.sxz.clone()),
        ("pjrdm", course.pjrdm.clone()),
        ("pjrmc", course.pjrmc.clone()),
        ("bpdm", course.target.bpdm.clone().unwrap_or_default()),
        ("bpmc", course.teacher_name.clone()),
        ("kcdm", course.target.kcdm.clone()),
        ("kcmc", course.course_name.clone()),
        ("rwh", course.rwh.clone()),
        ("xn", course.xn.clone()),
        ("xq", course.xq.clone()),
        ("xnxq", course.xnxq.clone()),
        ("pjlxid", course.pjlxid.clone()),
        ("sfksqbpj", course.sfksqbpj.clone()),
        ("yxsfktjst", course.yxsfktjst.clone()),
        ("yxdm", String::new()),
    ];
    url.query_pairs_mut()
        .extend_pairs(params.iter().map(|(key, value)| (*key, value.as_str())));
    let expected = url.to_string();
    let response = runtime.request(HttpRequest::get(expected.clone())).await?;
    super::super::check_response(&response, "评教")?;
    if response.final_url != expected {
        return Err(upstream_error("评教题目终点无效"));
    }
    let result = result_value(&super::super::body(&response))?;
    let rows = result
        .as_array()
        .ok_or_else(|| upstream_error("评教题目结果结构无效"))?;
    if rows.len() != 1 {
        return Err(upstream_error("评教题目结果不唯一"));
    }
    rows[0]
        .as_object()
        .cloned()
        .ok_or_else(|| upstream_error("评教题目结果结构无效"))
}

async fn submit_final(runtime: &mut ClientRuntime, pjjglist: &[Value]) -> EvaluationCourseOutcome {
    let Ok(body) = build_submit_body(pjjglist) else {
        return EvaluationCourseOutcome::Failure;
    };
    let request = match runtime.url(SUBMIT_URL) {
        Ok(url) => HttpRequest::post(url, body).with_header("Content-Type", "application/json"),
        Err(_) => return EvaluationCourseOutcome::Failure,
    };
    let expected = request.url.clone();
    match runtime.request_non_idempotent(request).await {
        Ok(response) => classify_submit_response(&response, &expected),
        Err(error) if error.code == ErrorCode::OutcomeUnknown => {
            EvaluationCourseOutcome::OutcomeUnknown
        }
        Err(_) => EvaluationCourseOutcome::Failure,
    }
}

fn classify_submit_response(
    response: &HttpResponse,
    expected_url: &str,
) -> EvaluationCourseOutcome {
    if !(200..300).contains(&response.status) || response.final_url != expected_url {
        return EvaluationCourseOutcome::OutcomeUnknown;
    }
    let Ok(root) = serde_json::from_slice::<Value>(&response.body) else {
        return EvaluationCourseOutcome::OutcomeUnknown;
    };
    let Some(object) = root.as_object() else {
        return EvaluationCourseOutcome::OutcomeUnknown;
    };
    match object.get("code") {
        Some(Value::Number(value)) => match value.as_i64() {
            Some(0 | 200) => EvaluationCourseOutcome::Success,
            Some(_) => EvaluationCourseOutcome::Failure,
            None => EvaluationCourseOutcome::OutcomeUnknown,
        },
        Some(Value::String(value)) => {
            if matches!(value.to_ascii_lowercase().as_str(), "0" | "200" | "success") {
                EvaluationCourseOutcome::Success
            } else {
                EvaluationCourseOutcome::Failure
            }
        }
        _ => EvaluationCourseOutcome::OutcomeUnknown,
    }
}

fn course_result(
    target: &EvaluationSubmitTarget,
    course_name: Option<String>,
    outcome: EvaluationCourseOutcome,
) -> EvaluationCourseResult {
    let message = match outcome {
        EvaluationCourseOutcome::Success => "评教已提交",
        EvaluationCourseOutcome::Failure => "评教未提交，请刷新课程后重试",
        EvaluationCourseOutcome::OutcomeUnknown => "评教提交结果未知，请刷新课程后核对",
        EvaluationCourseOutcome::Unattempted => "前序课程结果未知，本课程未尝试",
    };
    EvaluationCourseResult {
        target: target.clone(),
        course_name: course_name.unwrap_or_else(|| "评教课程".into()),
        outcome,
        message: message.into(),
    }
}

#[cfg(test)]
pub(super) fn classify_submit_response_for_test(
    response: &HttpResponse,
    expected_url: &str,
) -> EvaluationCourseOutcome {
    classify_submit_response(response, expected_url)
}
