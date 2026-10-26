use super::{GraduateSchedule, Row, error};
use crate::domain::{CourseClass, SectionTime, Term};
use crate::error::Result;
use chrono::{Datelike, Days, NaiveDate, Weekday};
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};

type Object = Map<String, Value>;
fn object(value: &Value) -> Result<&Object> {
    value.as_object().ok_or_else(error)
}
fn objects<'a>(root: &'a Object, key: &str) -> Result<Vec<&'a Object>> {
    root.get(key)
        .and_then(Value::as_array)
        .ok_or_else(error)?
        .iter()
        .map(object)
        .collect()
}
fn text(root: &Object, key: &str) -> Option<String> {
    match root.get(key)? {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}
fn required(root: &Object, key: &str) -> Result<String> {
    text(root, key)
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(error)
}
fn number(root: &Object, key: &str) -> Result<i32> {
    required(root, key)?.parse().map_err(|_| error())
}
fn json(body: &str) -> Result<Value> {
    serde_json::from_str(body).map_err(|_| error())
}
fn time(value: i32) -> Result<String> {
    if !(0..=2359).contains(&value) || value % 100 >= 60 {
        return Err(error());
    }
    Ok(format!("{:02}:{:02}", value / 100, value % 100))
}
pub(crate) fn parse_terms(body: &str) -> Result<Vec<Term>> {
    let value = json(body)?;
    let root = object(&value)?;
    if text(root, "code").as_deref() != Some("0") {
        return Err(error());
    }
    let data = object(root.get("datas").ok_or_else(error)?)?;
    let data = object(data.get("kfdxnxqcx").ok_or_else(error)?)?;
    let rows = objects(data, "rows")?;
    if usize::try_from(number(data, "totalSize")?).ok() != Some(rows.len()) {
        return Err(error());
    }
    let mut terms = BTreeMap::new();
    for row in rows {
        let code = required(row, "XNXQDM")?;
        if code.len() != 5
            || !code.bytes().take(4).all(|b| b.is_ascii_digit())
            || !matches!(code.as_bytes()[4], b'1' | b'2' | b'3')
        {
            return Err(error());
        }
        terms
            .entry(code)
            .or_insert(required(row, "XNXQDM_DISPLAY")?);
    }
    terms
        .into_iter()
        .rev()
        .enumerate()
        .map(|(index, (item_code, item_name))| {
            Ok(Term {
                item_code,
                item_name,
                selected: index == 0,
                item_index: i32::try_from(index).map_err(|_| error())?,
            })
        })
        .collect()
}
pub(super) fn parse_schedule(body: &str, terms: Vec<Term>, term: &str) -> Result<GraduateSchedule> {
    if terms.iter().filter(|t| t.item_code == term).count() != 1 {
        return Err(error());
    }
    let value = json(body)?;
    let root = object(&value)?;
    if text(root, "code").as_deref() != Some("1") {
        return Err(error());
    }
    let rows = objects(root, "jgList")?;
    let courses = objects(root, "rwList")?;
    let mut slots = Vec::new();
    for scheme in objects(root, "jcfaList")? {
        slots.extend(objects(scheme, "skjcList")?);
    }
    let mut course_ids = BTreeSet::new();
    for course in &courses {
        if required(course, "XNXQDM")? != term {
            return Err(error());
        }
        course_ids.insert(required(course, "BJDM")?);
    }
    for row in &rows {
        if !course_ids.contains(&required(row, "BJDM")?) {
            return Err(error());
        }
    }
    let monday = semester_start(&courses, &rows)?;
    let mut parsed = Vec::new();
    for row in rows {
        let begin = number(row, "KSJCDM")?;
        let end = number(row, "JSJCDM")?;
        let day = number(row, "XQ")?;
        let mask = required(row, "ZCBH")?;
        let scheme = text(row, "JCFADM");
        if begin <= 0
            || end < begin
            || !(1..=7).contains(&day)
            || !mask.bytes().all(|b| matches!(b, b'0' | b'1'))
        {
            return Err(error());
        }
        let slot = |section| -> Result<&Object> {
            let matches: Vec<_> = slots
                .iter()
                .filter(|s| text(s, "JCFADM") == scheme && number(s, "DM").ok() == Some(section))
                .collect();
            if matches.len() != 1 {
                return Err(error());
            }
            Ok(matches[0])
        };
        let start_time = number(slot(begin)?, "KSSJ")?;
        let end_time = number(slot(end)?, "JSSJ")?;
        if start_time >= end_time {
            return Err(error());
        }
        let teachers = text(row, "JGJSXM");
        let display = [text(row, "ZCMC"), teachers.clone()]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" ");
        parsed.push(Row {
            mask,
            scheme,
            teachers,
            course: CourseClass {
                course_code: required(row, "KCDM")?,
                course_name: required(row, "KCMC")?,
                course_serial_no: Some(required(row, "BJDM")?),
                // GSMIS规范化旧实现不携带XF，不能借原始课程字段补猜学分。
                credit: None,
                begin_time: Some(time(start_time)?),
                end_time: Some(time(end_time)?),
                begin_section: Some(begin),
                end_section: Some(end),
                place_name: text(row, "JASMC"),
                weeks_and_teachers: Some(display),
                day_of_week: Some(day),
                ..Default::default()
            },
        });
    }
    let sections = section_times(&slots, &parsed);
    Ok(GraduateSchedule {
        terms,
        term: term.into(),
        rows: parsed,
        sections,
        monday,
    })
}

fn semester_start(courses: &[&Object], rows: &[&Object]) -> Result<Option<NaiveDate>> {
    let mut starts = BTreeSet::new();
    for course in courses {
        let Some(first) = text(course, "SCSKRQ").filter(|s| !s.trim().is_empty()) else {
            continue;
        };
        let mut offsets = Vec::new();
        for row in rows
            .iter()
            .filter(|r| text(r, "BJDM") == text(course, "BJDM"))
        {
            let mask = required(row, "ZCBH")?;
            let day = number(row, "XQ")?;
            if !mask.bytes().all(|c| c == b'0' || c == b'1') || !(1..=7).contains(&day) {
                return Err(error());
            }
            if let Some(week) = mask.find('1') {
                offsets.push(
                    u64::try_from(week).map_err(|_| error())? * 7
                        + u64::try_from(day - 1).map_err(|_| error())?,
                );
            }
        }
        if let Some(offset) = offsets.into_iter().min() {
            let first = NaiveDate::parse_from_str(&first, "%Y-%m-%d").map_err(|_| error())?;
            starts.insert(
                first
                    .checked_sub_days(Days::new(offset))
                    .ok_or_else(error)?,
            );
        }
    }
    if !rows.is_empty()
        && (starts.len() != 1 || starts.first().is_none_or(|d| d.weekday() != Weekday::Mon))
    {
        return Err(error());
    }
    Ok(starts.into_iter().next())
}

fn section_times(slots: &[&Object], parsed: &[Row]) -> Vec<SectionTime> {
    let schemes: BTreeSet<_> = parsed.iter().filter_map(|r| r.scheme.as_ref()).collect();
    let mut sections = Vec::new();
    for slot in slots {
        if !schemes.is_empty() && !text(slot, "JCFADM").is_some_and(|s| schemes.contains(&s)) {
            continue;
        }
        let parsed_slot = (|| -> Result<SectionTime> {
            let section = number(slot, "DM")?;
            let start = number(slot, "KSSJ")?;
            let end = number(slot, "JSSJ")?;
            if section <= 0 || start >= end {
                return Err(error());
            }
            Ok(SectionTime {
                section,
                start: Some(time(start)?),
                end: Some(time(end)?),
            })
        })();
        if let Ok(slot) = parsed_slot
            && !sections.contains(&slot)
        {
            sections.push(slot);
        }
    }
    sections
}
