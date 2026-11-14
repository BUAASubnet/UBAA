//! 将产品内嵌套餐的可用流量计入免费剩余。
use super::parser::{belongs_to_table, invalid, text, traffic_amount};
use crate::domain::CampusAmount;
use crate::error::Result;
use scraper::{ElementRef, Selector};
use std::sync::LazyLock;

static TABLE: LazyLock<Selector> = LazyLock::new(|| Selector::parse("table").unwrap());
static HEAD: LazyLock<Selector> = LazyLock::new(|| Selector::parse("thead th").unwrap());
static ROW: LazyLock<Selector> = LazyLock::new(|| Selector::parse("tbody > tr").unwrap());
static CELL: LazyLock<Selector> = LazyLock::new(|| Selector::parse("td[data-col-seq]").unwrap());
static BUTTON: LazyLock<Selector> = LazyLock::new(|| Selector::parse("button").unwrap());
const UNITS: [&str; 5] = ["byte", "K", "M", "G", "T"];

pub(super) fn free_remaining(product: ElementRef<'_>, base: CampusAmount) -> Result<CampusAmount> {
    let mut amounts = vec![base];
    for table in product.select(&TABLE) {
        let headers: Vec<_> = table
            .select(&HEAD)
            .filter(|cell| belongs_to_table(*cell, table))
            .collect();
        if !headers.iter().any(|cell| text(*cell) == "套餐名称") {
            continue;
        }
        let mut stats = headers.iter().filter(|cell| text(**cell) == "统计");
        let sequence = stats
            .next()
            .and_then(|cell| cell.value().attr("data-col-seq"))
            .ok_or_else(invalid)?;
        if stats.next().is_some() {
            return Err(invalid());
        }
        for row in table
            .select(&ROW)
            .filter(|row| belongs_to_table(*row, table))
        {
            let cells: Vec<_> = row
                .select(&CELL)
                .filter(|cell| cell.parent() == Some(*row))
                .collect();
            if cells.is_empty() {
                continue;
            }
            let mut matches = cells
                .into_iter()
                .filter(|cell| cell.value().attr("data-col-seq") == Some(sequence));
            let cell = matches.next().ok_or_else(invalid)?;
            if matches.next().is_some() {
                return Err(invalid());
            }
            let available: Vec<_> = cell
                .select(&BUTTON)
                .filter(|button| belongs_to_table(*button, table))
                .map(text)
                .filter_map(|label| label.strip_prefix("可用流量：").map(str::to_owned))
                .collect();
            let [available] = available.as_slice() else {
                return Err(invalid());
            };
            amounts.push(traffic_amount(available)?);
        }
    }
    if amounts.len() == 1 {
        return Ok(amounts.remove(0));
    }
    // 汇总显示按 1024 进制折算，最多保留六位小数。
    let ranked = amounts
        .iter()
        .map(|amount| {
            let rank = UNITS
                .iter()
                .position(|unit| *unit == amount.unit)
                .ok_or_else(invalid)?;
            let value = amount.value.parse::<f64>().map_err(|_| invalid())?;
            Ok((rank, value))
        })
        .collect::<Result<Vec<_>>>()?;
    let rank = ranked
        .iter()
        .map(|(rank, _)| *rank)
        .max()
        .ok_or_else(invalid)?;
    let sum: f64 = ranked
        .iter()
        .map(|(source, value)| value / 1024_f64.powi(i32::try_from(rank - source).unwrap()))
        .sum();
    let value = format!("{sum:.6}")
        .trim_end_matches('0')
        .trim_end_matches('.')
        .to_owned();
    Ok(CampusAmount {
        value,
        unit: UNITS[rank].into(),
    })
}
