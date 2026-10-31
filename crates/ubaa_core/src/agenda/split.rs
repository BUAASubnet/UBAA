//! 系列拆分保持原始发生时间身份，COUNT 按排除前的发生次数计算。
use super::recurrence::{is_occurrence, parse_id, raw_dates, rule_set, shift_content};
use crate::cache::{CacheError, CacheResult};
use crate::domain::agenda::{AgendaContent, AgendaItem, AgendaTime};
use chrono::{Duration, Utc};

pub(super) fn truncate(item: &mut AgendaItem, at: AgendaTime, now: AgendaTime) -> CacheResult<()> {
    let dates = raw_dates(item, at)?;
    if dates.len() <= 1 {
        item.deleted_at = Some(now);
        return Ok(());
    }
    let raw = item.rrule.as_ref().ok_or(CacheError::InvalidInput)?;
    let mut parts: Vec<_> = raw
        .split(';')
        .filter(|s| !s.starts_with("UNTIL=") && !s.starts_with("COUNT="))
        .map(str::to_owned)
        .collect();
    let until = at
        .datetime
        .checked_sub_signed(Duration::seconds(1))
        .ok_or(CacheError::InvalidInput)?
        .with_timezone(&Utc);
    parts.push(format!("UNTIL={}", until.format("%Y%m%dT%H%M%SZ")));
    item.rrule = Some(parts.join(";"));
    item.exdates.retain(|t| *t < at);
    item.overrides
        .retain(|key, _| parse_id(key).is_ok_and(|t| t < at));
    item.completions
        .retain(|key, _| parse_id(key).is_ok_and(|t| t < at));
    Ok(())
}
pub(super) fn split(
    item: &mut AgendaItem,
    at: AgendaTime,
    content: AgendaContent,
    mut rule: Option<String>,
    now: AgendaTime,
) -> CacheResult<AgendaItem> {
    if rule == item.rrule {
        if let (Some(raw), Some(new_anchor)) = (&mut rule, content.anchor()) {
            *raw = shift_until(raw, new_anchor.datetime - at.datetime)?;
        }
        if let Some(set) = rule_set(item)?
            && let Some(count) = set.get_rrule()[0].get_count()
        {
            let before = raw_dates(item, at)?
                .len()
                .checked_sub(1)
                .ok_or(CacheError::InvalidInput)?;
            let remaining = count
                .checked_sub(u32::try_from(before).map_err(|_| CacheError::Capacity)?)
                .ok_or(CacheError::InvalidInput)?;
            let parts: Vec<_> = rule
                .as_deref()
                .ok_or(CacheError::InvalidInput)?
                .split(';')
                .filter(|s| !s.starts_with("COUNT="))
                .collect();
            rule = Some(format!("{};COUNT={remaining}", parts.join(";")));
        }
    }
    let mut next = AgendaItem::new(content, now);
    next.rrule = rule;
    next.exdates = item.exdates.iter().filter(|t| **t >= at).copied().collect();
    next.overrides = item
        .overrides
        .iter()
        .filter(|(k, _)| parse_id(k).is_ok_and(|t| t >= at))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    next.completions = item
        .completions
        .iter()
        .filter(|(k, _)| parse_id(k).is_ok_and(|t| t >= at))
        .map(|(k, v)| (k.clone(), *v))
        .collect();
    let anchor = next.content.anchor();
    remap_exceptions(&mut next, Some(at), anchor)?;
    truncate(item, at, now)?;
    Ok(next)
}
/// 时间平移时保留例外身份；新规则不再产生的例外随规则替换移除。
pub(super) fn remap_exceptions(
    item: &mut AgendaItem,
    old: Option<AgendaTime>,
    new: Option<AgendaTime>,
) -> CacheResult<()> {
    if old.is_none() && new.is_none() {
        return Ok(());
    }
    let (Some(old), Some(new)) = (old, new) else {
        let old_key = old.map_or_else(|| "undated".to_owned(), AgendaTime::recurrence_id);
        let completion = item.completions.get(&old_key).copied();
        item.exdates.clear();
        item.overrides.clear();
        item.completions.clear();
        if let Some(completion) = completion {
            let key = new.map_or_else(|| "undated".to_owned(), AgendaTime::recurrence_id);
            if new.is_none() || is_occurrence(item, new.ok_or(CacheError::InvalidInput)?)? {
                item.completions.insert(key, completion);
            }
        }
        return Ok(());
    };
    let delta = new.datetime - old.datetime;
    let shift = |t: AgendaTime| {
        t.datetime
            .checked_add_signed(delta)
            .map(AgendaTime::new)
            .ok_or(CacheError::InvalidInput)
    };
    let mut exdates = std::collections::BTreeSet::new();
    for at in &item.exdates {
        let at = shift(*at)?;
        if is_occurrence(item, at)? {
            exdates.insert(at);
        }
    }
    let mut overrides = std::collections::BTreeMap::new();
    for (key, content) in &item.overrides {
        let at = shift(parse_id(key)?)?;
        if is_occurrence(item, at)? {
            let content = if let Some(anchor) = content.anchor() {
                shift_content(content, shift(anchor)?)?
            } else {
                content.clone()
            };
            overrides.insert(at.recurrence_id(), content);
        }
    }
    let mut completions = std::collections::BTreeMap::new();
    for (key, value) in &item.completions {
        if key == "undated" {
            continue;
        }
        let at = shift(parse_id(key)?)?;
        if is_occurrence(item, at)? {
            completions.insert(at.recurrence_id(), *value);
        }
    }
    item.exdates = exdates;
    item.overrides = overrides;
    item.completions = completions;
    Ok(())
}

/// 相同系列平移后，UNTIL 也平移，保留最后一次发生。
pub(super) fn shift_until(raw: &str, delta: Duration) -> CacheResult<String> {
    raw.split(';')
        .map(|part| {
            if let Some(value) = part.strip_prefix("UNTIL=") {
                let until = if value.len() == 8 {
                    chrono::NaiveDate::parse_from_str(value, "%Y%m%d")
                        .map_err(|_| CacheError::InvalidInput)?
                        .and_hms_opt(0, 0, 0)
                        .ok_or(CacheError::InvalidInput)?
                        .and_local_timezone(chrono_tz::Asia::Shanghai)
                        .single()
                        .ok_or(CacheError::InvalidInput)?
                        .with_timezone(&Utc)
                } else {
                    chrono::NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%SZ")
                        .map_err(|_| CacheError::InvalidInput)?
                        .and_utc()
                };
                let until = until
                    .checked_add_signed(delta)
                    .ok_or(CacheError::InvalidInput)?;
                Ok(format!("UNTIL={}", until.format("%Y%m%dT%H%M%SZ")))
            } else {
                Ok(part.to_owned())
            }
        })
        .collect::<CacheResult<Vec<_>>>()
        .map(|v| v.join(";"))
}
