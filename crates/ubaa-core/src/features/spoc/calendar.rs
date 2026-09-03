//! SPOC 日期时间的冻结格式规范化。

pub(super) fn normalize_datetime(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    if raw.is_empty() {
        return None;
    }
    if let Some(converted) = normalize_offset_datetime(raw) {
        return Some(converted);
    }
    let normalized = raw.replace('T', " ");
    let normalized = normalized
        .split_once('.')
        .map_or(normalized.as_str(), |(value, _)| value);
    Some(normalized.to_string())
}

fn normalize_offset_datetime(raw: &str) -> Option<String> {
    let bytes = raw.as_bytes();
    if bytes.len() < 20 || bytes.get(10) != Some(&b'T') {
        return None;
    }
    let year = parse_digits(bytes.get(0..4)?)?;
    let month = parse_digits(bytes.get(5..7)?)?;
    let day = parse_digits(bytes.get(8..10)?)?;
    let hour = parse_digits(bytes.get(11..13)?)?;
    let minute = parse_digits(bytes.get(14..16)?)?;
    let second = parse_digits(bytes.get(17..19)?)?;
    if bytes.get(4) != Some(&b'-')
        || bytes.get(7) != Some(&b'-')
        || bytes.get(13) != Some(&b':')
        || bytes.get(16) != Some(&b':')
        || month == 0
        || month > 12
        || day == 0
        || day > days_in_month(year, month)
        || hour > 23
        || minute > 59
        || second > 59
    {
        return None;
    }
    let suffix = &raw[19..];
    let offset_seconds = if suffix.ends_with('Z') {
        0
    } else {
        let position = suffix
            .char_indices()
            .rev()
            .find(|(_, character)| matches!(character, '+' | '-'))?
            .0;
        let zone = &suffix[position..];
        let zone_bytes = zone.as_bytes();
        if zone_bytes.len() != 6 || zone_bytes[3] != b':' {
            return None;
        }
        let zone_hours = parse_digits(&zone_bytes[1..3])?;
        let zone_minutes = parse_digits(&zone_bytes[4..6])?;
        if zone_hours > 23 || zone_minutes > 59 {
            return None;
        }
        let seconds = i64::from(zone_hours * 3600 + zone_minutes * 60);
        if zone_bytes[0] == b'-' {
            -seconds
        } else if zone_bytes[0] == b'+' {
            seconds
        } else {
            return None;
        }
    };
    let utc_seconds = days_from_civil(year, month, day) * 86_400
        + i64::from(hour * 3600 + minute * 60 + second)
        - offset_seconds;
    let shanghai_seconds = utc_seconds + 8 * 60 * 60;
    let days = shanghai_seconds.div_euclid(86_400);
    let time = shanghai_seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    let hour = time / 3600;
    let minute = time % 3600 / 60;
    let second = time % 60;
    Some(format!(
        "{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}"
    ))
}

fn parse_digits(bytes: &[u8]) -> Option<u32> {
    bytes.iter().try_fold(0_u32, |value, byte| {
        byte.is_ascii_digit()
            .then(|| value * 10 + u32::from(*byte - b'0'))
    })
}

fn days_in_month(year: u32, month: u32) -> u32 {
    match month {
        2 if year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400)) => {
            29
        }
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

fn days_from_civil(year: u32, month: u32, day: u32) -> i64 {
    let year = i64::from(year) - i64::from(month <= 2);
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let month = i64::from(month);
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

fn civil_from_days(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = z.div_euclid(146_097);
    let day_of_era = z - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    (year + i64::from(month <= 2), month, day)
}
