use crate::{
    agenda::store::AgendaData,
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaItem, SchoolAgendaOverlay},
};
use std::collections::BTreeMap;
use uuid::Uuid;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Stamp {
    pub device_id: Uuid,
    pub sequence: u64,
}
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct SyncState {
    pub device_id: Uuid,
    pub next_sequence: u64,
    pub epoch: u64,
    pub items: BTreeMap<Uuid, Stamp>,
    pub overlays: BTreeMap<String, Stamp>,
    pub pending: Option<StoredPending>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct StoredPending {
    pub id: Uuid,
    pub(super) step: SyncStep,
    pub document: super::AgendaSyncDocument,
    pub object: Option<String>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum SyncStep {
    Directory,
    File,
}
impl SyncState {
    pub fn fresh() -> Self {
        Self {
            device_id: Uuid::new_v4(),
            next_sequence: 1,
            ..Self::default()
        }
    }
    pub(super) fn next(&mut self) -> CacheResult<Stamp> {
        let sequence = self.next_sequence;
        self.next_sequence = sequence
            .checked_add(1)
            .filter(|v| i64::try_from(*v).is_ok())
            .ok_or(CacheError::Capacity)?;
        Ok(Stamp {
            device_id: self.device_id,
            sequence,
        })
    }
    pub(crate) fn advance_epoch(&mut self) -> CacheResult<()> {
        self.epoch = self
            .epoch
            .checked_add(1)
            .filter(|v| i64::try_from(*v).is_ok())
            .ok_or(CacheError::Capacity)?;
        Ok(())
    }
}
pub(crate) fn track_local_changes(before: &AgendaData, after: &mut AgendaData) -> CacheResult<()> {
    if before.active != after.active {
        after.sync.advance_epoch()?;
    }
    after
        .sync
        .items
        .retain(|key, _| after.items.contains_key(key));
    after
        .sync
        .overlays
        .retain(|key, _| after.overlays.contains_key(key));
    for (key, item) in &after.items {
        if item.locally_modified
            && before
                .items
                .get(key)
                .is_none_or(|old| !same_item(old, item))
        {
            let stamp = after.sync.next()?;
            after.sync.items.insert(*key, stamp);
        }
    }
    for (key, value) in &after.overlays {
        if value.locally_modified
            && before
                .overlays
                .get(key)
                .is_none_or(|old| !same_overlay(old, value))
        {
            let stamp = after.sync.next()?;
            after.sync.overlays.insert(key.clone(), stamp);
        }
    }
    Ok(())
}
pub(super) fn same_item(a: &AgendaItem, b: &AgendaItem) -> bool {
    a.id == b.id
        && a.updated_at == b.updated_at
        && a.deleted_at == b.deleted_at
        && a.content == b.content
        && a.rrule == b.rrule
        && a.exdates == b.exdates
        && a.overrides == b.overrides
        && a.completions == b.completions
        && a.created_at == b.created_at
}
pub(super) fn same_overlay(a: &SchoolAgendaOverlay, b: &SchoolAgendaOverlay) -> bool {
    a.key == b.key
        && a.updated_at == b.updated_at
        && a.deleted_at == b.deleted_at
        && a.completed_at == b.completed_at
        && a.completion_override == b.completion_override
        && a.hidden == b.hidden
        && a.note == b.note
}
