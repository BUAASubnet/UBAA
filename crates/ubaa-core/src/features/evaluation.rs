//! SPOC 教学评教只读协议。
#![allow(clippy::missing_errors_doc)]

use std::collections::BTreeMap;

use rand::Rng;
use serde_json::{Map, Value};

use crate::domain::{
    EvaluationCourse, EvaluationCoursesResponse, EvaluationProgress, EvaluationResult,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

const CAS_URL: &str = "https://spoc.buaa.edu.cn/pjxt/cas";
const TASKS_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks";
const QUESTIONNAIRES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireListToTask";
const COURSES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData";
const SUBMIT_URL: &str = "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/submitSaveEvaluation";

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

/// 构造冻结评教提交 JSON 信封。
#[must_use]
pub fn build_submit_body(pjjglist: &[Value]) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "pjidlist": [],
        "pjjglist": pjjglist,
        "pjzt": "1"
    }))
    .unwrap_or_else(|_| b"{\"pjidlist\":[],\"pjjglist\":[],\"pjzt\":\"1\"}".to_vec())
}

fn build_submit_request(url: String, pjjglist: &[Value]) -> crate::ports::HttpRequest {
    crate::ports::HttpRequest::post(url, build_submit_body(pjjglist))
        .with_header("Content-Type", "application/json")
        .with_header("X-Requested-With", "XMLHttpRequest")
}

/// 提交已经由宿主构造好的评教结果列表。
pub(crate) async fn submit_payload(
    runtime: &mut crate::runtime::ClientRuntime,
    pjjglist: Vec<Value>,
) -> Result<Vec<EvaluationResult>> {
    super::require_session(runtime)?;
    if pjjglist.is_empty() {
        return Err(error("评教提交列表不能为空"));
    }
    let request = build_submit_request(runtime.url(SUBMIT_URL)?, &pjjglist);
    let response = runtime.request(request).await?;
    super::check_response(&response, "评教")?;
    let root: Value =
        serde_json::from_str(&super::body(&response)).map_err(|_| error("评教提交响应无法解析"))?;
    let code = root
        .get("code")
        .and_then(|v| v.as_i64().or_else(|| v.as_str()?.parse().ok()))
        .unwrap_or_default();
    if code != 0 && code != 200 {
        return Err(error(
            root.get("message")
                .and_then(Value::as_str)
                .unwrap_or("评教提交失败"),
        ));
    }
    Ok(vec![EvaluationResult {
        success: true,
        message: root
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("评教成功")
            .into(),
        course_name: String::new(),
    }])
}

/// 按冻结旧版顺序自动读取问卷并提交课程评教。
pub(crate) async fn submit_courses(
    runtime: &mut crate::runtime::ClientRuntime,
    courses: Vec<EvaluationCourse>,
) -> Result<Vec<EvaluationResult>> {
    super::require_session(runtime)?;
    if courses.is_empty() {
        return Ok(Vec::new());
    }
    let activation = super::get_with_redirects(runtime, runtime.url(CAS_URL)?, &[], "评教").await?;
    super::check_response(&activation, "评教")?;
    let mut results = Vec::with_capacity(courses.len());
    for course in courses {
        let result = submit_one_course(runtime, &course).await;
        results.push(match result {
            Ok(()) => EvaluationResult {
                success: true,
                message: "评教成功".into(),
                course_name: course.kcmc,
            },
            Err(error) => EvaluationResult {
                success: false,
                message: error.message.clone(),
                course_name: course.kcmc,
            },
        });
    }
    Ok(results)
}

async fn submit_one_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course: &EvaluationCourse,
) -> Result<()> {
    revise_questionnaire_pattern(runtime, course).await;
    let topic = fetch_questionnaire_topic(runtime, course)
        .await?
        .ok_or_else(|| error("无法获取问卷题目"))?;
    let question_index = rand::thread_rng().r#gen::<usize>();
    let payload = build_evaluation_payload(course, &topic, question_index);
    if payload.is_empty() {
        return Err(error("问卷没有题目"));
    }
    let response = submit_payload(runtime, payload).await?;
    if response.first().is_some_and(|item| item.success) {
        Ok(())
    } else {
        Err(error(
            response
                .first()
                .map_or("评教提交失败", |item| item.message.as_str()),
        ))
    }
}

async fn revise_questionnaire_pattern(
    runtime: &mut crate::runtime::ClientRuntime,
    course: &EvaluationCourse,
) {
    let body = serde_json::json!({"rwid": course.rwid, "wjid": course.wjid, "msid": course.msid});
    let Ok(url) =
        runtime.url("https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/reviseQuestionnairePattern")
    else {
        return;
    };
    if let Ok(response) = super::post_json(
        runtime,
        url,
        body.to_string().into_bytes(),
        &[("X-Requested-With", "XMLHttpRequest")],
    )
    .await
    {
        let _ = super::check_response(&response, "评教");
    }
}

async fn fetch_questionnaire_topic(
    runtime: &mut crate::runtime::ClientRuntime,
    course: &EvaluationCourse,
) -> Result<Option<Value>> {
    let mut url = url::Url::parse(
        &runtime.url("https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireTopic")?,
    )
    .map_err(|_| error("评教地址无效"))?;
    let params = [
        ("id", String::new()),
        ("rwid", course.rwid.clone()),
        ("wjid", course.wjid.clone()),
        ("zdmc", course.zdmc.clone().unwrap_or_else(|| "STID".into())),
        ("ypjcs", course.ypjcs.unwrap_or_default().to_string()),
        ("xypjcs", course.xypjcs.unwrap_or(1).to_string()),
        ("sxz", course.sxz.clone().unwrap_or_default()),
        ("pjrdm", course.pjrdm.clone().unwrap_or_default()),
        ("pjrmc", course.pjrmc.clone().unwrap_or_default()),
        ("bpdm", course.bpdm.clone().unwrap_or_default()),
        ("bpmc", course.bpmc.clone()),
        ("kcdm", course.kcdm.clone()),
        ("kcmc", course.kcmc.clone()),
        ("rwh", course.rwh.clone().unwrap_or_default()),
        ("xn", course.xn.clone().unwrap_or_default()),
        ("xq", course.xq.clone().unwrap_or_default()),
        ("xnxq", course.xnxq.clone().unwrap_or_default()),
        (
            "pjlxid",
            course.pjlxid.clone().unwrap_or_else(|| "2".into()),
        ),
        (
            "sfksqbpj",
            course.sfksqbpj.clone().unwrap_or_else(|| "1".into()),
        ),
        ("yxsfktjst", course.yxsfktjst.clone().unwrap_or_default()),
        ("yxdm", String::new()),
    ];
    url.query_pairs_mut()
        .extend_pairs(params.iter().map(|(key, value)| (*key, value.as_str())));
    let value = fetch(runtime, url, BTreeMap::new()).await?;
    Ok(value
        .as_array()
        .and_then(|items| items.first())
        .cloned()
        .or_else(|| value.is_object().then_some(value)))
}

fn build_question_answer(
    course: &EvaluationCourse,
    payload: &Map<String, Value>,
    question: &Map<String, Value>,
    use_second_option: bool,
) -> Value {
    let question_type = string(question, "tmlx").unwrap_or_else(|| "1".into());
    let choice = question_type == "1";
    let options = question
        .get("tmxxlist")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let first = options
        .first()
        .and_then(Value::as_object)
        .and_then(|item| item.get("tmxxid"))
        .cloned();
    let selected = if choice && use_second_option && options.len() > 1 {
        options
            .get(1)
            .and_then(Value::as_object)
            .and_then(|item| item.get("tmxxid"))
            .cloned()
    } else if choice {
        first.clone()
    } else {
        None
    };
    serde_json::json!({
        "sjly": "1",
        "stlx": if choice { "1" } else { "6" },
        "wjid": course.wjid,
        "wjssrwid": payload.get("wjssrwid").cloned().unwrap_or(Value::Null),
        "wjstctid": if choice { Value::String(String::new()) } else { first.unwrap_or(Value::String(String::new())) },
        "wjstid": question.get("tmid").cloned().unwrap_or(Value::Null),
        "xxdalist": selected.into_iter().collect::<Vec<_>>(),
    })
}

/// 根据冻结问卷结构构造一门课程的提交结果；`question_index` 仅用于确定性测试。
pub fn build_evaluation_payload(
    course: &EvaluationCourse,
    topic: &Value,
    question_index: usize,
) -> Vec<Value> {
    let Some(entity) = topic
        .get("pjxtWjWjbReturnEntity")
        .and_then(Value::as_object)
    else {
        return Vec::new();
    };
    let questions: Vec<Map<String, Value>> = entity
        .get("wjzblist")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .flat_map(|section| {
            section
                .get("tklist")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
        })
        .filter_map(Value::as_object)
        .cloned()
        .collect();
    if questions.is_empty() {
        return Vec::new();
    }
    let use_second = question_index % questions.len();
    let pjmap = topic.get("pjmap").cloned().unwrap_or(Value::Null);
    topic.get("pjxtPjjgPjjgckb").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_object).map(|payload| {
        let answers = questions.iter().enumerate().map(|(index, question)| build_question_answer(course, payload, question, index == use_second)).collect::<Vec<_>>();
        serde_json::json!({
            "bprdm": payload.get("bprdm").cloned().unwrap_or(Value::Null), "bprmc": payload.get("bprmc").cloned().unwrap_or(Value::Null),
            "kcdm": payload.get("kcdm").cloned().unwrap_or(Value::Null), "kcmc": payload.get("kcmc").cloned().unwrap_or(Value::Null),
            "pjdf": 93, "pjfs": payload.get("pjfs").cloned().unwrap_or(Value::String("1".into())),
            "pjid": payload.get("pjid").cloned().unwrap_or(Value::Null), "pjlx": payload.get("pjlx").cloned().unwrap_or(Value::Null),
            "pjmap": pjmap, "pjrdm": payload.get("pjrdm").cloned().unwrap_or(Value::Null), "pjrjsdm": payload.get("pjrjsdm").cloned().unwrap_or(Value::Null),
            "pjrxm": payload.get("pjrxm").cloned().unwrap_or(Value::Null), "pjsx": 1, "pjxxlist": answers,
            "rwh": payload.get("rwh").cloned().unwrap_or(Value::Null), "stzjid": "xx", "wjid": course.wjid,
            "wjssrwid": payload.get("wjssrwid").cloned().unwrap_or(Value::Null), "wtjjy": "", "xhgs": Value::Null,
            "xnxq": payload.get("xnxq").cloned().unwrap_or(Value::Null), "sfxxpj": payload.get("sfxxpj").cloned().unwrap_or(Value::String("1".into())),
            "sqzt": Value::Null, "yxfz": Value::Null, "zsxz": payload.get("pjrjsdm").cloned().unwrap_or(Value::String(String::new())), "sfnm": "1"
        })
    }).collect()
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

#[cfg(test)]
mod tests {
    use super::{SUBMIT_URL, build_submit_request};
    use super::{build_evaluation_payload, build_submit_body};
    use crate::domain::EvaluationCourse;

    #[test]
    fn 评教题目按冻结结构生成题目答案() {
        let course = EvaluationCourse {
            wjid: "wj-safe".into(),
            kcdm: "kc-safe".into(),
            ..EvaluationCourse::default()
        };
        let topic = serde_json::json!({
            "pjmap": {"safe": true},
            "pjxtPjjgPjjgckb": [{"pjid":"pj-safe","kcdm":"kc-safe","pjfs":"1"}],
            "pjxtWjWjbReturnEntity": {"wjzblist": [{"tklist": [{"tmid":"tm-safe","tmlx":"1","tmxxlist":[{"tmxxid":"opt-safe"}]}]}]}
        });
        let payload = build_evaluation_payload(&course, &topic, 0);
        assert_eq!(payload.len(), 1);
        assert_eq!(payload[0]["wjid"], "wj-safe");
        assert_eq!(payload[0]["pjxxlist"][0]["wjstid"], "tm-safe");
        assert_eq!(payload[0]["pjxxlist"][0]["xxdalist"][0], "opt-safe");
    }

    #[test]
    fn 评教提交正文匹配冻结信封字段() {
        let body = build_submit_body(&[serde_json::json!({"pjid":"safe-id","pjdf":93})]);
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["pjzt"], "1");
        assert_eq!(value["pjidlist"], serde_json::json!([]));
        assert_eq!(value["pjjglist"][0]["pjdf"], 93);
    }

    #[test]
    fn 评教提交请求固定地址头和_json正文() {
        let request =
            build_submit_request(SUBMIT_URL.into(), &[serde_json::json!({"pjid": "safe"})]);
        assert!(
            request
                .url
                .ends_with("/pjxt/evaluationMethodSix/submitSaveEvaluation")
        );
        assert_eq!(
            request.headers.get("Content-Type").map(String::as_str),
            Some("application/json")
        );
        let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
        assert_eq!(body["pjidlist"], serde_json::json!([]));
        assert_eq!(body["pjzt"], "1");
    }
}
