//! GSMIS protocol shared by graduate academic features; see source-parity.md.
mod academic;
mod schedule;

pub(crate) use academic::{exam_terms, exams, grades};
pub(crate) use schedule::{current_date, schedule, terms, today};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
use serde_json::Value;

const ORIGIN: &str = "https://gsmis.buaa.edu.cn/gsapp/sys";
const ACCEPT: &str = "application/json, text/javascript, */*; q=0.01";

pub(crate) fn is_term(term: &str) -> bool {
    term.len() == 5
        && term.bytes().take(4).all(|c| c.is_ascii_digit())
        && matches!(term.as_bytes()[4], b'1'..=b'3')
}

fn require_term(term: &str) -> Result<()> {
    if is_term(term) {
        Ok(())
    } else {
        Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "研究生学期代码必须为四位年份和学期1/2/3",
        ))
    }
}

async fn activate(runtime: &mut ClientRuntime, app: &str) -> Result<()> {
    let url = runtime.url(&format!("{ORIGIN}/{app}/*default/index.do"))?;
    let response = super::get_with_redirects(runtime, url, &[], "GSMIS").await?;
    check(&response)
}

async fn post(
    runtime: &mut ClientRuntime,
    app: &str,
    path: &str,
    form: Option<&[(&str, String)]>,
) -> Result<Value> {
    super::require_session(runtime)?;
    let url = runtime.url(&format!("{ORIGIN}/{app}/{path}"))?;
    let referer = runtime.url(&format!("{ORIGIN}/{app}/*default/index.do"))?;
    let headers = [
        ("Accept", ACCEPT),
        ("X-Requested-With", "XMLHttpRequest"),
        ("Referer", referer.as_str()),
    ];
    let response = if let Some(form) = form {
        super::post_form(runtime, url, form, &headers).await?
    } else {
        let mut request = HttpRequest::post(url, Vec::new());
        for (name, value) in headers {
            request.headers.insert(name.into(), value.into());
        }
        runtime.request(request).await?
    };
    check(&response)?;
    serde_json::from_slice(&response.body).map_err(|_| invalid("JSON语法"))
}

fn check(response: &HttpResponse) -> Result<()> {
    let body = super::body(response);
    if body
        .to_ascii_lowercase()
        .contains("<title>cas login</title>")
        || body.contains("name=\"execution\"")
        || body.contains("name='execution'")
    {
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "GSMIS 尚未完成统一认证，请重新登录",
        ));
    }
    super::check_response(response, "GSMIS").map_err(|mut error| {
        error.message = format!("{}（HTTP {}）", error.message, response.status);
        error
    })
}

fn invalid(field: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::ParseError,
        ErrorKind::Parse,
        false,
        format!("GSMIS 响应字段校验失败：{field}"),
    )
}

fn text(row: &Value, key: &str) -> Option<String> {
    match row.get(key)? {
        Value::String(s) if !s.trim().is_empty() => Some(s.trim().to_owned()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

fn required(row: &Value, key: &str) -> Result<String> {
    text(row, key).ok_or_else(|| invalid(key))
}
fn integer(row: &Value, key: &str) -> Result<i32> {
    required(row, key)?.parse().map_err(|_| invalid(key))
}
fn number(row: &Value, key: &str) -> Option<f64> {
    text(row, key)?
        .parse::<f64>()
        .ok()
        .filter(|n| n.is_finite())
}
fn array<'a>(row: &'a Value, key: &str) -> Result<&'a Vec<Value>> {
    row.get(key)
        .and_then(Value::as_array)
        .ok_or_else(|| invalid(key))
}
fn table<'a>(root: &'a Value, name: &str) -> Result<&'a Value> {
    if text(root, "code").as_deref() != Some("0") {
        return Err(invalid("code"));
    }
    root.get("datas")
        .and_then(|v| v.get(name))
        .filter(|v| v.is_object())
        .ok_or_else(|| invalid("datas"))
}

#[cfg(test)]
mod tests;
