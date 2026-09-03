//! 场馆预约响应信封、站点、用途、日期和订单解析。

use serde_json::{Map, Value};

use crate::domain::{
    CgyyActionResult, CgyyDayInfo, CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeSource,
    CgyyPurposeType, CgyySlotStatus, CgyySpaceAvailability, CgyyTimeSlot, CgyyVenueSite,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(super) struct CgyyDayContext {
    pub(super) info: CgyyDayInfo,
    pub(super) reservation_token: Option<String>,
}

/// 解析场馆预约写操作响应。
pub fn parse_action_result(body: &str) -> Result<CgyyActionResult> {
    let root = object(body)?;
    let message = string(&root, "message").unwrap_or_default();
    let value = data(body)?;
    let order = value.as_object().map(parse_order);
    Ok(CgyyActionResult { message, order })
}

pub(super) fn error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

pub(super) fn object(body: &str) -> Result<Map<String, Value>> {
    let value: Value = serde_json::from_str(body).map_err(|_| error("场馆预约响应无法解析"))?;
    value
        .as_object()
        .cloned()
        .ok_or_else(|| error("场馆预约响应结构无效"))
}

fn success_root(body: &str) -> Result<Map<String, Value>> {
    let root = object(body)?;
    let code = root.get("code").and_then(|value| {
        value
            .as_i64()
            .or_else(|| value.as_str()?.parse::<i64>().ok())
    });
    if code != Some(200) {
        let message = string(&root, "message").unwrap_or_else(|| "场馆预约请求失败".into());
        return Err(error(message));
    }
    Ok(root)
}

pub(super) fn data(body: &str) -> Result<Value> {
    let root = success_root(body)?;
    Ok(root.get("data").cloned().unwrap_or(Value::Null))
}

pub(super) fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    let value = map.get(key)?;
    value
        .as_str()
        .map(str::to_owned)
        .or_else(|| value.as_i64().map(|number| number.to_string()))
        .or_else(|| value.as_u64().map(|number| number.to_string()))
        .or_else(|| value.as_f64().map(|number| number.to_string()))
        .or_else(|| value.as_bool().map(|boolean| boolean.to_string()))
}

fn int(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(|value| value.as_i64().or_else(|| value.as_str()?.parse().ok()))
        .and_then(|value| i32::try_from(value).ok())
}

fn bool_value(map: &Map<String, Value>, key: &str) -> Option<bool> {
    map.get(key).and_then(|value| {
        value.as_bool().or_else(|| match value.as_str()? {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        })
    })
}

/// 解析场馆站点列表。
pub fn parse_sites(body: &str) -> Result<Vec<CgyyVenueSite>> {
    let value = data(body)?;
    let values = value
        .as_array()
        .or_else(|| {
            value
                .as_object()
                .and_then(|map| map.get("content"))
                .and_then(Value::as_array)
        })
        .ok_or_else(|| error("场馆站点响应结构无效"))?;
    let mut flattened = Vec::new();
    for item in values {
        let Some(map) = item.as_object() else {
            continue;
        };
        if let Some(site_list) = map.get("siteList").and_then(Value::as_array) {
            for site in site_list {
                let Some(site_map) = site.as_object() else {
                    continue;
                };
                let mut merged = site_map.clone();
                for key in ["venueName", "campusName"] {
                    if !merged.contains_key(key)
                        && let Some(value) = map.get(key)
                    {
                        merged.insert(key.to_owned(), value.clone());
                    }
                }
                flattened.push(merged);
            }
        } else {
            flattened.push(map.clone());
        }
    }
    Ok(flattened
        .iter()
        .map(|item| CgyyVenueSite {
            id: int(item, "id").unwrap_or_default(),
            site_name: string(item, "siteName").unwrap_or_default(),
            venue_name: string(item, "venueName").unwrap_or_default(),
            campus_name: string(item, "campusName").unwrap_or_default(),
            seat_count: int(item, "seatCount"),
            reservation_space_count: int(item, "reservationSpaceCount"),
            site_telephone: string(item, "siteTelephone"),
            open_start_date: string(item, "openStartDate"),
            open_end_date: string(item, "openEndDate"),
        })
        .collect())
}

pub(super) fn parse_purpose_types_with_source(
    body: &str,
) -> Result<(Vec<CgyyPurposeType>, CgyyPurposeSource)> {
    let value = data(body)?;
    let mut result = Vec::new();
    collect_purpose_types(&value, &mut result);
    result.sort_by_key(|item| item.key);
    result.dedup_by_key(|item| item.key);
    Ok(if result.is_empty() {
        (fallback_purpose_types(), CgyyPurposeSource::StaticFallback)
    } else {
        (result, CgyyPurposeSource::Upstream)
    })
}

fn collect_purpose_types(value: &Value, result: &mut Vec<CgyyPurposeType>) {
    match value {
        Value::Array(values) => values
            .iter()
            .for_each(|value| collect_purpose_types(value, result)),
        Value::Object(map) => {
            let key = int(map, "key")
                .or_else(|| int(map, "value"))
                .or_else(|| int(map, "id"));
            let name = string(map, "name");
            if let (Some(key), Some(name)) = (key, name)
                && name.contains('类')
            {
                result.push(CgyyPurposeType { key, name });
            }
            map.values()
                .for_each(|value| collect_purpose_types(value, result));
        }
        _ => {}
    }
}

pub(super) fn fallback_purpose_types() -> Vec<CgyyPurposeType> {
    [
        "导学活动类",
        "学业支持类（串讲、答疑、学习小组讨论等）",
        "学术研讨类（竞赛、答辩、展示等小组讨论）",
        "党建活动类",
        "工作会议类（单位工作例会、学生组织工作会议等）",
        "团队建设类（班级、社团、学生会等学生组织团建）",
        "培训面试类（梦拓、学生组织培训及面试等）",
        "博雅课程类",
        "讲座、沙龙研讨类",
        "其他特色活动类",
    ]
    .into_iter()
    .enumerate()
    .map(|(index, name)| CgyyPurposeType {
        key: i32::try_from(index + 1).unwrap_or_default(),
        name: name.into(),
    })
    .collect()
}

pub(super) fn parse_day_context(
    body: &str,
    venue_site_id: i32,
    reservation_date: &str,
) -> Result<CgyyDayContext> {
    let root = success_root(body)?
        .get("data")
        .and_then(Value::as_object)
        .cloned()
        .ok_or_else(|| error("场馆日期响应结构无效"))?;
    let time_slots: Vec<_> = root
        .get("spaceTimeInfo")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .filter_map(|slot| {
            Some(CgyyTimeSlot {
                id: int(slot, "id")?,
                begin_time: string(slot, "beginTime")?,
                end_time: string(slot, "endTime")?,
                label: format!(
                    "{}-{}",
                    string(slot, "beginTime")?,
                    string(slot, "endTime")?
                ),
            })
        })
        .collect();
    let date_map = root
        .get("reservationDateSpaceInfo")
        .and_then(Value::as_object);
    let date_key = date_map
        .and_then(|map| {
            map.contains_key(reservation_date)
                .then_some(reservation_date.to_owned())
                .or_else(|| map.keys().next().cloned())
        })
        .unwrap_or_else(|| reservation_date.to_owned());
    let mut spaces: Vec<_> = date_map
        .and_then(|map| map.get(&date_key))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .map(|space| {
            let mut slots: Vec<_> = time_slots
                .iter()
                .filter_map(|slot| {
                    space
                        .get(&slot.id.to_string())
                        .and_then(Value::as_object)
                        .map(|raw| parse_slot(slot.id, raw))
                })
                .collect();
            slots.sort_by_key(|slot| slot.time_id);
            CgyySpaceAvailability {
                space_id: int(space, "id").unwrap_or_default(),
                space_name: string(space, "spaceName").unwrap_or_default(),
                venue_site_id: int(space, "venueSiteId").unwrap_or(venue_site_id),
                venue_space_group_id: int(space, "venueSpaceGroupId"),
                slots,
            }
        })
        .collect();
    spaces.sort_by(|left, right| left.space_name.cmp(&right.space_name));
    let available_dates = root
        .get("ableReservationDateList")
        .or_else(|| root.get("reservationDateList"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect();
    Ok(CgyyDayContext {
        info: CgyyDayInfo {
            venue_site_id,
            reservation_date: date_key,
            available_dates,
            time_slots,
            spaces,
            reservation_total_num: int(&root, "reservationTotalNum"),
        },
        reservation_token: string(&root, "token"),
    })
}

fn parse_slot(time_id: i32, raw: &Map<String, Value>) -> CgyySlotStatus {
    let reservation_status = int(raw, "reservationStatus").unwrap_or_default();
    let trade_no = string(raw, "tradeNo");
    let order_id = int(raw, "orderId");
    let take_up = bool_value(raw, "takeUp");
    CgyySlotStatus {
        time_id,
        reservation_status,
        is_reservable: reservation_status == 1
            && trade_no.is_none()
            && order_id.is_none()
            && take_up != Some(true),
        start_date: string(raw, "startDate"),
        end_date: string(raw, "endDate"),
        trade_no,
        order_id,
        use_num: int(raw, "useNum"),
        already_num: int(raw, "alreadyNum"),
        take_up,
        take_up_explain: string(raw, "takeUpExplain"),
    }
}

/// 解析预约订单分页。
pub fn parse_orders(body: &str) -> Result<CgyyOrdersPage> {
    let value = data(body)?;
    let root = value
        .as_object()
        .cloned()
        .or_else(|| value.is_null().then(Map::new))
        .ok_or_else(|| error("场馆订单响应结构无效"))?;
    Ok(CgyyOrdersPage {
        content: root
            .get("content")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_object)
            .map(parse_order)
            .collect(),
        total_elements: int(&root, "totalElements").unwrap_or_default(),
        total_pages: int(&root, "totalPages").unwrap_or_default(),
        size: int(&root, "size").unwrap_or(20),
        number: int(&root, "number").unwrap_or_default(),
    })
}

/// 解析单个预约订单详情。
pub fn parse_order_detail(body: &str) -> Result<CgyyOrder> {
    let value = data(body)?;
    value
        .as_object()
        .cloned()
        .or_else(|| value.is_null().then(Map::new))
        .map(|root| parse_order(&root))
        .ok_or_else(|| error("场馆订单详情结构无效"))
}

pub(super) fn parse_order(raw: &Map<String, Value>) -> CgyyOrder {
    let purpose_type = int(raw, "purposeType");
    CgyyOrder {
        id: int(raw, "id").unwrap_or_default(),
        trade_no: string(raw, "tradeNo"),
        venue_site_id: int(raw, "venueSiteId"),
        reservation_date: string(raw, "reservationDate"),
        reservation_date_detail: string(raw, "reservationDateDetail"),
        venue_space_name: string(raw, "venueSpaceName"),
        campus_name: string(raw, "campusName"),
        venue_name: string(raw, "venueName"),
        site_name: string(raw, "siteName"),
        reservation_start_date: string(raw, "reservationStartDate"),
        reservation_end_date: string(raw, "reservationEndDate"),
        phone: string(raw, "phone"),
        order_status: int(raw, "orderStatus"),
        pay_status: int(raw, "payStatus"),
        check_status: int(raw, "checkStatus"),
        theme: string(raw, "theme"),
        purpose_type,
        purpose_type_name: purpose_type.and_then(|key| {
            fallback_purpose_types()
                .into_iter()
                .find(|item| item.key == key)
                .map(|item| item.name)
        }),
        joiner_num: int(raw, "joinerNum"),
        activity_content: string(raw, "activityContent"),
        joiners: string(raw, "joiners"),
        check_content: string(raw, "checkContent"),
        handle_reason: string(raw, "handleReason"),
        remark: string(raw, "remark"),
    }
}

/// 解析门锁码响应，仅保留是否存在数据的安全摘要。
pub fn parse_lock_code(body: &str) -> Result<CgyyLockCode> {
    let root = success_root(body)?;
    Ok(CgyyLockCode {
        available: !root.get("data").is_none_or(Value::is_null),
    })
}
