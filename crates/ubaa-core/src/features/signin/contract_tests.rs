use super::parse_today;
use crate::domain::ActionEligibility;

#[test]
fn parses_legacy_iclass_today_classes() {
    let classes = parse_today(
        r#"{"STATUS":"0","result":[{"id":"schedule-safe","courseName":"Rust","classBeginTime":"08:00","classEndTime":"09:40","signStatus":"0"}]}"#,
    )
    .expect("冻结签到响应应可解析");

    assert_eq!(classes.len(), 1);
    assert_eq!(classes[0].course_id, "schedule-safe");
    assert_eq!(classes[0].course_name, "Rust");
    assert_eq!(classes[0].sign_status, Some(0));
    assert_eq!(classes[0].signin_eligibility, ActionEligibility::Allowed);
    assert_eq!(classes[0].signin_target.as_deref(), Some("schedule-safe"));
}

#[test]
fn parses_numeric_legacy_sign_status() {
    let classes = parse_today(
        r#"{"STATUS":0,"result":[{"id":"schedule-safe","courseName":"Rust","classBeginTime":"08:00","classEndTime":"09:40","signStatus":1}]}"#,
    )
    .expect("数字状态应兼容冻结实现");

    assert_eq!(classes[0].sign_status, Some(1));
    assert_eq!(classes[0].signin_eligibility, ActionEligibility::Denied);
    assert_eq!(classes[0].signin_target.as_deref(), Some("schedule-safe"));
}

#[test]
fn missing_malformed_or_unrecognized_status_is_unknown() {
    for status_field in [
        "",
        r#","signStatus":null"#,
        r#","signStatus":true"#,
        r#","signStatus":{}"#,
        r#","signStatus":1.5"#,
        r#","signStatus":"bad""#,
        r#","signStatus":2147483648"#,
        r#","signStatus":-2147483649"#,
        r#","signStatus":2"#,
    ] {
        let body = format!(
            r#"{{"STATUS":"0","result":[{{"id":"schedule-safe","courseName":"Rust","classBeginTime":"08:00","classEndTime":"09:40"{status_field}}}]}}"#,
        );
        let classes = parse_today(&body).expect("不完整状态仍应保留只读课程");
        assert_eq!(classes[0].signin_eligibility, ActionEligibility::Unknown);
    }
}

#[test]
fn empty_schedule_id_has_no_write_target() {
    let classes = parse_today(
        r#"{"STATUS":"0","result":[{"id":" ","courseName":"Rust","classBeginTime":"08:00","classEndTime":"09:40","signStatus":0}]}"#,
    )
    .expect("空目标仍可作为只读状态展示");

    assert_eq!(classes[0].signin_eligibility, ActionEligibility::Unknown);
    assert_eq!(classes[0].signin_target, None);
}
