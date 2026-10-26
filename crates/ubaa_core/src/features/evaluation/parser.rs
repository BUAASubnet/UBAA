//! 评教响应信封、课程 authority 与安全公开投影解析。

use std::collections::HashMap;

use serde_json::{Map, Value};

use crate::domain::{
    ActionEligibility, EvaluationCourse, EvaluationCoursesResponse, EvaluationProgress,
    EvaluationSubmitTarget,
};
use crate::error::Result;

use super::upstream_error;

#[derive(Clone, Debug)]
pub(super) struct CourseContext {
    pub(super) rwid: String,
    pub(super) wjid: String,
    pub(super) msid: String,
}

/// 最终 topic GET 所需的完整字段；该结构不会越过 Core。
#[derive(Clone, Debug)]
pub(super) struct EvaluationCourseAuthority {
    pub(super) target: EvaluationSubmitTarget,
    pub(super) course_name: String,
    pub(super) teacher_name: String,
    pub(super) msid: String,
    pub(super) zdmc: String,
    pub(super) ypjcs: i32,
    pub(super) xypjcs: i32,
    pub(super) sxz: String,
    pub(super) pjrdm: String,
    pub(super) pjrmc: String,
    pub(super) rwh: String,
    pub(super) xn: String,
    pub(super) xq: String,
    pub(super) xnxq: String,
    pub(super) pjlxid: String,
    pub(super) sfksqbpj: String,
    pub(super) yxsfktjst: String,
}

#[derive(Clone, Debug)]
pub(super) struct AuthorityEntry {
    pub(super) identity: Option<EvaluationSubmitTarget>,
    pub(super) course: EvaluationCourse,
    pub(super) authority: Option<EvaluationCourseAuthority>,
}

#[derive(Clone, Debug, Default)]
pub(super) struct EvaluationAuthoritySnapshot {
    pub(super) entries: Vec<AuthorityEntry>,
}

impl EvaluationAuthoritySnapshot {
    pub(super) fn finalize(mut entries: Vec<AuthorityEntry>) -> Self {
        let mut counts = HashMap::<EvaluationSubmitTarget, usize>::new();
        for identity in entries.iter().filter_map(|entry| entry.identity.clone()) {
            *counts.entry(identity).or_default() += 1;
        }
        for entry in &mut entries {
            if entry
                .identity
                .as_ref()
                .and_then(|identity| counts.get(identity))
                .is_some_and(|count| *count != 1)
            {
                entry.course.submit_eligibility = ActionEligibility::Unknown;
                entry.course.submit_target = None;
                entry.authority = None;
            }
        }
        entries.sort_by_key(|entry| entry.course.is_evaluated);
        Self { entries }
    }

    pub(super) fn into_response(self) -> EvaluationCoursesResponse {
        response_from_courses(self.entries.into_iter().map(|entry| entry.course).collect())
    }

    pub(super) fn unique_allowed(
        &self,
        target: &EvaluationSubmitTarget,
    ) -> Option<(&EvaluationCourse, &EvaluationCourseAuthority)> {
        let mut matches = self.entries.iter().filter(|entry| {
            entry.course.submit_eligibility == ActionEligibility::Allowed
                && entry.course.submit_target.as_ref() == Some(target)
                && entry.authority.is_some()
        });
        let entry = matches.next()?;
        matches.next().is_none().then(|| {
            (
                &entry.course,
                entry.authority.as_ref().expect("上方已验证 authority"),
            )
        })
    }

    pub(super) fn course_name_for(&self, target: &EvaluationSubmitTarget) -> Option<String> {
        self.entries
            .iter()
            .find(|entry| entry.identity.as_ref() == Some(target))
            .map(|entry| entry.course.kcmc.clone())
    }
}

/// 将单个课程响应解析为安全公开结果。完整业务读取会在全部 task/form 聚合后再统一去重。
#[cfg(test)]
pub fn parse_courses(body: &str) -> Result<EvaluationCoursesResponse> {
    let result = result_value(body)?;
    let rows = result
        .get("list")
        .and_then(Value::as_array)
        .or_else(|| result.as_array())
        .ok_or_else(|| upstream_error("评教课程列表结构无效"))?;
    let mut entries = Vec::new();
    for row in rows {
        let Some(object) = row.as_object() else {
            continue;
        };
        let context = CourseContext {
            rwid: canonical_string(object, "rwid").unwrap_or_default(),
            wjid: canonical_string(object, "wjid").unwrap_or_default(),
            msid: canonical_string(object, "msid").unwrap_or_default(),
        };
        entries.push(parse_course_entry(object, &context));
    }
    Ok(EvaluationAuthoritySnapshot::finalize(entries).into_response())
}

pub(super) fn result_value(body: &str) -> Result<Value> {
    let root: Value = serde_json::from_str(body).map_err(|_| upstream_error("评教响应无法解析"))?;
    let object = root
        .as_object()
        .ok_or_else(|| upstream_error("评教响应结构无效"))?;
    if !read_success_code(object.get("code")) {
        return Err(upstream_error("评教上游返回失败"));
    }
    object
        .get("result")
        .or_else(|| object.get("content"))
        .cloned()
        .ok_or_else(|| upstream_error("评教响应缺少 result"))
}

fn read_success_code(code: Option<&Value>) -> bool {
    match code {
        Some(Value::Number(value)) => value
            .as_i64()
            .is_some_and(|value| value == 0 || value == 200),
        Some(Value::String(value)) => {
            matches!(value.to_ascii_lowercase().as_str(), "0" | "200" | "success")
        }
        _ => false,
    }
}

pub(super) fn parse_course_rows(
    result: &Value,
    context: &CourseContext,
) -> Result<Vec<AuthorityEntry>> {
    let rows = result
        .as_array()
        .ok_or_else(|| upstream_error("评教课程 authority 结构无效"))?;
    Ok(rows
        .iter()
        .filter_map(Value::as_object)
        .map(|row| parse_course_entry(row, context))
        .collect())
}

fn parse_course_entry(row: &Map<String, Value>, context: &CourseContext) -> AuthorityEntry {
    let row_conflicts = [
        ("rwid", context.rwid.as_str()),
        ("wjid", context.wjid.as_str()),
        ("msid", context.msid.as_str()),
    ]
    .into_iter()
    .any(|(key, expected)| supplied_string_conflicts(row, key, expected));
    let kcdm = canonical_string(row, "kcdm").unwrap_or_default();
    let bpdm = canonical_optional_identity(row, "bpdm");
    // 冲突行仍参与父级确定的目标去重，避免另一重复行错误获得唯一资格。
    let identity = (!context.rwid.is_empty() && !context.wjid.is_empty() && !kcdm.is_empty())
        .then(|| {
            bpdm.clone().ok().map(|bpdm| EvaluationSubmitTarget {
                rwid: context.rwid.clone(),
                wjid: context.wjid.clone(),
                kcdm: kcdm.clone(),
                bpdm,
            })
        })
        .flatten();
    let course_name = canonical_string(row, "kcmc").unwrap_or_else(|| "未知课程".into());
    let teacher_name = canonical_string(row, "bpmc").unwrap_or_else(|| "未知教师".into());
    let ypjcs = canonical_i32(row, "ypjcs");

    let authority = identity.as_ref().and_then(|target| {
        if row_conflicts {
            return None;
        }
        let authority = EvaluationCourseAuthority {
            target: target.clone(),
            course_name: canonical_string(row, "kcmc")?,
            teacher_name: canonical_string(row, "bpmc")?,
            msid: canonical_nonempty_owned(&context.msid)?,
            zdmc: canonical_string_or_default(row, "zdmc", "STID")?,
            ypjcs: ypjcs?,
            xypjcs: canonical_i32_or_default(row, "xypjcs", 1)?,
            sxz: canonical_string(row, "sxz")?,
            pjrdm: canonical_string(row, "pjrdm")?,
            pjrmc: canonical_string(row, "pjrmc")?,
            rwh: canonical_string(row, "rwh")?,
            xn: canonical_string(row, "xn")?,
            xq: canonical_string(row, "xq")?,
            xnxq: canonical_string(row, "xnxq")?,
            pjlxid: canonical_string_or_default(row, "pjlxid", "2")?,
            sfksqbpj: canonical_string_or_default(row, "sfksqbpj", "1")?,
            yxsfktjst: canonical_string(row, "yxsfktjst")?,
        };
        (authority.ypjcs == 0).then_some(authority)
    });
    let submit_eligibility = match ypjcs {
        Some(value) if value > 0 => ActionEligibility::Denied,
        Some(0) if authority.is_some() => ActionEligibility::Allowed,
        _ => ActionEligibility::Unknown,
    };
    let submit_target = (submit_eligibility == ActionEligibility::Allowed)
        .then(|| identity.clone())
        .flatten();
    let id = identity.as_ref().map_or_else(String::new, identity_key);

    AuthorityEntry {
        identity,
        course: EvaluationCourse {
            id,
            kcmc: course_name,
            bpmc: teacher_name,
            is_evaluated: ypjcs.is_some_and(|value| value > 0),
            submit_eligibility,
            submit_target,
        },
        authority,
    }
}

fn identity_key(target: &EvaluationSubmitTarget) -> String {
    format!(
        "{}_{}_{}_{}",
        target.rwid,
        target.wjid,
        target.kcdm,
        target.bpdm.as_deref().unwrap_or_default()
    )
}

pub(super) fn canonical_string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(|value| match value {
            Value::String(value) => Some(value.clone()),
            Value::Number(value) => Some(value.to_string()),
            Value::Bool(value) => Some(value.to_string()),
            Value::Null | Value::Array(_) | Value::Object(_) => None,
        })
        .filter(|value| !value.is_empty() && value == value.trim())
}

fn canonical_nonempty_owned(value: &str) -> Option<String> {
    (!value.is_empty() && value == value.trim()).then(|| value.to_owned())
}

fn canonical_optional_identity(
    map: &Map<String, Value>,
    key: &str,
) -> std::result::Result<Option<String>, ()> {
    match map.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if value.is_empty() => Ok(None),
        Some(_) => canonical_string(map, key).map(Some).ok_or(()),
    }
}

fn canonical_i32(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|value| i32::try_from(value).ok())
}

fn canonical_i32_or_default(map: &Map<String, Value>, key: &str, default: i32) -> Option<i32> {
    match map.get(key) {
        None | Some(Value::Null) => Some(default),
        Some(_) => canonical_i32(map, key),
    }
}

fn canonical_string_or_default(
    map: &Map<String, Value>,
    key: &str,
    default: &str,
) -> Option<String> {
    match map.get(key) {
        None | Some(Value::Null) => Some(default.to_owned()),
        Some(_) => canonical_string(map, key),
    }
}

fn supplied_string_conflicts(map: &Map<String, Value>, key: &str, expected: &str) -> bool {
    map.get(key)
        .is_some_and(|_| canonical_string(map, key).as_deref() != Some(expected))
}

fn response_from_courses(courses: Vec<EvaluationCourse>) -> EvaluationCoursesResponse {
    let total = courses.len();
    let evaluated = courses.iter().filter(|course| course.is_evaluated).count();
    EvaluationCoursesResponse {
        courses,
        progress: EvaluationProgress {
            total_courses: i32::try_from(total).unwrap_or(i32::MAX),
            evaluated_courses: i32::try_from(evaluated).unwrap_or(i32::MAX),
            pending_courses: i32::try_from(total.saturating_sub(evaluated)).unwrap_or(i32::MAX),
        },
    }
}
