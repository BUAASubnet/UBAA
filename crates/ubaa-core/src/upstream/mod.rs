//! Verified SSO and User Center URLs, form parsing, and response mapping.

use std::collections::BTreeMap;
use std::sync::LazyLock;

use regex::Regex;
use scraper::{Html, Selector};

use crate::domain::{LoginInput, UserInfoResponse, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// Frozen SSO login endpoint.
pub const SSO_LOGIN_URL: &str = "https://sso.buaa.edu.cn/login";
/// Frozen SSO captcha endpoint.
pub const SSO_CAPTCHA_URL: &str = "https://sso.buaa.edu.cn/captcha";
/// Frozen SSO logout endpoint.
pub const SSO_LOGOUT_URL: &str = "https://sso.buaa.edu.cn/logout";
/// Frozen User Center activation endpoint.
pub const UC_ACTIVATE_URL: &str =
    "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
/// Frozen User Center status endpoint.
pub const UC_STATUS_URL: &str = "https://uc.buaa.edu.cn/api/uc/status";
/// Frozen User Center profile endpoint.
pub const UC_USERINFO_URL: &str = "https://uc.buaa.edu.cn/api/uc/userinfo";

static CAPTCHA_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r#"config\.captcha\s*=\s*\{\s*type:\s*['\"]([^'\"]+)['\"],\s*id:\s*['\"]([^'\"]+)['\"]"#,
    )
    .expect("verified captcha regex compiles")
});

/// Extract the current CAS execution token from an HTML form.
#[must_use]
pub fn extract_execution(html: &str) -> Option<String> {
    select_first_attr(html, "input[name=execution]", "value").filter(|value| !value.is_empty())
}

/// Extract the verified `config.captcha` type and identifier.
#[must_use]
pub fn detect_captcha(html: &str) -> Option<(String, String)> {
    let captures = CAPTCHA_PATTERN.captures(html)?;
    Some((
        captures.get(1)?.as_str().into(),
        captures.get(2)?.as_str().into(),
    ))
}

/// Build the ordinary CAS form while preserving verified hidden/default inputs.
///
/// # Errors
///
/// Returns an upstream-changed error when the form cannot be selected.
pub fn build_login_form(
    html: &str,
    input: &LoginInput,
    execution: &str,
) -> Result<BTreeMap<String, String>> {
    let document = Html::parse_document(html);
    let form = document
        .select(&selector("form#fm1, form[action]"))
        .next()
        .ok_or_else(|| upstream_changed("SSO login form is missing"))?;
    let input_selector = selector("input[name]");
    let mut values = BTreeMap::new();
    let mut captcha_names = Vec::new();
    for element in form.select(&input_selector) {
        let value = element.value();
        let Some(name) = value
            .attr("name")
            .map(str::trim)
            .filter(|name| !name.is_empty())
        else {
            continue;
        };
        if name == "username" || name == "password" {
            continue;
        }
        let input_type = value
            .attr("type")
            .unwrap_or_default()
            .trim()
            .to_ascii_lowercase();
        let field_value = value.attr("value").unwrap_or_default();
        #[allow(clippy::match_same_arms)]
        match input_type.as_str() {
            "submit" | "button" | "image" => {}
            "checkbox" if value.attr("checked").is_some() => {
                values.insert(
                    name.into(),
                    if field_value.is_empty() {
                        "on".into()
                    } else {
                        field_value.into()
                    },
                );
            }
            "checkbox" => {}
            "hidden" => {
                values.insert(name.into(), field_value.into());
            }
            _ if !field_value.is_empty() => {
                values.insert(name.into(), field_value.into());
            }
            _ => {}
        }
        if name == "captcha" || name == "captchaResponse" {
            captcha_names.push(name.to_string());
        }
    }
    values.insert("username".into(), input.username.clone());
    values.insert("password".into(), input.password.expose_secret().into());
    values.insert("submit".into(), "登录".into());
    if let Some(captcha) = input
        .captcha
        .as_deref()
        .filter(|captcha| !captcha.is_empty())
    {
        for name in captcha_names {
            values.insert(name, captcha.into());
        }
    }
    values
        .entry("execution".into())
        .or_insert_with(|| execution.into());
    values
        .entry("_eventId".into())
        .or_insert_with(|| "submit".into());
    values
        .entry("type".into())
        .or_insert_with(|| "username_password".into());
    Ok(values)
}

/// Build the fixed captcha form observed in the frozen implementation.
#[must_use]
pub fn build_captcha_form(input: &LoginInput, execution: &str) -> BTreeMap<String, String> {
    let captcha = input.captcha.clone().unwrap_or_default();
    BTreeMap::from([
        ("username".into(), input.username.clone()),
        ("password".into(), input.password.expose_secret().into()),
        ("captcha".into(), captcha.clone()),
        ("captchaResponse".into(), captcha),
        ("execution".into(), execution.into()),
        ("_eventId".into(), "submit".into()),
        ("submit".into(), "登录".into()),
        ("type".into(), "username_password".into()),
    ])
}

/// Detect the one password-risk continuation recognized by the frozen clients.
#[must_use]
pub fn is_password_risk_page(html: &str) -> bool {
    extract_execution(html).is_some()
        && (html.to_ascii_lowercase().contains("continueform")
            || html.to_ascii_lowercase().contains("ignoreandcontinue")
            || html.contains("账号存在安全风险")
            || html.contains("密码过期"))
}

/// Extract a human-safe authentication error from known CAS containers.
#[must_use]
pub fn find_login_error(html: &str) -> Option<String> {
    let document = Html::parse_document(html);
    for query in [
        ".tip-text",
        "#errorDiv",
        "div.errors",
        "p.errors",
        "span.errors",
    ] {
        if let Some(element) = document.select(&selector(query)).next() {
            let text = element.text().collect::<Vec<_>>().join(" ");
            let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
            if !text.is_empty() {
                return Some(text);
            }
        }
    }
    None
}

/// Parse the User Center `code/data` wrapper.
///
/// # Errors
///
/// Returns a stable parse/upstream error for malformed, nonzero, or missing data.
pub fn parse_user_info(body: &str) -> Result<UserProfile> {
    let payload: UserInfoResponse = serde_json::from_str(body).map_err(|_| {
        UbaaError::new(
            ErrorCode::ParseError,
            ErrorKind::Parse,
            false,
            "User Center response is not valid JSON",
        )
    })?;
    if payload.code != 0 {
        return Err(upstream_changed("User Center returned a nonzero code"));
    }
    payload
        .data
        .ok_or_else(|| upstream_changed("User Center response is missing data"))
}

/// Encode an ordered form using standard URL form encoding.
#[must_use]
pub fn encode_form(form: &BTreeMap<String, String>) -> Vec<u8> {
    url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(form.iter())
        .finish()
        .into_bytes()
}

fn select_first_attr(html: &str, query: &str, attribute: &str) -> Option<String> {
    Html::parse_document(html)
        .select(&selector(query))
        .next()
        .and_then(|element| element.value().attr(attribute))
        .map(str::to_string)
}

fn selector(query: &str) -> Selector {
    Selector::parse(query).expect("static selector compiles")
}

fn upstream_changed(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[cfg(test)]
mod tests;
