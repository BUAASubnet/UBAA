use serde_json::json;
use ubaa_core::facade::{
    ActionEligibility, EvaluationCourseOutcome, EvaluationSubmitCoursesRequest,
};

use super::evaluation_support::{
    EvaluationMock, Scenario, course_row, route_client, runtime, target,
};

#[test]
fn preflight_and_commit_each_rebuild_the_complete_authority_chain() {
    let mut scenario = Scenario::one_course();
    scenario
        .course_rounds
        .push(vec![course_row("course-1", Some("teacher-1"), &json!(0))]);
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("double-fresh", transport.clone());
    let request = EvaluationSubmitCoursesRequest {
        targets: vec![target("course-1", Some("teacher-1"))],
    };
    let runtime = runtime();

    let preview = runtime
        .block_on(client.preflight_evaluation_submit_courses(&request))
        .unwrap()
        .data;
    let result = runtime
        .block_on(client.evaluation_submit_courses(request))
        .unwrap()
        .data;

    assert_eq!(preview.courses.len(), 1);
    assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Success);
    let paths = paths(&transport);
    assert_eq!(paths.iter().filter(|path| *path == "/pjxt/cas").count(), 2);
    assert_eq!(
        paths
            .iter()
            .filter(|path| path.ends_with("listObtainPersonnelEvaluationTasks"))
            .count(),
        2
    );
    assert_eq!(
        paths
            .iter()
            .filter(|path| path.ends_with("getQuestionnaireListToTask"))
            .count(),
        2
    );
    assert_eq!(
        paths
            .iter()
            .filter(|path| path.ends_with("getRequiredReviewsData"))
            .count(),
        2
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn commit_does_not_reuse_preflight_authority() {
    let mut scenario = Scenario::one_course();
    scenario
        .course_rounds
        .push(vec![course_row("course-1", Some("teacher-1"), &json!(1))]);
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("fresh-change", transport.clone());
    let request = EvaluationSubmitCoursesRequest {
        targets: vec![target("course-1", Some("teacher-1"))],
    };
    let runtime = runtime();

    runtime
        .block_on(client.preflight_evaluation_submit_courses(&request))
        .unwrap();
    let result = runtime
        .block_on(client.evaluation_submit_courses(request))
        .unwrap()
        .data;

    assert_eq!(result.items[0].outcome, EvaluationCourseOutcome::Failure);
    assert!(
        !paths(&transport)
            .iter()
            .any(|path| path.ends_with("submitSaveEvaluation"))
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn duplicate_identity_across_repeated_tasks_or_forms_is_unknown_for_every_row() {
    for (label, tasks, forms) in [("duplicate-task", 2, 1), ("duplicate-form", 1, 2)] {
        let mut scenario = Scenario::one_course();
        scenario.task_repetitions = tasks;
        scenario.form_repetitions = forms;
        let transport = EvaluationMock::new(scenario);
        let (mut client, root) = route_client(label, transport);

        let response = runtime().block_on(client.evaluation_all()).unwrap().data;

        assert!(response.courses.len() > 1);
        assert!(response.courses.iter().all(|course| {
            course.submit_eligibility == ActionEligibility::Unknown
                && course.submit_target.is_none()
        }));
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn a_course_row_that_conflicts_with_its_task_or_form_parent_is_unknown() {
    let mut conflicting = course_row("course-1", Some("teacher-1"), &json!(0));
    conflicting["rwid"] = json!("different-task");
    conflicting["wjid"] = json!("different-form");
    let mut scenario = Scenario::one_course();
    scenario.course_rounds = vec![vec![conflicting]];
    let transport = EvaluationMock::new(scenario);
    let (mut client, root) = route_client("parent-conflict", transport);

    let response = runtime().block_on(client.evaluation_all()).unwrap().data;

    assert_eq!(response.courses.len(), 1);
    assert_eq!(
        response.courses[0].submit_eligibility,
        ActionEligibility::Unknown
    );
    assert!(response.courses[0].submit_target.is_none());
    let _ = std::fs::remove_dir_all(root);
}

fn paths(transport: &EvaluationMock) -> Vec<String> {
    transport
        .requests()
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect()
}
