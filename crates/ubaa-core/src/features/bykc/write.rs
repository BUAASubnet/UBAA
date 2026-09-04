//! 博雅选课、退选与签到写操作。
#![allow(clippy::missing_errors_doc)]

use std::f64::consts::PI;

use chrono::Local;
use rand::Rng;
use rand::seq::SliceRandom;
use serde::Deserialize;
use serde_json::Value;

use super::auth::{request_write_api, write_outcome_unknown};
use super::error;
use super::parser::sign_eligibilities;
use super::read::{
    get_chosen_courses_for_write, get_course_detail_for_write, get_course_sign_config_for_write,
};
use crate::domain::{
    ActionEligibility, BykcActionResult, BykcSignConfig, BykcSignLocationRequirement,
    BykcSignPreflight, BykcSignRequest,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 选课写操作。
pub(crate) async fn select_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
) -> Result<BykcActionResult> {
    preflight_course_action(runtime, course_id, CourseAction::Select).await?;
    let value = request_write_api(
        runtime,
        "choseCourse",
        serde_json::json!({"courseId": course_id}),
    )
    .await?;
    course_action_result(&value, "选课成功")
}

/// 退选写操作。
pub(crate) async fn deselect_course(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
) -> Result<BykcActionResult> {
    preflight_course_action(runtime, course_id, CourseAction::Deselect).await?;
    let value = request_write_api(
        runtime,
        "delChosenCourse",
        serde_json::json!({"id": course_id}),
    )
    .await?;
    course_action_result(&value, "退选成功")
}

#[derive(Clone, Copy)]
enum CourseAction {
    Select,
    Deselect,
}

async fn preflight_course_action(
    runtime: &mut crate::runtime::ClientRuntime,
    course_id: i64,
    action: CourseAction,
) -> Result<()> {
    validate_course_id(course_id)?;
    let course = get_course_detail_for_write(runtime, course_id).await?;
    if course.id != course_id {
        return Err(error("博雅课程详情标识与请求不一致"));
    }
    let eligibility = match action {
        CourseAction::Select => course.select_eligibility,
        CourseAction::Deselect => course.deselect_eligibility,
    };
    match (action, eligibility) {
        (_, ActionEligibility::Allowed) => Ok(()),
        (CourseAction::Select, ActionEligibility::Denied) => {
            Err(unavailable("课程当前不可选，请刷新课程详情后重试"))
        }
        (CourseAction::Deselect, ActionEligibility::Denied) => {
            Err(unavailable("课程当前不可退选，请刷新课程详情后重试"))
        }
        (CourseAction::Select, ActionEligibility::Unknown) => {
            Err(error("博雅选课资格缺少必要字段"))
        }
        (CourseAction::Deselect, ActionEligibility::Unknown) => {
            Err(error("博雅退选资格缺少必要字段"))
        }
    }
}

fn validate_course_id(course_id: i64) -> Result<()> {
    if course_id <= 0 {
        return Err(invalid_input("课程标识必须为正数"));
    }
    Ok(())
}

fn course_action_result(value: &Value, fallback_message: &str) -> Result<BykcActionResult> {
    let value = value.as_object().ok_or_else(write_outcome_unknown)?;
    serde_json::from_value::<CourseActionPayload>(Value::Object(value.clone()))
        .map_err(|_| write_outcome_unknown())?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or(fallback_message)
            .to_owned(),
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CourseActionPayload {
    #[allow(dead_code)]
    course_current_count: Option<i32>,
}

/// 博雅签到或签退写操作。
pub(crate) async fn preflight_sign_course(
    runtime: &mut crate::runtime::ClientRuntime,
    request: &BykcSignRequest,
) -> Result<(BykcSignPreflight, BykcSignConfig)> {
    validate_sign_request(request)?;
    let chosen = get_chosen_courses_for_write(runtime)
        .await?
        .into_iter()
        .find(|course| course.course_id == request.course_id)
        .ok_or_else(|| unavailable("该课程不在当前学期已选列表中"))?;
    let config = match chosen.sign_config {
        Some(config) => Some(config),
        None => get_course_sign_config_for_write(runtime, request.course_id).await?,
    };
    let (sign, sign_out) = sign_eligibilities(
        chosen.course_id,
        chosen.checkin,
        chosen.pass,
        config.as_ref(),
        Local::now().naive_local(),
    );
    let eligibility = if request.sign_type == 1 {
        sign
    } else {
        sign_out
    };
    match eligibility {
        ActionEligibility::Allowed => {}
        ActionEligibility::Denied => return Err(unavailable("课程当前不允许执行该签到操作")),
        ActionEligibility::Unknown => return Err(error("博雅签到资格缺少必要字段")),
    }
    let config = config.ok_or_else(|| error("博雅签到配置缺少必要字段"))?;
    let needs_fallback = sign_location_requires_fallback(&config);
    if needs_fallback && request.lat.is_none() {
        return Err(invalid_input("未提供签到坐标且后端未返回签到范围"));
    }
    let (window_start, window_end) = if request.sign_type == 1 {
        (config.sign_start_date.clone(), config.sign_end_date.clone())
    } else {
        (
            config.sign_out_start_date.clone(),
            config.sign_out_end_date.clone(),
        )
    };
    let (window_start, window_end) = window_start
        .zip(window_end)
        .ok_or_else(|| error("博雅签到时间窗缺少必要字段"))?;
    let preflight = BykcSignPreflight {
        course_id: chosen.course_id,
        course_name: chosen.course_name,
        sign_type: request.sign_type,
        window_start,
        window_end,
        location_requirement: if needs_fallback {
            BykcSignLocationRequirement::ProvidedCoordinates
        } else {
            BykcSignLocationRequirement::ConfiguredRange
        },
    };
    Ok((preflight, config))
}

/// 博雅签到或签退写操作。
pub(crate) async fn sign_course(
    runtime: &mut crate::runtime::ClientRuntime,
    request: BykcSignRequest,
) -> Result<BykcActionResult> {
    let (_, config) = preflight_sign_course(runtime, &request).await?;
    let (lat, lng) = resolve_sign_location(&config, request.lat, request.lng)?;
    let value = request_write_api(
        runtime,
        "signCourseByUser",
        sign_payload(&request, lat, lng),
    )
    .await?;
    Ok(BykcActionResult {
        message: value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or(if request.sign_type == 1 {
                "签到成功"
            } else {
                "签退成功"
            })
            .to_owned(),
    })
}

pub(super) fn sign_payload(request: &BykcSignRequest, lat: f64, lng: f64) -> Value {
    serde_json::json!({
        "courseId": request.course_id,
        "signLat": lat,
        "signLng": lng,
        "signType": request.sign_type,
    })
}

fn validate_sign_request(request: &BykcSignRequest) -> Result<()> {
    if request.course_id <= 0 || !matches!(request.sign_type, 1 | 2) {
        return Err(invalid_input("课程标识或签到类型无效"));
    }
    match (request.lat, request.lng) {
        (None, None) => Ok(()),
        (Some(lat), Some(lng))
            if lat.is_finite()
                && lng.is_finite()
                && (-90.0..=90.0).contains(&lat)
                && (-180.0..=180.0).contains(&lng) =>
        {
            Ok(())
        }
        _ => Err(invalid_input("签到经纬度必须同时提供且位于有效范围")),
    }
}

pub(super) fn resolve_sign_location(
    config: &BykcSignConfig,
    fallback_lat: Option<f64>,
    fallback_lng: Option<f64>,
) -> Result<(f64, f64)> {
    let mut rng = rand::thread_rng();
    if let Some(point) = config.sign_points.choose(&mut rng)
        && is_usable_sign_point(point)
    {
        let distance = point.radius * rng.r#gen::<f64>().sqrt();
        let angle = rng.r#gen::<f64>() * 2.0 * PI;
        return Ok(destination_point(point.lat, point.lng, distance, angle));
    }
    fallback_lat
        .zip(fallback_lng)
        .ok_or_else(|| invalid_input("未提供签到坐标且后端未返回签到范围"))
}

pub(super) fn sign_location_requires_fallback(config: &BykcSignConfig) -> bool {
    config.sign_points.is_empty()
        || config
            .sign_points
            .iter()
            .any(|point| !is_usable_sign_point(point))
}

fn is_usable_sign_point(point: &crate::domain::BykcSignPoint) -> bool {
    point.lat.is_finite()
        && point.lng.is_finite()
        && point.radius.is_finite()
        && (-90.0..=90.0).contains(&point.lat)
        && (-180.0..=180.0).contains(&point.lng)
        && point.radius > 0.0
}

fn destination_point(lat: f64, lng: f64, distance: f64, angle: f64) -> (f64, f64) {
    const EARTH_RADIUS_METERS: f64 = 6_371_000.0;
    let angular_distance = distance / EARTH_RADIUS_METERS;
    let lat_radians = lat.to_radians();
    let lng_radians = lng.to_radians();
    let destination_lat = (lat_radians.sin() * angular_distance.cos()
        + lat_radians.cos() * angular_distance.sin() * angle.cos())
    .asin();
    let destination_lng = lng_radians
        + (angle.sin() * angular_distance.sin() * lat_radians.cos())
            .atan2(angular_distance.cos() - lat_radians.sin() * destination_lat.sin());
    (destination_lat.to_degrees(), destination_lng.to_degrees())
}

fn invalid_input(message: &str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

fn unavailable(message: &str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, true, message)
}
