use super::parse_courses;

#[test]
fn evaluation_success_envelope_preserves_pending_progress() {
    let body = r#"{"code":"200","result":{"list":[{"rwid":"task-1","rwmc":"课程评教","wjid":"form-1","kcdm":"course-1","kcmc":"课程","bpmc":"教师","ypjcs":0}]}}"#;
    let response = parse_courses(body).expect("evaluation fixture should parse");
    assert_eq!(response.courses.len(), 1);
    assert_eq!(response.progress.pending_courses, 1);
}
