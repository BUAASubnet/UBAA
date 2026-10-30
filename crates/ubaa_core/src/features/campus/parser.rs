use std::collections::{BTreeMap, BTreeSet};
use std::sync::LazyLock;

use crate::domain::{CampusAmount, NetworkProductUsage, NetworkUsage, PortalProfile};
use crate::error::{Result, UbaaError};
use regex::Regex;
use scraper::{Html, Selector};
use serde_json::Value;

static DECIMAL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$").unwrap());
static TRAFFIC: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^([0-9]+(?:\.[0-9]+)?)(byte|[KMGT])$").unwrap());
static TABLE: LazyLock<Selector> = LazyLock::new(|| Selector::parse("table").unwrap());
static HEAD: LazyLock<Selector> = LazyLock::new(|| Selector::parse("thead th").unwrap());
static ROW: LazyLock<Selector> = LazyLock::new(|| Selector::parse("tbody > tr").unwrap());
static CELL: LazyLock<Selector> = LazyLock::new(|| Selector::parse("td[data-col-seq]").unwrap());
const LABELS: [&str; 4] = [
    "产品名称",
    "已用流量",
    "免费流量剩余(不含套餐)",
    "计费流量剩余(不含套餐)",
];

pub(super) fn profile(payload: &Value, fetched_at: i64) -> Result<PortalProfile> {
    let data = envelope(payload)?;
    let info = data.get("info").ok_or_else(invalid)?;
    Ok(PortalProfile {
        identity: nonblank(&info["identity"])?.into(),
        department: nonblank(&info["depart"])?.into(),
        fetched_at,
    })
}

pub(super) fn envelope(payload: &Value) -> Result<&Value> {
    match payload.get("e").and_then(Value::as_i64) {
        Some(0) => payload
            .get("d")
            .filter(|v| v.is_object())
            .ok_or_else(invalid),
        Some(10013) => Err(business_login_required()),
        Some(_) => Err(UbaaError::upstream_unavailable("校园账户服务暂时不可用")),
        None => Err(invalid()),
    }
}

pub(super) fn business_login_required() -> UbaaError {
    UbaaError::new(
        crate::error::ErrorCode::UpstreamUnavailable,
        crate::error::ErrorKind::Authentication,
        false,
        "业务登录暂不可用，请重新认证后重试",
    )
}

pub(super) fn nonblank(value: &Value) -> Result<&str> {
    value
        .as_str()
        .map(str::trim)
        .filter(|v| !v.is_empty() && v.len() <= 512 && !v.chars().any(char::is_control))
        .ok_or_else(invalid)
}

fn decimal(value: &Value) -> Result<String> {
    let text = match value {
        Value::Number(v) => v.to_string(),
        Value::String(v) => v.trim().to_owned(),
        _ => return Err(invalid()),
    };
    if text.len() > 64 || !DECIMAL.is_match(&text) {
        return Err(invalid());
    }
    Ok(text)
}

pub(super) fn amount(data: &Value) -> Result<CampusAmount> {
    let value = decimal(&data["value"])?;
    let unit = data["unit"]
        .as_str()
        .filter(|s| s.len() <= 16 && !s.chars().any(char::is_control))
        .ok_or_else(invalid)?;
    Ok(CampusAmount {
        value,
        unit: unit.into(),
    })
}

pub(super) fn count(data: &Value) -> Result<u64> {
    let value = decimal(&data["value"])?;
    if value.contains('.') {
        return Err(invalid());
    }
    value.parse().map_err(|_| invalid())
}

fn text(element: scraper::ElementRef<'_>) -> String {
    element
        .text()
        .collect::<String>()
        .split_whitespace()
        .collect::<String>()
        .replace('（', "(")
        .replace('）', ")")
}

fn traffic_amount(value: &str) -> Result<CampusAmount> {
    let captures = TRAFFIC.captures(value).ok_or_else(invalid)?;
    Ok(CampusAmount {
        value: decimal(&Value::String(captures[1].into()))?,
        unit: captures[2].into(),
    })
}

pub(super) fn traffic(page: &str, fetched_at: i64) -> Result<NetworkUsage> {
    let document = Html::parse_document(page);
    let mut tables = Vec::new();
    for table in document.select(&TABLE) {
        let headers: Vec<_> = table.select(&HEAD).collect();
        if !headers.iter().any(|cell| text(*cell) == LABELS[1]) {
            continue;
        }
        let mut columns = BTreeMap::new();
        let mut sequences = BTreeSet::new();
        for cell in headers {
            let label = text(cell);
            if LABELS.contains(&label.as_str()) {
                let seq = cell
                    .value()
                    .attr("data-col-seq")
                    .filter(|v| !v.is_empty())
                    .ok_or_else(invalid)?;
                if columns.insert(label, seq.to_owned()).is_some()
                    || !sequences.insert(seq.to_owned())
                {
                    return Err(invalid());
                }
            }
        }
        if !LABELS.iter().all(|label| columns.contains_key(*label)) {
            return Err(invalid());
        }
        let mut products = Vec::new();
        for row in table.select(&ROW) {
            // 套餐展开行不带列标识；不把嵌套表格当作产品行。
            let mut cells = BTreeMap::new();
            for cell in row.select(&CELL).filter(|cell| cell.parent() == Some(*row)) {
                let seq = cell.value().attr("data-col-seq").ok_or_else(invalid)?;
                if cells.insert(seq, text(cell)).is_some() {
                    return Err(invalid());
                }
            }
            if cells.is_empty() {
                continue;
            }
            let get = |label: &str| -> Result<&str> {
                cells
                    .get(columns.get(label).ok_or_else(invalid)?.as_str())
                    .map(String::as_str)
                    .ok_or_else(invalid)
            };
            let name = get(LABELS[0])?;
            if name.is_empty() || name.len() > 512 {
                return Err(invalid());
            }
            products.push(NetworkProductUsage {
                product_name: name.into(),
                used: traffic_amount(get(LABELS[1])?)?,
                free_remaining: traffic_amount(get(LABELS[2])?)?,
                billable_remaining: traffic_amount(get(LABELS[3])?)?,
            });
        }
        if products.is_empty() {
            return Err(invalid());
        }
        tables.push(products);
    }
    if tables.len() != 1 {
        return Err(invalid());
    }
    Ok(NetworkUsage {
        products: tables.remove(0),
        remaining_excludes_packages: true,
        fetched_at,
    })
}

pub(super) fn invalid() -> UbaaError {
    UbaaError::upstream_changed("校园账户响应不符合已验证的格式")
}
