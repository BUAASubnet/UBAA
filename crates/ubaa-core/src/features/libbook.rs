//! 图书馆座位只读响应解析与业务查询。
#![allow(clippy::missing_errors_doc)]

use crate::domain::{
    LibBookArea, LibBookAreaDetail, LibBookBooking, LibBookBookingsPage, LibBookLibrary,
    LibBookSeat, LibBookStorey, LibBookTimeSlot,
};
use crate::domain::{LibBookCancelResult, LibBookReserveRequest, LibBookReserveResult};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use aes::Aes128;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use serde_json::{Map, Value, json};

/// 图书馆查询所需的路线内业务凭据。
#[derive(Clone)]
pub(crate) struct LibBookCredential {
    pub(crate) token: String,
}

#[derive(serde::Serialize)]
struct EncryptedReserveBody<'a> {
    #[serde(rename = "seat_id")]
    seat_id: &'a str,
    segment: &'a str,
    day: &'a str,
    #[serde(rename = "start_time")]
    start_time: &'a str,
    #[serde(rename = "end_time")]
    end_time: &'a str,
}

impl std::fmt::Debug for LibBookCredential {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LibBookCredential")
            .field("token", &"[已隐藏]")
            .finish()
    }
}

const BASE_URL: &str = "https://booking.lib.buaa.edu.cn";
const CAS_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbooking.lib.buaa.edu.cn%2Fv4%2Flogin%2Fcas";
const REDIRECT_LIMIT: usize = 8;

fn error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn text(map: &Map<String, Value>, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| map.get(*key).and_then(Value::as_str))
        .unwrap_or_default()
        .to_owned()
}

fn number(map: &Map<String, Value>, keys: &[&str]) -> i32 {
    keys.iter()
        .find_map(|key| {
            map.get(*key)
                .and_then(Value::as_i64)
                .and_then(|v| i32::try_from(v).ok())
                .or_else(|| {
                    map.get(*key)
                        .and_then(Value::as_str)
                        .and_then(|v| v.parse().ok())
                })
        })
        .unwrap_or_default()
}

fn array<'a>(map: &'a Map<String, Value>, keys: &[&str]) -> &'a [Value] {
    keys.iter()
        .find_map(|key| map.get(*key).and_then(Value::as_array).map(Vec::as_slice))
        .unwrap_or(&[])
}

fn envelope(body: &str) -> Result<Value> {
    let value: Value = serde_json::from_str(body).map_err(|_| error("图书馆响应无法解析"))?;
    let object = value
        .as_object()
        .ok_or_else(|| error("图书馆响应结构无效"))?;
    let code = object.get("code").and_then(|v| {
        v.as_i64()
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    });
    if matches!(code, Some(0 | 1)) {
        Ok(object
            .get("data")
            .or_else(|| object.get("result"))
            .cloned()
            .unwrap_or(Value::Null))
    } else {
        let message = text(object, &["message", "msg"]);
        if is_expired_message(&message) {
            return Err(UbaaError::new(
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "图书馆业务会话已失效",
            ));
        }
        Err(error(if message.is_empty() {
            "图书馆请求失败".to_owned()
        } else {
            message
        }))
    }
}

fn list_value<'a>(value: &'a Value, keys: &[&str]) -> &'a [Value] {
    value
        .as_array()
        .map(Vec::as_slice)
        .or_else(|| value.as_object().map(|o| array(o, keys)))
        .unwrap_or(&[])
}

/// 解析图书馆与楼层列表。
pub fn parse_libraries(body: &str) -> Result<Vec<LibBookLibrary>> {
    let value = envelope(body)?;
    Ok(list_value(&value, &["list", "libraries"])
        .iter()
        .filter_map(Value::as_object)
        .map(|object| LibBookLibrary {
            id: text(object, &["id"]),
            name: text(object, &["name"]),
            free_num: number(object, &["free_num", "freeNum"]),
            total_num: number(object, &["total_num", "totalNum"]),
            storeys: array(object, &["children", "storeys"])
                .iter()
                .filter_map(Value::as_object)
                .map(|storey| LibBookStorey {
                    id: text(storey, &["id"]),
                    name: text(storey, &["name"]),
                    free_num: number(storey, &["free_num", "freeNum"]),
                    total_num: number(storey, &["total_num", "totalNum"]),
                })
                .collect(),
        })
        .collect())
}

/// 解析图书馆分区列表。
pub fn parse_areas(body: &str) -> Result<Vec<LibBookArea>> {
    let value = envelope(body)?;
    Ok(list_value(&value, &["area", "areas", "list"])
        .iter()
        .filter_map(Value::as_object)
        .map(|object| LibBookArea {
            id: text(object, &["id"]),
            name: text(object, &["name"]),
            area_name: text(object, &["area", "areaName"]),
            premises_id: text(object, &["premises_id", "premisesId"]),
            storey_id: text(object, &["storey_id", "storeyId"]),
            free_num: number(object, &["free_num", "freeNum"]),
            total_num: number(object, &["total_num", "totalNum"]),
        })
        .collect())
}

/// 解析分区详情、可用日期和时段。
pub fn parse_area_detail(body: &str) -> Result<LibBookAreaDetail> {
    parse_area_detail_for("", body)
}

/// 解析分区详情，并在上游缺少区域 ID 时使用请求 ID 回退。
pub fn parse_area_detail_for(area_id: &str, body: &str) -> Result<LibBookAreaDetail> {
    let value = envelope(body)?;
    let object = value
        .as_object()
        .ok_or_else(|| error("图书馆分区响应结构无效"))?;
    let area = object
        .get("area")
        .and_then(Value::as_object)
        .unwrap_or(object);
    let dates = object.get("date").and_then(Value::as_object).map_or_else(
        || array(object, &["availableDates", "available_dates"]),
        |date| array(date, &["list"]),
    );
    let available_dates = dates
        .iter()
        .filter_map(|entry| {
            entry
                .as_str()
                .map(str::to_owned)
                .or_else(|| entry.as_object().map(|o| text(o, &["day", "date"])))
        })
        .filter(|date| !date.is_empty())
        .collect();
    let slots = dates.first().and_then(Value::as_object).map_or_else(
        || array(object, &["timeSlots", "time_slots"]),
        |date| array(date, &["times", "timeSlots"]),
    );
    let time_slots = slots
        .iter()
        .filter_map(Value::as_object)
        .map(|slot| {
            let start = text(slot, &["start"]);
            let end = text(slot, &["end"]);
            let mut value = LibBookTimeSlot {
                id: text(slot, &["id"]),
                start,
                end,
                label: text(slot, &["label"]),
            };
            if value.label.is_empty() {
                value.label = format!("{}-{}", value.start, value.end);
            }
            value
        })
        .collect();
    let id = text(area, &["id"]);
    Ok(LibBookAreaDetail {
        id: if id.is_empty() {
            area_id.to_owned()
        } else {
            id
        },
        name: text(area, &["name"]),
        available_dates,
        time_slots,
    })
}

/// 解析座位列表，并将状态 `1` 映射为可用。
pub fn parse_seats(body: &str) -> Result<Vec<LibBookSeat>> {
    let value = envelope(body)?;
    let mut seats: Vec<_> = list_value(&value, &["list", "seats"])
        .iter()
        .filter_map(Value::as_object)
        .map(|object| {
            let status = text(object, &["status"]);
            LibBookSeat {
                id: text(object, &["id"]),
                name: text(object, &["name"]),
                no: text(object, &["no", "seat_no"]),
                status: status.clone(),
                status_name: text(object, &["status_name", "statusName"]),
                is_available: status == "1",
            }
        })
        .collect();
    seats.sort_by(|left, right| left.no.cmp(&right.no));
    Ok(seats)
}

/// 解析当前用户的图书馆预约分页。
pub fn parse_bookings(body: &str) -> Result<LibBookBookingsPage> {
    let value = envelope(body)?;
    let object = value
        .as_object()
        .ok_or_else(|| error("图书馆预约响应结构无效"))?;
    let bookings = array(object, &["data", "bookings", "list"])
        .iter()
        .filter_map(Value::as_object)
        .map(|booking| LibBookBooking {
            id: text(booking, &["id"]),
            name_merge: text(booking, &["nameMerge", "name_merge"]),
            area_name: text(booking, &["name", "area_name", "areaName"]),
            seat_no: text(booking, &["no", "seat_no", "seatNo"]),
            day: text(booking, &["day", "date"]),
            begin_time: text(booking, &["beginTime", "begin_time"]),
            end_time: text(booking, &["endTime", "end_time"]),
            status: text(booking, &["status"]),
            status_name: text(booking, &["status_name", "statusName"]),
        })
        .collect::<Vec<_>>();
    let total = object
        .get("total")
        .and_then(|value| {
            value
                .as_i64()
                .and_then(|value| i32::try_from(value).ok())
                .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
        })
        .unwrap_or_else(|| i32::try_from(bookings.len()).unwrap_or(i32::MAX));
    Ok(LibBookBookingsPage {
        bookings,
        page: number(object, &["current_page", "page"]).max(1),
        limit: number(object, &["per_page", "limit"]).max(1),
        total,
    })
}

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
    if page <= 0 || limit <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    parse_bookings(
        &request_json(
            runtime,
            "member/seat",
            json!({"type": "1", "page": page, "limit": limit}),
            true,
        )
        .await?,
    )
}

fn encrypt_reserve_request(request: &LibBookReserveRequest) -> Result<String> {
    let digits: String = request.day.chars().filter(char::is_ascii_digit).collect();
    if digits.len() != 8 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约日期无效",
        ));
    }
    let key_text = format!("{digits}{}", digits.chars().rev().collect::<String>());
    let key = key_text.as_bytes();
    let plain = serde_json::to_vec(&EncryptedReserveBody {
        seat_id: &request.seat_id,
        segment: &request.segment,
        day: &request.day,
        start_time: "",
        end_time: "",
    })
    .map_err(|_| error("图书馆预约参数无效"))?;
    let cipher = Aes128::new_from_slice(key).map_err(|_| error("图书馆 AES 密钥无效"))?;
    let pad = 16 - (plain.len() % 16);
    let mut padded = plain;
    padded.extend(std::iter::repeat_n(u8::try_from(pad).unwrap_or(16), pad));
    let mut previous = *b"ZZWBKJ_ZHIHUAWEI";
    let mut encrypted = Vec::with_capacity(padded.len());
    for chunk in padded.chunks_exact(16) {
        let mut block = [0_u8; 16];
        for (index, byte) in chunk.iter().enumerate() {
            block[index] = *byte ^ previous[index];
        }
        cipher.encrypt_block(GenericArray::from_mut_slice(&mut block));
        encrypted.extend_from_slice(&block);
        previous = block;
    }
    Ok(STANDARD.encode(encrypted))
}

pub(crate) async fn reserve(
    runtime: &mut crate::runtime::ClientRuntime,
    request: LibBookReserveRequest,
) -> Result<LibBookReserveResult> {
    if request.seat_id.trim().is_empty()
        || request.segment.trim().is_empty()
        || request.day.trim().is_empty()
    {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约座位、时段和日期不能为空",
        ));
    }
    let body = json!({"aesjson": encrypt_reserve_request(&request)?});
    let response = request_json(runtime, "space/confirm", body, true).await?;
    let value = envelope(&response)?;
    let object = value.as_object();
    let success = object
        .and_then(|m| m.get("success"))
        .and_then(Value::as_bool)
        .or_else(|| {
            object
                .and_then(|m| m.get("status"))
                .and_then(Value::as_i64)
                .map(|v| v == 1)
        })
        .unwrap_or(true);
    let message = object
        .and_then(|m| m.get("message").or_else(|| m.get("msg")))
        .and_then(Value::as_str)
        .unwrap_or(if success {
            "预约成功"
        } else {
            "预约失败"
        })
        .to_owned();
    Ok(LibBookReserveResult {
        success,
        message,
        booking: None,
    })
}

pub(crate) async fn cancel_booking(
    runtime: &mut crate::runtime::ClientRuntime,
    booking_id: &str,
) -> Result<LibBookCancelResult> {
    if booking_id.trim().is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约编号不能为空",
        ));
    }
    let response = request_json(runtime, "space/cancel", json!({"id": booking_id}), true).await?;
    let value = envelope(&response)?;
    let object = value.as_object();
    let success = object
        .and_then(|m| m.get("success"))
        .and_then(Value::as_bool)
        .or_else(|| {
            object
                .and_then(|m| m.get("status"))
                .and_then(Value::as_i64)
                .map(|v| v == 1)
        })
        .unwrap_or(true);
    let message = object
        .and_then(|m| m.get("message").or_else(|| m.get("msg")))
        .and_then(Value::as_str)
        .unwrap_or(if success {
            "取消成功"
        } else {
            "取消失败"
        })
        .to_owned();
    Ok(LibBookCancelResult { success, message })
}

async fn request_json(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    body: Value,
    allow_retry: bool,
) -> Result<String> {
    super::require_session(runtime)?;
    let credential = current_credential(runtime).await?;
    let url = runtime.url(&format!("{BASE_URL}/v4/{path}"))?;
    let request_body = serde_json::to_vec(&body).map_err(|_| error("图书馆请求参数无效"))?;
    let authorization = format!("bearer{}", credential.token);
    let referer = format!("{BASE_URL}/");
    let response = super::post_json(
        runtime,
        url,
        request_body,
        &[
            ("Authorization", &authorization),
            ("Origin", BASE_URL),
            ("Referer", &referer),
            ("X-Requested-With", "XMLHttpRequest"),
        ],
    )
    .await?;
    if response.status == 401 || (allow_retry && is_expired_body(&super::body(&response))) {
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
    Ok(super::body(&response))
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
    let response = super::post_json(runtime, url, body, &[("Origin", BASE_URL)]).await?;
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
        let response = runtime
            .request(HttpRequest::get(runtime.url(&current)?))
            .await?;
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

fn is_expired_message(message: &str) -> bool {
    ["登录失效", "请重新登录", "未登录", "登录状态"]
        .iter()
        .any(|part| message.contains(part))
}
fn is_expired_body(body: &str) -> bool {
    serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|value| value.as_object().cloned())
        .is_some_and(|object| is_expired_message(&text(&object, &["message", "msg"])))
}

#[cfg(test)]
mod crypto_tests {
    use super::encrypt_reserve_request;
    use crate::domain::LibBookReserveRequest;

    #[test]
    fn reserve_request_matches_frozen_golden_vector() {
        let encrypted = encrypt_reserve_request(&LibBookReserveRequest {
            area_id: "8".into(),
            seat_id: "101".into(),
            day: "2026-05-08".into(),
            segment: "seg-1".into(),
            start_time: String::new(),
            end_time: String::new(),
        })
        .expect("vector should encrypt");
        assert_eq!(
            encrypted,
            "lGWxL9YCYE0sXIQzPsUCs3jfaFPunT/NyR93uF2nVP1OQPYYihpMRBvm7jxYdUZNTMCyIRtdY8d3DgCNz8G3lmeWmPjvy6jV2KeuJXR8nrOmk26JK+ATZB1VXBNOFebA"
        );
    }
}
