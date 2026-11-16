//! 可导出和上报的错误上下文。响应只保留结构和已确认无个人数据的提示。

use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

static SOURCE: LazyLock<regex::Regex> = LazyLock::new(|| {
    regex::Regex::new(r"\Acrates/ubaa_[a-z_]+/(?:src|tests)/[A-Za-z0-9_/]+\.rs:[0-9]+\z")
        .expect("静态源码规则有效")
});
static NAME: LazyLock<regex::Regex> =
    LazyLock::new(|| regex::Regex::new(r"\A[a-z][a-z0-9_]{0,63}\z").expect("静态诊断规则有效"));

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ErrorDiagnostic {
    pub source: String,
    #[serde(default, skip_serializing_if = "std::collections::BTreeMap::is_empty")]
    pub json_types: std::collections::BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub upstream_code: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub upstream_message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub json_line: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub json_column: Option<usize>,
}

impl ErrorDiagnostic {
    /// 编码经过边界校验的诊断上下文。
    #[must_use]
    pub fn to_json(&self) -> Option<String> {
        self.is_valid()
            .then(|| serde_json::to_string(self).ok())
            .flatten()
    }

    /// 从 Bridge 的安全诊断载荷恢复，拒绝未知字段和不合法内容。
    #[must_use]
    pub fn from_json(text: &str) -> Option<Self> {
        if text.len() > 2048 {
            return None;
        }
        let value: Self = serde_json::from_str(text).ok()?;
        value.is_valid().then_some(value)
    }

    #[must_use]
    pub fn is_valid(&self) -> bool {
        self.upstream_code
            .is_none_or(|v| bounded_upstream_code(v).is_some())
            && self.json_types.iter().all(|(key, value)| {
                JSON_FIELDS.contains(&key.as_str()) && JSON_TYPES.contains(&value.as_str())
            })
            && self.source.len() <= 200
            && SOURCE.is_match(&self.source)
            && self.stage.as_ref().is_none_or(|v| NAME.is_match(v))
            && self.reason.as_ref().is_none_or(|v| NAME.is_match(v))
            && self.status.is_none_or(|v| (100..=599).contains(&v))
            && self
                .upstream_message
                .as_ref()
                .is_none_or(|v| safe_upstream_message(v))
            && self.response_kind.as_deref().is_none_or(|v| {
                matches!(
                    v,
                    "json_object"
                        | "json_array"
                        | "json_null"
                        | "json_scalar"
                        | "login_html"
                        | "html"
                        | "text_or_binary"
                )
            })
    }

    pub(super) fn at(location: &std::panic::Location<'_>) -> Self {
        Self {
            source: format!("{}:{}", location.file().replace('\\', "/"), location.line()),
            ..Self::default()
        }
    }

    /// 只提取响应类别和经过逐字确认的业务提示，不保留业务字段值。
    pub(crate) fn response(&mut self, body: &[u8], status: Option<u16>, code_field: Option<&str>) {
        self.upstream_code = None;
        self.upstream_message = None;
        self.json_types.clear();
        self.json_line = None;
        self.json_column = None;
        self.status = status;
        self.response_bytes = Some(body.len() as u64);
        self.response_kind = Some(
            match serde_json::from_slice::<serde_json::Value>(body) {
                Ok(value) => {
                    self.upstream_code = code_field
                        .and_then(|key| value.get(key))
                        .and_then(|raw| raw.as_i64().or_else(|| raw.as_str()?.parse::<i64>().ok()))
                        .and_then(bounded_upstream_code);
                    for key in JSON_FIELDS {
                        let mut item = Some(&value);
                        for part in key.split('.') {
                            item = item.and_then(|v| v.get(part));
                        }
                        if let Some(item) = item {
                            let kind = match item {
                                serde_json::Value::Null => "null",
                                serde_json::Value::Bool(_) => "boolean",
                                serde_json::Value::Number(_) => "number",
                                serde_json::Value::String(_) => "string",
                                serde_json::Value::Array(_) => "array",
                                serde_json::Value::Object(_) => "object",
                            };
                            self.json_types.insert(key.to_owned(), kind.into());
                        }
                    }
                    if code_field.is_some() {
                        self.upstream_message = ["errmsg", "msg", "message"]
                            .iter()
                            .filter_map(|key| value.get(key)?.as_str())
                            .find(|text| safe_upstream_message(text))
                            .map(str::to_owned);
                    }
                    match value {
                        serde_json::Value::Object(_) => "json_object",
                        serde_json::Value::Array(_) => "json_array",
                        serde_json::Value::Null => "json_null",
                        _ => "json_scalar",
                    }
                }
                Err(error) => {
                    self.json_line = Some(error.line());
                    self.json_column = Some(error.column());
                    let text = String::from_utf8_lossy(body);
                    if text.contains("统一身份认证") || text.contains("input name=\"execution\"")
                    {
                        "login_html"
                    } else if text.trim_start().starts_with('<') {
                        "html"
                    } else {
                        "text_or_binary"
                    }
                }
            }
            .to_owned(),
        );
    }
}

pub(super) fn bounded_upstream_code(code: i64) -> Option<i64> {
    i32::try_from(code).ok().map(i64::from)
}

const JSON_FIELDS: [&str; 14] = [
    "code",
    "status",
    "success",
    "msg",
    "message",
    "errmsg",
    "data",
    "result",
    "content",
    "data.items",
    "data.rows",
    "data.list",
    "result.items",
    "content.list",
];
const JSON_TYPES: [&str; 6] = ["null", "boolean", "number", "string", "array", "object"];

/// 冻结旧版已经识别的完整业务提示。未知提示不猜测脱敏是否充分。
#[must_use]
pub fn safe_upstream_message(text: &str) -> bool {
    matches!(
        text,
        "已报名过该课程，请不要重复报名"
            | "报名失败，该课程人数已满"
            | "选课失败，该课程不可选择"
            | "您的会话已失效,请重新登录后再试"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 响应保留业务拒绝说明但剔除身份和会话() {
        let mut diagnostic = ErrorDiagnostic::at(std::panic::Location::caller());
        diagnostic.response(
            br#"{"status":"12","msg":"secret","data":{"name":"private","token":"secret"}}"#,
            Some(200),
            Some("status"),
        );
        let text = diagnostic.to_json().unwrap();
        assert!(!text.contains("secret"));
        assert!(!text.contains("private"));
        assert_eq!(diagnostic.upstream_code, Some(12));
        assert_eq!(
            diagnostic.json_types.get("data").map(String::as_str),
            Some("object")
        );
        diagnostic.response(
            "{\"msg\":\"报名失败，该课程人数已满\"}".as_bytes(),
            Some(200),
            Some("status"),
        );
        assert_eq!(
            diagnostic.upstream_message.as_deref(),
            Some("报名失败，该课程人数已满")
        );
    }

    #[test]
    fn 登录页面和无效json可以区分() {
        let mut diagnostic = ErrorDiagnostic::at(std::panic::Location::caller());
        diagnostic.response(
            "<html>统一身份认证<input value='private'></html>".as_bytes(),
            Some(200),
            None,
        );
        assert_eq!(diagnostic.response_kind.as_deref(), Some("login_html"));
        diagnostic.response(b"{\n bad", Some(200), None);
        assert_eq!(diagnostic.response_kind.as_deref(), Some("text_or_binary"));
        assert_eq!(diagnostic.json_line, Some(2));
    }
}

#[cfg(test)]
mod contract_tests {
    use crate::error::UbaaError;

    #[test]
    fn 错误诊断保留产生位置且不复制异常正文() {
        let error = UbaaError::parse_error("token=private，张三的成绩");
        let diagnostic = serde_json::to_value(error.diagnostic()).unwrap();
        let text = diagnostic.to_string();
        assert!(text.contains("diagnostic.rs"));
        assert!(!text.contains("private"));
        assert!(!text.contains("张三"));
        assert_eq!(
            serde_json::to_value(error)
                .unwrap()
                .as_object()
                .unwrap()
                .len(),
            4
        );
    }
}
