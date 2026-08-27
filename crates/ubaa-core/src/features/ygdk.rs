//! 阳光打卡只读响应解析与业务查询。
#![allow(clippy::missing_errors_doc)]

use crate::domain::{YgdkItem, YgdkOverview, YgdkRecord, YgdkRecordsPage, YgdkTermSummary};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use serde_json::{Map, Value};

#[derive(Clone, Debug)]
pub(crate) struct YgdkCredential {
    pub(crate) uid: i32,
    pub(crate) token: String,
}

fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}
fn integer(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|v| i32::try_from(v).ok())
        .or_else(|| {
            map.get(key)
                .and_then(Value::as_str)
                .and_then(|v| v.parse().ok())
        })
}
fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .filter(|v| !v.trim().is_empty())
}
fn list(map: &Map<String, Value>, key: &str) -> Vec<Value> {
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
        _ => Err(error(
            string(object, "msg")
                .as_deref()
                .unwrap_or("阳光打卡请求失败"),
        )),
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
    let classify_id =
        integer(&selected, "classify_id").ok_or_else(|| error("阳光打卡分类缺少标识"))?;
    let classify_name = string(&selected, "name").ok_or_else(|| error("阳光打卡分类缺少名称"))?;
    let parsed_items = parse_items(items)?;
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
fn classifies_fallback(value: &Value) -> Option<Map<String, Value>> {
    value
        .as_object()?
        .get("list")?
        .as_array()?
        .iter()
        .find_map(|v| v.as_object().cloned())
        .filter(|v| integer(v, "classify_id") == Some(1))
        .or_else(|| {
            value
                .as_object()?
                .get("list")?
                .as_array()?
                .iter()
                .find_map(|v| v.as_object().cloned())
        })
}
pub fn parse_items(body: &str) -> Result<Vec<YgdkItem>> {
    let result = parse_envelope(body)?;
    Ok(result
        .as_object()
        .map(|v| list(v, "list"))
        .unwrap_or_default()
        .into_iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            Some(YgdkItem {
                item_id: integer(o, "item_id")?,
                name: string(o, "name")?,
                kind: integer(o, "type"),
                sort: integer(o, "sort"),
            })
        })
        .collect())
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
                    serde_json::from_str::<Vec<String>>(v).unwrap_or_default()
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
                start_time: string(o, "start_time"),
                end_time: string(o, "end_time"),
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
