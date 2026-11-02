use super::models::{
    BridgeAgendaCompletion, BridgeAgendaContent, BridgeAgendaEditScope, BridgeAgendaError,
    BridgeAgendaFailure, BridgeAgendaItem, BridgeAgendaKind, BridgeAgendaOccurrence,
    BridgeAgendaOverlay, BridgeAgendaOverlayDraft, BridgeAgendaOverride, BridgeAgendaTime,
    BridgeSchoolAgendaKey,
};
use chrono::{DateTime, NaiveDate, Timelike};
use ubaa_core::facade as core;
use uuid::Uuid;
pub(crate) fn error(e: core::CacheError) -> BridgeAgendaError {
    BridgeAgendaError {
        failure: match e {
            core::CacheError::Unavailable => BridgeAgendaFailure::Unavailable,
            core::CacheError::InvalidInput => BridgeAgendaFailure::InvalidInput,
            core::CacheError::Corrupt => BridgeAgendaFailure::Corrupt,
            core::CacheError::UnsupportedVersion => BridgeAgendaFailure::UnsupportedVersion,
            core::CacheError::Inactive => BridgeAgendaFailure::Inactive,
            core::CacheError::Superseded => BridgeAgendaFailure::Superseded,
            core::CacheError::Capacity => BridgeAgendaFailure::Capacity,
        },
    }
}
pub(super) fn invalid() -> BridgeAgendaError {
    error(core::CacheError::InvalidInput)
}
pub(super) fn date(v: &str) -> Result<NaiveDate, BridgeAgendaError> {
    let d = NaiveDate::parse_from_str(v, "%Y-%m-%d").map_err(|_| invalid())?;
    if d.to_string() != v {
        return Err(invalid());
    }
    Ok(d)
}
pub(super) fn id(v: &str) -> Result<Uuid, BridgeAgendaError> {
    let id = Uuid::parse_str(v).map_err(|_| invalid())?;
    if id.is_nil() || id.to_string() != v {
        return Err(invalid());
    }
    Ok(id)
}
impl TryFrom<BridgeAgendaTime> for core::AgendaTime {
    type Error = BridgeAgendaError;
    fn try_from(v: BridgeAgendaTime) -> Result<Self, Self::Error> {
        let t = DateTime::parse_from_rfc3339(&v.rfc3339).map_err(|_| invalid())?;
        let value = Self::new(t);
        if v.timezone != "Asia/Shanghai"
            || t.nanosecond() != 0
            || t.offset() != value.datetime.offset()
        {
            return Err(invalid());
        }
        Ok(value)
    }
}
impl From<core::AgendaTime> for BridgeAgendaTime {
    fn from(v: core::AgendaTime) -> Self {
        Self {
            rfc3339: v.datetime.to_rfc3339(),
            timezone: v.timezone.to_string(),
        }
    }
}
pub(super) fn time(
    v: Option<BridgeAgendaTime>,
) -> Result<Option<core::AgendaTime>, BridgeAgendaError> {
    v.map(TryInto::try_into).transpose()
}
impl TryFrom<BridgeAgendaContent> for core::AgendaContent {
    type Error = BridgeAgendaError;
    fn try_from(v: BridgeAgendaContent) -> Result<Self, Self::Error> {
        Ok(Self {
            kind: match v.kind {
                BridgeAgendaKind::Event => core::AgendaKind::Event,
                BridgeAgendaKind::Task => core::AgendaKind::Task,
            },
            title: v.title,
            location: v.location,
            notes: v.notes,
            color: v.color,
            start: time(v.start)?,
            end: time(v.end)?,
            due: time(v.due)?,
            all_day: v.all_day,
        })
    }
}
impl From<core::AgendaContent> for BridgeAgendaContent {
    fn from(v: core::AgendaContent) -> Self {
        Self {
            kind: match v.kind {
                core::AgendaKind::Event => BridgeAgendaKind::Event,
                core::AgendaKind::Task => BridgeAgendaKind::Task,
            },
            title: v.title,
            location: v.location,
            notes: v.notes,
            color: v.color,
            start: v.start.map(Into::into),
            end: v.end.map(Into::into),
            due: v.due.map(Into::into),
            all_day: v.all_day,
        }
    }
}
impl From<BridgeAgendaEditScope> for core::AgendaEditScope {
    fn from(v: BridgeAgendaEditScope) -> Self {
        match v {
            BridgeAgendaEditScope::This => Self::This,
            BridgeAgendaEditScope::ThisAndFuture => Self::ThisAndFuture,
            BridgeAgendaEditScope::All => Self::All,
        }
    }
}
impl From<BridgeSchoolAgendaKey> for core::SchoolAgendaKey {
    fn from(v: BridgeSchoolAgendaKey) -> Self {
        Self {
            source: v.source,
            upstream_id: v.upstream_id,
        }
    }
}
impl From<core::SchoolAgendaKey> for BridgeSchoolAgendaKey {
    fn from(v: core::SchoolAgendaKey) -> Self {
        Self {
            source: v.source,
            upstream_id: v.upstream_id,
        }
    }
}
impl From<core::AgendaItem> for BridgeAgendaItem {
    fn from(v: core::AgendaItem) -> Self {
        Self {
            id: v.id.to_string(),
            content: v.content.into(),
            rrule: v.rrule,
            exdates: v.exdates.into_iter().map(Into::into).collect(),
            overrides: v
                .overrides
                .into_iter()
                .map(|(recurrence_id, content)| BridgeAgendaOverride {
                    recurrence_id,
                    content: content.into(),
                })
                .collect(),
            completions: v
                .completions
                .into_iter()
                .map(|(recurrence_id, at)| BridgeAgendaCompletion {
                    recurrence_id,
                    completed_at: at.map(Into::into),
                })
                .collect(),
            created_at: v.created_at.into(),
            updated_at: v.updated_at.into(),
            deleted_at: v.deleted_at.map(Into::into),
            locally_modified: v.locally_modified,
        }
    }
}
impl From<core::AgendaOccurrence> for BridgeAgendaOccurrence {
    fn from(v: core::AgendaOccurrence) -> Self {
        Self {
            item_id: v.item_id.to_string(),
            recurrence_id: v.recurrence_id,
            content: v.content.into(),
            completed_at: v.completed_at.map(Into::into),
            overridden: v.overridden,
        }
    }
}
impl From<core::SchoolAgendaOverlay> for BridgeAgendaOverlay {
    fn from(v: core::SchoolAgendaOverlay) -> Self {
        Self {
            value: BridgeAgendaOverlayDraft {
                key: v.key.into(),
                completed_at: v.completed_at.map(Into::into),
                completion_override: v.completion_override,
                hidden: v.hidden,
                note: v.note,
            },
            updated_at: v.updated_at.into(),
            deleted_at: v.deleted_at.map(Into::into),
            locally_modified: v.locally_modified,
        }
    }
}
