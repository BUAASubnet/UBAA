use super::super::parse_courses;
use super::super::parser::{CourseContext, EvaluationAuthoritySnapshot, parse_course_rows};
use crate::domain::{ActionEligibility, EvaluationCourseOutcome, EvaluationSubmitTarget};

#[test]
fn evaluation_success_envelope_preserves_pending_progress() {
    let body = complete_course_envelope(&[course_row(&serde_json::json!(0))]);
    let response = parse_courses(&body).expect("evaluation fixture should parse");
    assert_eq!(response.courses.len(), 1);
    assert_eq!(response.progress.pending_courses, 1);
}

#[test]
fn canonical_pending_course_exposes_typed_submit_target() {
    let body = complete_course_envelope(&[course_row(&serde_json::json!(0))]);
    let response = parse_courses(&body).expect("完整待评行应形成 typed target");
    let course = &response.courses[0];

    assert_eq!(course.submit_eligibility, ActionEligibility::Allowed);
    assert_eq!(
        course.submit_target,
        Some(EvaluationSubmitTarget {
            rwid: "task-1".into(),
            wjid: "form-1".into(),
            kcdm: "course-1".into(),
            bpdm: Some("teacher-1".into()),
        })
    );
}

#[test]
fn string_or_negative_evaluation_count_never_grants_submit_authority() {
    for ypjcs in [
        serde_json::Value::Null,
        serde_json::json!("0"),
        serde_json::json!(-1),
        serde_json::json!(0.5),
        serde_json::json!(false),
    ] {
        let body = complete_course_envelope(&[course_row(&ypjcs)]);
        let response = parse_courses(&body).expect("畸形状态仍应形成可展示的安全课程");
        let course = &response.courses[0];
        assert_eq!(course.submit_eligibility, ActionEligibility::Unknown);
        assert!(course.submit_target.is_none());
    }
}

#[test]
fn positive_canonical_evaluation_count_is_denied_and_evaluated() {
    let response = parse_courses(&complete_course_envelope(&[course_row(
        &serde_json::json!(1),
    )]))
    .unwrap();
    let course = &response.courses[0];

    assert!(course.is_evaluated);
    assert_eq!(course.submit_eligibility, ActionEligibility::Denied);
    assert!(course.submit_target.is_none());
}

#[test]
fn every_required_fresh_authority_field_fails_closed_when_missing() {
    for key in [
        "rwid",
        "wjid",
        "msid",
        "kcdm",
        "kcmc",
        "bpmc",
        "ypjcs",
        "sxz",
        "pjrdm",
        "pjrmc",
        "rwh",
        "xn",
        "xq",
        "xnxq",
        "yxsfktjst",
    ] {
        let mut row = course_row(&serde_json::json!(0));
        row.as_object_mut().unwrap().remove(key);
        let response = parse_courses(&complete_course_envelope(&[row])).unwrap();
        assert_eq!(
            response.courses[0].submit_eligibility,
            ActionEligibility::Unknown,
            "缺少 {key} 不得形成写权限"
        );
        assert!(response.courses[0].submit_target.is_none(), "缺少 {key}");
    }
}

#[test]
fn duplicate_typed_identity_never_grants_submit_authority() {
    let row = course_row(&serde_json::json!(0));
    let body = complete_course_envelope(&[row.clone(), row]);
    let response = parse_courses(&body).expect("重复行仍应保留安全展示");
    assert_eq!(response.courses.len(), 2);
    assert!(response.courses.iter().all(|course| {
        course.submit_eligibility == ActionEligibility::Unknown && course.submit_target.is_none()
    }));
}

#[test]
fn a_malformed_duplicate_still_revokes_the_other_rows_authority() {
    let valid = course_row(&serde_json::json!(0));
    let mut malformed = valid.clone();
    malformed.as_object_mut().unwrap().remove("sxz");
    let response = parse_courses(&complete_course_envelope(&[valid, malformed])).unwrap();

    assert!(response.courses.iter().all(|course| {
        course.submit_eligibility == ActionEligibility::Unknown && course.submit_target.is_none()
    }));
}

#[test]
fn conflicting_parent_fields_do_not_hide_a_duplicate_typed_identity() {
    let context = CourseContext {
        rwid: "task-1".into(),
        wjid: "form-1".into(),
        msid: "mode-1".into(),
    };
    for key in ["msid", "rwid", "wjid"] {
        let valid = course_row(&serde_json::json!(0));
        let mut conflicting = valid.clone();
        conflicting[key] = serde_json::json!("conflicting-parent");
        let entries = parse_course_rows(&serde_json::json!([valid, conflicting]), &context)
            .expect("冲突行仍需参与同目标唯一性判断");
        let response = EvaluationAuthoritySnapshot::finalize(entries).into_response();

        for course in response.courses {
            assert_eq!(
                course.submit_eligibility,
                ActionEligibility::Unknown,
                "同目标重复行的 {key} 冲突不能使另一行获得资格"
            );
            assert!(course.submit_target.is_none());
        }
    }
}

#[test]
fn absent_and_empty_bpdm_share_the_same_duplicate_identity() {
    let absent = course_row(&serde_json::json!(0));
    let mut empty = course_row(&serde_json::json!(0));
    absent.as_object().expect("fixture object");
    empty
        .as_object_mut()
        .expect("fixture object")
        .insert("bpdm".into(), serde_json::json!(""));
    let mut absent = absent;
    absent
        .as_object_mut()
        .expect("fixture object")
        .remove("bpdm");
    let response = parse_courses(&complete_course_envelope(&[absent, empty])).unwrap();
    assert!(response.courses.iter().all(|course| {
        course.submit_eligibility == ActionEligibility::Unknown && course.submit_target.is_none()
    }));
}

#[test]
fn outcome_unknown_uses_committed_public_spelling() {
    assert_eq!(
        serde_json::to_value(EvaluationCourseOutcome::OutcomeUnknown).unwrap(),
        serde_json::json!("outcomeUnknown")
    );
}

#[test]
fn non_status_text_primitives_keep_the_frozen_content_or_null_semantics() {
    let mut row = course_row(&serde_json::json!(0));
    row["kcdm"] = serde_json::json!(101);
    row["bpdm"] = serde_json::json!(7);
    row["sxz"] = serde_json::json!(true);
    let response = parse_courses(&complete_course_envelope(&[row])).unwrap();

    assert_eq!(
        response.courses[0].submit_eligibility,
        ActionEligibility::Allowed
    );
    assert_eq!(
        response.courses[0].submit_target,
        Some(EvaluationSubmitTarget {
            rwid: "task-1".into(),
            wjid: "form-1".into(),
            kcdm: "101".into(),
            bpdm: Some("7".into()),
        })
    );
}

fn complete_course_envelope(rows: &[serde_json::Value]) -> String {
    serde_json::json!({"code": 200, "result": {"list": rows}}).to_string()
}

fn course_row(ypjcs: &serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "rwid":"task-1", "wjid":"form-1", "msid":"mode-1",
        "kcdm":"course-1", "bpdm":"teacher-1", "kcmc":"课程", "bpmc":"教师",
        "ypjcs":ypjcs, "xypjcs":1, "sxz":"student", "pjrdm":"reviewer-1",
        "pjrmc":"评价人", "rwh":"task-row-1", "xn":"2026", "xq":"1",
        "xnxq":"2026-2027-1", "yxsfktjst":"1"
    })
}
