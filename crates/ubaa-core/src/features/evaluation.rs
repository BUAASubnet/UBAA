//! SPOC 教学评教只读协议。
#![allow(clippy::missing_errors_doc)]

use std::collections::BTreeMap;

use serde_json::{Map, Value};

use crate::domain::{EvaluationCourse, EvaluationCoursesResponse, EvaluationProgress};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

const CAS_URL: &str = "https://spoc.buaa.edu.cn/pjxt/cas";
const TASKS_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks";
const QUESTIONNAIRES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireListToTask";
const COURSES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData";

fn error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn value<'a>(object: &'a Map<String, Value>, key: &str) -> Option<&'a Value> {
    object.get(key)
}

fn string(object: &Map<String, Value>, key: &str) -> Option<String> {
    value(object, key).and_then(|v| {
        v.as_str()
            .map(str::to_owned)
            .or_else(|| v.as_i64().map(|n| n.to_string()))
    })
}

fn int(object: &Map<String, Value>, key: &str) -> Option<i32> {
    value(object, key).and_then(|v| {
        v.as_i64()
            .and_then(|n| i32::try_from(n).ok())
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    })
}

fn boolish(object: &Map<String, Value>, key: &str) -> bool {
    match value(object, key) {
        Some(Value::Bool(value)) => *value,
        Some(Value::Number(value)) => value.as_i64() == Some(1),
        Some(Value::String(value)) => value == "1" || value.eq_ignore_ascii_case("true"),
        _ => false,
    }
}

fn result_value(body: &str) -> Result<Value> {
    let root: Value = serde_json::from_str(body).map_err(|_| error("评教响应无法解析"))?;
    let object = root.as_object().ok_or_else(|| error("评教响应结构无效"))?;
    let code = object.get("code").and_then(|v| {
        v.as_i64()
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    });
    if let Some(code) = code.filter(|code| *code != 0 && *code != 200) {
        return Err(error(format!("评教上游返回错误码 {code}")));
    }
    object
        .get("result")
        .or_else(|| object.get("data"))
        .or_else(|| object.get("content"))
        .cloned()
        .ok_or_else(|| error("评教响应缺少 result"))
}

/// 将一个课程结果列表转换为稳定的评教响应。
pub fn parse_courses(body: &str) -> Result<EvaluationCoursesResponse> {
    let result = result_value(body)?;
    let rows = result
        .get("list")
        .and_then(Value::as_array)
        .or_else(|| result.as_array())
        .ok_or_else(|| error("评教课程列表结构无效"))?;
    let mut courses = Vec::new();
    for row in rows {
        let Some(object) = row.as_object() else {
            continue;
        };
        let rwid = string(object, "rwid").unwrap_or_default();
        let wjid = string(object, "wjid").unwrap_or_default();
        let kcdm = string(object, "kcdm").ok_or_else(|| error("评教课程缺少课程代码"))?;
        let bpdm = string(object, "bpdm");
        let id = format!(
            "{}_{}_{}_{}",
            rwid,
            wjid,
            kcdm,
            bpdm.clone().unwrap_or_default()
        );
        courses.push(EvaluationCourse {
            id,
            kcmc: string(object, "kcmc").unwrap_or_else(|| "未知课程".into()),
            bpmc: string(object, "bpmc").unwrap_or_else(|| "未知教师".into()),
            is_evaluated: boolish(object, "isEvaluated")
                || int(object, "ypjcs").unwrap_or_default() > 0,
            rwid,
            wjid,
            kcdm,
            bpdm,
            pjrdm: string(object, "pjrdm"),
            pjrmc: string(object, "pjrmc"),
            xnxq: string(object, "xnxq"),
            msid: string(object, "msid").unwrap_or_else(|| "1".into()),
            zdmc: string(object, "zdmc").or_else(|| Some("STID".into())),
            ypjcs: int(object, "ypjcs"),
            xypjcs: int(object, "xypjcs"),
            sxz: string(object, "sxz"),
            rwh: string(object, "rwh"),
            xn: string(object, "xn"),
            xq: string(object, "xq"),
            pjlxid: string(object, "pjlxid").or_else(|| Some("2".into())),
            sfksqbpj: string(object, "sfksqbpj").or_else(|| Some("1".into())),
            yxsfktjst: string(object, "yxsfktjst"),
        });
    }
    courses.sort_by_key(|course| course.is_evaluated);
    let evaluated = courses.iter().filter(|course| course.is_evaluated).count();
    let total = courses.len();
    Ok(EvaluationCoursesResponse {
        courses,
        progress: EvaluationProgress {
            total_courses: i32::try_from(total).unwrap_or(i32::MAX),
            evaluated_courses: i32::try_from(evaluated).unwrap_or(i32::MAX),
            pending_courses: i32::try_from(total.saturating_sub(evaluated)).unwrap_or(i32::MAX),
        },
    })
}

/// 查询全部评教课程；待评教课程由同一稳定 DTO 的 `is_evaluated=false` 表示。
pub(crate) async fn get_all(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<EvaluationCoursesResponse> {
    super::require_session(runtime)?;
    let activation = super::get_with_redirects(runtime, runtime.url(CAS_URL)?, &[], "评教").await?;
    super::check_response(&activation, "评教")?;
    let mut task_url =
        url::Url::parse(&runtime.url(TASKS_URL)?).map_err(|_| error("评教地址无效"))?;
    task_url
        .query_pairs_mut()
        .append_pair("yhdm", "")
        .append_pair("pageNum", "1")
        .append_pair("pageSize", "10");
    let tasks = fetch(runtime, task_url, BTreeMap::new()).await?;
    let task_rows = tasks
        .get("list")
        .and_then(Value::as_array)
        .or_else(|| tasks.as_array())
        .cloned()
        .unwrap_or_default();
    let mut courses = Vec::new();
    for task in task_rows {
        let Some(task) = task.as_object() else {
            continue;
        };
        let rwid = string(task, "rwid").unwrap_or_default();
        let mut questionnaire_url = url::Url::parse(&runtime.url(QUESTIONNAIRES_URL)?)
            .map_err(|_| error("评教地址无效"))?;
        questionnaire_url
            .query_pairs_mut()
            .append_pair("rwid", &rwid);
        let forms = fetch(runtime, questionnaire_url, BTreeMap::new()).await?;
        let forms = forms.as_array().cloned().unwrap_or_default();
        for form in forms {
            let Some(form) = form.as_object() else {
                continue;
            };
            let wjid = string(form, "wjid").unwrap_or_default();
            let mut course_url =
                url::Url::parse(&runtime.url(COURSES_URL)?).map_err(|_| error("评教地址无效"))?;
            course_url.query_pairs_mut().append_pair("wjid", &wjid);
            let rows = fetch(runtime, course_url, BTreeMap::new()).await?;
            for row in rows.as_array().cloned().unwrap_or_default() {
                if let Some(mut parsed) = parse_courses(&serde_json::json!({"code":200,"result":[{ "rwid": rwid, "wjid": wjid, "kcdm": row.get("kcdm").and_then(Value::as_str).unwrap_or_default(), "kcmc": row.get("kcmc").and_then(Value::as_str).unwrap_or(""), "bpmc": row.get("bpmc").and_then(Value::as_str).unwrap_or(""), "ypjcs": row.get("ypjcs").cloned().unwrap_or(Value::from(0)) }]}).to_string())?.courses.pop() {
                    parsed.pjrdm = row.get("pjrdm").and_then(Value::as_str).map(str::to_owned);
                    courses.push(parsed);
                }
            }
        }
    }
    let mut response = EvaluationCoursesResponse {
        courses,
        progress: EvaluationProgress::default(),
    };
    let evaluated = response
        .courses
        .iter()
        .filter(|course| course.is_evaluated)
        .count();
    let total_courses = i32::try_from(response.courses.len()).unwrap_or(i32::MAX);
    let evaluated_courses = i32::try_from(evaluated).unwrap_or(i32::MAX);
    let pending_courses =
        i32::try_from(response.courses.len().saturating_sub(evaluated)).unwrap_or(i32::MAX);
    response.progress = EvaluationProgress {
        total_courses,
        evaluated_courses,
        pending_courses,
    };
    Ok(response)
}

async fn fetch(
    runtime: &mut crate::runtime::ClientRuntime,
    mut url: url::Url,
    params: BTreeMap<String, String>,
) -> Result<Value> {
    for (key, value) in params {
        url.query_pairs_mut().append_pair(&key, &value);
    }
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[("X-Requested-With", "XMLHttpRequest")],
    )
    .await?;
    super::check_response(&response, "评教")?;
    result_value(&super::body(&response))
}

/// 仅用于测试和宿主校验的待评教过滤。
#[must_use]
pub fn pending(response: &EvaluationCoursesResponse) -> Vec<EvaluationCourse> {
    response
        .courses
        .iter()
        .filter(|course| !course.is_evaluated)
        .cloned()
        .collect()
}
