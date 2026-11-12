use super::pending::StoredPending;
use crate::{
    agenda::store::AgendaData,
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaItem, AgendaTime, SchoolAgendaOverlay},
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
    pub next_publication: u64,
    pub enabled: bool,
    pub epoch: u64,
    pub items: BTreeMap<Uuid, Stamp>,
    pub overlays: BTreeMap<String, Stamp>,
    pub item_deletions: BTreeMap<Uuid, Deletion>,
    pub overlay_deletions: BTreeMap<String, Deletion>,
    pub pending: Option<StoredPending>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Deletion {
    pub deleted_at: AgendaTime,
    pub updated_at: AgendaTime,
    pub stamp: Stamp,
}
impl Deletion {
    pub(super) fn version(self) -> (AgendaTime, Uuid, u64) {
        (self.updated_at, self.stamp.device_id, self.stamp.sequence)
    }
}
impl SyncState {
    pub fn fresh() -> Self {
        Self {
            device_id: Uuid::new_v4(),
            next_sequence: 1,
            next_publication: 1,
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
            if after
                .sync
                .overlay_deletions
                .get(key)
                .is_some_and(|deleted| {
                    (value.updated_at, stamp.device_id, stamp.sequence) <= deleted.version()
                })
            {
                return Err(CacheError::InvalidInput);
            }
            after.sync.overlays.insert(key.clone(), stamp);
        }
    }
    remember_deletions(after);
    Ok(())
}
pub(super) fn remember_deletions(data: &mut AgendaData) {
    for (key, item) in &data.items {
        if let Some(deleted_at) = item.deleted_at
            && let Some(stamp) = data.sync.items.get(key)
        {
            remember(
                &mut data.sync.item_deletions,
                *key,
                Deletion {
                    deleted_at,
                    updated_at: item.updated_at,
                    stamp: *stamp,
                },
            );
        }
    }
    for (key, overlay) in &data.overlays {
        if let Some(deleted_at) = overlay.deleted_at
            && let Some(stamp) = data.sync.overlays.get(key)
        {
            remember(
                &mut data.sync.overlay_deletions,
                key.clone(),
                Deletion {
                    deleted_at,
                    updated_at: overlay.updated_at,
                    stamp: *stamp,
                },
            );
        }
    }
}
fn remember<K: Ord>(map: &mut BTreeMap<K, Deletion>, key: K, value: Deletion) {
    if map
        .get(&key)
        .is_none_or(|old| value.version() > old.version())
    {
        map.insert(key, value);
    }
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
