//! 博雅只读服务调用与当前学期选择。
#![allow(clippy::missing_errors_doc)]

use chrono::Local;
use serde_json::Value;

use super::auth::{request_api, request_preflight_api};
use super::catalog::{
    merge_chosen_display, parse_catalog_at, parse_chosen_display, parse_full_detail,
};
use super::parser::{
    parse_chosen_courses, parse_chosen_courses_for_write, parse_course_detail,
    parse_course_detail_for_write, parse_courses_at, parse_profile, parse_sign_config,
    parse_statistics, resolve_current_semester,
};
use crate::domain::{
    BykcChosenCourse, BykcCourse, BykcCoursePage, BykcStatistics, BykcUserProfile,
};
use crate::error::Result;

fn wrap(value: &Value) -> String {
    serde_json::json!({"status":"0","data":value}).to_string()
}

pub(crate) async fn get_profile(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcUserProfile> {
    parse_profile(&wrap(
        &request_api(runtime, "getUserProfile", serde_json::json!({})).await?,
    ))
}

pub(crate) async fn get_courses(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    size: i32,
    all: bool,
) -> Result<BykcCoursePage> {
    parse_courses_at(
        &wrap(
            &request_api(
                runtime,
                "queryStudentSemesterCourseByPage",
                catalog_payload(page, size),
            )
            .await?,
        ),
        all,
        Local::now().naive_local(),
    )
}

pub(crate) async fn get_course_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i64,
) -> Result<BykcCourse> {
    get_course_detail_inner(runtime, id, false).await
}

pub(crate) async fn get_course_catalog(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    size: i32,
    all: bool,
) -> Result<crate::domain::BykcCourseCatalogPage> {
    let body = wrap(
        &request_api(
            runtime,
            "queryStudentSemesterCourseByPage",
            catalog_payload(page, size),
        )
        .await?,
    );
    parse_catalog_at(&body, all, Local::now().naive_local())
}

pub(crate) async fn get_course_full_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i64,
) -> Result<crate::domain::BykcCourseFullDetail> {
    let body = wrap(&request_api(runtime, "queryCourseById", detail_payload(id)).await?);
    let mut detail = parse_full_detail(&body, id)?;
    if detail.course.course.selected == Some(true) {
        let chosen = parse_chosen_display(&get_chosen_body(runtime, false).await?)?;
        merge_chosen_display(&mut detail, chosen);
    }
    Ok(detail)
}

pub(crate) async fn get_course_detail_for_write(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i64,
) -> Result<BykcCourse> {
    get_course_detail_inner(runtime, id, true).await
}

async fn get_course_detail_inner(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i64,
    write_preflight: bool,
) -> Result<BykcCourse> {
    let body = wrap(
        &request_for_purpose(
            runtime,
            "queryCourseById",
            detail_payload(id),
            write_preflight,
        )
        .await?,
    );
    if write_preflight {
        parse_course_detail_for_write(&body)
    } else {
        parse_course_detail(&body)
    }
}

pub(crate) async fn get_course_sign_config_for_write(
    runtime: &mut crate::runtime::ClientRuntime,
    id: i64,
) -> Result<Option<crate::domain::BykcSignConfig>> {
    let value = request_preflight_api(runtime, "queryCourseById", detail_payload(id)).await?;
    let course = value
        .as_object()
        .ok_or_else(|| super::error("博雅课程详情结构无效"))?;
    let actual_id = course
        .get("id")
        .and_then(Value::as_i64)
        .ok_or_else(|| super::error("博雅课程详情缺少标识"))?;
    if actual_id != id {
        return Err(super::error("博雅课程详情标识与请求不一致"));
    }
    Ok(course
        .get("courseSignConfig")
        .and_then(Value::as_str)
        .and_then(parse_sign_config))
}

pub(crate) async fn get_chosen_courses(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<BykcChosenCourse>> {
    get_chosen_courses_inner(runtime, false).await
}

pub(crate) async fn get_chosen_courses_for_write(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<BykcChosenCourse>> {
    get_chosen_courses_inner(runtime, true).await
}

async fn get_chosen_courses_inner(
    runtime: &mut crate::runtime::ClientRuntime,
    write_preflight: bool,
) -> Result<Vec<BykcChosenCourse>> {
    let body = get_chosen_body(runtime, write_preflight).await?;
    if write_preflight {
        parse_chosen_courses_for_write(&body)
    } else {
        parse_chosen_courses(&body)
    }
}

async fn get_chosen_body(
    runtime: &mut crate::runtime::ClientRuntime,
    write_preflight: bool,
) -> Result<String> {
    let config = request_for_purpose(
        runtime,
        "getAllConfig",
        serde_json::json!({}),
        write_preflight,
    )
    .await?;
    let (start, end) = resolve_current_semester(&config, Local::now().naive_local())?;
    Ok(wrap(
        &request_for_purpose(
            runtime,
            "queryChosenCourse",
            chosen_payload(&start, &end),
            write_preflight,
        )
        .await?,
    ))
}

async fn request_for_purpose(
    runtime: &mut crate::runtime::ClientRuntime,
    api_name: &str,
    payload: Value,
    write_preflight: bool,
) -> Result<Value> {
    if write_preflight {
        request_preflight_api(runtime, api_name, payload).await
    } else {
        request_api(runtime, api_name, payload).await
    }
}

pub(crate) async fn get_statistics(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcStatistics> {
    parse_statistics(&wrap(
        &request_api(runtime, "queryStatisticByUserId", serde_json::json!({})).await?,
    ))
}

fn catalog_payload(page: i32, size: i32) -> Value {
    serde_json::json!({"pageNumber":page,"pageSize":size})
}
fn detail_payload(id: i64) -> Value {
    serde_json::json!({"id":id})
}
fn chosen_payload(start: &str, end: &str) -> Value {
    serde_json::json!({"startDate":start,"endDate":end})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 博雅读取参数保持冻结精确键并直接使用学期字符串() {
        assert_eq!(
            catalog_payload(2, 17),
            serde_json::json!({"pageNumber":2,"pageSize":17})
        );
        assert_eq!(detail_payload(71), serde_json::json!({"id":71}));
        let (start, end) = resolve_current_semester(
            &serde_json::json!({"semester":[{
                "semesterStartDate":"2000-01-02 03:04:05", "semesterEndDate":"2999-06-07 08:09:10"
            }]}),
            Local::now().naive_local(),
        )
        .unwrap();
        assert_eq!(
            chosen_payload(&start, &end),
            serde_json::json!({
            "startDate":"2000-01-02 03:04:05","endDate":"2999-06-07 08:09:10"})
        );
    }
}
