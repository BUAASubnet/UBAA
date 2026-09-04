//! 博雅响应信封、课程、选课记录和统计解析。
#![allow(clippy::missing_errors_doc)]

use chrono::{Local, NaiveDateTime};
use serde_json::{Map, Value};

use super::error;
use crate::domain::{
    ActionEligibility, BykcChosenCourse, BykcCourse, BykcCourseCategory, BykcCoursePage,
    BykcCourseStatus, BykcCourseSubCategory, BykcSignConfig, BykcSignPoint, BykcStatistic,
    BykcStatistics, BykcUserProfile,
};
use crate::error::Result;

pub(super) fn envelope(body: &str) -> Result<Value> {
    let value: Value = serde_json::from_str(body).map_err(|_| error("博雅响应无法解析"))?;
    let object = value.as_object().ok_or_else(|| error("博雅响应结构无效"))?;
    let status = object
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if status != "0" && object.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(error(
            object
                .get("msg")
                .and_then(Value::as_str)
                .unwrap_or("博雅请求失败"),
        ));
    }
    object
        .get("data")
        .or_else(|| object.get("result"))
        .cloned()
        .ok_or_else(|| error("博雅响应缺少数据"))
}

fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn int(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|v| i32::try_from(v).ok())
        .or_else(|| {
            map.get(key)
                .and_then(Value::as_str)
                .and_then(|v| v.parse().ok())
        })
}

fn course(value: &Value, now: NaiveDateTime) -> Result<BykcCourse> {
    let m = value.as_object().ok_or_else(|| error("博雅课程字段无效"))?;
    let id = m
        .get("id")
        .and_then(Value::as_i64)
        .ok_or_else(|| error("博雅课程缺少标识"))?;
    let course_start_date = string(m, "courseStartDate");
    let course_select_start_date = string(m, "courseSelectStartDate");
    let course_select_end_date = string(m, "courseSelectEndDate");
    let selected = m.get("selected").and_then(Value::as_bool);
    let course_max_count = int(m, "courseMaxCount");
    let course_current_count = int(m, "courseCurrentCount");
    let status = course_status(
        course_start_date.as_deref(),
        course_select_start_date.as_deref(),
        course_select_end_date.as_deref(),
        selected,
        course_current_count,
        course_max_count,
        now,
    );
    let select_eligibility = select_eligibility(
        course_start_date.as_deref(),
        course_select_start_date.as_deref(),
        course_select_end_date.as_deref(),
        selected,
        course_current_count,
        course_max_count,
        status,
        now,
    );
    let deselect_eligibility =
        deselect_eligibility(id, selected, course_start_date.as_deref(), now);
    Ok(BykcCourse {
        id,
        course_name: string(m, "courseName").ok_or_else(|| error("博雅课程缺少名称"))?,
        course_position: string(m, "coursePosition"),
        course_teacher: string(m, "courseTeacher"),
        course_start_date,
        course_end_date: string(m, "courseEndDate"),
        course_select_start_date,
        course_select_end_date,
        course_cancel_end_date: string(m, "courseCancelEndDate"),
        course_max_count,
        course_current_count,
        status,
        selected,
        select_eligibility,
        deselect_eligibility,
    })
}

fn parse_datetime(value: Option<&str>) -> Option<NaiveDateTime> {
    let value = value?.trim();
    [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S%.f",
        "%Y-%m-%dT%H:%M:%S%.f",
    ]
    .into_iter()
    .find_map(|format| NaiveDateTime::parse_from_str(value, format).ok())
}

#[allow(clippy::too_many_arguments)]
fn course_status(
    course_start: Option<&str>,
    select_start: Option<&str>,
    select_end: Option<&str>,
    selected: Option<bool>,
    current_count: Option<i32>,
    max_count: Option<i32>,
    now: NaiveDateTime,
) -> BykcCourseStatus {
    if parse_datetime(course_start).is_some_and(|value| now > value) {
        BykcCourseStatus::Expired
    } else if selected == Some(true) {
        BykcCourseStatus::Selected
    } else if parse_datetime(select_end).is_some_and(|value| now > value) {
        BykcCourseStatus::Ended
    } else if current_count
        .zip(max_count)
        .is_some_and(|(current, max)| current >= max)
    {
        BykcCourseStatus::Full
    } else if parse_datetime(select_start).is_some_and(|value| now < value) {
        BykcCourseStatus::Preview
    } else {
        BykcCourseStatus::Available
    }
}

#[allow(clippy::too_many_arguments)]
fn select_eligibility(
    course_start: Option<&str>,
    select_start: Option<&str>,
    select_end: Option<&str>,
    selected: Option<bool>,
    current_count: Option<i32>,
    max_count: Option<i32>,
    status: BykcCourseStatus,
    now: NaiveDateTime,
) -> ActionEligibility {
    if parse_datetime(course_start).is_none() {
        return ActionEligibility::Unknown;
    }
    let Some(selected) = selected else {
        return ActionEligibility::Unknown;
    };
    let (Some(current_count), Some(max_count)) = (current_count, max_count) else {
        return ActionEligibility::Unknown;
    };
    let (Some(select_start), Some(select_end)) =
        (parse_datetime(select_start), parse_datetime(select_end))
    else {
        return ActionEligibility::Unknown;
    };

    if selected
        || (max_count > 0 && current_count >= max_count)
        || now < select_start
        || now > select_end
        || status != BykcCourseStatus::Available
    {
        ActionEligibility::Denied
    } else {
        ActionEligibility::Allowed
    }
}

fn deselect_eligibility(
    course_id: i64,
    selected: Option<bool>,
    course_start: Option<&str>,
    now: NaiveDateTime,
) -> ActionEligibility {
    if course_id <= 0 {
        return ActionEligibility::Unknown;
    }
    match selected {
        None => ActionEligibility::Unknown,
        Some(false) => ActionEligibility::Denied,
        Some(true) => match parse_datetime(course_start) {
            None => ActionEligibility::Unknown,
            Some(start) if now > start => ActionEligibility::Denied,
            Some(_) => ActionEligibility::Allowed,
        },
    }
}

/// 解析用户资料。
pub(crate) fn parse_profile(body: &str) -> Result<BykcUserProfile> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅资料结构无效"))?;
    Ok(BykcUserProfile {
        id: m
            .get("id")
            .and_then(Value::as_i64)
            .ok_or_else(|| error("博雅资料缺少用户标识"))?,
        employee_id: string(&m, "employeeId"),
        real_name: string(&m, "realName"),
        student_no: string(&m, "studentNo"),
        college_name: m
            .get("college")
            .and_then(Value::as_object)
            .and_then(|v| string(v, "collegeName")),
    })
}

/// 解析课程分页。
#[allow(dead_code)]
pub(crate) fn parse_courses(body: &str) -> Result<BykcCoursePage> {
    parse_courses_at(body, true, Local::now().naive_local())
}

pub(super) fn parse_courses_at(
    body: &str,
    all: bool,
    now: NaiveDateTime,
) -> Result<BykcCoursePage> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅课程分页结构无效"))?;
    let content = m
        .get("content")
        .and_then(Value::as_array)
        .ok_or_else(|| error("博雅课程分页缺少列表"))?
        .iter()
        .map(|value| course(value, now))
        .collect::<Result<Vec<_>>>()?;
    let content = content
        .into_iter()
        .filter(|course| {
            all || !matches!(
                course.status,
                BykcCourseStatus::Expired | BykcCourseStatus::Ended
            )
        })
        .collect();
    Ok(BykcCoursePage {
        content,
        total_elements: int(&m, "totalElements").unwrap_or_default(),
        total_pages: int(&m, "totalPages").unwrap_or_default(),
        size: int(&m, "size").unwrap_or_default(),
        number: int(&m, "number").unwrap_or_default(),
    })
}

/// 解析课程详情。
pub(crate) fn parse_course_detail(body: &str) -> Result<BykcCourse> {
    course(&envelope(body)?, Local::now().naive_local())
}

pub(super) fn parse_course_detail_for_write(body: &str) -> Result<BykcCourse> {
    let value = envelope(body)?;
    let map = value
        .as_object()
        .ok_or_else(|| error("博雅课程详情结构无效"))?;
    ensure_optional_i32(map, "courseCurrentCount")?;
    ensure_optional_i32(map, "courseMaxCount")?;
    course(&value, Local::now().naive_local())
}

/// 解析已选课程列表。
pub(crate) fn parse_chosen_courses(body: &str) -> Result<Vec<BykcChosenCourse>> {
    parse_chosen_courses_at(body, Local::now().naive_local())
}

pub(super) fn parse_chosen_courses_for_write(body: &str) -> Result<Vec<BykcChosenCourse>> {
    parse_chosen_courses_at_for_purpose(body, Local::now().naive_local(), true)
}

pub(super) fn parse_chosen_courses_at(
    body: &str,
    now: NaiveDateTime,
) -> Result<Vec<BykcChosenCourse>> {
    parse_chosen_courses_at_for_purpose(body, now, false)
}

fn parse_chosen_courses_at_for_purpose(
    body: &str,
    now: NaiveDateTime,
    write_preflight: bool,
) -> Result<Vec<BykcChosenCourse>> {
    let payload = envelope(body)?;
    let courses = if write_preflight {
        payload.get("courseList").and_then(Value::as_array)
    } else {
        payload
            .as_array()
            .or_else(|| payload.get("courseList").and_then(Value::as_array))
    };
    courses
        .ok_or_else(|| error("博雅已选课程结构无效"))?
        .iter()
        .map(|v| {
            let m = v.as_object().ok_or_else(|| error("博雅已选课程字段无效"))?;
            if write_preflight {
                ensure_optional_i32(m, "checkin")?;
                ensure_optional_i32(m, "pass")?;
            }
            let course = m.get("courseInfo").and_then(Value::as_object);
            let course_id = course
                .and_then(|course| course.get("id"))
                .and_then(Value::as_i64)
                .unwrap_or_default();
            let course_start_date = course.and_then(|course| string(course, "courseStartDate"));
            let deselect_eligibility =
                deselect_eligibility(course_id, Some(true), course_start_date.as_deref(), now);
            let sign_config = course
                .and_then(|course| string(course, "courseSignConfig"))
                .as_deref()
                .and_then(parse_sign_config);
            let checkin = int(m, "checkin");
            let pass = int(m, "pass");
            let (sign_eligibility, sign_out_eligibility) =
                sign_eligibilities(course_id, checkin, pass, sign_config.as_ref(), now);
            Ok(BykcChosenCourse {
                id: m
                    .get("id")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| error("博雅选课记录缺少标识"))?,
                course_id,
                course_name: course
                    .and_then(|course| string(course, "courseName"))
                    .unwrap_or_else(|| "未知课程".to_owned()),
                course_position: course
                    .and_then(|course| normalized_string(course, "coursePosition")),
                course_teacher: course
                    .and_then(|course| normalized_string(course, "courseTeacher")),
                course_start_date,
                course_end_date: course.and_then(|course| string(course, "courseEndDate")),
                select_date: string(m, "selectDate"),
                course_cancel_end_date: course
                    .and_then(|course| string(course, "courseCancelEndDate")),
                category: course
                    .and_then(|course| nested_kind_name(course, "courseNewKind1"))
                    .map(parse_category),
                sub_category: course
                    .and_then(|course| nested_kind_name(course, "courseNewKind2"))
                    .map(parse_sub_category),
                checkin,
                score: int(m, "score"),
                pass,
                sign_eligibility,
                sign_out_eligibility,
                deselect_eligibility,
                sign_config,
                course_sign_type: course.and_then(|course| int(course, "courseSignType")),
                homework: normalized_string(m, "homework"),
                homework_attachment_name: None,
                homework_attachment_path: None,
                sign_info: normalized_string(m, "signInfo"),
            })
        })
        .collect()
}

fn ensure_optional_i32(map: &Map<String, Value>, key: &str) -> Result<()> {
    let Some(value) = map.get(key) else {
        return Ok(());
    };
    if value.is_null()
        || value
            .as_i64()
            .and_then(|value| i32::try_from(value).ok())
            .is_some()
    {
        return Ok(());
    }
    Err(error("博雅写前资格字段类型无效"))
}

fn normalized_string(map: &Map<String, Value>, key: &str) -> Option<String> {
    string(map, key)
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn nested_kind_name<'a>(map: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    map.get(key)
        .and_then(Value::as_object)
        .and_then(|kind| kind.get("kindName"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn parse_category(value: &str) -> BykcCourseCategory {
    match value {
        "博雅课程" => BykcCourseCategory::Boya,
        _ => BykcCourseCategory::Unknown,
    }
}

fn parse_sub_category(value: &str) -> BykcCourseSubCategory {
    match value {
        "德育" => BykcCourseSubCategory::Moral,
        "美育" => BykcCourseSubCategory::Aesthetic,
        "劳动教育" => BykcCourseSubCategory::Labor,
        "安全健康" => BykcCourseSubCategory::SafetyHealth,
        "其他方面" => BykcCourseSubCategory::Other,
        _ => BykcCourseSubCategory::Unknown,
    }
}

pub(super) fn parse_sign_config(raw: &str) -> Option<BykcSignConfig> {
    let map = serde_json::from_str::<Value>(raw).ok()?;
    let map = map.as_object()?;
    let sign_points = match map.get("signPointList") {
        None => Vec::new(),
        Some(value) => value
            .as_array()?
            .iter()
            .map(|point| {
                let point = point.as_object()?;
                Some(BykcSignPoint {
                    lat: point.get("lat")?.as_f64()?,
                    lng: point.get("lng")?.as_f64()?,
                    radius: point.get("radius").map_or(Some(0.0), Value::as_f64)?,
                })
            })
            .collect::<Option<Vec<_>>>()?,
    };
    Some(BykcSignConfig {
        sign_start_date: string(map, "signStartDate"),
        sign_end_date: string(map, "signEndDate"),
        sign_out_start_date: string(map, "signOutStartDate"),
        sign_out_end_date: string(map, "signOutEndDate"),
        sign_points,
    })
}

pub(super) fn sign_eligibilities(
    course_id: i64,
    checkin: Option<i32>,
    pass: Option<i32>,
    config: Option<&BykcSignConfig>,
    now: NaiveDateTime,
) -> (ActionEligibility, ActionEligibility) {
    if course_id <= 0 || checkin.is_none() || pass.is_none() {
        return (ActionEligibility::Unknown, ActionEligibility::Unknown);
    }
    if pass == Some(1) {
        return (ActionEligibility::Denied, ActionEligibility::Denied);
    }
    let checkin = checkin.expect("已校验考勤状态存在");
    let sign = if checkin == 0 {
        window_eligibility(
            config.and_then(|value| value.sign_start_date.as_deref()),
            config.and_then(|value| value.sign_end_date.as_deref()),
            now,
        )
    } else {
        ActionEligibility::Denied
    };
    let sign_out = if matches!(checkin, 0 | 5 | 6) {
        window_eligibility(
            config.and_then(|value| value.sign_out_start_date.as_deref()),
            config.and_then(|value| value.sign_out_end_date.as_deref()),
            now,
        )
    } else {
        ActionEligibility::Denied
    };
    (sign, sign_out)
}

fn window_eligibility(
    start: Option<&str>,
    end: Option<&str>,
    now: NaiveDateTime,
) -> ActionEligibility {
    let Some((start, end)) = start
        .and_then(|value| parse_datetime(Some(value)))
        .zip(end.and_then(|value| parse_datetime(Some(value))))
    else {
        return ActionEligibility::Unknown;
    };
    if start > end {
        return ActionEligibility::Unknown;
    }
    if start <= now && now <= end {
        ActionEligibility::Allowed
    } else {
        ActionEligibility::Denied
    }
}

pub(super) fn resolve_current_semester(
    config: &Value,
    now: NaiveDateTime,
) -> Result<(String, String)> {
    let semesters = config
        .get("semester")
        .and_then(Value::as_array)
        .filter(|items| !items.is_empty())
        .ok_or_else(|| error("无法获取当前学期信息"))?;
    let parse = |value: Option<&Value>| {
        value.and_then(Value::as_str).and_then(|text| {
            NaiveDateTime::parse_from_str(text, "%Y-%m-%d %H:%M:%S")
                .or_else(|_| NaiveDateTime::parse_from_str(text, "%Y-%m-%dT%H:%M:%S"))
                .ok()
        })
    };
    let fallback = NaiveDateTime::parse_from_str("1970-01-01T00:00:00", "%Y-%m-%dT%H:%M:%S")
        .expect("固定回退时间必须有效");
    let selected = semesters
        .iter()
        .find(|semester| {
            let start = parse(semester.get("semesterStartDate"));
            let end = parse(semester.get("semesterEndDate"));
            matches!((start, end), (Some(start), Some(end)) if start <= now && now <= end)
        })
        .or_else(|| {
            semesters
                .iter()
                .max_by_key(|semester| parse(semester.get("semesterEndDate")).unwrap_or(fallback))
        })
        .ok_or_else(|| error("无法获取当前学期信息"))?;
    let required = |field| {
        selected
            .get(field)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| error("无法获取当前学期信息"))
    };
    Ok((required("semesterStartDate")?, required("semesterEndDate")?))
}

/// 解析修读统计。
pub(crate) fn parse_statistics(body: &str) -> Result<BykcStatistics> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅统计结构无效"))?;
    let categories = m
        .get("categories")
        .or_else(|| m.get("list"))
        .and_then(Value::as_array)
        .map_or(&[][..], |v| v)
        .iter()
        .filter_map(Value::as_object)
        .map(|v| BykcStatistic {
            category_name: string(v, "categoryName"),
            sub_category_name: string(v, "subCategoryName"),
            required_count: int(v, "requiredCount"),
            passed_count: int(v, "passedCount"),
            qualified: v.get("isQualified").and_then(Value::as_bool),
        })
        .collect();
    Ok(BykcStatistics {
        total_valid_count: int(&m, "totalValidCount"),
        categories,
    })
}
