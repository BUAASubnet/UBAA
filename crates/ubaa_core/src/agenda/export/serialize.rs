//! 将已展开条目序列化为有大小限制的 RFC 5545 快照。
use super::{AgendaExportOptions, AgendaExportResult};
use crate::{
    agenda::store::AgendaData,
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaEntry, AgendaEntryItem, AgendaTime, AgendaTiming},
};
use chrono::{Datelike, Utc};
use icalendar::{Calendar, Component, Event, EventLike, Property, Todo, TodoStatus};
use sha2::{Digest, Sha256};
use std::fmt::{self, Write};
pub(super) fn serialize(
    data: &AgendaData,
    entries: &[AgendaEntry],
    o: &AgendaExportOptions,
    account: &str,
) -> CacheResult<AgendaExportResult> {
    let mut calendar = Calendar::new();
    calendar.append_property(Property::new("PRODID", "-//UBAA//Agenda Snapshot//ZH"));
    calendar.append_property(Property::new("X-UBAA-EXPORT-MODE", "RANGE-SNAPSHOT"));
    calendar.append_property(Property::new("X-UBAA-RANGE-FROM", o.from.to_string()));
    calendar.append_property(Property::new("X-UBAA-RANGE-TO", o.to.to_string()));
    calendar.append_property(Property::new("X-UBAA-TIMEZONE", "Asia/Shanghai"));
    let header = calendar.to_string();
    let mut out = LimitedOutput(
        header
            .strip_suffix("END:VCALENDAR\r\n")
            .ok_or(CacheError::Unavailable)?
            .to_owned(),
    );
    let mut result = AgendaExportResult {
        ics: String::new(),
        exported_count: 0,
        skipped_unknown_time_count: 0,
    };
    for entry in entries {
        if entry.completed && !o.include_completed {
            continue;
        }
        match entry.timing() {
            AgendaTiming::Period {
                start: Some(start),
                end: Some(end),
            } if end > start => {
                check_time(start)?;
                check_time(end)?;
                let mut event = Event::new();
                event
                    .starts(start.datetime.with_timezone(&Utc))
                    .ends(end.datetime.with_timezone(&Utc));
                decorate(&mut event, entry, data, o, account)?;
                event
                    .fmt_write(&mut out)
                    .map_err(|_| CacheError::Capacity)?;
            }
            AgendaTiming::AllDay { from, to }
                if matches!(entry.item, AgendaEntryItem::Local(_)) && from < to =>
            {
                if [from, to].iter().any(|d| !(1..=9999).contains(&d.year())) {
                    return Err(CacheError::InvalidInput);
                }
                let mut event = Event::new();
                event.starts(from).ends(to);
                decorate(&mut event, entry, data, o, account)?;
                event
                    .fmt_write(&mut out)
                    .map_err(|_| CacheError::Capacity)?;
            }
            timing @ (AgendaTiming::Deadline(_) | AgendaTiming::Undated)
                if matches!(timing, AgendaTiming::Deadline(_))
                    || matches!(entry.item, AgendaEntryItem::Local(_)) =>
            {
                let mut todo = Todo::new();
                if let AgendaTiming::Deadline(due) = timing {
                    check_time(due)?;
                    todo.due(due.datetime.with_timezone(&Utc));
                }
                todo.status(if entry.completed {
                    TodoStatus::Completed
                } else {
                    TodoStatus::NeedsAction
                });
                if entry.completed {
                    todo.percent_complete(100);
                    let completed_at = match &entry.item {
                        AgendaEntryItem::Local(v) => v.completed_at,
                        AgendaEntryItem::School(v) => data
                            .overlays
                            .get(&crate::agenda::operations::overlay_key(&v.key)?)
                            .filter(|v| v.deleted_at.is_none() && v.completion_override)
                            .and_then(|v| v.completed_at),
                    };
                    if let Some(at) = completed_at {
                        check_time(at)?;
                        todo.completed(at.datetime.with_timezone(&Utc));
                    }
                }
                decorate(&mut todo, entry, data, o, account)?;
                todo.fmt_write(&mut out).map_err(|_| CacheError::Capacity)?;
            }
            // 学校的全天占位、未知端点或无日期并不能证明真实的事件/待办时间。
            _ => {
                result.skipped_unknown_time_count += 1;
                continue;
            }
        }
        result.exported_count += 1;
    }
    out.write_str("END:VCALENDAR\r\n")
        .map_err(|_| CacheError::Capacity)?;
    result.ics = out.0;
    Ok(result)
}

fn decorate(
    c: &mut impl Component,
    entry: &AgendaEntry,
    data: &AgendaData,
    o: &AgendaExportOptions,
    account: &str,
) -> CacheResult<()> {
    c.timestamp(o.generated_at.datetime.with_timezone(&Utc))
        .summary(&text(entry.title())?);
    if let Some(note) = &entry.note {
        c.description(&text(note)?);
    }
    c.add_property("X-UBAA-COMPLETED", boolean(entry.completed));
    c.add_property("X-UBAA-HIDDEN", boolean(entry.hidden));
    let (key, location) = match &entry.item {
        AgendaEntryItem::Local(v) => {
            let item = data.items.get(&v.item_id).ok_or(CacheError::Corrupt)?;
            check_time(item.created_at)?;
            check_time(item.updated_at)?;
            c.created(item.created_at.datetime.with_timezone(&Utc))
                .last_modified(item.updated_at.datetime.with_timezone(&Utc));
            c.add_property("X-UBAA-SOURCE", "local");
            c.add_property("X-UBAA-RECURRENCE-ID", &v.recurrence_id);
            (
                serde_json::to_vec(&("local", v.item_id, &v.recurrence_id)),
                &v.content.location,
            )
        }
        AgendaEntryItem::School(v) => {
            c.append_property(
                Property::new("X-UBAA-SOURCE", text(&v.key.source)?).add_parameter("VALUE", "TEXT"),
            );
            c.add_property(
                "X-UBAA-UPSTREAM-COMPLETED",
                boolean(v.upstream_status.completed()),
            );
            // 上游修改时间未知；本地覆盖时间只作扩展属性，不能冒充上游 LAST-MODIFIED。
            if let Some(overlay) = data
                .overlays
                .get(&crate::agenda::operations::overlay_key(&v.key)?)
            {
                check_time(overlay.updated_at)?;
                c.add_property(
                    "X-UBAA-OVERLAY-MODIFIED",
                    overlay
                        .updated_at
                        .datetime
                        .with_timezone(&Utc)
                        .format("%Y%m%dT%H%M%SZ")
                        .to_string(),
                );
            }
            (
                serde_json::to_vec(&("school", account, &v.key.source, &v.key.upstream_id)),
                &v.location,
            )
        }
    };
    if let Some(location) = location {
        c.add_property("LOCATION", text(location)?);
    }
    let hash = Sha256::digest(key.map_err(|_| CacheError::InvalidInput)?);
    c.uid(&format!("{}@agenda.ubaa", hex::encode(hash)));
    Ok(())
}
fn boolean(value: bool) -> &'static str {
    if value { "TRUE" } else { "FALSE" }
}
pub(super) fn valid_time(value: AgendaTime) -> bool {
    value.valid()
        && (1..=9999).contains(&value.datetime.year())
        && (1..=9999).contains(&value.datetime.with_timezone(&Utc).year())
}
fn check_time(value: AgendaTime) -> CacheResult<()> {
    if valid_time(value) {
        Ok(())
    } else {
        Err(CacheError::InvalidInput)
    }
}
fn text(value: &str) -> CacheResult<String> {
    let value = value.replace("\r\n", "\n");
    if value.chars().any(|c| c.is_control() && c != '\n') {
        return Err(CacheError::InvalidInput);
    }
    Ok(value)
}
struct LimitedOutput(String);
impl fmt::Write for LimitedOutput {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        // 独立于磁盘容量限制的输出预算；超限整体失败，不交付截断内容。
        if self.0.len().saturating_add(s.len()) > 32 * 1024 * 1024 {
            return Err(fmt::Error);
        }
        self.0.push_str(s);
        Ok(())
    }
}
