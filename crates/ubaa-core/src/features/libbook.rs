//! 图书馆座位只读响应解析。
#![allow(clippy::missing_errors_doc)]
use crate::domain::{
    LibBookArea, LibBookAreaDetail, LibBookBooking, LibBookBookingsPage, LibBookLibrary,
    LibBookSeat, LibBookStorey, LibBookTimeSlot,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use serde_json::{Map, Value};

#[derive(Clone, Debug)]
pub(crate) struct LibBookCredential {
    pub(crate) token: String,
}

fn err(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}
fn text(o: &Map<String, Value>, key: &str) -> String {
    o.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned()
}
fn num(o: &Map<String, Value>, key: &str) -> i32 {
    o.get(key)
        .and_then(Value::as_i64)
        .and_then(|v| i32::try_from(v).ok())
        .or_else(|| {
            o.get(key)
                .and_then(Value::as_str)
                .and_then(|v| v.parse().ok())
        })
        .unwrap_or_default()
}
fn arr<'a>(o: &'a Map<String, Value>, key: &str) -> &'a [Value] {
    o.get(key)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[])
}
fn envelope(body: &str) -> Result<Value> {
    let value: Value = serde_json::from_str(body).map_err(|_| err("图书馆响应无法解析"))?;
    let o = value.as_object().ok_or_else(|| err("图书馆响应结构无效"))?;
    let code = o.get("code").and_then(Value::as_i64).or_else(|| {
        o.get("code")
            .and_then(Value::as_str)
            .and_then(|v| v.parse().ok())
    });
    if matches!(code, Some(0) | Some(1)) {
        Ok(o.get("data")
            .or_else(|| o.get("result"))
            .cloned()
            .unwrap_or(Value::Null))
    } else {
        Err(err(o
            .get("msg")
            .and_then(Value::as_str)
            .unwrap_or("图书馆请求失败")))
    }
}
pub fn parse_libraries(body: &str) -> Result<Vec<LibBookLibrary>> {
    let v = envelope(body)?;
    let list = v.as_array().map(Vec::as_slice).unwrap_or_else(|| {
        v.get("list")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    });
    Ok(list
        .iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            Some(LibBookLibrary {
                id: text(o, "id"),
                name: text(o, "name"),
                free_num: num(o, "freeNum"),
                total_num: num(o, "totalNum"),
                storeys: arr(o, "storeys")
                    .iter()
                    .filter_map(|s| {
                        let x = s.as_object()?;
                        Some(LibBookStorey {
                            id: text(x, "id"),
                            name: text(x, "name"),
                            free_num: num(x, "freeNum"),
                            total_num: num(x, "totalNum"),
                        })
                    })
                    .collect(),
            })
        })
        .collect())
}
pub fn parse_areas(body: &str) -> Result<Vec<LibBookArea>> {
    let v = envelope(body)?;
    let list = v.as_array().map(Vec::as_slice).unwrap_or_else(|| {
        v.get("list")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    });
    Ok(list
        .iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            Some(LibBookArea {
                id: text(o, "id"),
                name: text(o, "name"),
                area_name: text(o, "areaName"),
                premises_id: text(o, "premisesId"),
                storey_id: text(o, "storeyId"),
                free_num: num(o, "freeNum"),
                total_num: num(o, "totalNum"),
            })
        })
        .collect())
}
pub fn parse_area_detail(body: &str) -> Result<LibBookAreaDetail> {
    let v = envelope(body)?;
    let o = v.as_object().ok_or_else(|| err("图书馆分区响应结构无效"))?;
    let slots = arr(o, "timeSlots")
        .iter()
        .filter_map(|v| {
            let x = v.as_object()?;
            let start = text(x, "start");
            let end = text(x, "end");
            Some(LibBookTimeSlot {
                id: text(x, "id"),
                start: start.clone(),
                end: end.clone(),
                label: text(x, "label"),
            })
        })
        .map(|mut s| {
            if s.label.is_empty() {
                s.label = format!("{}-{}", s.start, s.end);
            }
            s
        })
        .collect();
    Ok(LibBookAreaDetail {
        id: text(o, "id"),
        name: text(o, "name"),
        available_dates: arr(o, "availableDates")
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect(),
        time_slots: slots,
    })
}
pub fn parse_seats(body: &str) -> Result<Vec<LibBookSeat>> {
    let v = envelope(body)?;
    let list = v.as_array().map(Vec::as_slice).unwrap_or_else(|| {
        v.get("list")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    });
    Ok(list
        .iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            let status = text(o, "status");
            Some(LibBookSeat {
                id: text(o, "id"),
                name: text(o, "name"),
                no: text(o, "no"),
                status: status.clone(),
                status_name: text(o, "statusName"),
                is_available: status == "1",
            })
        })
        .collect())
}
pub fn parse_bookings(body: &str) -> Result<LibBookBookingsPage> {
    let v = envelope(body)?;
    let o = v.as_object().ok_or_else(|| err("图书馆预约响应结构无效"))?;
    let list = arr(o, "bookings")
        .iter()
        .filter_map(|v| {
            let x = v.as_object()?;
            Some(LibBookBooking {
                id: text(x, "id"),
                name_merge: text(x, "nameMerge"),
                area_name: text(x, "areaName"),
                seat_no: text(x, "seatNo"),
                day: text(x, "day"),
                begin_time: text(x, "beginTime"),
                end_time: text(x, "endTime"),
                status: text(x, "status"),
                status_name: text(x, "statusName"),
            })
        })
        .collect();
    Ok(LibBookBookingsPage {
        bookings: list,
        page: num(o, "page").max(1),
        limit: num(o, "limit").max(1),
        total: num(o, "total"),
    })
}
