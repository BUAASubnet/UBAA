use std::collections::BTreeMap;

use serde_json::{Value, json};
use ubaa_core::facade::{EvaluationCourseOutcome, EvaluationSubmitCoursesRequest};

use super::evaluation_support::{EvaluationMock, Scenario, route_client, runtime, target};

#[test]
fn direct_commit_uses_frozen_sequence_headers_query_and_envelope() {
    let transport = EvaluationMock::new(Scenario::one_course());
    let (mut client, root) = route_client("protocol", transport.clone());
    let result = runtime()
        .block_on(
            client.evaluation_submit_courses(EvaluationSubmitCoursesRequest {
                targets: vec![target("course-1", Some("teacher-1"))],
            }),
        )
        .unwrap()
        .data;

    assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Success);
    let requests = transport.requests();
    let paths = requests
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(
        paths,
        vec![
            "/pjxt/cas",
            "/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks",
            "/pjxt/evaluationMethodSix/getQuestionnaireListToTask",
            "/pjxt/evaluationMethodSix/getRequiredReviewsData",
            "/pjxt/evaluationMethodSix/reviseQuestionnairePattern",
            "/pjxt/evaluationMethodSix/getQuestionnaireTopic",
            "/pjxt/evaluationMethodSix/submitSaveEvaluation",
        ]
    );
    assert!(requests.iter().all(|request| {
        !request
            .headers
            .keys()
            .any(|name| name.eq_ignore_ascii_case("X-Requested-With"))
    }));

    assert_query(
        &requests[1],
        &[("yhdm", ""), ("pageNum", "1"), ("pageSize", "10")],
    );
    assert_query(&requests[2], &[("rwid", "task-1")]);
    assert_query(&requests[3], &[("wjid", "form-1")]);
    assert_eq!(
        serde_json::from_slice::<Value>(&requests[4].body).unwrap(),
        json!({"rwid":"task-1","wjid":"form-1","msid":"mode-1"})
    );
    assert_eq!(
        requests[4].headers.get("Content-Type").map(String::as_str),
        Some("application/json")
    );

    let topic_query = query(&requests[5]);
    assert_eq!(topic_query.len(), 21);
    assert_eq!(
        topic_query,
        BTreeMap::from([
            ("id".into(), String::new()),
            ("rwid".into(), "task-1".into()),
            ("wjid".into(), "form-1".into()),
            ("zdmc".into(), "STID".into()),
            ("ypjcs".into(), "0".into()),
            ("xypjcs".into(), "1".into()),
            ("sxz".into(), "student-kind".into()),
            ("pjrdm".into(), "reviewer-1".into()),
            ("pjrmc".into(), "评价人".into()),
            ("bpdm".into(), "teacher-1".into()),
            ("bpmc".into(), "教师 course-1".into()),
            ("kcdm".into(), "course-1".into()),
            ("kcmc".into(), "课程 course-1".into()),
            ("rwh".into(), "row-course-1".into()),
            ("xn".into(), "2026".into()),
            ("xq".into(), "1".into()),
            ("xnxq".into(), "2026-2027-1".into()),
            ("pjlxid".into(), "2".into()),
            ("sfksqbpj".into(), "1".into()),
            ("yxsfktjst".into(), "0".into()),
            ("yxdm".into(), String::new()),
        ])
    );

    assert_eq!(requests[6].headers.len(), 1);
    assert_eq!(
        requests[6].headers.get("Content-Type").map(String::as_str),
        Some("application/json")
    );
    let final_body: Value = serde_json::from_slice(&requests[6].body).unwrap();
    assert_eq!(final_body["pjidlist"], json!([]));
    assert_eq!(final_body["pjzt"], "1");
    assert_eq!(final_body["pjjglist"].as_array().unwrap().len(), 1);
    assert_eq!(final_body["pjjglist"][0]["pjdf"], 93);
    assert_eq!(final_body["pjjglist"][0]["rwh"], Value::Null);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn absent_bpdm_is_an_empty_topic_query_and_remains_part_of_the_typed_identity() {
    let mut scenario = Scenario::one_course();
    scenario.course_rounds = vec![vec![super::evaluation_support::course_row(
        "course-1",
        None,
        &json!(0),
    )]];
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("optional-bpdm", transport.clone());

    let result = runtime()
        .block_on(
            client.evaluation_submit_courses(EvaluationSubmitCoursesRequest {
                targets: vec![target("course-1", None)],
            }),
        )
        .unwrap()
        .data;

    assert_eq!(result.items[0].target.bpdm, None);
    assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Success);
    let requests = transport.requests();
    let topic = requests
        .iter()
        .find(|request| request.url.contains("getQuestionnaireTopic"))
        .unwrap();
    assert_eq!(query(topic).get("bpdm").map(String::as_str), Some(""));
    let final_request = requests
        .iter()
        .find(|request| request.url.contains("submitSaveEvaluation"))
        .unwrap();
    let body: Value = serde_json::from_slice(&final_request.body).unwrap();
    assert_eq!(body["pjjglist"][0]["bprdm"], "");
    let _ = std::fs::remove_dir_all(root);
}

fn assert_query(request: &ubaa_core::facade::testing::HttpRequest, pairs: &[(&str, &str)]) {
    assert_eq!(
        query(request),
        pairs
            .iter()
            .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
            .collect()
    );
}

fn query(request: &ubaa_core::facade::testing::HttpRequest) -> BTreeMap<String, String> {
    url::Url::parse(&request.url)
        .unwrap()
        .query_pairs()
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect()
}
