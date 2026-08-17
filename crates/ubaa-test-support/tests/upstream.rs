use std::collections::BTreeMap;

use ubaa_core::domain::{LoginInput, SecretValue};
use ubaa_core::upstream::{
    build_captcha_form, build_login_form, detect_captcha, extract_execution, find_login_error,
    is_password_risk_page, parse_user_info,
};
use ubaa_test_support::auth_fixture;

#[test]
fn cas_parser_preserves_hidden_and_checked_fields_and_filters_buttons() {
    let html = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="hidden" name="lt" value="lt-value">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="checkbox" name="checked" value="yes" checked>
        <input type="checkbox" name="unchecked" value="no">
        <input type="submit" name="submit-button" value="ignore">
        <input type="image" name="image-button" value="ignore">
      </form>
    "#;
    let form = build_login_form(
        html,
        &LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha: None,
        },
        "e1s1",
    )
    .unwrap();

    assert_eq!(form.get("execution").map(String::as_str), Some("e1s1"));
    assert_eq!(form.get("lt").map(String::as_str), Some("lt-value"));
    assert_eq!(form.get("checked").map(String::as_str), Some("yes"));
    assert!(!form.contains_key("unchecked"));
    assert!(!form.contains_key("submit-button"));
    assert!(!form.contains_key("image-button"));
    assert_eq!(form.get("_eventId").map(String::as_str), Some("submit"));
    assert_eq!(
        form.get("type").map(String::as_str),
        Some("username_password")
    );
}

#[test]
fn captcha_and_risk_pages_follow_frozen_parser_contract() {
    let captcha = detect_captcha(
        "<script>config.captcha = { type: 'image', id: 'captcha-fixture' }</script>",
    )
    .expect("captcha detected");
    assert_eq!(captcha.0, "image");
    assert_eq!(captcha.1, "captcha-fixture");

    let risk = r#"<form id="continueForm"><input name="execution" value="e-risk"><div>密码过期</div><button value="ignoreAndContinue"></button></form>"#;
    assert_eq!(extract_execution(risk).as_deref(), Some("e-risk"));
    assert!(is_password_risk_page(risk));

    let form = build_captcha_form(
        &LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
            captcha: Some("abcd".into()),
        },
        "e-cap",
    );
    let expected = BTreeMap::from([
        ("_eventId".into(), "submit".into()),
        ("captcha".into(), "abcd".into()),
        ("captchaResponse".into(), "abcd".into()),
        ("execution".into(), "e-cap".into()),
        ("password".into(), "fixture-password".into()),
        ("submit".into(), "登录".into()),
        ("type".into(), "username_password".into()),
        ("username".into(), "fixture-user".into()),
    ]);
    assert_eq!(form, expected);
}

#[test]
fn parser_extracts_safe_login_errors_and_userinfo_wrapper() {
    assert_eq!(
        find_login_error(r#"<div id="errorDiv"><p>Fixture credentials rejected</p></div>"#)
            .as_deref(),
        Some("Fixture credentials rejected")
    );
    let profile = parse_user_info(auth_fixture("userinfo-success.json").unwrap()).unwrap();
    assert_eq!(profile.school_id.as_deref(), Some("TEST-0001"));
    let partial = parse_user_info(r#"{"code":0,"data":{"name":"Only Fixture Field"}}"#).unwrap();
    assert_eq!(partial.name.as_deref(), Some("Only Fixture Field"));
}
