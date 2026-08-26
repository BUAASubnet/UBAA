//! Verified SSO and User Center URLs, form parsing, and response mapping.

use scraper::{Html, Selector};
use std::collections::BTreeMap;

use crate::domain::{LoginInput, UserInfoResponse, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// Frozen SSO login endpoint.
pub const SSO_LOGIN_URL: &str = "https://sso.buaa.edu.cn/login";
/// Frozen SSO logout endpoint.
pub const SSO_LOGOUT_URL: &str = "https://sso.buaa.edu.cn/logout";
/// Frozen User Center activation endpoint.
pub const UC_ACTIVATE_URL: &str =
    "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
/// Frozen User Center status endpoint.
pub const UC_STATUS_URL: &str = "https://uc.buaa.edu.cn/api/uc/status";
/// Frozen User Center profile endpoint.
pub const UC_USERINFO_URL: &str = "https://uc.buaa.edu.cn/api/uc/userinfo";

/// Extract the current CAS execution token from an HTML form.
#[must_use]
pub fn extract_execution(html: &str) -> Option<String> {
    select_first_attr(html, "input[name=execution]", "value").filter(|value| !value.is_empty())
}

/// Identify a login page shape that this client deliberately does not support.
///
/// The frozen CAS parser only defines hidden fields, username/password controls,
/// checkboxes, and submit/button/image controls. A page with the known captcha or
/// deny-only `config.*` verification markers, an extra visible control, or a
/// non-input form control is therefore treated as an unsupported interactive step.
/// This is a closed-world safety boundary: it rejects unknown verification UI
/// without inventing its fields.
#[must_use]
pub(crate) fn has_unsupported_login_step(html: &str) -> bool {
    let lower = html.to_ascii_lowercase();
    if [
        "captcha",
        "mfa",
        "otp",
        "verification",
        "verify",
        "challenge",
    ]
    .iter()
    .any(|marker| lower.contains(&format!("config.{marker}")))
    {
        return true;
    }

    let document = Html::parse_document(html);
    let Some(form) = document.select(&selector("form#fm1, form[action]")).next() else {
        return false;
    };
    if form.select(&selector("textarea, select")).next().is_some() {
        return true;
    }
    if form.select(&selector("button")).next().is_some() {
        return true;
    }

    form.select(&selector("input")).any(|element| {
        let value = element.value();
        let name = value
            .attr("name")
            .map(str::trim)
            .unwrap_or_default()
            .to_ascii_lowercase();
        let input_type = value
            .attr("type")
            .unwrap_or_default()
            .trim()
            .to_ascii_lowercase();
        if name.is_empty() {
            return !matches!(
                input_type.as_str(),
                "hidden" | "submit" | "button" | "image"
            );
        }
        if name == "captcha" || name == "captcharesponse" {
            return true;
        }
        if input_type.is_empty() && value.attr("value").is_some_and(|field| !field.is_empty()) {
            return false;
        }
        match input_type.as_str() {
            "hidden" | "submit" | "button" | "image" | "checkbox" => false,
            _ => !matches!(name.as_str(), "username" | "password"),
        }
    })
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
    }
    values.insert("username".into(), input.username.clone());
    values.insert("password".into(), input.password.expose_secret().into());
    values.insert("submit".into(), "登录".into());
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
