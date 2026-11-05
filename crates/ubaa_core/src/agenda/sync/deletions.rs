use super::{
    AgendaSyncDocument,
    document::valid_version,
    state::{Deletion, Stamp},
};
use crate::{
    agenda::{operations::overlay_key, store::AgendaData},
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaTime, SchoolAgendaKey},
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use uuid::Uuid;

/// 自建事项的删除版本，不保留已删除内容。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaSyncItemDeletion {
    pub id: Uuid,
    pub deleted_at: AgendaTime,
    pub updated_at: AgendaTime,
    pub device_id: Uuid,
    pub sequence: u64,
}
/// 学校事项覆盖的删除版本，不保留备注与状态正文。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AgendaSyncOverlayDeletion {
    pub key: SchoolAgendaKey,
    pub deleted_at: AgendaTime,
    pub updated_at: AgendaTime,
    pub device_id: Uuid,
    pub sequence: u64,
}
impl AgendaSyncItemDeletion {
    pub(super) fn value(&self) -> Deletion {
        value(
            self.deleted_at,
            self.updated_at,
            self.device_id,
            self.sequence,
        )
    }
    pub(super) fn version(&self) -> (AgendaTime, Uuid, u64) {
        self.value().version()
    }
}
impl AgendaSyncOverlayDeletion {
    pub(super) fn value(&self) -> Deletion {
        value(
            self.deleted_at,
            self.updated_at,
            self.device_id,
            self.sequence,
        )
    }
    pub(super) fn version(&self) -> (AgendaTime, Uuid, u64) {
        self.value().version()
    }
}
fn value(
    deleted_at: AgendaTime,
    updated_at: AgendaTime,
    device_id: Uuid,
    sequence: u64,
) -> Deletion {
    Deletion {
        deleted_at,
        updated_at,
        stamp: Stamp {
            device_id,
            sequence,
        },
    }
}
fn valid(value: Deletion) -> CacheResult<()> {
    valid_version(value.stamp.device_id, value.stamp.sequence)?;
    if !value.deleted_at.valid() || !value.updated_at.valid() {
        return Err(CacheError::Corrupt);
    }
    Ok(())
}
pub(super) fn normalize(document: &mut AgendaSyncDocument) -> CacheResult<()> {
    document.item_deletions.sort_by_key(|v| v.id);
    let mut items = BTreeMap::new();
    for value in &document.item_deletions {
        valid(value.value())?;
        if value.id.is_nil() || items.insert(value.id, value.version()).is_some() {
            return Err(CacheError::Corrupt);
        }
    }
    let mut overlays = BTreeMap::new();
    for value in &document.overlay_deletions {
        valid(value.value())?;
        let key = overlay_key(&value.key).map_err(|_| CacheError::Corrupt)?;
        if overlays.insert(key, value).is_some() {
            return Err(CacheError::Corrupt);
        }
    }
    for value in &document.items {
        if items.get(&value.item.id)
            == Some(&(value.item.updated_at, value.device_id, value.sequence))
        {
            return Err(CacheError::Corrupt);
        }
    }
    for value in &document.overlays {
        if overlays
            .get(&overlay_key(&value.overlay.key)?)
            .is_some_and(|deletion| {
                deletion.version() == (value.overlay.updated_at, value.device_id, value.sequence)
            })
        {
            return Err(CacheError::Corrupt);
        }
    }
    document.items.retain(|value| {
        items.get(&value.item.id).is_none_or(|deleted| {
            *deleted < (value.item.updated_at, value.device_id, value.sequence)
        })
    });
    document.overlays.retain(|value| {
        overlays
            .get(&overlay_key(&value.overlay.key).expect("覆盖键已经验证"))
            .is_none_or(|deleted| {
                deleted.version() < (value.overlay.updated_at, value.device_id, value.sequence)
            })
    });
    document.overlay_deletions = overlays.into_values().cloned().collect();
    Ok(())
}
pub(super) fn append(data: &AgendaData, document: &mut AgendaSyncDocument) -> CacheResult<()> {
    for (id, value) in &data.sync.item_deletions {
        document.item_deletions.push(AgendaSyncItemDeletion {
            id: *id,
            deleted_at: value.deleted_at,
            updated_at: value.updated_at,
            device_id: value.stamp.device_id,
            sequence: value.stamp.sequence,
        });
    }
    for (key, value) in &data.sync.overlay_deletions {
        let (source, upstream_id) = serde_json::from_str(key).map_err(|_| CacheError::Corrupt)?;
        document.overlay_deletions.push(AgendaSyncOverlayDeletion {
            key: SchoolAgendaKey {
                source,
                upstream_id,
            },
            deleted_at: value.deleted_at,
            updated_at: value.updated_at,
            device_id: value.stamp.device_id,
            sequence: value.stamp.sequence,
        });
    }
    Ok(())
}

pub(super) fn merge_into(
    data: &mut AgendaData,
    merged: &AgendaSyncDocument,
    remote: &AgendaSyncDocument,
) -> CacheResult<usize> {
    let mut changed = 0;
    let remote_items: BTreeMap<_, _> = remote.item_deletions.iter().map(|v| (v.id, v)).collect();
    for record in &merged.item_deletions {
        let value = record.value();
        super::transaction::imported_sequence(&mut data.sync, value.stamp)?;
        let mut record_changed = data.sync.item_deletions.get(&record.id) != Some(&value);
        data.sync.item_deletions.insert(record.id, value);
        if let Some(item) = data.items.get_mut(&record.id) {
            let stamp = data.sync.items.get(&record.id).ok_or(CacheError::Corrupt)?;
            let old_version = (item.updated_at, stamp.device_id, stamp.sequence);
            if old_version <= value.version() {
                let old = item.clone();
                item.deleted_at = Some(record.deleted_at);
                item.updated_at = record.updated_at;
                item.locally_modified = data.sync.pending.is_some()
                    && item.locally_modified
                    && old_version == value.version()
                    || remote_items.get(&record.id).copied() != Some(record)
                        && (item.locally_modified || old_version != value.version());
                data.sync.items.insert(record.id, value.stamp);
                record_changed |= item != &old;
            }
        }
        changed += usize::from(record_changed);
    }
    let remote_overlays: BTreeMap<_, _> = remote
        .overlay_deletions
        .iter()
        .map(|v| Ok((overlay_key(&v.key)?, v)))
        .collect::<CacheResult<_>>()?;
    for record in &merged.overlay_deletions {
        let key = overlay_key(&record.key)?;
        let value = record.value();
        super::transaction::imported_sequence(&mut data.sync, value.stamp)?;
        let mut record_changed = data.sync.overlay_deletions.get(&key) != Some(&value);
        data.sync.overlay_deletions.insert(key.clone(), value);
        if let Some(overlay) = data.overlays.get_mut(&key) {
            let stamp = data.sync.overlays.get(&key).ok_or(CacheError::Corrupt)?;
            let old_version = (overlay.updated_at, stamp.device_id, stamp.sequence);
            if old_version <= value.version() {
                let old = overlay.clone();
                overlay.deleted_at = Some(record.deleted_at);
                overlay.updated_at = record.updated_at;
                overlay.locally_modified = data.sync.pending.is_some()
                    && overlay.locally_modified
                    && old_version == value.version()
                    || remote_overlays.get(&key).copied() != Some(record)
                        && (overlay.locally_modified || old_version != value.version());
                data.sync.overlays.insert(key, value.stamp);
                record_changed |= overlay != &old;
            }
        }
        changed += usize::from(record_changed);
    }
    Ok(changed)
}

pub(super) fn confirm(data: &mut AgendaData, sent: &AgendaSyncDocument) -> CacheResult<usize> {
    let mut confirmed = 0;
    for record in &sent.item_deletions {
        if data.sync.items.get(&record.id) == Some(&record.value().stamp)
            && let Some(item) = data.items.get_mut(&record.id)
            && item.deleted_at == Some(record.deleted_at)
            && item.updated_at == record.updated_at
        {
            confirmed += usize::from(item.locally_modified);
            item.locally_modified = false;
        }
    }
    for record in &sent.overlay_deletions {
        let key = overlay_key(&record.key)?;
        if data.sync.overlays.get(&key) == Some(&record.value().stamp)
            && let Some(overlay) = data.overlays.get_mut(&key)
            && overlay.deleted_at == Some(record.deleted_at)
            && overlay.updated_at == record.updated_at
        {
            confirmed += usize::from(overlay.locally_modified);
            overlay.locally_modified = false;
        }
    }
    Ok(confirmed)
}

#[cfg(test)]
#[path = "deletion_write_tests.rs"]
mod write_tests;
