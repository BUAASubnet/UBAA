//! SPOC 日期时间的冻结格式规范化。

use std::sync::LazyLock;

use chrono::{DateTime, Datelike, FixedOffset, NaiveDateTime, TimeZone, Timelike};
use chrono_tz::Asia::Shanghai;
use regex::Regex;

pub(super) fn normalize_datetime(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    if raw.is_empty() {
        return None;
    }
    if let Some(value) = parse_instant(raw) {
        let value = value.with_timezone(&Shanghai);
        return Some(format!(
            "{}-{:02}-{:02} {:02}:{:02}:{:02}",
            value.year(),
            value.month(),
            value.day(),
            value.hour(),
            value.minute(),
            value.second(),
        ));
    }
    // 冻结 Instant 解析失败后保留展示文本，不把未知格式改成业务错误。
    let normalized = raw.replace('T', " ");
    let normalized = normalized
        .split_once('.')
        .map_or(normalized.as_str(), |(value, _)| value);
    Some(normalized.to_string())
}

fn parse_instant(raw: &str) -> Option<DateTime<FixedOffset>> {
    // 只保留 Kotlin Instant 的协议语法；日期有效性及跨日/闰年/时区运算交给 Chrono。
    static INSTANT: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(concat!(
            r"^([0-9]{4}|-[0-9]{4,10}|\+[0-9]{5,10})",
            r"(-[0-9]{2}-[0-9]{2})[Tt]",
            r"([0-9]{2}:[0-9]{2}:[0-5][0-9](?:\.[0-9]{1,9})?)",
            r"([Zz]|[+-][0-9]{2}(?::[0-9]{2}){0,2})$",
        ))
        .expect("静态 Instant 语法有效")
    });
    let captures = INSTANT.captures(raw)?;
    let year = &captures[1];
    let digits = year.trim_start_matches(['+', '-']);
    if digits.len() == 10 && digits.as_bytes()[0] > b'1' {
        return None;
    }
    // 冻结解析允许十位前导零；Chrono 接收其数值的规范写法，不改变日期范围。
    let year: i32 = year.parse().ok()?;
    let year = if (0..=9999).contains(&year) {
        format!("{year:04}")
    } else {
        format!("{year:+05}")
    };
    let local = format!("{year}{}T{}", &captures[2], &captures[3]);
    let local = NaiveDateTime::parse_from_str(&local, "%Y-%m-%dT%H:%M:%S%.f").ok()?;
    let offset = &captures[4];
    let seconds = if matches!(offset, "Z" | "z") {
        0
    } else {
        let mut fields = offset[1..].split(':');
        let hour: i32 = fields.next()?.parse().ok()?;
        let minute: i32 = fields.next().unwrap_or("0").parse().ok()?;
        let second: i32 = fields.next().unwrap_or("0").parse().ok()?;
        if minute > 59 || second > 59 {
            return None;
        }
        let seconds = hour * 3600 + minute * 60 + second;
        if seconds > 18 * 3600 {
            return None;
        }
        if offset.starts_with('-') {
            -seconds
        } else {
            seconds
        }
    };
    FixedOffset::east_opt(seconds)?
        .from_local_datetime(&local)
        .single()
}
