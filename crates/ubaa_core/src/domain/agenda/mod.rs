//! 自建日程及学校事项的本地覆盖值，不含上游协议。
use chrono::{DateTime, FixedOffset, Timelike};
use chrono_tz::{Asia::Shanghai, Tz};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

/// 带 IANA 时区标识的校园时间。序列化保留偏移量与时区。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaTime {
    pub datetime: DateTime<FixedOffset>,
    pub timezone: Tz,
}
impl AgendaTime {
    #[must_use]
    pub fn new(datetime: DateTime<FixedOffset>) -> Self {
        Self {
            datetime: datetime.with_timezone(&Shanghai).fixed_offset(),
            timezone: Shanghai,
        }
    }
    #[must_use]
    pub fn recurrence_id(self) -> String {
        self.datetime.to_rfc3339()
    }
    pub(crate) fn valid(self) -> bool {
        self.timezone == Shanghai
            && self.datetime.nanosecond() == 0
            && self.datetime.offset()
                == self
                    .datetime
                    .with_timezone(&Shanghai)
                    .fixed_offset()
                    .offset()
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AgendaKind {
    Event,
    Task,
}

/// 可编辑内容；全天结束时间为不包含在事项内的次日零点。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaContent {
    pub kind: AgendaKind,
    pub title: String,
    pub location: Option<String>,
    pub notes: Option<String>,
    pub color: Option<String>,
    pub start: Option<AgendaTime>,
    pub end: Option<AgendaTime>,
    pub all_day: bool,
    pub due: Option<AgendaTime>,
}
impl AgendaContent {
    #[must_use]
    pub fn anchor(&self) -> Option<AgendaTime> {
        self.start.or(self.due)
    }
    pub(crate) fn valid(&self) -> bool {
        !self.title.trim().is_empty()
            && self.title.len() <= 4096
            && [&self.location, &self.notes, &self.color]
                .iter()
                .all(|s| s.as_ref().is_none_or(|s| s.len() <= 65536))
            && [self.start, self.end, self.due]
                .into_iter()
                .flatten()
                .all(AgendaTime::valid)
            && match self.kind {
                AgendaKind::Event => {
                    self.due.is_none()
                        && self.start.zip(self.end).is_some_and(|(a, b)| {
                            b.datetime > a.datetime
                                && (!self.all_day
                                    || [a, b]
                                        .iter()
                                        .all(|t| t.datetime.time() == chrono::NaiveTime::MIN))
                        })
                }
                AgendaKind::Task => self.start.is_none() && self.end.is_none() && !self.all_day,
            }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaItem {
    pub id: Uuid,
    pub content: AgendaContent,
    /// 仅包含 RFC 5545 的规则正文，不含 RRULE: 前缀或 DTSTART。
    pub rrule: Option<String>,
    pub exdates: BTreeSet<AgendaTime>,
    /// 键为原始发生时间的 RFC 3339 字符串；移动后仍使用原键。
    pub overrides: BTreeMap<String, AgendaContent>,
    /// 无日期事项使用 undated 键；None 明确表示本地取消完成。
    pub completions: BTreeMap<String, Option<AgendaTime>>,
    pub created_at: AgendaTime,
    pub updated_at: AgendaTime,
    pub deleted_at: Option<AgendaTime>,
    pub locally_modified: bool,
}
impl AgendaItem {
    #[must_use]
    pub fn new(content: AgendaContent, now: AgendaTime) -> Self {
        Self {
            id: Uuid::new_v4(),
            content,
            rrule: None,
            exdates: BTreeSet::new(),
            overrides: BTreeMap::new(),
            completions: BTreeMap::new(),
            created_at: now,
            updated_at: now,
            deleted_at: None,
            locally_modified: true,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct SchoolAgendaKey {
    pub source: String,
    pub upstream_id: String,
}
/// `记录存在且未删除时，completed_at=None` 表示明确重新挂起，优先于上游完成。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct SchoolAgendaOverlay {
    pub key: SchoolAgendaKey,
    pub completed_at: Option<AgendaTime>,
    /// false 表示只设置隐藏或备注，完成状态继续沿用上游。
    pub completion_override: bool,
    pub hidden: bool,
    pub note: Option<String>,
    pub updated_at: AgendaTime,
    pub deleted_at: Option<AgendaTime>,
    pub locally_modified: bool,
}
impl SchoolAgendaOverlay {
    #[must_use]
    pub fn effective_completed(&self, upstream: bool) -> bool {
        if self.deleted_at.is_some() || !self.completion_override {
            upstream
        } else {
            self.completed_at.is_some()
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AgendaOccurrence {
    pub item_id: Uuid,
    pub recurrence_id: String,
    pub content: AgendaContent,
    pub completed_at: Option<AgendaTime>,
    pub overridden: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AgendaEditScope {
    This,
    ThisAndFuture,
    All,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TeachingWeekPattern {
    Every,
    Odd,
    Even,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TeachingWeekRule {
    pub start: AgendaTime,
    pub rrule: String,
    pub exdates: BTreeSet<AgendaTime>,
}

impl Ord for AgendaTime {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        (self.datetime, self.timezone.name()).cmp(&(other.datetime, other.timezone.name()))
    }
}
impl PartialOrd for AgendaTime {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
