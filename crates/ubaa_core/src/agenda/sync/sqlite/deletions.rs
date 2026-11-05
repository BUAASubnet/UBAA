use super::{device, integer};
use crate::{
    agenda::{
        operations::overlay_key,
        store::AgendaData,
        sync::state::{Deletion, Stamp, SyncState},
    },
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaTime, SchoolAgendaKey},
};
use rusqlite::{Transaction, params};
use std::collections::BTreeMap;
use uuid::Uuid;

pub(super) fn initialize(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    tx.execute_batch("CREATE TABLE agenda_sync_deletions(kind INTEGER NOT NULL CHECK(kind IN (1,2)),key TEXT NOT NULL,deleted_at TEXT NOT NULL,updated_at TEXT NOT NULL,device_id TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),PRIMARY KEY(kind,key));")?;
    crate::agenda::sync::state::remember_deletions(data);
    save(tx, &SyncState::default(), &data.sync)
}
pub(super) fn load(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    let mut statement = tx
        .prepare(
            "SELECT kind,key,deleted_at,updated_at,device_id,sequence FROM agenda_sync_deletions",
        )
        .map_err(|_| CacheError::Corrupt)?;
    let mut rows = statement.query([]).map_err(|_| CacheError::Corrupt)?;
    while let Some(row) = rows.next().map_err(|_| CacheError::Corrupt)? {
        let kind: i64 = row.get(0).map_err(|_| CacheError::Corrupt)?;
        let key: String = row.get(1).map_err(|_| CacheError::Corrupt)?;
        let deleted: String = row.get(2).map_err(|_| CacheError::Corrupt)?;
        let updated: String = row.get(3).map_err(|_| CacheError::Corrupt)?;
        let id: String = row.get(4).map_err(|_| CacheError::Corrupt)?;
        let sequence: i64 = row.get(5).map_err(|_| CacheError::Corrupt)?;
        let value = Deletion {
            deleted_at: time(&deleted)?,
            updated_at: time(&updated)?,
            stamp: Stamp {
                device_id: device(&id)?,
                sequence: u64::try_from(sequence).map_err(|_| CacheError::Corrupt)?,
            },
        };
        if value.stamp.sequence == 0
            || value.stamp.device_id == data.sync.device_id
                && value.stamp.sequence >= data.sync.next_sequence
        {
            return Err(CacheError::Corrupt);
        }
        match kind {
            1 => {
                let id = Uuid::parse_str(&key).map_err(|_| CacheError::Corrupt)?;
                if id.to_string() != key || data.sync.item_deletions.insert(id, value).is_some() {
                    return Err(CacheError::Corrupt);
                }
            }
            2 => {
                let (source, upstream_id): (String, String) =
                    serde_json::from_str(&key).map_err(|_| CacheError::Corrupt)?;
                if overlay_key(&SchoolAgendaKey {
                    source,
                    upstream_id,
                })
                .map_err(|_| CacheError::Corrupt)?
                    != key
                    || data.sync.overlay_deletions.insert(key, value).is_some()
                {
                    return Err(CacheError::Corrupt);
                }
            }
            _ => return Err(CacheError::Corrupt),
        }
    }
    Ok(())
}
pub(super) fn save(tx: &Transaction<'_>, before: &SyncState, after: &SyncState) -> CacheResult<()> {
    let left = records(before);
    let right = records(after);
    for (kind, key) in left.keys().filter(|key| !right.contains_key(*key)) {
        tx.execute(
            "DELETE FROM agenda_sync_deletions WHERE kind=?1 AND key=?2",
            params![kind, key],
        )?;
    }
    for ((kind, key), value) in &right {
        if left.get(&(*kind, key.clone())) != Some(value) {
            tx.execute("INSERT INTO agenda_sync_deletions VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(kind,key) DO UPDATE SET deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,device_id=excluded.device_id,sequence=excluded.sequence",
                params![kind, key, serde_json::to_string(&value.deleted_at).map_err(|_| CacheError::Corrupt)?, serde_json::to_string(&value.updated_at).map_err(|_| CacheError::Corrupt)?, value.stamp.device_id.to_string(), integer(value.stamp.sequence)?])?;
        }
    }
    Ok(())
}
fn records(state: &SyncState) -> BTreeMap<(i64, String), Deletion> {
    state
        .item_deletions
        .iter()
        .map(|(k, v)| ((1, k.to_string()), *v))
        .chain(
            state
                .overlay_deletions
                .iter()
                .map(|(k, v)| ((2, k.clone()), *v)),
        )
        .collect()
}
fn time(raw: &str) -> CacheResult<AgendaTime> {
    let value: AgendaTime = serde_json::from_str(raw).map_err(|_| CacheError::Corrupt)?;
    if !value.valid() {
        return Err(CacheError::Corrupt);
    }
    Ok(value)
}
