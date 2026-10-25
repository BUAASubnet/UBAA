//! 旧版 iHome 白名单投影。
use crate::domain::{
    IhomeAppeal, IhomeCategory, IhomeConfig, IhomeEntry, IhomeEvaluation, IhomeHistory,
    IhomeNotice, IhomePage, IhomeReply, IhomeScope,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use serde_json::Value;
pub(super) fn invalid() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "iHome 数据结构发生变化，请稍后重试",
    )
}
pub(crate) fn envelope(body: &str) -> Result<Value> {
    let value: Value = serde_json::from_str(body).map_err(|_| invalid())?;
    if number(&value, "code") != Some(20000) || value.get("success") != Some(&Value::Bool(true)) {
        return Err(invalid());
    }
    value.get("data").cloned().ok_or_else(invalid)
}
fn text(v: &Value, k: &str) -> String {
    match v.get(k) {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}
fn number(v: &Value, k: &str) -> Option<i64> {
    let n = v.get(k)?;
    n.as_i64().or_else(|| n.as_str()?.parse().ok())
}
fn integer(v: &Value, k: &str) -> Option<i32> {
    number(v, k).and_then(|n| i32::try_from(n).ok())
}
fn objects<'a>(v: &'a Value, k: &str) -> Result<Vec<&'a Value>> {
    match v.get(k) {
        None | Some(Value::Null) => Ok(vec![]),
        Some(Value::Array(a)) if a.iter().all(Value::is_object) => Ok(a.iter().collect()),
        _ => Err(invalid()),
    }
}
fn plain(v: &Value, k: &str) -> String {
    crate::features::spoc::to_plain_text(&text(v, k)).unwrap_or_default()
}
fn id(v: &Value) -> Result<i64> {
    number(v, "id").filter(|n| *n > 0).ok_or_else(invalid)
}
fn evaluation(v: &Value) -> Result<IhomeEvaluation> {
    Ok(IhomeEvaluation {
        id: id(v)?,
        department: text(&v["department"], "name"),
        speed: integer(v, "speed").unwrap_or(0),
        satisfaction: integer(v, "satisfaction").unwrap_or(0),
        degree: integer(v, "degree").unwrap_or(0),
        content: plain(v, "content"),
        created_at: text(v, "created_at"),
    })
}
pub(crate) fn appeal(v: &Value) -> Result<IhomeAppeal> {
    let published = text(v, "publish_date");
    let restart = integer(v, "is_restart").unwrap_or(0);
    Ok(IhomeAppeal {
        id: id(v)?,
        content: plain(v, "content"),
        status: text(v, "publish_status_text"),
        category: text(&v["sqlb"], "type_name"),
        published_at: if published.is_empty() {
            text(v, "created_at")
        } else {
            published
        },
        departments: objects(v, "departments")?
            .iter()
            .map(|v| text(v, "name"))
            .collect(),
        is_mine: integer(v, "is_user") == Some(1),
        is_followed: integer(v, "is_follow").map(|n| n == 1),
        is_supported: integer(v, "is_praise").map(|n| n == 1),
        follow_count: integer(v, "follow_count"),
        support_count: integer(v, "praise_count"),
        replies: objects(v, "appeal_reply")?
            .iter()
            .map(|v| IhomeReply {
                content: plain(v, "content"),
                department: text(&v["department"], "name"),
                created_at: text(v, "created_at"),
            })
            .collect(),
        evaluations: objects(v, "appraise")?
            .iter()
            .map(|v| evaluation(v))
            .collect::<Result<_>>()?,
        history: objects(v, "change_history")?
            .iter()
            .filter(|v| integer(v, "restart") == Some(restart))
            .map(|v| IhomeHistory {
                content: plain(v, "contents"),
                created_at: text(v, "created_at"),
            })
            .collect(),
    })
}
pub(crate) fn page(v: &Value, scope: IhomeScope) -> Result<IhomePage> {
    let rows = v
        .get("data")
        .and_then(Value::as_array)
        .ok_or_else(invalid)?;
    Ok(IhomePage {
        entries: rows
            .iter()
            .map(|v| {
                Ok(if scope == IhomeScope::Appraised {
                    IhomeEntry {
                        appeal: appeal(&v["appeal"])?,
                        evaluation: Some(evaluation(v)?),
                    }
                } else {
                    IhomeEntry {
                        appeal: appeal(v)?,
                        evaluation: None,
                    }
                })
            })
            .collect::<Result<_>>()?,
        page: integer(v, "current_page")
            .filter(|n| *n > 0)
            .ok_or_else(invalid)?,
        last_page: integer(v, "last_page")
            .filter(|n| *n >= 0)
            .ok_or_else(invalid)?,
        total: integer(v, "total")
            .filter(|n| *n >= 0)
            .ok_or_else(invalid)?,
    })
}
pub(super) fn config(settings: &Value, types: &Value) -> Result<IhomeConfig> {
    let values = settings.as_array().ok_or_else(invalid)?;
    let find = |key| {
        values
            .iter()
            .find(|v| text(v, "key") == key)
            .map(|v| text(v, "value"))
            .unwrap_or_default()
    };
    let label = find("fabulous_show");
    Ok(IhomeConfig {
        support_enabled: find("fabulous") == "1",
        support_label: if label.trim().is_empty() {
            "支持".into()
        } else {
            label
        },
        categories: objects(types, "SQLB")?
            .iter()
            .map(|v| {
                Ok(IhomeCategory {
                    id: id(v)?,
                    name: text(v, "type_name"),
                })
            })
            .collect::<Result<_>>()?,
    })
}
pub(super) fn notice(v: &Value) -> Result<IhomeNotice> {
    Ok(IhomeNotice {
        id: id(v)?,
        title: text(v, "title"),
        content: plain(v, "content"),
        date: text(v, "date"),
    })
}
pub(super) fn notices(v: &Value) -> Result<Vec<IhomeNotice>> {
    v.as_array()
        .ok_or_else(invalid)?
        .iter()
        .map(notice)
        .collect()
}
