use crate::domain::{LoginInput, SecretValue};

use super::{
    build_login_form, extract_execution, find_login_error, has_unsupported_login_step,
    is_password_risk_page, parse_user_info,
};

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
fn unsupported_interactive_login_pages_are_rejected_without_a_form() {
    assert!(has_unsupported_login_step(
        "<script>config.captcha = { type: 'image', id: 'captcha-fixture' }</script>",
    ));

    let risk = r#"<form id="continueForm"><input name="execution" value="e-risk"><div>密码过期</div><button value="ignoreAndContinue"></button></form>"#;
    assert_eq!(extract_execution(risk).as_deref(), Some("e-risk"));
    assert!(is_password_risk_page(risk));
}

#[test]
fn unsupported_interactive_login_controls_are_rejected_fail_closed() {
    let ordinary = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="text" name="username">
        <input type="password" name="password">
        <input name="type" value="username_password">
        <input name="_eventId" value="submit">
        <input type="checkbox" name="remember" value="yes" checked>
        <input type="submit" name="submit" value="登录">
      </form>
    "#;
    assert!(!has_unsupported_login_step(ordinary));

    let extra_visible_control = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="text" name="verificationCode">
      </form>
    "#;
    assert!(has_unsupported_login_step(extra_visible_control));

    let captcha_field = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="hidden" name="captchaResponse" value="">
      </form>
    "#;
    assert!(has_unsupported_login_step(captcha_field));

    let unknown_interactive_marker = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="text" name="username">
        <input type="password" name="password">
      </form>
      <script>config.mfa = { required: true }</script>
    "#;
    assert!(has_unsupported_login_step(unknown_interactive_marker));

    let button_control = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="text" name="username">
        <input type="password" name="password">
        <button type="button">验证</button>
      </form>
    "#;
    assert!(has_unsupported_login_step(button_control));

    let nameless_visible_input = r#"
      <form id="fm1">
        <input type="hidden" name="execution" value="e1s1">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="text">
      </form>
    "#;
    assert!(has_unsupported_login_step(nameless_visible_input));
}

#[test]
fn parser_extracts_safe_login_errors_and_userinfo_wrapper() {
    assert_eq!(
        find_login_error(r#"<div id="errorDiv"><p>Fixture credentials rejected</p></div>"#)
            .as_deref(),
        Some("Fixture credentials rejected")
    );
    let profile = parse_user_info(include_str!(
        "../../../../fixtures/auth/userinfo-success.json"
    ))
    .unwrap();
    assert_eq!(profile.school_id.as_deref(), Some("TEST-0001"));
    let partial = parse_user_info(r#"{"code":0,"data":{"name":"Only Fixture Field"}}"#).unwrap();
    assert_eq!(partial.name.as_deref(), Some("Only Fixture Field"));
}
