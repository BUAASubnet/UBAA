//! 评教会话激活与 tasks → questionnaires → courses fresh authority 读取。

use serde_json::Value;

use crate::domain::EvaluationCoursesResponse;
use crate::error::Result;
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;

use super::parser::{
    CourseContext, EvaluationAuthoritySnapshot, canonical_string, parse_course_rows, result_value,
};
use super::{
    CAS_URL, COURSES_URL, QUESTIONNAIRES_URL, TASKS_URL, is_authentication_error, upstream_error,
};

pub(crate) async fn get_all(runtime: &mut ClientRuntime) -> Result<EvaluationCoursesResponse> {
    read_authority(runtime, false)
        .await
        .map(EvaluationAuthoritySnapshot::into_response)
}

pub(super) async fn read_authority(
    runtime: &mut ClientRuntime,
    strict: bool,
) -> Result<EvaluationAuthoritySnapshot> {
    super::super::require_session(runtime)?;
    if let Err(error) = activate(runtime).await {
        if !strict && !is_authentication_error(&error) {
            return Ok(EvaluationAuthoritySnapshot::default());
        }
        return Err(error);
    }

    let tasks = fetch_result(runtime, tasks_url(runtime)?, strict).await?;
    let task_rows = rows_from_page_or_array(&tasks, "评教任务列表结构无效", strict)?;
    let mut entries = Vec::new();

    for task in task_rows {
        let Some(task) = task.as_object() else {
            continue;
        };
        let Some(rwid) = canonical_string(task, "rwid") else {
            continue;
        };
        let forms = fetch_result(runtime, questionnaires_url(runtime, &rwid)?, strict).await?;
        let form_rows = rows_from_array(&forms, "评教问卷列表结构无效", strict)?;
        for form in form_rows {
            let Some(form) = form.as_object() else {
                continue;
            };
            let Some(wjid) = canonical_string(form, "wjid") else {
                continue;
            };
            let context = course_context(form, &rwid, wjid);
            let courses =
                fetch_result(runtime, courses_url(runtime, &context.wjid)?, strict).await?;
            match parse_course_rows(&courses, &context) {
                Ok(parsed) => entries.extend(parsed),
                Err(error) if !strict && !is_authentication_error(&error) => {}
                Err(error) => return Err(error),
            }
        }
    }
    Ok(EvaluationAuthoritySnapshot::finalize(entries))
}

pub(super) fn tasks_url(runtime: &ClientRuntime) -> Result<url::Url> {
    let mut url = parsed_runtime_url(runtime, TASKS_URL)?;
    url.query_pairs_mut()
        .append_pair("yhdm", runtime.account_name().unwrap_or_default())
        .append_pair("pageNum", "1")
        .append_pair("pageSize", "10");
    Ok(url)
}

pub(super) fn questionnaires_url(runtime: &ClientRuntime, rwid: &str) -> Result<url::Url> {
    let mut url = parsed_runtime_url(runtime, QUESTIONNAIRES_URL)?;
    url.query_pairs_mut().append_pair("rwid", rwid);
    Ok(url)
}

pub(super) fn courses_url(runtime: &ClientRuntime, wjid: &str) -> Result<url::Url> {
    let mut url = parsed_runtime_url(runtime, COURSES_URL)?;
    url.query_pairs_mut().append_pair("wjid", wjid);
    Ok(url)
}

pub(super) fn course_context(
    form: &serde_json::Map<String, Value>,
    rwid: &str,
    wjid: String,
) -> CourseContext {
    CourseContext {
        rwid: rwid.to_owned(),
        wjid,
        msid: canonical_string(form, "msid").unwrap_or_default(),
    }
}

pub(super) async fn activate(runtime: &mut ClientRuntime) -> Result<()> {
    let response =
        super::super::get_with_redirects(runtime, runtime.url(CAS_URL)?, &[], "评教").await?;
    super::super::check_response(&response, "评教")?;
    ensure_activation_terminal(&response)
}

pub(super) fn ensure_activation_terminal(response: &HttpResponse) -> Result<()> {
    let direct = crate::connection::from_webvpn_url(&response.final_url)
        .unwrap_or_else(|_| response.final_url.clone());
    let url = url::Url::parse(&direct).map_err(|_| upstream_error("评教激活终点无效"))?;
    if url.host_str() != Some("spoc.buaa.edu.cn")
        || !(url.path() == "/pjxt" || url.path().starts_with("/pjxt/"))
    {
        return Err(upstream_error("评教激活终点无效"));
    }
    Ok(())
}

pub(super) async fn fetch_result(
    runtime: &mut ClientRuntime,
    url: url::Url,
    strict: bool,
) -> Result<Value> {
    let expected = url.to_string();
    let result = async {
        let response = runtime.request(HttpRequest::get(expected.clone())).await?;
        super::super::check_response(&response, "评教")?;
        if response.final_url != expected {
            return Err(upstream_error("评教读取终点无效"));
        }
        result_value(&super::super::body(&response))
    }
    .await;
    match result {
        Ok(value) => Ok(value),
        Err(error) if !strict && !is_authentication_error(&error) => Ok(Value::Array(Vec::new())),
        Err(error) => Err(error),
    }
}

pub(super) fn parsed_runtime_url(runtime: &ClientRuntime, direct: &str) -> Result<url::Url> {
    url::Url::parse(&runtime.url(direct)?).map_err(|_| upstream_error("评教地址无效"))
}

pub(super) fn rows_from_page_or_array<'a>(
    value: &'a Value,
    message: &'static str,
    strict: bool,
) -> Result<&'a [Value]> {
    if let Some(rows) = value
        .get("list")
        .and_then(Value::as_array)
        .or_else(|| value.as_array())
    {
        return Ok(rows);
    }
    if strict {
        Err(upstream_error(message))
    } else {
        Ok(&[])
    }
}

pub(super) fn rows_from_array<'a>(
    value: &'a Value,
    message: &'static str,
    strict: bool,
) -> Result<&'a [Value]> {
    if let Some(rows) = value.as_array() {
        return Ok(rows);
    }
    if strict {
        Err(upstream_error(message))
    } else {
        Ok(&[])
    }
}

/// 显示完整度只核对可读身份/名称/状态和父上下文，不替代 fresh 写资格。
pub(super) fn course_rows_complete(value: &Value, context: &CourseContext) -> bool {
    value.as_array().is_some_and(|rows| {
        rows.iter().all(|row| {
            row.as_object().is_some_and(|row| {
                ["kcdm", "kcmc", "bpmc"]
                    .iter()
                    .all(|key| canonical_string(row, key).is_some())
                    && row
                        .get("ypjcs")
                        .and_then(Value::as_i64)
                        .is_some_and(|v| v >= 0)
                    && [
                        ("rwid", &context.rwid),
                        ("wjid", &context.wjid),
                        ("msid", &context.msid),
                    ]
                    .iter()
                    .all(|(key, expected)| {
                        !row.contains_key(*key)
                            || canonical_string(row, key).as_ref() == Some(*expected)
                    })
            })
        })
    })
}
