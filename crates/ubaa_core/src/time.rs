//! 校园业务统一使用的上海时区日期和时间辅助函数。

use chrono::{DateTime, FixedOffset, NaiveDateTime, TimeZone, Utc};
use std::time::SystemTime;

const SHANGHAI_OFFSET_SECONDS: i32 = 8 * 60 * 60;

/// 将当前时刻格式化为校园接口使用的 `yyyy-mm-dd` 日期。
pub(crate) fn shanghai_date(now: SystemTime) -> String {
    let seconds = now
        .duration_since(SystemTime::UNIX_EPOCH)
        .map_or(0, |value| value.as_secs())
        + SHANGHAI_OFFSET_SECONDS as u64;
    let days = seconds / 86_400;
    let days = i64::try_from(days).unwrap_or(i64::MAX);
    let (year, month, day) = civil_date(days);
    format!("{year:04}-{month:02}-{day:02}")
}

/// 将当前时刻格式化为签到缓存使用的 `yyyymmdd` 日期。
pub(crate) fn shanghai_compact_date(now: SystemTime) -> String {
    shanghai_date(now).replace('-', "")
}

/// 按固定的东八区偏移将时刻转换为本地无时区时间。
pub(crate) fn shanghai_datetime(now: SystemTime) -> NaiveDateTime {
    let offset =
        FixedOffset::east_opt(SHANGHAI_OFFSET_SECONDS).expect("Asia/Shanghai 固定偏移必须有效");
    DateTime::<Utc>::from(now)
        .with_timezone(&offset)
        .naive_local()
}

/// 将 Unix 秒时间戳按校园时区格式化。
pub(crate) fn format_shanghai_timestamp(seconds: i64, format: &str) -> Option<String> {
    let offset = FixedOffset::east_opt(SHANGHAI_OFFSET_SECONDS)?;
    offset
        .timestamp_opt(seconds, 0)
        .single()
        .map(|value| value.format(format).to_string())
}

fn civil_date(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + i64::from(month <= 2);
    (year, month, day)
}

#[cfg(test)]
mod tests {
    use super::{
        format_shanghai_timestamp, shanghai_compact_date, shanghai_date, shanghai_datetime,
    };
    use chrono::NaiveDateTime;
    use std::time::{Duration, SystemTime};

    #[test]
    fn 上海日期在纪元和跨日边界保持冻结格式() {
        assert_eq!(shanghai_date(SystemTime::UNIX_EPOCH), "1970-01-01");
        assert_eq!(shanghai_compact_date(SystemTime::UNIX_EPOCH), "19700101");
        assert_eq!(
            shanghai_date(SystemTime::UNIX_EPOCH + Duration::from_secs(86_400 - 1)),
            "1970-01-02"
        );
    }

    #[test]
    fn 上海时间保持固定东八区和时间戳格式() {
        assert_eq!(
            shanghai_datetime(SystemTime::UNIX_EPOCH),
            NaiveDateTime::parse_from_str("1970-01-01 08:00:00", "%Y-%m-%d %H:%M:%S").unwrap()
        );
        assert_eq!(
            format_shanghai_timestamp(0, "%Y-%m-%d %H:%M"),
            Some("1970-01-01 08:00".into())
        );
    }
}
