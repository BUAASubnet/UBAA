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
                "{} | {} | {} | 金额 {} 元 | 税额 {} 元 | 实发 {} 元 | 部门 {} | 项目编号 {} | 项目名称 {}",
                e["recordedDate"].as_str().unwrap_or("未知日期"),
                e["project"].as_str().unwrap_or("未提供项目"),
                e["description"].as_str().unwrap_or(""),
                money(&e["amountCents"]),
                money(&e["taxCents"]),
                money(&e["paidCents"]),
                e["department"].as_str().unwrap_or("未知"),
                e["projectCode"].as_str().unwrap_or("未知"),
                e["projectName"].as_str().unwrap_or("未知")
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
#[cfg(test)]
mod tests {
    use super::write;
    use serde_json::json;
    use ubaa_core::facade::ConnectionMode;
    #[test]
    fn 人类输出显示部门和项目字段且缺失时为未知() {
        let data = json!({
            "total": 2,
            "entries": [
                {
                    "recordedDate": "2026-11-20",
                    "project": "合成发放项目",
                    "description": "合成摘要",
                    "department": "示例学院",
                    "projectCode": "SYNTH-PROJECT-01",
                    "projectName": "合成项目名称",
                    "amountCents": 10000,
                    "taxCents": 0,
                    "paidCents": 10000
                },
                {
                    "recordedDate": "2026-11-19",
                    "project": null,
                    "description": null,
                    "department": null,
                    "projectCode": null,
                    "projectName": null,
                    "amountCents": null,
                    "taxCents": null,
                    "paidCents": null
                }
            ]
        });
        let mut out = Vec::new();
        write(&mut out, ConnectionMode::Direct, &data).unwrap();
        let out = String::from_utf8(out).unwrap();
        assert!(out.contains("部门 示例学院"));
        assert!(out.contains("项目编号 SYNTH-PROJECT-01"));
        assert!(out.contains("项目名称 合成项目名称"));
        assert!(out.contains("部门 未知 | 项目编号 未知 | 项目名称 未知"));
    }
}
