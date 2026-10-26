//! Judge 历史课程使用的上海时间六个月截止算法。

use chrono::{Datelike, Months, NaiveDateTime, Timelike, Utc};
use chrono_tz::Asia::Shanghai;

pub(super) fn six_month_cutoff() -> String {
    six_month_cutoff_from_shanghai(
        &Utc::now()
            .with_timezone(&Shanghai)
            .format("%Y-%m-%d %H:%M:%S")
            .to_string(),
    )
    .expect("当前上海日期应可表示")
}

pub(super) fn six_month_cutoff_from_shanghai(value: &str) -> Option<String> {
    let value = parse_judge_datetime(value)?;
    let date = value.date().checked_sub_months(Months::new(6))?;
    Some(format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
        date.year(),
        date.month(),
        date.day(),
        value.hour(),
        value.minute(),
        value.second()
    ))
}

pub(super) fn started_before_cutoff(start: &str, cutoff: &str) -> bool {
    parse_judge_datetime(start)
        .zip(parse_judge_datetime(cutoff))
        .is_some_and(|(start, cutoff)| start < cutoff)
}

fn parse_judge_datetime(value: &str) -> Option<NaiveDateTime> {
    // 协议只接受完整到秒的四位年份；Chrono 的宽松宽度和闰秒不扩大旧接受集合。
    let parsed = NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M:%S").ok()?;
    (value.len() == 19
        && parsed.format("%Y-%m-%d %H:%M:%S").to_string() == value
        && parsed.nanosecond() == 0)
        .then_some(parsed)
}
