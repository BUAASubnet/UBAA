use super::parse_today;

#[test]
fn parses_legacy_iclass_today_classes() {
    let classes = parse_today(
        r#"{"STATUS":"0","result":[{"id":"course-1","courseName":"Rust","classBeginTime":"08:00","classEndTime":"09:40","stuSignStatus":"0"}]}"#,
    )
    .expect("冻结签到响应应可解析");

    assert_eq!(classes.len(), 1);
    assert_eq!(classes[0].course_id, "course-1");
    assert_eq!(classes[0].course_name, "Rust");
    assert_eq!(classes[0].sign_status, 0);
}

#[test]
fn parses_numeric_legacy_sign_status() {
    let classes = parse_today(
        r#"{"STATUS":0,"result":[{"id":"course-1","courseName":"Rust","classBeginTime":"08:00","classEndTime":"09:40","stuSignStatus":1}]}"#,
    )
    .expect("数字状态应兼容冻结实现");

    assert_eq!(classes[0].sign_status, 1);
}
