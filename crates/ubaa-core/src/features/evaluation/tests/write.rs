use super::super::write::classify_submit_response_for_test;
use crate::domain::EvaluationCourseOutcome;
use crate::ports::HttpResponse;

const FINAL_URL: &str = "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/submitSaveEvaluation";

#[test]
fn final_submit_accepts_only_the_committed_success_primitives() {
    for body in [
        r#"{"code":0}"#,
        r#"{"code":200}"#,
        r#"{"code":"0"}"#,
        r#"{"code":"200"}"#,
        r#"{"code":"success"}"#,
        r#"{"code":"SuCcEsS"}"#,
    ] {
        assert_eq!(
            classify(200, FINAL_URL, body),
            EvaluationCourseOutcome::Success
        );
    }
    for body in [r#"{"code":1}"#, r#"{"code":500}"#, r#"{"code":"failed"}"#] {
        assert_eq!(
            classify(200, FINAL_URL, body),
            EvaluationCourseOutcome::Failure
        );
    }
}

#[test]
fn final_submit_ambiguity_is_always_outcome_unknown() {
    for body in [
        "not-json",
        "[]",
        r#"{"message":"missing"}"#,
        r#"{"code":true}"#,
        r#"{"code":null}"#,
        r#"{"code":200.5}"#,
        r#"{"code":[]}"#,
        r#"{"code":{}}"#,
    ] {
        assert_eq!(
            classify(200, FINAL_URL, body),
            EvaluationCourseOutcome::OutcomeUnknown
        );
    }
    assert_eq!(
        classify(500, FINAL_URL, r#"{"code":200}"#),
        EvaluationCourseOutcome::OutcomeUnknown
    );
    assert_eq!(
        classify(
            200,
            "https://spoc.buaa.edu.cn/pjxt/login",
            r#"{"code":200}"#
        ),
        EvaluationCourseOutcome::OutcomeUnknown
    );
}

fn classify(status: u16, final_url: &str, body: &str) -> EvaluationCourseOutcome {
    classify_submit_response_for_test(
        &HttpResponse::new(status, final_url, body.as_bytes().to_vec()),
        FINAL_URL,
    )
}
