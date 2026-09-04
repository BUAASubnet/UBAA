//! 图书馆 CAS/token 生命周期、业务请求与读写操作。

use serde_json::{Value, json};
use tracing::debug;

use crate::domain::{
    ActionEligibility, LibBookArea, LibBookAreaDetail, LibBookBookingsPage, LibBookCancelPreflight,
    LibBookCancelRequest, LibBookCancelResult, LibBookLibrary, LibBookReservePreflight,
    LibBookReserveRequest, LibBookReserveResult, LibBookSeat,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;

use super::LibBookCredential;
use super::crypto::encrypt_reserve_request;
use super::parser::{
    error, is_expired_body, parse_area_detail_for, parse_area_detail_for_day, parse_areas,
    parse_bookings_for_request, parse_bookings_with_strict_metadata, parse_libraries, parse_seats,
};

const BASE_URL: &str = "https://booking.lib.buaa.edu.cn";
const CAS_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbooking.lib.buaa.edu.cn%2Fv4%2Flogin%2Fcas";
const REDIRECT_LIMIT: usize = 8;
const ACCEPT: &str = "application/json, text/plain, */*";
const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36";

/// 查询图书馆楼馆列表。
pub(crate) async fn get_libraries(
    runtime: &mut crate::runtime::ClientRuntime,
    day: &str,
) -> Result<Vec<LibBookLibrary>> {
    parse_libraries(&request_json(runtime, "space/pcTopFor", json!({"day": day}), true).await?)
}

/// 查询图书馆分区列表。
pub(crate) async fn get_areas(
    runtime: &mut crate::runtime::ClientRuntime,
    premises_id: &str,
    storey_id: Option<&str>,
    day: &str,
) -> Result<Vec<LibBookArea>> {
    let body = json!({"premisesIds": premises_id, "categoryIds": [], "storeyIds": storey_id.map_or_else(Vec::new, |id| vec![id]), "boutiqueIds": [], "date": day});
    parse_areas(&request_json(runtime, "space/pick", body, true).await?)
}

/// 查询分区详情。
pub(crate) async fn get_area_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    area_id: &str,
) -> Result<LibBookAreaDetail> {
    parse_area_detail_for(
        area_id,
        &request_json(runtime, "Space/map", json!({"id": area_id}), true).await?,
    )
}

/// 查询指定日期和时段的座位。
pub(crate) async fn get_seats(
    runtime: &mut crate::runtime::ClientRuntime,
    area_id: &str,
    day: &str,
    start_time: &str,
    end_time: &str,
) -> Result<Vec<LibBookSeat>> {
    let body = json!({"id": area_id, "day": day, "label_id": [], "start_time": start_time, "end_time": end_time, "begdate": "", "enddate": ""});
    parse_seats(&request_json(runtime, "Space/seat", body, true).await?)
}

/// 查询当前用户的预约记录。
pub(crate) async fn get_bookings(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    limit: i32,
) -> Result<LibBookBookingsPage> {
    validate_bookings_page(page, limit)?;
    let body = request_bookings(runtime, page, limit).await?;
    parse_bookings_for_request(&body, page, limit)
}

fn validate_bookings_page(page: i32, limit: i32) -> Result<()> {
    if page <= 0 || limit <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    Ok(())
}

async fn request_bookings(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    limit: i32,
) -> Result<String> {
    request_json(
        runtime,
        "member/seat",
        json!({"type": "1", "page": page, "limit": limit}),
        true,
    )
    .await
}

async fn get_cancel_bookings(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    limit: i32,
) -> Result<LibBookBookingsPage> {
    validate_bookings_page(page, limit)?;
    let body = request_bookings(runtime, page, limit).await?;
    parse_bookings_with_strict_metadata(&body).map_err(sanitize_cancel_authority_error)
}

fn sanitize_cancel_authority_error(error: UbaaError) -> UbaaError {
    if error.code != ErrorCode::UpstreamChanged {
        return error;
    }
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "图书馆预约取消资格核对响应无效",
    )
}

pub(crate) async fn reserve(
    runtime: &mut crate::runtime::ClientRuntime,
    request: LibBookReserveRequest,
) -> Result<LibBookReserveResult> {
    let preflight = preflight_reserve(runtime, &request).await?;
    let request = request_from_preflight(&preflight);
    crate::features::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    let body = serde_json::to_vec(&json!({
        "aesjson": encrypt_reserve_request(&request)?,
    }))
    .map_err(|_| error("图书馆预约参数无效"))?;
    let url = runtime.url(&format!("{BASE_URL}/v4/space/confirm"))?;
    let authorization = format!("bearer{}", credential.token);
    let mut http_request = HttpRequest::post(url, body);
    http_request
        .headers
        .insert("Content-Type".into(), "application/json".into());
    apply_headers(runtime, &mut http_request, Some(&authorization))?;
    let response = runtime.request_non_idempotent(http_request).await?;
    if response.status != 200 || final_url_is_authentication(&response.final_url) {
        return Err(write_outcome_unknown());
    }
    let (success, message) = parse_reserve_outcome(&response.body)?;
    Ok(LibBookReserveResult {
        success,
        message,
        booking: None,
    })
}

/// 重新读取分区、时段与座位，形成不含凭证或原始响应的预约权威摘要。
pub(crate) async fn preflight_reserve(
    runtime: &mut crate::runtime::ClientRuntime,
    request: &LibBookReserveRequest,
) -> Result<LibBookReservePreflight> {
    let request = normalize_reserve_request(request)?;
    let detail_body =
        request_json(runtime, "Space/map", json!({"id": request.area_id}), true).await?;
    let detail = parse_area_detail_for_day(&request.area_id, &request.day, &detail_body)?
        .ok_or_else(|| unavailable("图书馆预约日期已变化，请刷新后重新准备"))?;
    if detail.id.trim() != request.area_id {
        return Err(error("图书馆分区详情标识与预约目标不一致"));
    }
    let matching_slots = detail
        .time_slots
        .iter()
        .filter(|slot| slot.id.trim() == request.segment)
        .collect::<Vec<_>>();
    let [slot] = matching_slots.as_slice() else {
        return if matching_slots.is_empty() {
            Err(unavailable("图书馆预约时段已变化，请刷新后重新准备"))
        } else {
            Err(error("图书馆分区详情包含重复预约时段"))
        };
    };
    if slot.start.trim() != request.start_time || slot.end.trim() != request.end_time {
        return Err(unavailable("图书馆预约时段已变化，请刷新后重新准备"));
    }

    let matching_seats = get_seats(
        runtime,
        &request.area_id,
        &request.day,
        &request.start_time,
        &request.end_time,
    )
    .await?
    .into_iter()
    .filter(|seat| seat.id.trim() == request.seat_id)
    .collect::<Vec<_>>();
    let [seat] = matching_seats.as_slice() else {
        return if matching_seats.is_empty() {
            Err(unavailable("图书馆预约座位已变化，请刷新后重新准备"))
        } else {
            Err(error("图书馆座位响应包含重复座位标识"))
        };
    };
    match seat.reserve_eligibility {
        ActionEligibility::Allowed => {}
        ActionEligibility::Denied => {
            return Err(unavailable("该图书馆座位当前不可预约，请刷新后重试"));
        }
        ActionEligibility::Unknown => return Err(error("图书馆座位预约资格缺少必要字段")),
    }
    if seat.reserve_target.as_deref() != Some(request.seat_id.as_str()) {
        return Err(error("图书馆座位预约目标与请求不一致"));
    }

    Ok(LibBookReservePreflight {
        area_id: request.area_id,
        seat_id: request.seat_id.clone(),
        seat_name: safe_summary_field(&seat.name, "图书馆座位"),
        seat_no: safe_summary_field(&seat.no, &request.seat_id),
        day: request.day,
        segment: request.segment,
        start_time: request.start_time,
        end_time: request.end_time,
    })
}

fn normalize_reserve_request(request: &LibBookReserveRequest) -> Result<LibBookReserveRequest> {
    let normalized = LibBookReserveRequest {
        area_id: request.area_id.trim().to_owned(),
        seat_id: request.seat_id.trim().to_owned(),
        day: request.day.trim().to_owned(),
        segment: request.segment.trim().to_owned(),
        start_time: request.start_time.trim().to_owned(),
        end_time: request.end_time.trim().to_owned(),
    };
    if [
        normalized.area_id.as_str(),
        normalized.seat_id.as_str(),
        normalized.day.as_str(),
        normalized.segment.as_str(),
        normalized.start_time.as_str(),
        normalized.end_time.as_str(),
    ]
    .iter()
    .any(|value| value.is_empty())
    {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "图书馆预约目标字段不完整",
        ));
    }
    Ok(normalized)
}

fn request_from_preflight(preflight: &LibBookReservePreflight) -> LibBookReserveRequest {
    LibBookReserveRequest {
        area_id: preflight.area_id.clone(),
        seat_id: preflight.seat_id.clone(),
        day: preflight.day.clone(),
        segment: preflight.segment.clone(),
        start_time: preflight.start_time.clone(),
        end_time: preflight.end_time.clone(),
    }
}

fn safe_summary_field(value: &str, fallback: &str) -> String {
    let value = value
        .chars()
        .filter(|character| !character.is_control())
        .collect::<String>();
    let value = value.trim();
    if value.is_empty() {
        fallback.to_owned()
    } else {
        value.to_owned()
    }
}

fn parse_reserve_outcome(body: &[u8]) -> Result<(bool, String)> {
    let value: Value = serde_json::from_slice(body).map_err(|_| write_outcome_unknown())?;
    let object = value.as_object().ok_or_else(write_outcome_unknown)?;
    let code = object
        .get("code")
        .and_then(strict_i32)
        .filter(|code| matches!(code, 0 | 1))
        .ok_or_else(write_outcome_unknown)?;
    debug_assert!(matches!(code, 0 | 1));

    let data = object.get("data").and_then(Value::as_object);
    let explicit_success = match data.and_then(|data| data.get("success")) {
        Some(Value::Bool(success)) => Some(*success),
        Some(_) => return Err(write_outcome_unknown()),
        None => None,
    };
    let message = [object, data.unwrap_or(object)]
        .into_iter()
        .find_map(|candidate| {
            candidate
                .get("message")
                .or_else(|| candidate.get("msg"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|message| !message.is_empty())
        });
    if message.is_some_and(is_authentication_message) {
        return Err(write_outcome_unknown());
    }
    let frozen_success = message.map(frozen_business_success);
    let success = match (explicit_success, frozen_success) {
        // 冻结客户端以明确负面消息判定业务失败；新响应中的
        // success=true 不得把该信号降级为成功。
        (_, Some(false)) | (Some(false), _) => false,
        (Some(true), _) | (None, Some(true)) => true,
        (None, None) => return Err(write_outcome_unknown()),
    };
    Ok((
        success,
        message
            .unwrap_or(if success {
                "预约成功"
            } else {
                "预约失败"
            })
            .to_owned(),
    ))
}

fn strict_i32(value: &Value) -> Option<i32> {
    match value {
        Value::Number(number) => number
            .as_i64()
            .and_then(|number| i32::try_from(number).ok()),
        Value::String(value) => value.parse().ok(),
        _ => None,
    }
}

fn frozen_business_success(message: &str) -> bool {
    [
        "失败",
        "不可",
        "已被",
        "不能取消",
        "无法取消",
        "已取消",
        "用户取消",
        "已结束",
        "已完成",
    ]
    .iter()
    .all(|negative| !message.contains(negative))
}

fn is_authentication_message(message: &str) -> bool {
    ["登录失效", "请重新登录", "未登录", "登录状态"]
        .iter()
        .any(|part| message.contains(part))
}

fn final_url_is_authentication(value: &str) -> bool {
    let direct = crate::connection::from_webvpn_url(value).unwrap_or_else(|_| value.to_owned());
    url::Url::parse(&direct).is_ok_and(|url| {
        url.host_str()
            .is_some_and(|host| host.eq_ignore_ascii_case("sso.buaa.edu.cn"))
            || matches!(url.path(), "/login" | "/v4/login/cas")
    })
}

fn unavailable(message: &'static str) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, true, message)
}

fn write_outcome_unknown() -> UbaaError {
    UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        "图书馆预约结果未知，请刷新预约记录后再决定是否重试",
    )
}

/// 重新读取 action 产生时所在分页，并形成唯一 active 预约的取消权威摘要。
pub(crate) async fn preflight_cancel(
    runtime: &mut crate::runtime::ClientRuntime,
    request: &LibBookCancelRequest,
) -> Result<LibBookCancelPreflight> {
    let request = normalize_cancel_request(request)?;
    let page = get_cancel_bookings(runtime, request.page, request.limit).await?;
    if page.page != request.page || page.limit != request.limit {
        return Err(error("图书馆预约响应分页与取消目标上下文不一致"));
    }
    let matching = page
        .bookings
        .into_iter()
        .filter(|booking| booking.id.trim() == request.booking_id)
        .collect::<Vec<_>>();
    let [booking] = matching.as_slice() else {
        return if matching.is_empty() {
            Err(unavailable("图书馆预约记录已变化，请刷新后重新准备"))
        } else {
            Err(error("图书馆预约响应包含重复预约标识"))
        };
    };
    match booking.cancel_eligibility {
        ActionEligibility::Allowed => {}
        ActionEligibility::Denied => {
            return Err(unavailable("该图书馆预约已结束或已取消，无需取消"));
        }
        ActionEligibility::Unknown => return Err(error("图书馆预约取消资格缺少必要字段")),
    }
    if booking.cancel_target.as_deref() != Some(request.booking_id.as_str()) {
        return Err(error("图书馆预约取消目标与请求不一致"));
    }

    Ok(LibBookCancelPreflight {
        booking_id: request.booking_id.clone(),
        booking_name: safe_summary_field(&booking.name_merge, "图书馆预约"),
        area_name: safe_summary_field(&booking.area_name, "图书馆分区"),
        seat_no: safe_summary_field(&booking.seat_no, "未知座位"),
        day: safe_summary_field(&booking.day, "未知日期"),
        begin_time: safe_summary_field(&booking.begin_time, "未知开始时间"),
        end_time: safe_summary_field(&booking.end_time, "未知结束时间"),
    })
}

fn normalize_cancel_request(request: &LibBookCancelRequest) -> Result<LibBookCancelRequest> {
    let request = LibBookCancelRequest {
        booking_id: request.booking_id.trim().to_owned(),
        page: request.page,
        limit: request.limit,
    };
    if request.booking_id.is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约编号不能为空",
        ));
    }
    if request.page <= 0 || request.limit <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "图书馆预约分页参数必须为正数",
        ));
    }
    Ok(request)
}

pub(crate) async fn cancel_booking(
    runtime: &mut crate::runtime::ClientRuntime,
    request: LibBookCancelRequest,
) -> Result<LibBookCancelResult> {
    let preflight = preflight_cancel(runtime, &request).await?;
    crate::features::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    let body = serde_json::to_vec(&json!({"id": preflight.booking_id}))
        .map_err(|_| error("图书馆取消参数无效"))?;
    let url = runtime.url(&format!("{BASE_URL}/v4/space/cancel"))?;
    let expected_final_url = url.clone();
    let authorization = format!("bearer{}", credential.token);
    let mut http_request = HttpRequest::post(url, body);
    http_request
        .headers
        .insert("Content-Type".into(), "application/json".into());
    apply_headers(runtime, &mut http_request, Some(&authorization))?;
    let response = runtime.request_non_idempotent(http_request).await?;
    if response.status != 200
        || !final_url_matches_request(&expected_final_url, &response.final_url)
    {
        return Err(cancel_outcome_unknown());
    }
    parse_cancel_outcome(&response.body)
}

fn parse_cancel_outcome(body: &[u8]) -> Result<LibBookCancelResult> {
    let value: Value = serde_json::from_slice(body).map_err(|_| cancel_outcome_unknown())?;
    let object = value.as_object().ok_or_else(cancel_outcome_unknown)?;
    let code = object
        .get("code")
        .and_then(canonical_i32)
        .ok_or_else(cancel_outcome_unknown)?;
    let message = object
        .get("message")
        .or_else(|| object.get("msg"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .ok_or_else(cancel_outcome_unknown)?;
    if is_authentication_message(message) {
        return Err(cancel_outcome_unknown());
    }
    if is_known_cancel_terminal_message(message) {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "图书馆预约已结束、已取消或不存在",
        ));
    }
    if matches!(code, 0 | 1) && message == "取消成功" {
        return Ok(LibBookCancelResult {
            success: true,
            message: "图书馆预约已取消".to_owned(),
        });
    }
    if matches!(code, 0 | 1) && !frozen_business_success(message) {
        return Ok(LibBookCancelResult {
            success: false,
            message: "图书馆预约取消未完成".to_owned(),
        });
    }
    Err(cancel_outcome_unknown())
}

fn canonical_i32(value: &Value) -> Option<i32> {
    match value {
        Value::Number(number) => number
            .as_i64()
            .and_then(|number| i32::try_from(number).ok()),
        Value::String(value) => value
            .parse::<i32>()
            .ok()
            .filter(|parsed| parsed.to_string() == *value),
        _ => None,
    }
}

fn is_known_cancel_terminal_message(message: &str) -> bool {
    [
        "已取消",
        "用户取消",
        "已结束",
        "不能取消",
        "无法取消",
        "已完成",
        "不存在",
        "失效",
    ]
    .iter()
    .any(|part| message.contains(part))
}

fn final_url_matches_request(expected: &str, actual: &str) -> bool {
    let expected =
        crate::connection::from_webvpn_url(expected).unwrap_or_else(|_| expected.to_owned());
    let actual = crate::connection::from_webvpn_url(actual).unwrap_or_else(|_| actual.to_owned());
    url::Url::parse(&expected)
        .ok()
        .zip(url::Url::parse(&actual).ok())
        .is_some_and(|(expected, actual)| expected == actual)
}

fn cancel_outcome_unknown() -> UbaaError {
    UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        "图书馆取消结果未知，请刷新预约记录后再决定是否重试",
    )
}

async fn request_json(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    body: Value,
    allow_retry: bool,
) -> Result<String> {
    crate::features::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    let url = runtime.url(&format!("{BASE_URL}/v4/{path}"))?;
    let request_body = serde_json::to_vec(&body).map_err(|_| error("图书馆请求参数无效"))?;
    let authorization = format!("bearer{}", credential.token);
    let mut request = HttpRequest::post(url, request_body);
    request
        .headers
        .insert("Content-Type".into(), "application/json".into());
    apply_headers(runtime, &mut request, Some(&authorization))?;
    let response = runtime.request(request).await?;
    debug!(
        target: "ubaa::libbook",
        operation = path,
        route = ?runtime.mode(),
        status = response.status,
        final_url = %safe_url(&response.final_url),
        body_len = response.body.len(),
        body_shape = %safe_body_shape(&response.body),
        "图书馆业务响应摘要"
    );
    if response.status == 401 || (allow_retry && is_expired_body(&crate::features::body(&response)))
    {
        if allow_retry {
            runtime.feature_state().libbook.clear_credential();
            return Box::pin(request_json(runtime, path, body, false)).await;
        }
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "图书馆业务会话已失效",
        ));
    }
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "图书馆服务暂时不可用",
        ));
    }
    Ok(crate::features::body(&response))
}

fn safe_url(value: &str) -> String {
    url::Url::parse(value).map_or_else(
        |_| "<无效 URL>".to_owned(),
        |url| {
            format!(
                "{}://{}{}",
                url.scheme(),
                url.host_str().unwrap_or("<无主机>"),
                url.path()
            )
        },
    )
}

fn safe_body_shape(body: &[u8]) -> String {
    let Ok(value) = serde_json::from_slice::<Value>(body) else {
        return "非 JSON".to_owned();
    };
    let Some(object) = value.as_object() else {
        return format!("顶层={}", json_kind(&value));
    };
    let mut keys = object.keys().cloned().collect::<Vec<_>>();
    keys.sort_unstable();
    let code = object.get("code").map_or_else(
        || "无 code".to_owned(),
        |value| format!("code={}", safe_scalar(value)),
    );
    let data = object.get("data").map_or_else(
        || "无 data".to_owned(),
        |value| format!("data={}", json_kind(value)),
    );
    format!("{}; keys={}; {}", code, keys.join(","), data)
}

fn json_kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "bool",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

fn safe_scalar(value: &Value) -> String {
    match value {
        Value::Number(number) => number.to_string(),
        Value::Bool(value) => value.to_string(),
        Value::String(value) => format!("字符串(len={})", value.len()),
        _ => json_kind(value).to_owned(),
    }
}

async fn current_credential(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<LibBookCredential> {
    let state = runtime.feature_state();
    if let Some(value) = state.libbook.credential() {
        return Ok(value);
    }
    let _guard = state.libbook.login_guard().await;
    if let Some(value) = state.libbook.credential() {
        return Ok(value);
    }
    let cas = fetch_cas(runtime).await?;
    let body = serde_json::to_vec(&json!({"cas": cas})).map_err(|_| error("图书馆登录参数无效"))?;
    let url = runtime.url(&format!("{BASE_URL}/v4/login/user"))?;
    let mut request = HttpRequest::post(url, body);
    request
        .headers
        .insert("Content-Type".into(), "application/json".into());
    apply_headers(runtime, &mut request, None)?;
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "图书馆登录失败",
        ));
    }
    let value: Value =
        serde_json::from_slice(&response.body).map_err(|_| error("图书馆登录响应无法解析"))?;
    let token = value
        .pointer("/data/member/token")
        .and_then(Value::as_str)
        .filter(|v| !v.is_empty())
        .ok_or_else(|| {
            UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "图书馆登录响应缺少 token",
            )
        })?
        .to_owned();
    let credential = LibBookCredential { token };
    state.libbook.set(credential.clone());
    Ok(credential)
}

async fn fetch_cas(runtime: &mut crate::runtime::ClientRuntime) -> Result<String> {
    let mut current = CAS_URL.to_owned();
    for _ in 0..REDIRECT_LIMIT {
        let mut request = HttpRequest::get(runtime.url(&current)?);
        apply_headers(runtime, &mut request, None)?;
        let response = runtime.request(request).await?;
        if let Some(value) = cas_from_url(&response.final_url) {
            return Ok(value);
        }
        let location = response
            .headers
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case("location"))
            .and_then(|(_, values)| values.first())
            .ok_or_else(|| error("图书馆 CAS 登录跳转缺少目标地址"))?;
        let direct_final = crate::connection::from_webvpn_url(&response.final_url)
            .unwrap_or_else(|_| response.final_url.clone());
        let direct_location =
            crate::connection::from_webvpn_url(location).unwrap_or_else(|_| location.clone());
        let target = url::Url::parse(&direct_final)
            .map_err(|_| error("图书馆登录跳转地址无效"))?
            .join(&direct_location)
            .map_err(|_| error("图书馆登录跳转地址无效"))?;
        if !matches!(
            target.host_str(),
            Some("sso.buaa.edu.cn" | "booking.lib.buaa.edu.cn")
        ) {
            return Err(error("图书馆登录跳转到未允许的主机"));
        }
        current = target.to_string();
        if let Some(value) = cas_from_url(&current) {
            return Ok(value);
        }
    }
    Err(error("图书馆登录跳转次数超过限制"))
}

fn apply_headers(
    runtime: &crate::runtime::ClientRuntime,
    request: &mut HttpRequest,
    authorization: Option<&str>,
) -> Result<()> {
    let routed_base = runtime.url(BASE_URL)?;
    for (name, value) in [
        ("Accept", ACCEPT),
        ("User-Agent", USER_AGENT),
        ("X-Requested-With", "XMLHttpRequest"),
        ("Referer", routed_base.as_str()),
        ("Origin", routed_base.as_str()),
    ] {
        request.headers.insert(name.into(), value.into());
    }
    if let Some(value) = authorization {
        request.headers.insert("Authorization".into(), value.into());
    }
    Ok(())
}

fn cas_from_url(raw: &str) -> Option<String> {
    let url = url::Url::parse(raw).ok()?;
    url.query_pairs()
        .find(|(key, _)| key.eq_ignore_ascii_case("cas"))
        .map(|(_, value)| value.into_owned())
        .or_else(|| {
            url.fragment().and_then(|fragment| {
                let query = fragment
                    .split_once('?')
                    .map_or(fragment, |(_, query)| query);
                url::form_urlencoded::parse(query.as_bytes())
                    .find(|(key, _)| key.eq_ignore_ascii_case("cas"))
                    .map(|(_, value)| value.into_owned())
            })
        })
}
