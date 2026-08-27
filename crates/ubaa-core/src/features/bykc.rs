//! 博雅课程只读响应解析。
#![allow(clippy::missing_errors_doc)]

use crate::domain::{
    BykcChosenCourse, BykcCourse, BykcCoursePage, BykcStatistic, BykcStatistics, BykcUserProfile,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use serde_json::{Map, Value};

fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn envelope(body: &str) -> Result<Value> {
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

fn course(value: &Value) -> Result<BykcCourse> {
    let m = value.as_object().ok_or_else(|| error("博雅课程字段无效"))?;
    Ok(BykcCourse {
        id: m
            .get("id")
            .and_then(Value::as_i64)
            .ok_or_else(|| error("博雅课程缺少标识"))?,
        course_name: string(m, "courseName").ok_or_else(|| error("博雅课程缺少名称"))?,
        course_position: string(m, "coursePosition"),
        course_teacher: string(m, "courseTeacher"),
        course_start_date: string(m, "courseStartDate"),
        course_end_date: string(m, "courseEndDate"),
        course_max_count: int(m, "courseMaxCount"),
        course_current_count: int(m, "courseCurrentCount"),
        selected: m.get("selected").and_then(Value::as_bool),
    })
}

/// 解析用户资料。
pub fn parse_profile(body: &str) -> Result<BykcUserProfile> {
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
pub fn parse_courses(body: &str) -> Result<BykcCoursePage> {
    let m = envelope(body)?
        .as_object()
        .cloned()
        .ok_or_else(|| error("博雅课程分页结构无效"))?;
    let content = m
        .get("content")
        .and_then(Value::as_array)
        .ok_or_else(|| error("博雅课程分页缺少列表"))?
        .iter()
        .map(course)
        .collect::<Result<Vec<_>>>()?;
    Ok(BykcCoursePage {
        content,
        total_elements: int(&m, "totalElements").unwrap_or_default(),
        total_pages: int(&m, "totalPages").unwrap_or_default(),
        size: int(&m, "size").unwrap_or_default(),
        number: int(&m, "number").unwrap_or_default(),
    })
}

/// 解析课程详情。
pub fn parse_course_detail(body: &str) -> Result<BykcCourse> {
    course(&envelope(body)?)
}

/// 解析已选课程列表。
pub fn parse_chosen_courses(body: &str) -> Result<Vec<BykcChosenCourse>> {
    envelope(body)?
        .as_array()
        .ok_or_else(|| error("博雅已选课程结构无效"))?
        .iter()
        .map(|v| {
            let m = v.as_object().ok_or_else(|| error("博雅已选课程字段无效"))?;
            Ok(BykcChosenCourse {
                id: m
                    .get("id")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| error("博雅选课记录缺少标识"))?,
                course_id: m.get("courseId").and_then(Value::as_i64),
                course_name: string(m, "courseName"),
                select_date: string(m, "selectDate"),
                checkin: int(m, "checkin"),
                score: int(m, "score"),
            })
        })
        .collect()
}

/// 解析修读统计。
pub fn parse_statistics(body: &str) -> Result<BykcStatistics> {
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
