//! 图书馆响应 envelope、primitive fallback 与 DTO 解析。

use serde_json::{Map, Value};

use crate::domain::{
    ActionEligibility, LibBookArea, LibBookAreaDetail, LibBookBooking, LibBookBookingsPage,
    LibBookLibrary, LibBookSeat, LibBookStorey, LibBookTimeSlot,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(super) fn error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

fn text(map: &Map<String, Value>, keys: &[&str]) -> String {
    keys.iter()
        .find_map(|key| {
            let value = map.get(*key)?;
            value
                .as_str()
                .map(str::to_owned)
                .or_else(|| value.as_i64().map(|number| number.to_string()))
                .or_else(|| value.as_u64().map(|number| number.to_string()))
                .or_else(|| value.as_f64().map(|number| number.to_string()))
                .or_else(|| value.as_bool().map(|boolean| boolean.to_string()))
        })
        .unwrap_or_default()
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

fn optional_i32(map: &Map<String, Value>, key: &str) -> Option<i32> {
    match map.get(key)? {
        Value::Number(value) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
        Value::String(value) => value
            .parse::<i32>()
            .ok()
            .filter(|parsed| parsed.to_string() == *value),
        _ => None,
    }
}

fn array<'a>(map: &'a Map<String, Value>, keys: &[&str]) -> &'a [Value] {
    keys.iter()
        .find_map(|key| map.get(*key).and_then(Value::as_array).map(Vec::as_slice))
        .unwrap_or(&[])
}

pub(super) fn envelope(body: &str) -> Result<Value> {
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
    let time_slots = parse_time_slots(slots);
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

/// 从 `Space/map` 原始日期列表中唯一选择目标日期，并只返回该日期的时段。
pub(super) fn parse_area_detail_for_day(
    area_id: &str,
    day: &str,
    body: &str,
) -> Result<Option<LibBookAreaDetail>> {
    let value = envelope(body)?;
    let object = value
        .as_object()
        .ok_or_else(|| error("图书馆分区响应结构无效"))?;
    let area = object
        .get("area")
        .and_then(Value::as_object)
        .unwrap_or(object);
    let dates = object
        .get("date")
        .and_then(Value::as_object)
        .map_or(&[] as &[Value], |date| array(date, &["list"]));
    let matching_dates = dates
        .iter()
        .filter_map(Value::as_object)
        .filter(|date| text(date, &["day", "date"]).trim() == day)
        .collect::<Vec<_>>();
    let [date] = matching_dates.as_slice() else {
        return if matching_dates.is_empty() {
            Ok(None)
        } else {
            Err(error("图书馆分区响应包含重复预约日期"))
        };
    };
    let id = text(area, &["id"]);
    Ok(Some(LibBookAreaDetail {
        id: if id.is_empty() {
            area_id.to_owned()
        } else {
            id
        },
        name: text(area, &["name"]),
        available_dates: vec![day.to_owned()],
        time_slots: parse_time_slots(array(date, &["times", "timeSlots"])),
    }))
}

fn parse_time_slots(slots: &[Value]) -> Vec<LibBookTimeSlot> {
    slots
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
        .collect()
}

/// 解析座位列表，并从严格整数状态与非空座位编号派生预约资格。
pub fn parse_seats(body: &str) -> Result<Vec<LibBookSeat>> {
    let value = envelope(body)?;
    let mut seats: Vec<_> = list_value(&value, &["list", "seats"])
        .iter()
        .filter_map(Value::as_object)
        .map(|object| {
            let id = text(object, &["id"]);
            let status = optional_i32(object, "status");
            let target = (!id.trim().is_empty()).then(|| id.trim().to_owned());
            let reserve_eligibility = match (status, target.as_ref()) {
                (Some(1), Some(_)) => ActionEligibility::Allowed,
                (Some(2 | 3), Some(_)) => ActionEligibility::Denied,
                _ => ActionEligibility::Unknown,
            };
            let reserve_target = match reserve_eligibility {
                ActionEligibility::Allowed | ActionEligibility::Denied => target,
                ActionEligibility::Unknown => None,
            };
            LibBookSeat {
                id,
                name: text(object, &["name"]),
                no: text(object, &["no", "seat_no"]),
                status,
                status_name: text(object, &["status_name", "statusName"]),
                reserve_eligibility,
                reserve_target,
            }
        })
        .collect();
    seats.sort_by(|left, right| left.no.cmp(&right.no));
    Ok(seats)
}

/// 按调用方请求值补齐普通只读分页；冻结实现允许响应省略分页元数据。
pub(super) fn parse_bookings_for_request(
    body: &str,
    requested_page: i32,
    requested_limit: i32,
) -> Result<LibBookBookingsPage> {
    parse_bookings_with_metadata(body, Some((requested_page, requested_limit)))
}

/// 取消 authority 必须由响应中的完整、无冲突分页元数据证明。
pub(super) fn parse_bookings_with_strict_metadata(body: &str) -> Result<LibBookBookingsPage> {
    parse_bookings_with_metadata(body, None)
}

fn parse_bookings_with_metadata(
    body: &str,
    fallback: Option<(i32, i32)>,
) -> Result<LibBookBookingsPage> {
    let value = envelope(body)?;
    let object = value
        .as_object()
        .ok_or_else(|| error("图书馆预约响应结构无效"))?;
    let bookings = array(object, &["data", "bookings", "list"])
        .iter()
        .filter_map(Value::as_object)
        .map(|booking| {
            let id = text(booking, &["id"]);
            let status = optional_i32(booking, "status");
            let target = (!id.trim().is_empty()).then(|| id.trim().to_owned());
            let cancel_eligibility = match (status, target.as_ref()) {
                (Some(1), Some(_)) => ActionEligibility::Allowed,
                (Some(6 | 8), Some(_)) => ActionEligibility::Denied,
                _ => ActionEligibility::Unknown,
            };
            let cancel_target = match cancel_eligibility {
                ActionEligibility::Allowed | ActionEligibility::Denied => target,
                ActionEligibility::Unknown => None,
            };
            LibBookBooking {
                id,
                name_merge: text(booking, &["nameMerge", "name_merge"]),
                area_name: text(booking, &["name", "area_name", "areaName"]),
                seat_no: text(booking, &["no", "seat_no", "seatNo"]),
                day: text(booking, &["day", "date"]),
                begin_time: text(booking, &["beginTime", "begin_time"]),
                end_time: text(booking, &["endTime", "end_time"]),
                status,
                status_name: text(booking, &["status_name", "statusName"]),
                cancel_eligibility,
                cancel_target,
            }
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
    let response_page = strict_positive_alias_number(object, &["current_page", "page"]);
    let response_limit = strict_positive_alias_number(object, &["per_page", "limit"]);
    let (page, limit) = match (response_page, response_limit, fallback) {
        (Some(page), Some(limit), _) => (page, limit),
        (_, _, Some((page, limit))) => (page.max(1), limit.max(1)),
        _ => return Err(error("图书馆预约响应分页元数据无效")),
    };
    Ok(LibBookBookingsPage {
        bookings,
        page,
        limit,
        total,
    })
}

fn strict_positive_alias_number(map: &Map<String, Value>, keys: &[&str]) -> Option<i32> {
    let mut result = None;
    for key in keys {
        let Some(value) = map.get(*key) else {
            continue;
        };
        let parsed = match value {
            Value::Number(value) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
            Value::String(value) => value
                .parse::<i32>()
                .ok()
                .filter(|parsed| parsed.to_string() == *value),
            _ => None,
        }?;
        if parsed <= 0 || result.is_some_and(|current| current != parsed) {
            return None;
        }
        result = Some(parsed);
    }
    result
}

fn is_expired_message(message: &str) -> bool {
    ["登录失效", "请重新登录", "未登录", "登录状态"]
        .iter()
        .any(|part| message.contains(part))
}
pub(super) fn is_expired_body(body: &str) -> bool {
    serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|value| value.as_object().cloned())
        .is_some_and(|object| is_expired_message(&text(&object, &["message", "msg"])))
}
