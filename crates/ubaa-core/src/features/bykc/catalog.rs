//! 博雅目录与完整详情的独立显示投影。

use chrono::{Local, NaiveDateTime};
use regex::Regex;
use serde_json::{Map, Value};
use std::sync::OnceLock;

use super::error;
use super::parser::{
    course, envelope, int, nested_kind_name, normalized_string, parse_category,
    parse_chosen_courses, parse_sign_config, parse_sub_category,
};
use crate::domain::{
    BykcChosenCourse, BykcCourseAttendanceDisplay, BykcCourseCatalogItem, BykcCourseCatalogPage,
    BykcCourseFullDetail, BykcCourseStatus, BykcSignConfig,
};
use crate::error::Result;

pub(super) fn parse_catalog_at(
    body: &str,
    all: bool,
    now: NaiveDateTime,
) -> Result<BykcCourseCatalogPage> {
    let value = envelope(body)?;
    let map = value
        .as_object()
        .ok_or_else(|| error("博雅课程分页结构无效"))?;
    let content = map
        .get("content")
        .and_then(Value::as_array)
        .ok_or_else(|| error("博雅课程分页缺少列表"))?
        .iter()
        .map(|value| catalog_item(value, now, display_config(value).as_ref()))
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .filter(|item| {
            all || !matches!(
                item.course.status,
                BykcCourseStatus::Expired | BykcCourseStatus::Ended
            )
        })
        .collect();
    Ok(BykcCourseCatalogPage {
        content,
        total_elements: int(map, "totalElements").unwrap_or_default(),
        total_pages: int(map, "totalPages").unwrap_or_default(),
        size: int(map, "size").unwrap_or_default(),
        number: int(map, "number").unwrap_or_default(),
    })
}

fn catalog_item(
    value: &Value,
    now: NaiveDateTime,
    sign: Option<&BykcSignConfig>,
) -> Result<BykcCourseCatalogItem> {
    let base = course(value, now)?;
    let map = value.as_object().ok_or_else(|| error("博雅课程字段无效"))?;
    Ok(BykcCourseCatalogItem {
        course: base,
        category: nested_kind_name(map, "courseNewKind1").map(parse_category),
        sub_category: nested_kind_name(map, "courseNewKind2").map(parse_sub_category),
        audience_campuses: campuses(map),
        has_sign_points: sign.is_some_and(|config| !config.sign_points.is_empty()),
    })
}

fn string_list(map: &Map<String, Value>, field: &str) -> Vec<String> {
    map.get(field)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_owned)
        .collect()
}

fn campuses(map: &Map<String, Value>) -> Vec<String> {
    let mut result = Vec::new();
    for campus in string_list(map, "courseCampusList") {
        let campus = if campus == "全部校区" {
            "未指定校区".to_owned()
        } else {
            campus
        };
        if !result.contains(&campus) {
            result.push(campus);
        }
    }
    if result.is_empty() && normalized_string(map, "courseCampus").as_deref() == Some("ALL") {
        result.push("未指定校区".to_owned());
    }
    result
}

pub(super) fn parse_full_detail(body: &str, id: i64) -> Result<BykcCourseFullDetail> {
    let value = envelope(body)?;
    let map = value
        .as_object()
        .ok_or_else(|| error("博雅课程详情结构无效"))?;
    let sign_config = display_config(&value);
    let course = catalog_item(&value, Local::now().naive_local(), sign_config.as_ref())?;
    if course.course.id != id {
        return Err(error("博雅课程详情标识与请求不一致"));
    }
    Ok(BykcCourseFullDetail {
        course,
        course_contact: normalized_string(map, "courseContact"),
        course_contact_mobile: normalized_string(map, "courseContactMobile"),
        organizer_college_name: map
            .get("courseBelongCollege")
            .and_then(Value::as_object)
            .and_then(|college| normalized_string(college, "collegeName")),
        description_plain_text: normalized_string(map, "courseDesc")
            .and_then(|text| plain_text(&text)),
        audience_colleges: string_list(map, "courseCollegeList"),
        audience_terms: string_list(map, "courseTermList"),
        audience_groups: string_list(map, "courseGroupList"),
        sign_config,
        attendance: None,
    })
}

/// 仅合并显示：主详情有效配置优先，绝不改动写前的已选配置优先级。
pub(super) fn merge_chosen_display(
    detail: &mut BykcCourseFullDetail,
    chosen: Vec<BykcChosenCourse>,
) {
    if let Some(record) = chosen
        .into_iter()
        .find(|item| item.course_id == detail.course.course.id)
    {
        if detail.sign_config.is_none() {
            detail.sign_config = record.sign_config.map(normalize_display_dates);
        }
        detail.attendance = Some(BykcCourseAttendanceDisplay {
            record_id: record.id,
            course_id: record.course_id,
            checkin: record.checkin,
            pass: record.pass,
        });
    }
    detail.course.has_sign_points = detail
        .sign_config
        .as_ref()
        .is_some_and(|config| !config.sign_points.is_empty());
}

pub(super) fn parse_chosen_display(body: &str) -> Result<Vec<BykcChosenCourse>> {
    let mut records = parse_chosen_courses(body)?;
    let payload = envelope(body)?;
    let values = payload
        .as_array()
        .or_else(|| payload.get("courseList").and_then(Value::as_array))
        .ok_or_else(|| error("博雅已选课程结构无效"))?;
    for (record, value) in records.iter_mut().zip(values) {
        record.sign_config = value.get("courseInfo").and_then(display_config);
    }
    Ok(records)
}

fn display_config(value: &Value) -> Option<BykcSignConfig> {
    let raw = value.get("courseSignConfig")?.as_str()?;
    let value: Value = serde_json::from_str(raw).ok()?;
    let map = value.as_object()?;
    // 冻结配置的日期字段类型为 String?；畸形类型使配置整体不可用。
    if [
        "signStartDate",
        "signEndDate",
        "signOutStartDate",
        "signOutEndDate",
    ]
    .iter()
    .any(|key| {
        map.get(*key)
            .is_some_and(|value| !value.is_null() && !value.is_string())
    }) {
        return None;
    }
    parse_sign_config(raw).map(normalize_display_dates)
}

fn normalize_display_dates(mut config: BykcSignConfig) -> BykcSignConfig {
    config.sign_start_date = display_date(config.sign_start_date);
    config.sign_end_date = display_date(config.sign_end_date);
    config.sign_out_start_date = display_date(config.sign_out_start_date);
    config.sign_out_end_date = display_date(config.sign_out_end_date);
    config
}

/// 冻结 `LocalDateTime` 显示规则独立于写用日期解析；不为无效日期补默认值。
fn display_date(value: Option<String>) -> Option<String> {
    let value = value?.trim().replace(' ', "T");
    [
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%S%.f",
        "%Y-%m-%dT%H:%M",
    ]
    .into_iter()
    .any(|format| NaiveDateTime::parse_from_str(&value, format).is_ok())
    .then_some(value)
}

fn plain_text(value: &str) -> Option<String> {
    static BREAK: OnceLock<Regex> = OnceLock::new();
    static PARAGRAPH: OnceLock<Regex> = OnceLock::new();
    static TAG: OnceLock<Regex> = OnceLock::new();
    static BLANKS: OnceLock<Regex> = OnceLock::new();
    let value = BREAK
        .get_or_init(|| Regex::new(r"(?i)<br\s*/?>").expect("固定换行规则"))
        .replace_all(value, "\n");
    let value = PARAGRAPH
        .get_or_init(|| Regex::new(r"(?i)</p>").expect("固定段落规则"))
        .replace_all(&value, "\n\n");
    let value = TAG
        .get_or_init(|| Regex::new(r"<[^>]+>").expect("固定标签规则"))
        .replace_all(&value, "");
    let value = value
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'");
    let value = value
        .lines()
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\n");
    let value = BLANKS
        .get_or_init(|| Regex::new(r"\n{3,}").expect("固定空行规则"))
        .replace_all(&value, "\n\n")
        .trim()
        .to_owned();
    (!value.is_empty()).then_some(value)
}

#[cfg(test)]
mod tests;
