//! 场馆预约响应信封、站点、用途、日期和订单解析。

use std::collections::HashMap;
use std::time::SystemTime;

use chrono::{DateTime, Duration, FixedOffset, NaiveDateTime, Utc};
use serde_json::{Map, Value};

use crate::domain::{
    ActionEligibility, CgyyCancelOrderTarget, CgyyDayInfo, CgyyLockCode, CgyyOrder, CgyyOrdersPage,
    CgyyPurposeSource, CgyyPurposeType, CgyyReservationTarget, CgyySlotStatus,
    CgyySpaceAvailability, CgyyTimeSlot, CgyyVenueSite,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(super) struct CgyyDayContext {
    pub(super) info: CgyyDayInfo,
    pub(super) reservation_token: Option<String>,
    pub(super) requested_date_exact: bool,
}

struct ParsedTimeSlot {
    value: CgyyTimeSlot,
    ordinal: Option<i32>,
    identity_valid: bool,
}

struct SlotTargetContext<'a> {
    venue_site_id: i32,
    reservation_date: &'a str,
    space_id: i32,
    venue_space_group_id: Option<i32>,
    identity_valid: bool,
}

enum NullableField<T> {
    Invalid,
    Null,
    Value(T),
}

impl<T> NullableField<T> {
    fn is_valid(&self) -> bool {
        !matches!(self, Self::Invalid)
    }

    fn as_option(&self) -> Option<&T> {
        match self {
            Self::Value(value) => Some(value),
            Self::Invalid | Self::Null => None,
        }
    }

    fn into_option(self) -> Option<T> {
        match self {
            Self::Value(value) => Some(value),
            Self::Invalid | Self::Null => None,
        }
    }
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
        return Err(error("场馆预约请求失败"));
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
    let parsed_time_slots = parse_time_slots(&root);
    let time_slots = parsed_time_slots
        .iter()
        .map(|slot| slot.value.clone())
        .collect();
    let (date_key, requested_date_exact, raw_spaces) = select_date_spaces(&root, reservation_date);
    let spaces = parse_spaces(
        raw_spaces,
        &parsed_time_slots,
        venue_site_id,
        reservation_date,
        requested_date_exact,
    );
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
        requested_date_exact,
    })
}

fn parse_time_slots(root: &Map<String, Value>) -> Vec<ParsedTimeSlot> {
    let raw_slots = root
        .get("spaceTimeInfo")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let mut time_id_counts = HashMap::new();
    for raw in raw_slots {
        if let Some(time_id) = raw
            .as_object()
            .and_then(|slot| int(slot, "id"))
            .filter(|time_id| *time_id > 0)
        {
            *time_id_counts.entry(time_id).or_insert(0_usize) += 1;
        }
    }
    raw_slots
        .iter()
        .enumerate()
        .filter_map(|(ordinal, raw)| {
            let slot = raw.as_object()?;
            let id = int(slot, "id")?;
            let begin_time = string(slot, "beginTime")?;
            let end_time = string(slot, "endTime")?;
            let identity_valid = id > 0
                && strict_i32(slot, "id") == Some(id)
                && time_id_counts.get(&id) == Some(&1)
                && !begin_time.trim().is_empty()
                && !end_time.trim().is_empty()
                && !begin_time.chars().any(char::is_control)
                && !end_time.chars().any(char::is_control);
            Some(ParsedTimeSlot {
                value: CgyyTimeSlot {
                    id,
                    label: format!("{begin_time}-{end_time}"),
                    begin_time,
                    end_time,
                },
                ordinal: i32::try_from(ordinal).ok(),
                identity_valid,
            })
        })
        .collect()
}

fn select_date_spaces<'a>(
    root: &'a Map<String, Value>,
    reservation_date: &str,
) -> (String, bool, Vec<&'a Map<String, Value>>) {
    let date_map = root
        .get("reservationDateSpaceInfo")
        .and_then(Value::as_object);
    let requested_date_exact = date_map
        .and_then(|map| map.get(reservation_date))
        .is_some_and(Value::is_array);
    let date_key = date_map
        .and_then(|map| {
            map.contains_key(reservation_date)
                .then_some(reservation_date.to_owned())
                .or_else(|| map.keys().next().cloned())
        })
        .unwrap_or_else(|| reservation_date.to_owned());
    let raw_spaces: Vec<_> = date_map
        .and_then(|map| map.get(&date_key))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_object)
        .collect();
    (date_key, requested_date_exact, raw_spaces)
}

fn parse_spaces(
    raw_spaces: Vec<&Map<String, Value>>,
    parsed_time_slots: &[ParsedTimeSlot],
    venue_site_id: i32,
    reservation_date: &str,
    requested_date_exact: bool,
) -> Vec<CgyySpaceAvailability> {
    let mut space_id_counts = HashMap::new();
    for space in &raw_spaces {
        if let Some(space_id) = int(space, "id")
            && space_id > 0
        {
            *space_id_counts.entry(space_id).or_insert(0_usize) += 1;
        }
    }
    let mut spaces: Vec<_> = raw_spaces
        .into_iter()
        .map(|space| {
            let space_id = int(space, "id").unwrap_or_default();
            let canonical_space_id = strict_i32(space, "id");
            let display_site_id = int(space, "venueSiteId");
            let canonical_site_id = strict_i32(space, "venueSiteId");
            let group = optional_group_id(space);
            let group_identity_valid =
                group.is_valid() && group.as_option().is_none_or(|group_id| *group_id > 0);
            let venue_space_group_id = int(space, "venueSpaceGroupId");
            let mut slot_key_counts = HashMap::new();
            for time_id in space.keys().filter_map(|key| positive_i32_text(key)) {
                *slot_key_counts.entry(time_id).or_insert(0_usize) += 1;
            }
            let space_identity_valid = requested_date_exact
                && space_id > 0
                && canonical_space_id == Some(space_id)
                && space_id_counts.get(&space_id) == Some(&1)
                && canonical_site_id == Some(venue_site_id)
                && group_identity_valid;
            let mut slots: Vec<_> = parsed_time_slots
                .iter()
                .filter_map(|slot| {
                    space
                        .get(&slot.value.id.to_string())
                        .and_then(Value::as_object)
                        .map(|raw| {
                            let context = SlotTargetContext {
                                venue_site_id,
                                reservation_date,
                                space_id,
                                venue_space_group_id,
                                identity_valid: space_identity_valid
                                    && slot_key_counts.get(&slot.value.id) == Some(&1),
                            };
                            parse_slot(raw, slot, &context)
                        })
                })
                .collect();
            slots.sort_by_key(|slot| slot.time_id);
            CgyySpaceAvailability {
                space_id,
                space_name: string(space, "spaceName").unwrap_or_default(),
                venue_site_id: display_site_id.unwrap_or(venue_site_id),
                venue_space_group_id,
                slots,
            }
        })
        .collect();
    spaces.sort_by(|left, right| left.space_name.cmp(&right.space_name));
    spaces
}

fn parse_slot(
    raw: &Map<String, Value>,
    time_slot: &ParsedTimeSlot,
    context: &SlotTargetContext<'_>,
) -> CgyySlotStatus {
    let reservation_status = strict_i32(raw, "reservationStatus");
    let trade_no_state = nullable_string(raw, "tradeNo");
    let order_id_state = nullable_i32(raw, "orderId");
    let take_up_state = nullable_bool(raw, "takeUp");
    let decisive_fields_valid = reservation_status.is_some()
        && trade_no_state.is_valid()
        && order_id_state.is_valid()
        && take_up_state.is_valid();
    let trade_no = trade_no_state.into_option();
    let order_id = order_id_state.into_option();
    let take_up = take_up_state.into_option();
    let reservation_eligibility = if !context.identity_valid
        || !time_slot.identity_valid
        || time_slot.ordinal.is_none()
        || !decisive_fields_valid
    {
        ActionEligibility::Unknown
    } else {
        match reservation_status {
            Some(1) if trade_no.is_none() && order_id.is_none() && take_up != Some(true) => {
                ActionEligibility::Allowed
            }
            Some(_) => ActionEligibility::Denied,
            None => ActionEligibility::Unknown,
        }
    };
    let reservation_target =
        (reservation_eligibility == ActionEligibility::Allowed).then(|| CgyyReservationTarget {
            venue_site_id: context.venue_site_id,
            reservation_date: context.reservation_date.to_owned(),
            space_id: context.space_id,
            time_id: time_slot.value.id,
            venue_space_group_id: context.venue_space_group_id,
            time_ordinal: time_slot
                .ordinal
                .expect("已验证的场馆时段必须具有可表示的 ordinal"),
        });
    CgyySlotStatus {
        time_id: time_slot.value.id,
        reservation_status,
        reservation_eligibility,
        reservation_target,
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

fn strict_i32(map: &Map<String, Value>, key: &str) -> Option<i32> {
    match map.get(key)? {
        Value::Number(value) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
        Value::String(value) => value
            .parse::<i32>()
            .ok()
            .filter(|parsed| parsed.to_string() == *value),
        _ => None,
    }
}

fn positive_i32_text(value: &str) -> Option<i32> {
    value.parse::<i32>().ok().filter(|value| *value > 0)
}

fn nullable_i32(map: &Map<String, Value>, key: &str) -> NullableField<i32> {
    match map.get(key) {
        Some(Value::Null) => NullableField::Null,
        Some(value) => strict_i32_value(value).map_or(NullableField::Invalid, NullableField::Value),
        None => NullableField::Invalid,
    }
}

fn optional_group_id(map: &Map<String, Value>) -> NullableField<i32> {
    match map.get("venueSpaceGroupId") {
        None | Some(Value::Null) => NullableField::Null,
        Some(value) => strict_i32_value(value).map_or(NullableField::Invalid, NullableField::Value),
    }
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

fn nullable_string(map: &Map<String, Value>, key: &str) -> NullableField<String> {
    match map.get(key) {
        Some(Value::Null) => NullableField::Null,
        Some(Value::String(value)) => NullableField::Value(value.clone()),
        Some(_) | None => NullableField::Invalid,
    }
}

fn nullable_bool(map: &Map<String, Value>, key: &str) -> NullableField<bool> {
    match map.get(key) {
        Some(Value::Null) => NullableField::Null,
        Some(Value::Bool(value)) => NullableField::Value(*value),
        Some(_) | None => NullableField::Invalid,
    }
}

pub(super) fn parse_orders_at(body: &str, now: NaiveDateTime) -> Result<CgyyOrdersPage> {
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
            .map(|order| parse_order_at(order, now))
            .collect(),
        total_elements: int(&root, "totalElements").unwrap_or_default(),
        total_pages: int(&root, "totalPages").unwrap_or_default(),
        size: int(&root, "size").unwrap_or(20),
        number: int(&root, "number").unwrap_or_default(),
    })
}

pub(super) fn parse_order_detail_at(body: &str, now: NaiveDateTime) -> Result<CgyyOrder> {
    let value = data(body)?;
    value
        .as_object()
        .cloned()
        .or_else(|| value.is_null().then(Map::new))
        .map(|root| parse_order_at(&root, now))
        .ok_or_else(|| error("场馆订单详情结构无效"))
}

pub(super) fn parse_order_at(raw: &Map<String, Value>, now: NaiveDateTime) -> CgyyOrder {
    let purpose_type = int(raw, "purposeType");
    let cancel = cancel_fields(raw, now);
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
        cancel_eligibility: cancel.eligibility,
        cancel_target: cancel.target,
        cancelled_target: cancel.cancelled_target,
    }
}

pub(super) struct CgyyCancelOrderAuthority {
    pub(super) order_id: i32,
    pub(super) order_status: Option<i32>,
    pub(super) check_status: Option<i32>,
    pub(super) eligibility: ActionEligibility,
    pub(super) reservation_start_date: Option<String>,
    pub(super) reservation_end_date: Option<String>,
}

pub(super) fn parse_cancel_order_authority(
    body: &str,
    expected_order_id: i32,
    now: NaiveDateTime,
) -> Result<CgyyCancelOrderAuthority> {
    let value = data(body)?;
    let raw = value
        .as_object()
        .ok_or_else(|| error("场馆取消详情必须是唯一对象"))?;
    let fields = cancel_fields(raw, now);
    let Some(order_id) = fields.order_id.filter(|id| *id == expected_order_id) else {
        return Err(error("场馆取消详情订单标识无效或不一致"));
    };
    Ok(CgyyCancelOrderAuthority {
        order_id,
        order_status: fields.order_status,
        check_status: fields.check_status,
        eligibility: fields.eligibility,
        reservation_start_date: fields.reservation_start_date,
        reservation_end_date: fields.reservation_end_date,
    })
}

struct CancelFields {
    order_id: Option<i32>,
    order_status: Option<i32>,
    check_status: Option<i32>,
    eligibility: ActionEligibility,
    target: Option<CgyyCancelOrderTarget>,
    cancelled_target: Option<CgyyCancelOrderTarget>,
    reservation_start_date: Option<String>,
    reservation_end_date: Option<String>,
}

fn cancel_fields(raw: &Map<String, Value>, now: NaiveDateTime) -> CancelFields {
    let order_id = strict_i32(raw, "id").filter(|id| *id > 0);
    let order_status = strict_i32(raw, "orderStatus");
    let check_status = strict_i32(raw, "checkStatus");
    let start = parse_cgyy_datetime(raw.get("reservationStartDate"));
    let end = parse_cgyy_datetime(raw.get("reservationEndDate"));
    let cancelled_target = match (order_id, order_status) {
        (Some(order_id), Some(2)) => Some(CgyyCancelOrderTarget { order_id }),
        _ => None,
    };
    let eligibility = if order_id.is_none() {
        ActionEligibility::Unknown
    } else if order_status == Some(2) || check_status.is_some_and(|status| status < 0) {
        ActionEligibility::Denied
    } else if !matches!(order_status, Some(1 | 3))
        || !check_status.is_some_and(|status| (1..=6).contains(&status))
    {
        ActionEligibility::Unknown
    } else if let Some(start) = start {
        match start.checked_sub_signed(Duration::hours(4)) {
            Some(deadline) if now < deadline => ActionEligibility::Allowed,
            Some(_) => ActionEligibility::Denied,
            None => ActionEligibility::Unknown,
        }
    } else if let Some(end) = end {
        if now < end {
            ActionEligibility::Allowed
        } else {
            ActionEligibility::Denied
        }
    } else {
        ActionEligibility::Allowed
    };
    let target = (eligibility == ActionEligibility::Allowed).then(|| CgyyCancelOrderTarget {
        order_id: order_id.expect("已允许的场馆取消订单必须具有正整数标识"),
    });
    CancelFields {
        order_id,
        order_status,
        check_status,
        eligibility,
        target,
        cancelled_target,
        reservation_start_date: start.map(format_cgyy_datetime),
        reservation_end_date: end.map(format_cgyy_datetime),
    }
}

fn parse_cgyy_datetime(value: Option<&Value>) -> Option<NaiveDateTime> {
    let normalized = value.and_then(Value::as_str)?.trim().replace(' ', "T");
    ["%Y-%m-%dT%H:%M:%S%.f", "%Y-%m-%dT%H:%M"]
        .into_iter()
        .find_map(|format| NaiveDateTime::parse_from_str(&normalized, format).ok())
}

fn format_cgyy_datetime(value: NaiveDateTime) -> String {
    value.format("%Y-%m-%d %H:%M:%S").to_string()
}

pub(super) fn shanghai_datetime(now: SystemTime) -> NaiveDateTime {
    let offset = FixedOffset::east_opt(8 * 60 * 60).expect("Asia/Shanghai 固定偏移必须有效");
    DateTime::<Utc>::from(now)
        .with_timezone(&offset)
        .naive_local()
}

/// 解析门锁码响应，仅保留是否存在数据的安全摘要。
pub fn parse_lock_code(body: &str) -> Result<CgyyLockCode> {
    let root = success_root(body)?;
    Ok(CgyyLockCode {
        available: !root.get("data").is_none_or(Value::is_null),
    })
}
