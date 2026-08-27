//! 已验证的 SSO 与用户中心地址、表单解析和响应映射。

use scraper::{Html, Selector};
use std::collections::BTreeMap;

use crate::domain::{LoginInput, UserInfoResponse, UserProfile};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 冻结的 SSO 登录地址。
pub const SSO_LOGIN_URL: &str = "https://sso.buaa.edu.cn/login";
/// 冻结的 SSO 登出地址。
pub const SSO_LOGOUT_URL: &str = "https://sso.buaa.edu.cn/logout";
/// 冻结的用户中心激活地址。
pub const UC_ACTIVATE_URL: &str =
    "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
/// 冻结的用户中心状态地址。
pub const UC_STATUS_URL: &str = "https://uc.buaa.edu.cn/api/uc/status";
/// 冻结的用户中心资料地址。
pub const UC_USERINFO_URL: &str = "https://uc.buaa.edu.cn/api/uc/userinfo";

/// 从 HTML 表单中提取当前 CAS execution 令牌。
#[must_use]
pub fn extract_execution(html: &str) -> Option<String> {
    select_first_attr(html, "input[name=execution]", "value").filter(|value| !value.is_empty())
}

/// 判断当前客户端明确不支持的登录页形态。
///
/// 冻结的 CAS 解析器只定义隐藏字段、用户名/密码控件、复选框以及提交/按钮/图片控件。
/// 因此，包含已知验证码或仅拒绝访问的 `config.*` 校验标记、额外可见控件或非 input
/// 表单控件的页面，都会被视为不支持的交互步骤。这是一个封闭世界安全边界：拒绝未知的
/// 校验界面，不擅自猜测其字段。
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

/// 保留已验证的隐藏/默认输入，构造普通 CAS 表单。
///
/// # Errors
///
/// 当无法选出表单时返回上游已变化错误。
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

/// 判断冻结客户端认可的唯一一种密码风险继续页面。
#[must_use]
pub fn is_password_risk_page(html: &str) -> bool {
    extract_execution(html).is_some()
        && (html.to_ascii_lowercase().contains("continueform")
            || html.to_ascii_lowercase().contains("ignoreandcontinue")
            || html.contains("账号存在安全风险")
            || html.contains("密码过期"))
}

/// 从已知 CAS 容器中提取可安全展示给用户的认证错误。
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

/// 解析用户中心的 `code/data` 响应包装。
///
/// # Errors
///
/// 对格式错误、非零状态码或缺少数据返回稳定的解析/上游错误。
pub fn parse_user_info(body: &str) -> Result<UserProfile> {
    let payload: UserInfoResponse = serde_json::from_str(body).map_err(|_| {
        UbaaError::new(
            ErrorCode::ParseError,
            ErrorKind::Parse,
            false,
            "用户中心响应不是有效 JSON",
        )
    })?;
    if payload.code != 0 {
        return Err(upstream_changed("用户中心返回非零状态码"));
    }
    payload
        .data
        .ok_or_else(|| upstream_changed("用户中心响应缺少数据"))
}

/// 使用标准 URL 表单编码方式编码有序表单。
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
