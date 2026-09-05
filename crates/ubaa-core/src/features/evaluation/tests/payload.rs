use serde_json::{Map, Value, json};

use super::super::parser::EvaluationCourseAuthority;
use super::super::payload::{build_evaluation_payload, build_submit_body};
use crate::domain::EvaluationSubmitTarget;

#[test]
fn frozen_payload_preserves_optional_nulls_and_answer_strategy() {
    let topic = topic(Some("teacher-1"), false);
    let payload = build_evaluation_payload(&authority(Some("teacher-1")), &topic, 0)
        .expect("冻结 fixture 的可空 rwh 必须保留为 null");

    assert_eq!(payload.len(), 1);
    assert_eq!(payload[0]["pjdf"], 93);
    assert_eq!(payload[0]["pjsx"], 1);
    assert_eq!(payload[0]["rwh"], Value::Null);
    assert_eq!(payload[0]["stzjid"], "xx");
    assert_eq!(payload[0]["wtjjy"], "");
    assert_eq!(payload[0]["sfnm"], "1");
    assert_eq!(payload[0]["pjxxlist"][0]["xxdalist"], json!(["opt-b"]));
    assert_eq!(payload[0]["pjxxlist"][1]["wjstctid"], "subjective-option");
    assert_eq!(payload[0]["pjxxlist"][1]["xxdalist"], json!([]));

    let body: Value = serde_json::from_slice(&build_submit_body(&payload).unwrap()).unwrap();
    assert_eq!(
        body,
        json!({"pjidlist": [], "pjjglist": payload, "pjzt": "1"})
    );
}

#[test]
fn missing_question_or_option_identity_fails_closed() {
    let mut missing_question = topic(Some("teacher-1"), true);
    missing_question["pjxtWjWjbReturnEntity"]["wjzblist"][0]["tklist"][0]
        .as_object_mut()
        .unwrap()
        .remove("tmid");
    assert!(build_evaluation_payload(&authority(Some("teacher-1")), &missing_question, 0).is_err());

    let mut missing_option = topic(Some("teacher-1"), true);
    missing_option["pjxtWjWjbReturnEntity"]["wjzblist"][0]["tklist"][0]["tmxxlist"][0]
        .as_object_mut()
        .unwrap()
        .remove("tmxxid");
    assert!(build_evaluation_payload(&authority(Some("teacher-1")), &missing_option, 0).is_err());
}

#[test]
fn absent_bpdm_preserves_the_teacher_returned_by_the_frozen_topic_payload() {
    let topic = topic(Some("teacher-from-topic"), true);
    let payload = build_evaluation_payload(&authority(None), &topic, 0)
        .expect("冻结实现只让缺失 bpdm 形成空 query，并逐项复制 topic payload");

    assert_eq!(payload[0]["bprdm"], "teacher-from-topic");
}

#[test]
fn topic_form_identity_must_match_commit_fresh_course() {
    let mut mismatched = topic(Some("teacher-other"), true);
    mismatched["pjxtPjjgPjjgckb"][0]["kcdm"] = json!("course-other");

    assert!(build_evaluation_payload(&authority(Some("teacher-1")), &mismatched, 0).is_err());
}

fn authority(bpdm: Option<&str>) -> EvaluationCourseAuthority {
    EvaluationCourseAuthority {
        target: EvaluationSubmitTarget {
            rwid: "task-1".into(),
            wjid: "form-1".into(),
            kcdm: "course-1".into(),
            bpdm: bpdm.map(str::to_owned),
        },
        course_name: "课程 one".into(),
        teacher_name: "教师 one".into(),
        msid: "mode-1".into(),
        zdmc: "STID".into(),
        ypjcs: 0,
        xypjcs: 1,
        sxz: "student-kind".into(),
        pjrdm: "reviewer-1".into(),
        pjrmc: "评价人".into(),
        rwh: "row-1".into(),
        xn: "2026".into(),
        xq: "1".into(),
        xnxq: "2026-2027-1".into(),
        pjlxid: "2".into(),
        sfksqbpj: "1".into(),
        yxsfktjst: "0".into(),
    }
}

fn topic(bprdm: Option<&str>, include_rwh: bool) -> Map<String, Value> {
    let mut template = json!({
        "wjssrwid": "assignment-1",
        "bprdm": bprdm,
        "bprmc": "教师 one",
        "kcdm": "course-1",
        "kcmc": "课程 one",
        "pjfs": "1",
        "pjid": "evaluation-1",
        "pjlx": "2",
        "pjrdm": "reviewer-1",
        "pjrjsdm": "student-role-1",
        "pjrxm": "评价人",
        "xnxq": "2026-2027-1",
        "sfxxpj": "1"
    });
    if include_rwh {
        template["rwh"] = json!("row-1");
    }
    json!({
        "pjmap": {"source": "fixture"},
        "pjxtPjjgPjjgckb": [template],
        "pjxtWjWjbReturnEntity": {"wjzblist": [{"tklist": [
            {"tmlx":"1","tmid":"choice-1","tmxxlist":[
                {"tmxxid":"opt-a"},{"tmxxid":"opt-b"}
            ]},
            {"tmlx":"6","tmid":"subjective-1","tmxxlist":[
                {"tmxxid":"subjective-option"}
            ]}
        ]}]}
    })
    .as_object()
    .unwrap()
    .clone()
}
