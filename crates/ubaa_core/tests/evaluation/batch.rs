use std::collections::HashSet;

use serde_json::json;
use ubaa_core::facade::{ErrorCode, EvaluationCourseOutcome, EvaluationSubmitCoursesRequest};

use super::evaluation_support::{
    EvaluationMock, FinalReply, ReviseReply, Scenario, course_row, route_client, runtime, target,
};

#[test]
fn deterministic_final_failure_continues_in_request_order() {
    let mut scenario = two_courses();
    scenario.final_replies = vec![FinalReply::Failure, FinalReply::Success];
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("failure-continues", transport.clone());

    let result = runtime()
        .block_on(client.evaluation_submit_courses(two_course_request()))
        .unwrap()
        .data;

    assert_eq!(
        result
            .items
            .iter()
            .map(|item| item.outcome)
            .collect::<Vec<_>>(),
        vec![
            EvaluationCourseOutcome::Failure,
            EvaluationCourseOutcome::Success
        ]
    );
    assert_eq!(result.items[0].message, "评教未提交，请刷新课程后重试");
    assert_eq!(result.items[1].message, "评教已提交");
    assert!(!result.success);
    assert!(!result.outcome_unknown);
    assert_eq!(count_path(&transport, "submitSaveEvaluation"), 2);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn topic_failure_is_a_course_failure_and_the_next_course_continues() {
    let mut scenario = two_courses();
    scenario.topic_failures = HashSet::from(["course-1".into()]);
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("topic-continues", transport.clone());

    let result = runtime()
        .block_on(client.evaluation_submit_courses(two_course_request()))
        .unwrap()
        .data;

    assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Failure);
    assert_eq!(result.items[1].outcome, EvaluationCourseOutcome::Success);
    assert_eq!(count_path(&transport, "submitSaveEvaluation"), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ambiguous_or_transport_final_stops_the_remaining_batch() {
    for (label, reply) in [
        ("ambiguous-stops", FinalReply::Ambiguous),
        ("transport-stops", FinalReply::TransportFailure),
    ] {
        let mut scenario = two_courses();
        scenario.final_replies = vec![reply];
        let transport = EvaluationMock::new(scenario);
        let (mut client, root) = route_client(label, transport.clone());

        let result = runtime()
            .block_on(client.evaluation_submit_courses(two_course_request()))
            .unwrap()
            .data;

        assert_eq!(
            result.items[0].outcome,
            EvaluationCourseOutcome::OutcomeUnknown
        );
        assert_eq!(
            result.items[1].outcome,
            EvaluationCourseOutcome::Unattempted
        );
        assert_eq!(
            result.items[0].message,
            "评教提交结果未知，请刷新课程后核对"
        );
        assert_eq!(result.items[1].message, "前序课程结果未知，本课程未尝试");
        assert!(!result.success);
        assert!(result.outcome_unknown);
        assert_eq!(count_path(&transport, "reviseQuestionnairePattern"), 1);
        assert_eq!(count_path(&transport, "submitSaveEvaluation"), 1);
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn revise_authentication_failure_aborts_the_batch_before_any_final() {
    let mut scenario = two_courses();
    scenario.revise_replies = vec![ReviseReply::AuthenticationFailure];
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("revise-auth", transport.clone());

    let error = runtime()
        .block_on(client.evaluation_submit_courses(two_course_request()))
        .expect_err("revise 认证失败必须传播并中止整批");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(count_path(&transport, "reviseQuestionnairePattern"), 1);
    assert_eq!(count_path(&transport, "getQuestionnaireTopic"), 0);
    assert_eq!(count_path(&transport, "submitSaveEvaluation"), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn authentication_after_an_earlier_success_still_aborts_without_a_second_final() {
    let mut scenario = two_courses();
    scenario.revise_replies = vec![ReviseReply::Success, ReviseReply::AuthenticationFailure];
    scenario.final_replies = vec![FinalReply::Success];
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("success-then-auth", transport.clone());

    let error = runtime()
        .block_on(client.evaluation_submit_courses(two_course_request()))
        .expect_err("先前 final 越界不能吞掉后续 fresh 认证失败");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(count_path(&transport, "reviseQuestionnairePattern"), 2);
    assert_eq!(count_path(&transport, "getQuestionnaireTopic"), 1);
    assert_eq!(count_path(&transport, "submitSaveEvaluation"), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn revise_non_authentication_failure_is_best_effort_and_continues() {
    let mut scenario = Scenario::one_course();
    scenario.revise_replies = vec![ReviseReply::NonAuthenticationFailure];
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("revise-best-effort", transport.clone());

    let result = runtime()
        .block_on(
            client.evaluation_submit_courses(EvaluationSubmitCoursesRequest {
                targets: vec![target("course-1", Some("teacher-1"))],
            }),
        )
        .unwrap()
        .data;

    assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Success);
    assert_eq!(count_path(&transport, "submitSaveEvaluation"), 1);
    let _ = std::fs::remove_dir_all(root);
}

fn two_courses() -> Scenario {
    let mut scenario = Scenario::one_course();
    scenario.course_rounds = vec![vec![
        course_row("course-1", Some("teacher-1"), &json!(0)),
        course_row("course-2", Some("teacher-2"), &json!(0)),
    ]];
    scenario.revise_replies = vec![ReviseReply::Success, ReviseReply::Success];
    scenario.final_replies = vec![FinalReply::Success, FinalReply::Success];
    scenario
}

fn two_course_request() -> EvaluationSubmitCoursesRequest {
    EvaluationSubmitCoursesRequest {
        targets: vec![
            target("course-1", Some("teacher-1")),
            target("course-2", Some("teacher-2")),
        ],
    }
}

fn count_path(transport: &EvaluationMock, suffix: &str) -> usize {
    transport
        .requests()
        .iter()
        .filter(|request| {
            url::Url::parse(&request.url)
                .unwrap()
                .path()
                .ends_with(suffix)
        })
        .count()
}
