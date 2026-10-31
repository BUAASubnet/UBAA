use crate::cache::{CacheError, CacheResult};
use crate::domain::agenda::{
    AgendaContent, AgendaItem, AgendaOccurrence, AgendaTime, TeachingWeekPattern, TeachingWeekRule,
};
use chrono::{Datelike, Duration, NaiveDate, NaiveTime, Utc, Weekday};
use chrono_tz::Asia::Shanghai;
use rrule::{RRule, RRuleSet, Unvalidated};

pub(super) fn rule_set(item: &AgendaItem) -> CacheResult<Option<RRuleSet>> {
    let Some(raw) = &item.rrule else {
        return Ok(None);
    };
    if raw.len() > 4096 || raw.contains(['\n', '\r', ':']) {
        return Err(CacheError::InvalidInput);
    }
    let anchor = item.content.anchor().ok_or(CacheError::InvalidInput)?;
    let start = anchor.datetime.with_timezone(&rrule::Tz::Tz(Shanghai));
    // 全天 DATE UNTIL 按校园零点转换后交给库，避免解析器使用机器本地时区。
    let normalized = raw
        .split(';')
        .map(|part| {
            if item.content.all_day
                && let Some(value) = part.strip_prefix("UNTIL=")
                && value.len() == 8
            {
                let day = NaiveDate::parse_from_str(value, "%Y%m%d")
                    .map_err(|_| CacheError::InvalidInput)?;
                let utc = local_time(day, NaiveTime::MIN)?
                    .datetime
                    .with_timezone(&Utc);
                Ok(format!("UNTIL={}", utc.format("%Y%m%dT%H%M%SZ")))
            } else {
                Ok(part.to_owned())
            }
        })
        .collect::<CacheResult<Vec<_>>>()?
        .join(";");
    let rule = normalized
        .parse::<RRule<Unvalidated>>()
        .map_err(|_| CacheError::InvalidInput)?
        .validate(start)
        .map_err(|_| CacheError::InvalidInput)?;
    Ok(Some(RRuleSet::new(start).rrule(rule)))
}
pub(super) fn raw_dates(item: &AgendaItem, through: AgendaTime) -> CacheResult<Vec<AgendaTime>> {
    let Some(set) = rule_set(item)? else {
        return Ok(item.content.anchor().into_iter().collect());
    };
    let result = set
        .before(through.datetime.with_timezone(&rrule::Tz::Tz(Shanghai)))
        .all(u16::MAX);
    if result.limited {
        return Err(CacheError::Capacity);
    }
    Ok(result
        .dates
        .into_iter()
        .map(|v| AgendaTime::new(v.fixed_offset()))
        .collect())
}
pub(super) fn validate_item(item: &AgendaItem) -> CacheResult<()> {
    if item.id.is_nil()
        || !item.content.valid()
        || !item.created_at.valid()
        || !item.updated_at.valid()
        || item.updated_at < item.created_at
        || item.deleted_at.is_some_and(|t| !t.valid())
        || item.exdates.iter().any(|t| !t.valid())
        || item.overrides.values().any(|v| !v.valid())
        || item.completions.values().flatten().any(|t| !t.valid())
        || item.overrides.len() + item.completions.len() + item.exdates.len() > 10000
    {
        return Err(CacheError::InvalidInput);
    }
    rule_set(item)?;
    let mut ids = std::collections::BTreeSet::new();
    for key in item.overrides.keys().chain(item.completions.keys()) {
        if key == "undated" && item.content.anchor().is_none() && item.rrule.is_none() {
            continue;
        }
        ids.insert(parse_id(key)?);
    }
    if let Some(last) = ids.last() {
        let actual: std::collections::BTreeSet<_> = raw_dates(item, *last)?.into_iter().collect();
        if !ids.is_subset(&actual) {
            return Err(CacheError::InvalidInput);
        }
    }
    Ok(())
}
pub(super) fn parse_id(key: &str) -> CacheResult<AgendaTime> {
    let time = AgendaTime::new(key.parse().map_err(|_| CacheError::InvalidInput)?);
    if time.recurrence_id() != key || !time.valid() {
        return Err(CacheError::InvalidInput);
    }
    Ok(time)
}
pub(super) fn is_occurrence(item: &AgendaItem, at: AgendaTime) -> CacheResult<bool> {
    if !at.valid() {
        return Ok(false);
    }
    Ok(raw_dates(item, at)?.contains(&at))
}
/// 展开 [from, to) 内相交的时段或落在范围内的截止事项。无日期待办始终返回。
///
/// # Errors
/// 非法内容、时间范围、规则或展开达到资源上限时返回稳定本地错误，绝不返回截断结果。
pub fn expand_agenda(
    item: &AgendaItem,
    from: NaiveDate,
    to: NaiveDate,
) -> CacheResult<Vec<AgendaOccurrence>> {
    if from >= to || (to - from).num_days() > 3660 {
        return Err(CacheError::InvalidInput);
    }
    validate_item(item)?;
    if item.deleted_at.is_some() {
        return Ok(Vec::new());
    }
    let end = local_time(to, NaiveTime::MIN)?;
    let dates = raw_dates(item, end)?;
    let mut rows = Vec::new();
    for at in dates {
        if at >= end || item.exdates.contains(&at) {
            continue;
        }
        let key = at.recurrence_id();
        let content = item
            .overrides
            .get(&key)
            .cloned()
            .unwrap_or(shift_content(&item.content, at)?);
        if intersects(&content, from, to) {
            rows.push(occurrence(item, key, content));
        }
    }
    // 原始时间在范围之外但移动到范围内的覆盖，同样必须可见。
    for (key, content) in &item.overrides {
        if parse_id(key)? >= end
            && !item.exdates.contains(&parse_id(key)?)
            && intersects(content, from, to)
        {
            rows.push(occurrence(item, key.clone(), content.clone()));
        }
    }
    if item.content.anchor().is_none() {
        rows.push(occurrence(item, "undated".into(), item.content.clone()));
    }
    rows.sort_by_key(|r| (r.content.anchor(), r.item_id, r.recurrence_id.clone()));
    Ok(rows)
}
fn occurrence(item: &AgendaItem, key: String, content: AgendaContent) -> AgendaOccurrence {
    AgendaOccurrence {
        item_id: item.id,
        overridden: item.overrides.contains_key(&key),
        completed_at: item.completions.get(&key).copied().flatten(),
        recurrence_id: key,
        content,
    }
}
fn intersects(content: &AgendaContent, from: NaiveDate, to: NaiveDate) -> bool {
    content.anchor().is_none_or(|t| {
        t.datetime.date_naive() < to
            && content.end.map_or(t.datetime.date_naive() >= from, |end| {
                end.datetime.date_naive() > from
                    || (end.datetime.date_naive() == from && end.datetime.time() > NaiveTime::MIN)
            })
    })
}
pub(super) fn shift_content(
    content: &AgendaContent,
    anchor: AgendaTime,
) -> CacheResult<AgendaContent> {
    let delta = anchor.datetime - content.anchor().ok_or(CacheError::InvalidInput)?.datetime;
    let mut content = content.clone();
    for t in [&mut content.start, &mut content.end, &mut content.due]
        .into_iter()
        .flatten()
    {
        *t = AgendaTime::new(
            t.datetime
                .checked_add_signed(delta)
                .ok_or(CacheError::InvalidInput)?,
        );
    }
    Ok(content)
}
fn local_time(day: NaiveDate, time: NaiveTime) -> CacheResult<AgendaTime> {
    day.and_time(time)
        .and_local_timezone(Shanghai)
        .single()
        .map(|t| AgendaTime::new(t.fixed_offset()))
        .ok_or(CacheError::InvalidInput)
}
/// 将教学周快捷输入转换为标准规则；周次以学期第一周为基准计算单双周。
///
/// # Errors
/// 第一周起点非周一、周范围非法、无匹配周或日期溢出时返回 `InvalidInput`。
pub fn teaching_week_rule(
    monday: NaiveDate,
    first: u32,
    last: u32,
    pattern: TeachingWeekPattern,
    weekday: Weekday,
    time: NaiveTime,
    skips: &[NaiveDate],
) -> CacheResult<TeachingWeekRule> {
    if monday.weekday() != Weekday::Mon || first == 0 || first > last || last > 104 {
        return Err(CacheError::InvalidInput);
    }
    let first = (first..=last)
        .find(|week| match pattern {
            TeachingWeekPattern::Every => true,
            TeachingWeekPattern::Odd => week % 2 == 1,
            TeachingWeekPattern::Even => week % 2 == 0,
        })
        .ok_or(CacheError::InvalidInput)?;
    let date = |week: u32| {
        monday
            .checked_add_signed(Duration::days(i64::from(
                (week - 1) * 7 + weekday.num_days_from_monday(),
            )))
            .ok_or(CacheError::InvalidInput)
    };
    let start = local_time(date(first)?, time)?;
    let until = local_time(date(last)?, time)?
        .datetime
        .with_timezone(&Utc)
        .format("%Y%m%dT%H%M%SZ");
    let byday = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][weekday.num_days_from_monday() as usize];
    let interval = if pattern == TeachingWeekPattern::Every {
        1
    } else {
        2
    };
    Ok(TeachingWeekRule {
        start,
        rrule: format!("FREQ=WEEKLY;INTERVAL={interval};BYDAY={byday};UNTIL={until}"),
        exdates: skips
            .iter()
            .map(|d| local_time(*d, time))
            .collect::<CacheResult<_>>()?,
    })
}
