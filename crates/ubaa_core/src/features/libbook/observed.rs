//! 只观察持久替换所需完整性，不改变旧解析容错或写入资格。
use super::parser::envelope;
use serde_json::Value;

fn list<'a>(value: &'a Value, keys: &[&str]) -> Option<&'a Vec<Value>> {
    value.as_array().or_else(|| {
        keys.iter()
            .find_map(|key| value.get(*key).and_then(Value::as_array))
    })
}
fn identified(value: &Value) -> bool {
    value
        .as_object()
        .and_then(|v| v.get("id"))
        .is_some_and(|v| v.as_str().is_some_and(|s| !s.trim().is_empty()) || v.is_number())
}
pub(super) fn list_complete(body: &str, keys: &[&str]) -> bool {
    envelope(body).ok().is_some_and(|v| {
        list(&v, keys).is_some_and(|items| {
            items.iter().all(|item| {
                identified(item)
                    && ["children", "storeys"].iter().all(|key| {
                        item.get(*key).is_none_or(|v| {
                            v.as_array()
                                .is_some_and(|items| items.iter().all(identified))
                        })
                    })
            })
        })
    })
}
pub(super) fn detail_complete(body: &str) -> bool {
    let Ok(value) = envelope(body) else {
        return false;
    };
    let dates = match value.get("date").and_then(Value::as_object) {
        Some(date) => date.get("list").and_then(Value::as_array),
        None => list(&value, &["availableDates", "available_dates"]),
    };
    let direct_slots_complete = ["timeSlots", "time_slots"].iter().all(|key| {
        value.get(*key).is_none_or(|slots| {
            slots
                .as_array()
                .is_some_and(|slots| slots.iter().all(identified))
        })
    });
    if !direct_slots_complete {
        return false;
    }
    dates.is_some_and(|items| {
        items.iter().all(|item| {
            if let Some(text) = item.as_str() {
                return !text.is_empty();
            }
            item.as_object().is_some_and(|v| {
                let day = v.get("day").or_else(|| v.get("date"));
                day.and_then(Value::as_str).is_some_and(|s| !s.is_empty())
                    && list(item, &["times", "timeSlots"])
                        .is_some_and(|slots| slots.iter().all(identified))
            })
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 缺失列表和丢弃项不证明完整而显式空集合可以替换() {
        assert!(!list_complete(r#"{"code":1,"data":{}}"#, &["list"]));
        assert!(!list_complete(
            r#"{"code":1,"data":{"list":[{"id":"1"},null]}}"#,
            &["list"]
        ));
        assert!(list_complete(r#"{"code":1,"data":{"list":[]}}"#, &["list"]));
    }
    #[test]
    fn 日期别名必须遵守原解析优先级且时段丢项不能完整() {
        assert!(!detail_complete(
            r#"{"code":1,"data":{"date":{},"availableDates":["2026-09-22"]}}"#
        ));
        assert!(!detail_complete(
            r#"{"code":1,"data":{"availableDates":["2026-09-22"],"timeSlots":[null]}}"#
        ));
        assert!(detail_complete(r#"{"code":1,"data":{"date":{"list":[]}}}"#));
    }
}
