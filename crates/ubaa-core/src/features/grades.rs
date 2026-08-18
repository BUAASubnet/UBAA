//! Verified grades term parsing and `e/m/d` response mapping.
#![allow(clippy::missing_errors_doc)]

use std::collections::BTreeMap;

use serde::Deserialize;
use serde_json::Value;

use crate::domain::{Grade, GradeData};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// Score application page and query endpoint.
pub const GRADES_URL: &str = "https://app.buaa.edu.cn/buaascore/wap/default/index";

/// Parsed score term components.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ScoreTerm {
    /// Academic year pair.
    pub year: String,
    /// Semester number.
    pub semester: u32,
}

/// Parse the legacy `yyyy-yyyy-semester` term code.
pub fn parse_term_code(term_code: &str) -> Result<ScoreTerm> {
    let trimmed = term_code.trim();
    let mut parts = trimmed.split('-');
    let (Some(first), Some(second), Some(semester), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err(invalid_term());
    };
    if first.len() != 4
        || second.len() != 4
        || !first.chars().all(|c| c.is_ascii_digit())
        || !second.chars().all(|c| c.is_ascii_digit())
    {
        return Err(invalid_term());
    }
    let semester = semester.parse().map_err(|_| invalid_term())?;
    Ok(ScoreTerm {
        year: format!("{first}-{second}"),
        semester,
    })
}

#[derive(Debug, Deserialize)]
struct ScoreResponse {
    #[serde(rename = "e", default)]
    code: i64,
    #[serde(rename = "d", default)]
    data: BTreeMap<String, ScoreCourse>,
}

#[derive(Debug, Deserialize)]
struct ScoreCourse {
    #[serde(default)]
    kcmc: Option<String>,
    #[serde(default)]
    kch: Option<String>,
    #[serde(default)]
    xf: Option<Value>,
    #[serde(default)]
    kccj: Option<Value>,
    #[serde(default)]
    fslx: Option<String>,
    #[serde(default)]
    kclx: Option<String>,
}

/// Parse the score application's verified `e/m/d` response.
pub fn parse_scores(term_code: &str, body: &str) -> Result<GradeData> {
    let response: ScoreResponse = serde_json::from_str(body).map_err(|_| parse_error())?;
    if response.code != 0 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "grades response returned a nonzero code",
        ));
    }
    Ok(GradeData {
        term_code: term_code.to_string(),
        grades: response
            .data
            .into_values()
            .map(|course| Grade {
                course_name: clean(course.kcmc),
                course_code: clean(course.kch),
                credit: value_text(course.xf).and_then(|v| v.parse().ok()),
                score: value_text(course.kccj),
                grade_point: None,
                course_type: clean(course.kclx),
                score_type: clean(course.fslx),
                term_code: Some(term_code.to_string()),
            })
            .collect(),
    })
}

/// Fetch and parse one term's grades using the verified activation/query sequence.
pub(crate) async fn get_grades(
    runtime: &mut crate::runtime::ClientRuntime,
    term_code: &str,
) -> Result<GradeData> {
    let term = parse_term_code(term_code)?;
    let page = super::get_with_redirects(
        runtime,
        runtime.url(GRADES_URL)?,
        &[(
            "Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        )],
        "grades",
    )
    .await?;
    super::check_response(&page, "grades")?;
    let response = super::post_form(
        runtime,
        runtime.url(GRADES_URL)?,
        &[("xq", term.semester.to_string()), ("year", term.year)],
        &[
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", GRADES_URL),
        ],
    )
    .await?;
    super::check_response(&response, "grades")?;
    parse_scores(term_code, &super::body(&response))
}

fn value_text(value: Option<Value>) -> Option<String> {
    value.and_then(|value| match value {
        Value::Null => None,
        Value::String(value) => clean(Some(value)),
        Value::Number(value) => Some(value.to_string()),
        other => Some(other.to_string()),
    })
}

fn clean(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let value = value.trim().to_string();
        (!value.is_empty()).then_some(value)
    })
}

fn invalid_term() -> UbaaError {
    UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "term code must use yyyy-yyyy-semester",
    )
}

fn parse_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::ParseError,
        ErrorKind::Parse,
        false,
        "grades response is not valid JSON",
    )
}
