/// 返回一个已知的编译期认证夹具。
#[must_use]
pub fn auth_fixture(name: &str) -> Option<&'static str> {
    match name {
        "login-page.html" => Some(include_str!("../../../fixtures/auth/login-page.html")),
        "userinfo-success.json" => {
            Some(include_str!("../../../fixtures/auth/userinfo-success.json"))
        }
        _ => None,
    }
}

/// 返回一个已知的编译期脱敏只读业务夹具。
#[must_use]
pub fn readonly_fixture(name: &str) -> Option<&'static str> {
    match name {
        "schedule-terms.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-terms.json"
        )),
        "schedule-weeks.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-weeks.json"
        )),
        "schedule-week.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-week.json"
        )),
        "schedule-today.json" => Some(include_str!(
            "../../../fixtures/readonly/schedule-today.json"
        )),
        "exam.json" => Some(include_str!("../../../fixtures/readonly/exam.json")),
        "grades-page.html" => Some(include_str!("../../../fixtures/readonly/grades-page.html")),
        "grades.json" => Some(include_str!("../../../fixtures/readonly/grades.json")),
        "classroom.json" => Some(include_str!("../../../fixtures/readonly/classroom.json")),
        "spoc-page.json" => Some(include_str!("../../../fixtures/readonly/spoc-page.json")),
        "spoc-detail.json" => Some(include_str!("../../../fixtures/readonly/spoc-detail.json")),
        "judge-courses.html" => Some(include_str!(
            "../../../fixtures/readonly/judge-courses.html"
        )),
        "judge-assignments.html" => Some(include_str!(
            "../../../fixtures/readonly/judge-assignments.html"
        )),
        "judge-detail.html" => Some(include_str!("../../../fixtures/readonly/judge-detail.html")),
        "cgyy-sites.json" => Some(include_str!("../../../fixtures/readonly/cgyy-sites.json")),
        "cgyy-day.json" => Some(include_str!("../../../fixtures/readonly/cgyy-day.json")),
        "cgyy-orders.json" => Some(include_str!("../../../fixtures/readonly/cgyy-orders.json")),
        _ => None,
    }
}

/// 拒绝常见凭据/请求头标记及疑似较长个人数字标识。
///
/// # Errors
///
/// 当夹具包含禁止标记或疑似个人标识时返回提示信息。
pub fn assert_fixture_is_sanitized(fixture: &str) -> std::result::Result<(), String> {
    let lower = fixture.to_ascii_lowercase();
    for marker in [
        "set-cookie:",
        "cookie:",
        "authorization:",
        "ubaa_test_password",
        "-----begin private key-----",
    ] {
        if lower.contains(marker) {
            return Err(format!("fixture 包含禁止标记: {marker}"));
        }
    }

    if fixture
        .split(|character: char| !character.is_ascii_digit())
        .any(|digits| digits.len() >= 8)
    {
        return Err("fixture 包含疑似个人数字标识".into());
    }
    Ok(())
}
