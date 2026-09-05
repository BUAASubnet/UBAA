//! 冻结本地答案策略与严格 submit JSON 信封构造。

use serde_json::{Map, Value};

use crate::error::Result;

use super::parser::EvaluationCourseAuthority;
use super::upstream_error;

pub(super) fn build_evaluation_payload(
    course: &EvaluationCourseAuthority,
    topic: &Map<String, Value>,
    question_index: usize,
) -> Result<Vec<Value>> {
    let entity = required_object(topic, "pjxtWjWjbReturnEntity")?;
    let sections = required_array(entity, "wjzblist")?;
    let mut questions = Vec::new();
    for section in sections {
        let section = section
            .as_object()
            .ok_or_else(|| upstream_error("评教问卷分组结构无效"))?;
        for question in required_array(section, "tklist")? {
            questions.push(
                question
                    .as_object()
                    .ok_or_else(|| upstream_error("评教题目结构无效"))?,
            );
        }
    }
    if questions.is_empty() {
        return Err(upstream_error("评教问卷没有题目"));
    }
    validate_questions(&questions)?;
    let selected_question = question_index % questions.len();
    let pjmap = topic.get("pjmap").cloned().unwrap_or(Value::Null);
    let payload_rows = required_array(topic, "pjxtPjjgPjjgckb")?;
    if payload_rows.is_empty() {
        return Err(upstream_error("评教题目缺少课程结果模板"));
    }

    payload_rows
        .iter()
        .map(|payload| {
            let payload = payload
                .as_object()
                .ok_or_else(|| upstream_error("评教课程结果模板结构无效"))?;
            validate_payload_identity(course, payload)?;
            let answers = questions
                .iter()
                .enumerate()
                .map(|(index, question)| {
                    build_question_answer(course, payload, question, index == selected_question)
                })
                .collect::<Result<Vec<_>>>()?;
            Ok(serde_json::json!({
                "bprdm": payload.get("bprdm").cloned().unwrap_or(Value::Null),
                "bprmc": required_value(payload, "bprmc")?,
                "kcdm": required_value(payload, "kcdm")?,
                "kcmc": required_value(payload, "kcmc")?,
                "pjdf": 93,
                "pjfs": payload.get("pjfs").cloned().unwrap_or_else(|| Value::String("1".into())),
                "pjid": required_value(payload, "pjid")?,
                "pjlx": required_value(payload, "pjlx")?,
                "pjmap": pjmap,
                "pjrdm": required_value(payload, "pjrdm")?,
                "pjrjsdm": required_value(payload, "pjrjsdm")?,
                "pjrxm": required_value(payload, "pjrxm")?,
                "pjsx": 1,
                "pjxxlist": answers,
                "rwh": payload.get("rwh").cloned().unwrap_or(Value::Null),
                "stzjid": "xx",
                "wjid": course.target.wjid,
                "wjssrwid": required_value(payload, "wjssrwid")?,
                "wtjjy": "",
                "xhgs": Value::Null,
                "xnxq": required_value(payload, "xnxq")?,
                "sfxxpj": payload.get("sfxxpj").cloned().unwrap_or_else(|| Value::String("1".into())),
                "sqzt": Value::Null,
                "yxfz": Value::Null,
                "zsxz": required_value(payload, "pjrjsdm")?,
                "sfnm": "1"
            }))
        })
        .collect()
}

fn validate_questions(questions: &[&Map<String, Value>]) -> Result<()> {
    for question in questions {
        required_text(question, "tmid")?;
        let kind = required_text(question, "tmlx")?;
        if kind != "1" && kind != "6" {
            return Err(upstream_error("评教题目类型无效"));
        }
        let options = required_array(question, "tmxxlist")?;
        if options.is_empty() {
            return Err(upstream_error("评教题目缺少选项标识"));
        }
        for option in options {
            required_text(
                option
                    .as_object()
                    .ok_or_else(|| upstream_error("评教题目选项结构无效"))?,
                "tmxxid",
            )?;
        }
    }
    Ok(())
}

fn build_question_answer(
    course: &EvaluationCourseAuthority,
    payload: &Map<String, Value>,
    question: &Map<String, Value>,
    use_second_option: bool,
) -> Result<Value> {
    let kind = required_text(question, "tmlx")?;
    let choice = kind == "1";
    let options = required_array(question, "tmxxlist")?;
    let first = required_value(
        options[0]
            .as_object()
            .ok_or_else(|| upstream_error("评教题目选项结构无效"))?,
        "tmxxid",
    )?;
    let selected = if choice && use_second_option && options.len() > 1 {
        Some(required_value(
            options[1]
                .as_object()
                .ok_or_else(|| upstream_error("评教题目选项结构无效"))?,
            "tmxxid",
        )?)
    } else if choice {
        Some(first.clone())
    } else {
        None
    };
    Ok(serde_json::json!({
        "sjly": "1",
        "stlx": if choice { "1" } else { "6" },
        "wjid": course.target.wjid,
        "wjssrwid": required_value(payload, "wjssrwid")?,
        "wjstctid": if choice { Value::String(String::new()) } else { first },
        "wjstid": required_value(question, "tmid")?,
        "xxdalist": selected.into_iter().collect::<Vec<_>>(),
    }))
}

fn validate_payload_identity(
    course: &EvaluationCourseAuthority,
    payload: &Map<String, Value>,
) -> Result<()> {
    for (key, expected) in [
        ("kcdm", course.target.kcdm.as_str()),
        ("kcmc", course.course_name.as_str()),
        ("bprmc", course.teacher_name.as_str()),
        ("pjrdm", course.pjrdm.as_str()),
        ("xnxq", course.xnxq.as_str()),
    ] {
        if required_text(payload, key)? != expected {
            return Err(upstream_error("评教题目身份与 fresh 课程不一致"));
        }
    }
    if let Some(bpdm) = course.target.bpdm.as_deref()
        && required_text(payload, "bprdm")? != bpdm
    {
        return Err(upstream_error("评教题目教师身份与 fresh 课程不一致"));
    }
    for key in ["pjid", "pjlx", "pjrjsdm", "pjrxm", "wjssrwid"] {
        required_text(payload, key)?;
    }
    Ok(())
}

pub(super) fn build_submit_body(pjjglist: &[Value]) -> Result<Vec<u8>> {
    serde_json::to_vec(&serde_json::json!({
        "pjidlist": [],
        "pjjglist": pjjglist,
        "pjzt": "1"
    }))
    .map_err(|_| upstream_error("评教提交正文无法编码"))
}

fn required_object<'a>(map: &'a Map<String, Value>, key: &str) -> Result<&'a Map<String, Value>> {
    map.get(key)
        .and_then(Value::as_object)
        .ok_or_else(|| upstream_error("评教问卷结构无效"))
}

fn required_array<'a>(map: &'a Map<String, Value>, key: &str) -> Result<&'a [Value]> {
    map.get(key)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .ok_or_else(|| upstream_error("评教问卷数组结构无效"))
}

fn required_text<'a>(map: &'a Map<String, Value>, key: &str) -> Result<&'a str> {
    map.get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty() && *value == value.trim())
        .ok_or_else(|| upstream_error("评教问卷标识无效"))
}

fn required_value(map: &Map<String, Value>, key: &str) -> Result<Value> {
    required_text(map, key)?;
    Ok(map.get(key).expect("required_text 已验证字段").clone())
}
