//! 博雅只读服务调用与当前学期选择。
#![allow(clippy::missing_errors_doc)]

use chrono::Local;
use serde_json::Value;

use super::auth::request_api;
use super::parser::{
    parse_chosen_courses, parse_course_detail, parse_courses_at, parse_profile, parse_statistics,
    resolve_current_semester,
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
                serde_json::json!({"pageNumber":page,"pageSize":size}),
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
    parse_course_detail(&wrap(
        &request_api(runtime, "queryCourseById", serde_json::json!({"id":id})).await?,
    ))
}

pub(crate) async fn get_chosen_courses(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<BykcChosenCourse>> {
    let config = request_api(runtime, "getAllConfig", serde_json::json!({})).await?;
    let (start, end) = resolve_current_semester(&config, Local::now().naive_local())?;
    parse_chosen_courses(&wrap(
        &request_api(
            runtime,
            "queryChosenCourse",
            serde_json::json!({"startDate":start,"endDate":end}),
        )
        .await?,
    ))
}

pub(crate) async fn get_statistics(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<BykcStatistics> {
    parse_statistics(&wrap(
        &request_api(runtime, "queryStatisticByUserId", serde_json::json!({})).await?,
    ))
}
