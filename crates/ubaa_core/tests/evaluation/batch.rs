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

#[test]
fn 门控拒绝首门时保留错误而在提交一门后保留已确认结果() {
    for earlier in [false, true] {
        let mut scenario = two_courses();
        scenario.revise_replies = if earlier {
            vec![ReviseReply::Success, ReviseReply::UpdateRequired]
        } else {
            vec![ReviseReply::UpdateRequired]
        };
        let transport = EvaluationMock::new(scenario);
        let label = if earlier {
            "update-after-submit"
        } else {
            "update-before-submit"
        };
        let (mut client, root) = route_client(label, transport.clone());

        let result = runtime().block_on(client.evaluation_submit_courses(two_course_request()));
        if earlier {
            let result = result.unwrap().data;
            assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Success);
            assert_eq!(
                result.items[1].outcome,
                EvaluationCourseOutcome::Unattempted
            );
            assert!(!result.success);
            assert!(!result.outcome_unknown);
        } else {
            let error = result.unwrap_err();
            assert_eq!(error.code, ErrorCode::UpdateRequired);
            assert!(!error.retryable);
        }
        assert_eq!(
            count_path(&transport, "getQuestionnaireTopic"),
            usize::from(earlier)
        );
        assert_eq!(
            count_path(&transport, "submitSaveEvaluation"),
            usize::from(earlier)
        );
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 校园网提示按每门课程的最终提交边界停止批次() {
    use EvaluationCourseOutcome::{OutcomeUnknown, Success, Unattempted};
    for (topic, expected, topic_count, sent) in [
        (
            Some("course-1"),
            [Unattempted, Unattempted, Unattempted],
            1,
            0,
        ),
        (Some("course-2"), [Success, Unattempted, Unattempted], 2, 1),
        (None, [Success, OutcomeUnknown, Unattempted], 2, 2),
    ] {
        let mut scenario = two_courses();
        scenario.course_rounds[0].push(course_row("course-3", Some("teacher-3"), &json!(0)));
        scenario.campus_topic = topic.map(str::to_owned);
        scenario.final_replies = vec![FinalReply::Success, FinalReply::CampusOnly];
        let transport = EvaluationMock::new(scenario);
        let (mut client, root) = route_client("campus-batch", transport.clone());
        let mut request = two_course_request();
        request.targets.push(target("course-3", Some("teacher-3")));
        let result = runtime()
            .block_on(client.evaluation_submit_courses(request.clone()))
            .unwrap()
            .data;
        assert_eq!(
            result
                .items
                .iter()
                .map(|item| item.outcome)
                .collect::<Vec<_>>(),
            expected
        );
        for (item, target) in result.items.iter().zip(request.targets) {
            assert_eq!(item.target, target);
            if item.outcome != Success {
                assert!(item.message.contains("未尝试") || item.message.contains("结果未知"));
            }
        }
        assert_eq!(result.outcome_unknown, topic.is_none());
        assert_eq!(count_path(&transport, "getQuestionnaireTopic"), topic_count);
        assert_eq!(count_path(&transport, "submitSaveEvaluation"), sent);
        std::fs::remove_dir_all(root).unwrap();
    }
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
