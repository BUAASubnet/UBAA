//! 从分区原始日期条目构造安全日程，不使用旧展平详情推断关联。

use std::collections::HashSet;

use serde_json::Value;

use super::parser::{error, parse_time_slots, text};
use crate::domain::{LibBookAreaSchedule, LibBookDaySchedule};
use crate::error::Result;

pub(super) fn parse_area_schedule_for(area_id: &str, value: &Value) -> Result<LibBookAreaSchedule> {
    let object = value
        .as_object()
        .ok_or_else(|| error("图书馆分区响应结构无效"))?;
    let area = object
        .get("area")
        .and_then(Value::as_object)
        .unwrap_or(object);
    let mut days = Vec::new();
    let mut seen = HashSet::new();
    // 旧顶层 availableDates/timeSlots 无法证明对应关系，不能在此补配。
    let dates = match object.get("date") {
        None | Some(Value::Null) => None,
        Some(value) => Some(
            value
                .as_object()
                .ok_or_else(|| error("图书馆分区日期结构无效"))?,
        ),
    };
    let entries = match dates.and_then(|date| date.get("list")) {
        None | Some(Value::Null) => &[][..],
        Some(value) => value
            .as_array()
            .ok_or_else(|| error("图书馆分区日期列表无效"))?
            .as_slice(),
    };
    for entry in entries {
        let entry = entry
            .as_object()
            .ok_or_else(|| error("图书馆分区日期条目无效"))?;
        let mut day = text(entry, &["day"]);
        if day.trim().is_empty() {
            day = text(entry, &["date"]);
        }
        if day.trim().is_empty() {
            continue;
        }
        if !seen.insert(day.trim().to_owned()) {
            return Err(error("图书馆分区响应包含重复预约日期"));
        }
        let slots = match entry.get("times").or_else(|| entry.get("timeSlots")) {
            None | Some(Value::Null) => &[][..],
            Some(value) => value
                .as_array()
                .ok_or_else(|| error("图书馆分区时段列表无效"))?
                .as_slice(),
        };
        let time_slots = parse_time_slots(slots);
        if time_slots.len() != slots.len()
            || time_slots.iter().any(|slot| {
                [&slot.id, &slot.start, &slot.end]
                    .iter()
                    .any(|value| value.trim().is_empty())
            })
        {
            return Err(error("图书馆分区时段字段不完整"));
        }
        days.push(LibBookDaySchedule { day, time_slots });
    }
    let id = text(area, &["id"]);
    Ok(LibBookAreaSchedule {
        id: if id.is_empty() {
            area_id.to_owned()
        } else {
            id
        },
        name: text(area, &["name"]),
        days,
    })
}
