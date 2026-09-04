//! 场馆预约、取消与提交表单构造。

use std::collections::BTreeMap;

use serde_json::{Map, Value};

use crate::domain::{
    ActionEligibility, CgyyActionResult, CgyyReservationPreflight, CgyyReservationReceipt,
    CgyyReservationResult, CgyyReservationSelection, CgyyReservationSubmitRequest,
    CgyyReservationTarget,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpMethod, HttpResponse};
use crate::runtime::ClientRuntime;

use super::auth::{business_request, ensure_login};
use super::captcha::{check_captcha, prepare_captcha_once};
use super::http::{log_response, signed_request};
use super::parser::{data, error, parse_action_result};
use super::read::get_day_context;

struct ReservationAuthority {
    request: CgyyReservationSubmitRequest,
    preflight: CgyyReservationPreflight,
    reservation_token: String,
    canonical_selections: Vec<CgyyReservationSelection>,
}

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
    request: CgyyReservationSubmitRequest,
) -> Result<CgyyReservationResult> {
    let authority = reservation_authority(runtime, &request).await?;
    let mut request = authority.request;
    let token = authority.reservation_token;
    let order_json = reservation_order_json(&authority.canonical_selections)?;
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
            Ok(()) => return submit_order(runtime, &request, &token, &order_json).await,
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| error("验证码处理失败")))
}

/// 重新读取日期与槽位，返回不含 token、验证码和表单正文的预约权威摘要。
pub(crate) async fn preflight_reservation(
    runtime: &mut ClientRuntime,
    request: &CgyyReservationSubmitRequest,
) -> Result<CgyyReservationPreflight> {
    Ok(reservation_authority(runtime, request).await?.preflight)
}

async fn reservation_authority(
    runtime: &mut ClientRuntime,
    request: &CgyyReservationSubmitRequest,
) -> Result<ReservationAuthority> {
    let request = normalize_submit_request(request)?;
    let day = get_day_context(runtime, request.venue_site_id, &request.reservation_date).await?;
    if !day.requested_date_exact || day.info.reservation_date != request.reservation_date {
        return Err(authority_changed("场馆预约日期响应与请求不一致"));
    }
    let reservation_token = day
        .reservation_token
        .filter(|token| !token.trim().is_empty())
        .ok_or_else(|| authority_changed("场馆预约上下文缺少必要令牌"))?;

    let requested_space_id = request.selections[0].space_id;
    let matching_spaces = day
        .info
        .spaces
        .iter()
        .filter(|space| space.space_id == requested_space_id)
        .collect::<Vec<_>>();
    let [space] = matching_spaces.as_slice() else {
        return Err(authority_changed("场馆预约空间身份不唯一或已变化"));
    };

    let mut targets = Vec::with_capacity(request.selections.len());
    for selection in &request.selections {
        let matching_slots = space
            .slots
            .iter()
            .filter(|slot| slot.time_id == selection.time_id)
            .collect::<Vec<_>>();
        let [slot] = matching_slots.as_slice() else {
            return Err(authority_changed("场馆预约时段身份不唯一或已变化"));
        };
        match slot.reservation_eligibility {
            ActionEligibility::Allowed => {}
            ActionEligibility::Denied => {
                return Err(unavailable("场馆预约时段当前不可预约，请刷新后重试"));
            }
            ActionEligibility::Unknown => {
                return Err(authority_changed("场馆预约时段资格缺少必要字段"));
            }
        }
        let target = slot
            .reservation_target
            .as_ref()
            .filter(|target| target_matches_request(target, &request, selection))
            .ok_or_else(|| authority_changed("场馆预约目标与请求不一致"))?;
        targets.push(target.clone());
    }
    targets.sort_by_key(|target| target.time_ordinal);
    if targets.len() == 2 && targets[1].time_ordinal.checked_sub(targets[0].time_ordinal) != Some(1)
    {
        return Err(invalid_input("同次预约的两个时段必须相邻"));
    }
    let canonical_selections = targets
        .iter()
        .map(|target| CgyyReservationSelection {
            space_id: target.space_id,
            time_id: target.time_id,
            venue_space_group_id: target.venue_space_group_id,
        })
        .collect();
    let preflight = CgyyReservationPreflight {
        venue_site_id: request.venue_site_id,
        reservation_date: request.reservation_date.clone(),
        targets,
    };
    Ok(ReservationAuthority {
        request,
        preflight,
        reservation_token,
        canonical_selections,
    })
}

fn target_matches_request(
    target: &CgyyReservationTarget,
    request: &CgyyReservationSubmitRequest,
    selection: &CgyyReservationSelection,
) -> bool {
    target.venue_site_id == request.venue_site_id
        && target.reservation_date == request.reservation_date
        && target.space_id == selection.space_id
        && target.time_id == selection.time_id
        && target.venue_space_group_id == selection.venue_space_group_id
        && target.time_ordinal >= 0
}

async fn submit_order(
    runtime: &mut ClientRuntime,
    request: &CgyyReservationSubmitRequest,
    token: &str,
    order_json: &str,
) -> Result<CgyyReservationResult> {
    let form = build_submit_form(request, token, order_json);
    let access_token = ensure_login(runtime).await?;
    let mut http_request = signed_request(
        runtime,
        HttpMethod::Post,
        "/api/reservation/order/submit",
        form.clone(),
        Some(&access_token),
    )?;
    http_request.body = crate::upstream::encode_form(&form);
    let expected_final_url = http_request.url.clone();
    let response = runtime.request_non_idempotent(http_request).await?;
    log_response(runtime, "reservation.submit", &response);
    if response.status == 401
        || (300..400).contains(&response.status)
        || response.final_url != expected_final_url
    {
        return Err(write_outcome_unknown());
    }
    let root = parse_submit_root(&response)?;
    let code = root.get("code").and_then(strict_i32_value);
    match code {
        Some(200) => {}
        Some(_) => return Err(submit_rejected()),
        None => return Err(write_outcome_unknown()),
    }
    let receipt = parse_receipt(&root, request)?;
    Ok(CgyyReservationResult {
        success: true,
        message: "预约成功".into(),
        receipt,
    })
}

pub(super) fn validate_submit_request(request: &CgyyReservationSubmitRequest) -> Result<()> {
    if request.venue_site_id <= 0 || request.reservation_date.trim().is_empty() {
        return Err(invalid_input("场馆站点和预约日期不能为空"));
    }
    if !(1..=2).contains(&request.selections.len())
        || request.selections.iter().any(|item| {
            item.space_id <= 0
                || item.time_id <= 0
                || item
                    .venue_space_group_id
                    .is_some_and(|group_id| group_id <= 0)
        })
    {
        return Err(invalid_input("场馆预约必须选择一至两个有效时段"));
    }
    let first = &request.selections[0];
    if request.selections.iter().any(|selection| {
        selection.space_id != first.space_id
            || selection.venue_space_group_id != first.venue_space_group_id
    }) {
        return Err(invalid_input("同次预约必须选择同一空间和空间组"));
    }
    if request.selections.len() == 2 && request.selections[0] == request.selections[1] {
        return Err(invalid_input("同次预约不能重复选择时段"));
    }
    if request.phone.trim().is_empty()
        || request.theme.trim().is_empty()
        || request.activity_content.trim().is_empty()
        || request.joiners.trim().is_empty()
        || request.purpose_type <= 0
        || request.joiner_num <= 0
    {
        return Err(invalid_input("场馆预约必填字段不完整"));
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
        && request
            .captcha_jigsaw_image_base64
            .as_deref()
            .is_some_and(|value| !value.is_empty())
        && !request.captcha_token.trim().is_empty()
        && !has_external;
    if (has_external && !external)
        || (has_solver_input && !solver_input)
        || (external && has_solver_input)
        || (!external && !solver_input && (has_external || has_solver_input || has_captcha_token))
    {
        return Err(invalid_input("验证码材料不完整或相互冲突"));
    }
    if !external && !solver_input {
        return Ok(());
    }
    Ok(())
}

fn normalize_submit_request(
    request: &CgyyReservationSubmitRequest,
) -> Result<CgyyReservationSubmitRequest> {
    validate_submit_request(request)?;
    let mut normalized = request.clone();
    request
        .reservation_date
        .trim()
        .clone_into(&mut normalized.reservation_date);
    request.phone.trim().clone_into(&mut normalized.phone);
    request.theme.trim().clone_into(&mut normalized.theme);
    request
        .activity_content
        .trim()
        .clone_into(&mut normalized.activity_content);
    request.joiners.trim().clone_into(&mut normalized.joiners);
    Ok(normalized)
}

fn parse_submit_root(response: &HttpResponse) -> Result<Map<String, Value>> {
    serde_json::from_slice::<Value>(&response.body)
        .ok()
        .and_then(|value| value.as_object().cloned())
        .ok_or_else(write_outcome_unknown)
}

fn parse_receipt(
    root: &Map<String, Value>,
    request: &CgyyReservationSubmitRequest,
) -> Result<Option<CgyyReservationReceipt>> {
    let Some(data) = root.get("data") else {
        return Ok(None);
    };
    let data = match data {
        Value::Null => return Ok(None),
        Value::Object(data) => data,
        _ => return Err(write_outcome_unknown()),
    };
    let Some(order_info) = data.get("orderInfo") else {
        return Ok(None);
    };
    let order_info = match order_info {
        Value::Null => return Ok(None),
        Value::Object(order_info) => order_info,
        _ => return Err(write_outcome_unknown()),
    };
    let Some(order_id) = order_info
        .get("id")
        .and_then(strict_i32_value)
        .filter(|order_id| *order_id > 0)
    else {
        return Ok(None);
    };
    let venue_site_id = order_info
        .get("venueSiteId")
        .and_then(strict_i32_value)
        .filter(|site_id| *site_id == request.venue_site_id);
    let reservation_date = order_info
        .get("reservationDate")
        .and_then(Value::as_str)
        .filter(|date| *date == request.reservation_date)
        .map(str::to_owned);
    let order_status = order_info.get("orderStatus").and_then(strict_i32_value);
    Ok(Some(CgyyReservationReceipt {
        order_id,
        venue_site_id,
        reservation_date,
        order_status,
    }))
}

fn strict_i32_value(value: &Value) -> Option<i32> {
    match value {
        Value::Number(value) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
        Value::String(value) => value
            .parse::<i32>()
            .ok()
            .filter(|parsed| parsed.to_string() == *value),
        _ => None,
    }
}

fn invalid_input(message: &'static str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

fn unavailable(message: &'static str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, true, message)
}

fn authority_changed(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn submit_rejected() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "场馆预约提交未被确认",
    )
}

fn write_outcome_unknown() -> UbaaError {
    UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        "场馆预约请求已发送，结果未知，请先刷新订单后再决定是否重试",
    )
}
