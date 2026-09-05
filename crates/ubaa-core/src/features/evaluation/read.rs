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

    let mut tasks_url = parsed_runtime_url(runtime, TASKS_URL)?;
    tasks_url
        .query_pairs_mut()
        .append_pair("yhdm", runtime.account_name().unwrap_or_default())
        .append_pair("pageNum", "1")
        .append_pair("pageSize", "10");
    let tasks = fetch_result(runtime, tasks_url, strict).await?;
    let task_rows = rows_from_page_or_array(&tasks, "评教任务列表结构无效", strict)?;
    let mut entries = Vec::new();

    for task in task_rows {
        let Some(task) = task.as_object() else {
            continue;
        };
        let Some(rwid) = canonical_string(task, "rwid") else {
            continue;
        };
        let mut questionnaire_url = parsed_runtime_url(runtime, QUESTIONNAIRES_URL)?;
        questionnaire_url
            .query_pairs_mut()
            .append_pair("rwid", &rwid);
        let forms = fetch_result(runtime, questionnaire_url, strict).await?;
        let form_rows = rows_from_array(&forms, "评教问卷列表结构无效", strict)?;
        for form in form_rows {
            let Some(form) = form.as_object() else {
                continue;
            };
            let Some(wjid) = canonical_string(form, "wjid") else {
                continue;
            };
            let msid = canonical_string(form, "msid").unwrap_or_default();
            let mut courses_url = parsed_runtime_url(runtime, COURSES_URL)?;
            courses_url.query_pairs_mut().append_pair("wjid", &wjid);
            let courses = fetch_result(runtime, courses_url, strict).await?;
            match parse_course_rows(
                &courses,
                &CourseContext {
                    rwid: rwid.clone(),
                    wjid,
                    msid,
                },
            ) {
                Ok(parsed) => entries.extend(parsed),
                Err(error) if !strict && !is_authentication_error(&error) => {}
                Err(error) => return Err(error),
            }
        }
    }
    Ok(EvaluationAuthoritySnapshot::finalize(entries))
}

async fn activate(runtime: &mut ClientRuntime) -> Result<()> {
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

async fn fetch_result(runtime: &mut ClientRuntime, url: url::Url, strict: bool) -> Result<Value> {
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

fn parsed_runtime_url(runtime: &ClientRuntime, direct: &str) -> Result<url::Url> {
    url::Url::parse(&runtime.url(direct)?).map_err(|_| upstream_error("评教地址无效"))
}

fn rows_from_page_or_array<'a>(
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

fn rows_from_array<'a>(
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
