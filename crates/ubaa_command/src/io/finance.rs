//! 财务查询的人类可读投影，金额使用整数分格式化。
use serde_json::Value;
use std::io::{self, Write};
use ubaa_core::facade::ConnectionMode;
pub(super) fn write(out: &mut impl Write, route: ConnectionMode, data: &Value) -> io::Result<()> {
    writeln!(out, "查询路线：{route:?}；收入记录：{} 笔", data["total"])?;
    if let Some(entries) = data["entries"].as_array() {
        for e in entries {
            writeln!(
                out,
                "{} | {} | {} | 金额 {} 元 | 税额 {} 元 | 实发 {} 元",
                e["recordedDate"].as_str().unwrap_or("未知日期"),
                e["project"].as_str().unwrap_or("未提供项目"),
                e["description"].as_str().unwrap_or(""),
                money(&e["amountCents"]),
                money(&e["taxCents"]),
                money(&e["paidCents"])
            )?;
        }
    }
    Ok(())
}
fn money(v: &Value) -> String {
    v.as_i64().map_or_else(
        || "未知".into(),
        |v| {
            let n = v.unsigned_abs();
            format!("{}{}.{:02}", if v < 0 { "-" } else { "" }, n / 100, n % 100)
        },
    )
}
