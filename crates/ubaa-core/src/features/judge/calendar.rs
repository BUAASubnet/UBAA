//! Judge 历史课程使用的上海时间六个月截止算法。

use std::time::{SystemTime, UNIX_EPOCH};

pub(super) fn six_month_cutoff() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
        + 8 * 60 * 60;
    let days = i64::try_from(seconds / 86_400).unwrap_or(i64::MAX);
    let seconds_of_day = seconds % 86_400;
    let hour = seconds_of_day / 3_600;
    let minute = seconds_of_day % 3_600 / 60;
    let second = seconds_of_day % 60;
    let (year, month, day) = civil_date(days);
    six_month_cutoff_from_shanghai(&format!(
        "{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}"
    ))
    .expect("the current Shanghai date is valid")
}

pub(super) fn six_month_cutoff_from_shanghai(value: &str) -> Option<String> {
    let (mut year, mut month, day, hour, minute, second) = parse_judge_datetime(value)?;
    if month <= 6 {
        year -= 1;
        month += 6;
    } else {
        month -= 6;
    }
    let target_day = day.min(days_in_month(year, month));
    Some(format!(
        "{year:04}-{month:02}-{target_day:02} {hour:02}:{minute:02}:{second:02}"
    ))
}

pub(super) fn started_before_cutoff(start: &str, cutoff: &str) -> bool {
    parse_judge_datetime(start)
        .zip(parse_judge_datetime(cutoff))
        .is_some_and(|(start, cutoff)| start < cutoff)
}

fn parse_judge_datetime(value: &str) -> Option<(i64, i64, i64, i64, i64, i64)> {
    let capture = regex::Regex::new(r"^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$")
        .expect("static Judge datetime regex")
        .captures(value)?;
    let year = capture.get(1)?.as_str().parse::<i64>().ok()?;
    let month = capture.get(2)?.as_str().parse::<i64>().ok()?;
    let day = capture.get(3)?.as_str().parse::<i64>().ok()?;
    let hour = capture.get(4)?.as_str().parse::<i64>().ok()?;
    let minute = capture.get(5)?.as_str().parse::<i64>().ok()?;
    let second = capture.get(6)?.as_str().parse::<i64>().ok()?;
    if !(1..=12).contains(&month)
        || !(1..=days_in_month(year, month)).contains(&day)
        || !(0..=23).contains(&hour)
        || !(0..=59).contains(&minute)
        || !(0..=59).contains(&second)
    {
        return None;
    }
    Some((year, month, day, hour, minute, second))
}

fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => unreachable!("month is validated before calculating its length"),
    }
}

fn is_leap_year(year: i64) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
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
    (year + i64::from(month <= 2), month, day)
}
