//! 阳光打卡响应信封、概览、项目与记录解析。

use chrono::{FixedOffset, TimeZone};
use serde_json::{Map, Value};

use crate::domain::{
    ActionEligibility, YgdkItem, YgdkOverview, YgdkRecord, YgdkRecordsPage, YgdkSubmitTarget,
    YgdkTermSummary,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(super) fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

pub(super) fn integer(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|v| i32::try_from(v).ok())
        .or_else(|| {
            map.get(key)
                .and_then(Value::as_str)
                .and_then(|v| v.parse().ok())
        })
}

fn canonical_positive_integer(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|value| i32::try_from(value).ok())
        .filter(|value| *value > 0)
}

fn canonical_nonempty_string<'a>(map: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    map.get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
}

pub(super) fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(|value| match value {
            Value::String(value) => Some(value.clone()),
            Value::Number(value) => Some(value.to_string()),
            Value::Bool(value) => Some(value.to_string()),
            _ => None,
        })
        .filter(|v| !v.trim().is_empty())
}

fn datetime_text(map: &Map<String, Value>, key: &str) -> Option<String> {
    if let Some(value) = string(map, key) {
        if let Ok(seconds) = value.trim().parse::<i64>() {
            return FixedOffset::east_opt(8 * 60 * 60)?
                .timestamp_opt(seconds, 0)
                .single()
                .map(|value| value.format("%Y-%m-%d %H:%M").to_string());
        }
        return Some(value);
    }
    let seconds = map.get(key).and_then(Value::as_i64)?;
    FixedOffset::east_opt(8 * 60 * 60)?
        .timestamp_opt(seconds, 0)
        .single()
        .map(|value| value.format("%Y-%m-%d %H:%M").to_string())
}

pub(super) fn list(map: &Map<String, Value>, key: &str) -> Vec<Value> {
    map.get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// 解析旧版响应包装，`code=1` 表示业务成功。
pub fn parse_envelope(body: &str) -> Result<Value> {
    let payload: Value = serde_json::from_str(body).map_err(|_| error("阳光打卡响应无法解析"))?;
    let object = payload
        .as_object()
        .ok_or_else(|| error("阳光打卡响应结构无效"))?;
    match integer(object, "code") {
        Some(1) => Ok(object.get("result").cloned().unwrap_or(Value::Null)),
        Some(-98) => Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "阳光打卡业务会话已失效",
        )),
        _ => Err(error("阳光打卡请求失败")),
    }
}

pub fn parse_overview(
    classify: &str,
    items: &str,
    count: &str,
    term: &str,
) -> Result<YgdkOverview> {
    let classify = parse_envelope(classify)?;
    let classifies = classify
        .as_object()
        .map(|v| list(v, "list"))
        .unwrap_or_default();
    let selected = classifies
        .iter()
        .filter_map(Value::as_object)
        .find(|v| string(v, "name").is_some_and(|n| n.contains("体育")))
        .cloned()
        .or_else(|| classifies_fallback(&classify))
        .ok_or_else(|| error("未获取到阳光打卡分类"))?;
    let classify_id = integer(&selected, "classify_id").unwrap_or_default();
    let classify_name = string(&selected, "name").unwrap_or_default();
    let classifies_are_canonical = classifies.iter().all(|entry| {
        entry.as_object().is_some_and(|entry| {
            canonical_positive_integer(entry, "classify_id").is_some()
                && canonical_nonempty_string(entry, "name").is_some()
        })
    });
    let classify_id_count = classifies
        .iter()
        .filter_map(Value::as_object)
        .filter(|entry| canonical_positive_integer(entry, "classify_id") == Some(classify_id))
        .count();
    let classify_is_canonical = classifies_are_canonical
        && canonical_positive_integer(&selected, "classify_id") == Some(classify_id)
        && canonical_nonempty_string(&selected, "name").is_some()
        && classify_id_count == 1
        && !classify_name.trim().is_empty();
    let item_result = parse_envelope(items)?;
    let item_rows = item_result
        .as_object()
        .map(|value| list(value, "list"))
        .unwrap_or_default();
    let items_are_canonical = item_rows.iter().all(|entry| {
        entry.as_object().is_some_and(|entry| {
            canonical_positive_integer(entry, "item_id").is_some()
                && canonical_nonempty_string(entry, "name").is_some()
        })
    });
    let mut parsed_items = parse_items(items)?;
    attach_submit_authority(
        &mut parsed_items,
        &item_rows,
        classify_id,
        classify_is_canonical,
        items_are_canonical,
    );
    let default = parsed_items
        .iter()
        .find(|v| v.name.contains('跑'))
        .or_else(|| {
            parsed_items
                .iter()
                .min_by_key(|v| v.sort.unwrap_or(i32::MAX))
        })
        .ok_or_else(|| error("未获取到阳光打卡项目列表"))?;
    let count = parse_envelope(count)?
        .as_object()
        .cloned()
        .unwrap_or_default();
    let term = parse_envelope(term)?
        .as_object()
        .cloned()
        .unwrap_or_default();
    Ok(YgdkOverview {
        summary: YgdkTermSummary {
            term_id: integer(&term, "term_id").or_else(|| integer(&term, "id")),
            term_name: string(&term, "name"),
            term_count: integer(&count, "term_good_count_show")
                .or_else(|| integer(&count, "term_good_count"))
                .or_else(|| integer(&count, "term_count_show"))
                .or_else(|| integer(&count, "term_count"))
                .unwrap_or(0),
            term_target: integer(&count, "term_num").or_else(|| integer(&selected, "term_num")),
            week_count: integer(&count, "week_count"),
            week_target: integer(&count, "week_num").or_else(|| integer(&selected, "week_num")),
            month_count: integer(&count, "month_count"),
            month_target: integer(&count, "month_num").or_else(|| integer(&selected, "month_num")),
            day_count: integer(&count, "day_count"),
            good_count: integer(&count, "term_good_count_show")
                .or_else(|| integer(&count, "term_good_count")),
        },
        classify_id,
        classify_name,
        default_item_id: default.item_id,
        default_item_name: default.name.clone(),
        items: parsed_items,
    })
}

fn attach_submit_authority(
    items: &mut [YgdkItem],
    rows: &[Value],
    classify_id: i32,
    classify_is_canonical: bool,
    items_are_canonical: bool,
) {
    for item in items {
        let item_id_count = rows
            .iter()
            .filter_map(Value::as_object)
            .filter(|entry| canonical_positive_integer(entry, "item_id") == Some(item.item_id))
            .count();
        if classify_is_canonical
            && items_are_canonical
            && item_id_count == 1
            && !item.name.trim().is_empty()
        {
            item.submit_eligibility = ActionEligibility::Allowed;
            item.submit_target = Some(YgdkSubmitTarget {
                classify_id,
                item_id: item.item_id,
            });
        }
    }
}

pub(super) fn classifies_fallback(value: &Value) -> Option<Map<String, Value>> {
    let rows = value.as_object()?.get("list")?.as_array()?;
    rows.iter()
        .filter_map(Value::as_object)
        .find(|entry| integer(entry, "classify_id") == Some(1))
        .cloned()
        .or_else(|| rows.iter().find_map(|entry| entry.as_object().cloned()))
}

pub fn parse_items(body: &str) -> Result<Vec<YgdkItem>> {
    let result = parse_envelope(body)?;
    let rows = result
        .as_object()
        .map(|v| list(v, "list"))
        .unwrap_or_default();
    Ok(parse_item_rows(&rows))
}

fn parse_item_rows(rows: &[Value]) -> Vec<YgdkItem> {
    rows.iter()
        .filter_map(|value| {
            let object = value.as_object()?;
            Some(YgdkItem {
                item_id: integer(object, "item_id")?,
                name: string(object, "name")?,
                kind: integer(object, "type"),
                sort: integer(object, "sort"),
                submit_eligibility: ActionEligibility::Unknown,
                submit_target: None,
            })
        })
        .collect()
}

pub fn parse_records(
    body: &str,
    items: &[YgdkItem],
    page: i32,
    size: i32,
) -> Result<YgdkRecordsPage> {
    if page <= 0 || size <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    let result = parse_envelope(body)?;
    let object = result
        .as_object()
        .ok_or_else(|| error("阳光打卡记录结构无效"))?;
    let content = list(object, "list")
        .into_iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            let item_id = integer(o, "item_id");
            let raw = o.get("images_fmt").or_else(|| o.get("images"));
            let images = match raw {
                Some(Value::Array(v)) => v
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect(),
                Some(Value::String(v)) => {
                    if v.trim().is_empty() {
                        vec![]
                    } else {
                        serde_json::from_str::<Vec<String>>(v)
                            .unwrap_or_else(|_| vec![v.to_owned()])
                    }
                }
                _ => vec![],
            };
            Some(YgdkRecord {
                record_id: integer(o, "record_id")?,
                item_id,
                item_name: string(o, "item_name").or_else(|| {
                    item_id.and_then(|id| {
                        items
                            .iter()
                            .find(|v| v.item_id == id)
                            .map(|v| v.name.clone())
                    })
                }),
                start_time: datetime_text(o, "start_time"),
                end_time: datetime_text(o, "end_time"),
                place: string(o, "place"),
                images,
                is_open: integer(o, "isopen") == Some(1),
                state: integer(o, "state"),
                created_at: string(o, "create_time_fmt"),
                created_at_label: string(o, "create_time_fmt"),
            })
        })
        .collect();
    let total = integer(object, "total").unwrap_or(0);
    Ok(YgdkRecordsPage {
        content,
        total,
        page,
        size,
        has_more: page.saturating_mul(size) < total,
    })
}
