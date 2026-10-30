use super::parse_today;
use crate::domain::ActionEligibility;

#[test]
fn 网关根相对跳转按实际签到目标验证() {
    let base =
        crate::connection::to_webvpn_url("https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter")
            .unwrap();
    for (upstream, allowed) in [
        ("https://iclass.buaa.edu.cn:8346/?loginName=fixture", true),
        ("https://evil.example.invalid/?loginName=fixture", false),
        (
            "https://sso.buaa.edu.cn:8346/login?loginName=fixture",
            false,
        ),
    ] {
        let wrapped = crate::connection::to_webvpn_url(upstream).unwrap();
        let location = wrapped.strip_prefix("https://d.buaa.edu.cn").unwrap();
        let target = crate::connection::business_redirect_target(&base, location).unwrap();
        assert_eq!(target.as_str(), upstream);
        assert_eq!(super::ensure_login_host(&target).is_ok(), allowed);
    }
}

#[test]
fn 登录跳转校验允许固定业务端口并拒绝用户信息与未声明端口() {
    for url in [
        "https://iclass.buaa.edu.cn:8346/?loginName=fixture",
        "https://iclass.buaa.edu.cn:8347/app/user/login.action",
        "https://sso.buaa.edu.cn/login",
    ] {
        assert!(super::ensure_login_host(&url::Url::parse(url).unwrap()).is_ok());
    }
    for url in [
        "https://user@sso.buaa.edu.cn/login",
        "https://sso.buaa.edu.cn:8443/login",
        "https://sso.buaa.edu.cn:8346/login",
        "https://sso.buaa.edu.cn:8347/login",
        "http://iclass.buaa.edu.cn:8346/?loginName=fixture",
        "https://iclass.buaa.edu.cn:9999/?loginName=fixture",
    ] {
        assert!(
            super::ensure_login_host(&url::Url::parse(url).unwrap()).is_err(),
            "不应接受非法签到登录跳转: {url}"
        );
    }
}

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

#[test]
fn 数字时间戳按旧版转为提交参数() {
    assert_eq!(
        super::parse_timestamp(br#"{"STATUS":"0","timestamp":1700000000000}"#).unwrap(),
        "1700000000000"
    );
    assert_eq!(
        super::parse_timestamp(br#"{"timestamp":"1700000000000"}"#).unwrap(),
        "1700000000000"
    );
    for body in [
        br#"{"timestamp":null}"#.as_slice(),
        br#"{"timestamp":true}"#,
        br#"{"timestamp":{}}"#,
        br#"{"timestamp":" "}"#,
    ] {
        assert!(super::parse_timestamp(body).is_err());
    }
}

#[test]
fn 旧版业务登录不能以跳转登录名替代缺失会话() {
    assert_eq!(
        super::SIGNIN_LOGIN_URL,
        "https://iclass.buaa.edu.cn:8347/app/user/login.action"
    );
    for body in [
        r#"{"STATUS":"0","result":{"id":"user-safe"}}"#,
        r#"{"STATUS":"0","result":{"id":"user-safe","sessionId":" "}}"#,
    ] {
        assert!(super::parse_login_credential(body.as_bytes()).is_err());
    }
}
