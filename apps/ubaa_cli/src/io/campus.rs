//! 校园查询的人类可读输出；仅消费 Core 的公开投影。
use super::schema::CliFeature;
use serde_json::Value;
use std::io::{self, Write};
use ubaa_core::facade::ConnectionMode;

pub(super) fn write<W: Write>(
    stdout: &mut W,
    feature: CliFeature,
    route: ConnectionMode,
    data: &Value,
) -> io::Result<bool> {
    if !matches!(feature, CliFeature::Portal | CliFeature::Network) {
        return Ok(false);
    }
    writeln!(stdout, "查询路线：{route:?}")?;
    if feature == CliFeature::Network {
        if let Some(products) = data["products"].as_array() {
            for product in products {
                writeln!(
                    stdout,
                    "网络产品：{}",
                    product["productName"].as_str().unwrap_or_default()
                )?;
                for (key, label) in [
                    ("used", "已用流量"),
                    ("freeRemaining", "免费流量剩余（不含套餐）"),
                    ("billableRemaining", "计费流量剩余（不含套餐）"),
                ] {
                    writeln!(stdout, "{label}：{}", amount(&product[key]))?;
                }
            }
        }
        writeln!(stdout, "取得时间：{}", data["fetchedAt"])?;
    } else if let Some(identity) = data["identity"].as_str() {
        writeln!(stdout, "身份：{identity}")?;
        writeln!(
            stdout,
            "学院：{}",
            data["department"].as_str().unwrap_or_default()
        )?;
        writeln!(stdout, "取得时间：{}", data["fetchedAt"])?;
    } else {
        for (key, label) in [
            ("networkBalance", "网费余额"),
            ("cardBalance", "校园卡余额"),
            ("unreadMail", "未读邮件"),
            ("borrowedBooks", "待还图书"),
            ("cloudStorageRemaining", "云盘剩余空间"),
        ] {
            let item = &data[key];
            let display = if item["status"] == "success" {
                if item["value"].is_object() {
                    amount(&item["value"])
                } else {
                    item["value"].to_string()
                }
            } else {
                "暂不可用".into()
            };
            writeln!(
                stdout,
                "{label}：{display}（取得时间：{}）",
                item["fetchedAt"]
            )?;
        }
    }
    Ok(true)
}

fn amount(value: &Value) -> String {
    format!(
        "{}{}",
        value["value"].as_str().unwrap_or_default(),
        value["unit"].as_str().unwrap_or_default()
    )
}
