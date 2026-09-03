//! 场馆预约、取消与提交表单构造。

use std::collections::BTreeMap;

use serde_json::Value;

use crate::domain::{
    CgyyActionResult, CgyyReservationResult, CgyyReservationSelection, CgyyReservationSubmitRequest,
};
use crate::error::Result;
use crate::ports::HttpMethod;
use crate::runtime::ClientRuntime;

use super::auth::business_request;
use super::captcha::{check_captcha, prepare_captcha_once};
use super::parser::{data, error, object, parse_action_result, parse_order, string};
use super::read::get_day_context;

/// 取消指定场馆预约订单。
pub(crate) async fn cancel_order(runtime: &mut ClientRuntime, id: i32) -> Result<CgyyActionResult> {
    let body = business_request(
        runtime,
        HttpMethod::Post,
        &format!("/api/orders/new/cancel/{id}"),
        BTreeMap::new(),
    )
    .await?;
    parse_action_result(&body)
}

fn reservation_order_json(selections: &[CgyyReservationSelection]) -> Result<String> {
    serde_json::to_string(selections).map_err(|_| error("预约时段无法编码"))
}

/// 构造冻结实现要求的预约提交表单。
#[must_use]
pub fn build_submit_form(
    request: &CgyyReservationSubmitRequest,
    token: &str,
    reservation_order_json: &str,
) -> BTreeMap<String, String> {
    let mut form = BTreeMap::new();
    form.insert("venueSiteId".into(), request.venue_site_id.to_string());
    form.insert("reservationDate".into(), request.reservation_date.clone());
    form.insert("reservationOrderJson".into(), reservation_order_json.into());
    form.insert("weekStartDate".into(), request.reservation_date.clone());
    form.insert("phone".into(), request.phone.trim().into());
    form.insert("theme".into(), request.theme.trim().into());
    form.insert("purposeType".into(), request.purpose_type.to_string());
    form.insert("joinerNum".into(), request.joiner_num.to_string());
    form.insert(
        "activityContent".into(),
        request.activity_content.trim().into(),
    );
    form.insert("joiners".into(), request.joiners.trim().into());
    form.insert(
        "isPhilosophySocialSciences".into(),
        if request.is_philosophy_social_sciences {
            "1"
        } else {
            "0"
        }
        .into(),
    );
    form.insert(
        "isOffSchoolJoiner".into(),
        if request.is_off_school_joiner {
            "1"
        } else {
            "0"
        }
        .into(),
    );
    form.insert(
        "captchaVerification".into(),
        request.captcha_verification.clone(),
    );
    form.insert("token".into(), token.into());
    form
}

/// 提交场馆预约；验证码材料可由调用方提供或由 Core 自动获取并校验。
pub(crate) async fn submit_reservation(
    runtime: &mut ClientRuntime,
    mut request: CgyyReservationSubmitRequest,
) -> Result<CgyyReservationResult> {
    validate_submit_request(&request)?;
    let day = get_day_context(runtime, request.venue_site_id, &request.reservation_date).await?;
    let token = day
        .reservation_token
        .ok_or_else(|| error("预约上下文 token 缺失，请刷新后重试"))?;
    let space_id = request.selections[0].space_id;
    if request
        .selections
        .iter()
        .any(|item| item.space_id != space_id)
    {
        return Err(error("同次预约只能选择同一房间的时段"));
    }
    let space = day
        .info
        .spaces
        .iter()
        .find(|item| item.space_id == space_id)
        .ok_or_else(|| error("所选房间不存在或已失效"))?;
    for selection in &request.selections {
        let slot = space
            .slots
            .iter()
            .find(|slot| slot.time_id == selection.time_id)
            .ok_or_else(|| error("所选时段不存在或已失效"))?;
        if !slot.is_reservable {
            return Err(error("所选时段已不可预约，请刷新后重试"));
        }
    }
    let order_json = reservation_order_json(&request.selections)?;
    let context_form = [
        ("venueSiteId".into(), request.venue_site_id.to_string()),
        ("reservationDate".into(), request.reservation_date.clone()),
        ("weekStartDate".into(), request.reservation_date.clone()),
        ("reservationOrderJson".into(), order_json.clone()),
        ("token".into(), token.clone()),
    ]
    .into_iter()
    .collect();
    let context_body = business_request(
        runtime,
        HttpMethod::Post,
        "/api/reservation/order/info",
        context_form,
    )
    .await?;
    data(&context_body)?;

    let external = !request.captcha_verification.trim().is_empty()
        && !request.captcha_point_json.trim().is_empty()
        && !request.captcha_token.trim().is_empty();
    if external {
        check_captcha(runtime, &request).await?;
        return submit_order(runtime, &request, &token, &order_json).await;
    }
    let mut last_error = None;
    for _ in 0..3 {
        match prepare_captcha_once(runtime, &mut request).await {
            Ok(()) => match submit_order(runtime, &request, &token, &order_json).await {
                Ok(result) => return Ok(result),
                Err(error) => last_error = Some(error),
            },
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| error("验证码处理失败")))
}

async fn submit_order(
    runtime: &mut ClientRuntime,
    request: &CgyyReservationSubmitRequest,
    token: &str,
    order_json: &str,
) -> Result<CgyyReservationResult> {
    let form = build_submit_form(request, token, order_json);
    let body = business_request(
        runtime,
        HttpMethod::Post,
        "/api/reservation/order/submit",
        form,
    )
    .await?;
    let root = object(&body)?;
    let message = string(&root, "message").unwrap_or_else(|| "预约提交完成".into());
    let value = data(&body)?;
    let order = value
        .as_object()
        .and_then(|map| map.get("orderInfo"))
        .and_then(Value::as_object)
        .map(parse_order);
    Ok(CgyyReservationResult {
        success: true,
        message,
        order,
    })
}

pub(super) fn validate_submit_request(request: &CgyyReservationSubmitRequest) -> Result<()> {
    if request.venue_site_id <= 0 || request.reservation_date.trim().is_empty() {
        return Err(error("场馆站点和预约日期不能为空"));
    }
    if request.selections.is_empty()
        || request
            .selections
            .iter()
            .any(|item| item.space_id <= 0 || item.time_id <= 0)
    {
        return Err(error("至少选择一个有效的预约时段"));
    }
    let has_external = !request.captcha_verification.trim().is_empty()
        || !request.captcha_point_json.trim().is_empty();
    let external = !request.captcha_verification.trim().is_empty()
        && !request.captcha_point_json.trim().is_empty()
        && !request.captcha_token.trim().is_empty();
    let has_solver_input = request
        .captcha_secret_key
        .as_deref()
        .is_some_and(|value| !value.is_empty())
        || request
            .captcha_original_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        || request
            .captcha_jigsaw_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty());
    let has_captcha_token = !request.captcha_token.trim().is_empty();
    let solver_input = request
        .captcha_secret_key
        .as_deref()
        .is_some_and(|value| !value.is_empty())
        && request
            .captcha_original_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        && !request.captcha_token.trim().is_empty()
        && !has_external;
    if (has_external && !external)
        || (has_solver_input && !solver_input)
        || (external && has_solver_input)
        || (!external && !solver_input && (has_external || has_solver_input || has_captcha_token))
    {
        return Err(error("验证码材料不完整或相互冲突"));
    }
    if !external && !solver_input {
        return Ok(());
    }
    Ok(())
}
