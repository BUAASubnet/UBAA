use super::state::{Stamp, StoredPending, SyncState, SyncStep};
use crate::{
    agenda::store::AgendaData,
    cache::{CacheError, CacheResult},
};
use rusqlite::{OptionalExtension, Transaction, params};
use uuid::Uuid;
mod deletions;

pub(crate) fn initialize(tx: &Transaction<'_>, data: &AgendaData) -> CacheResult<()> {
    tx.execute_batch("CREATE TABLE agenda_sync_meta(id INTEGER PRIMARY KEY CHECK(id=1),device_id TEXT NOT NULL,next_sequence INTEGER NOT NULL CHECK(next_sequence>0),epoch INTEGER NOT NULL CHECK(epoch>=0),next_publication INTEGER NOT NULL CHECK(next_publication>0),enabled INTEGER NOT NULL CHECK(enabled IN (0,1))); CREATE TABLE agenda_sync_stamps(kind INTEGER NOT NULL CHECK(kind IN (1,2)),key TEXT NOT NULL,device_id TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),PRIMARY KEY(kind,key));")?;
    create_pending(tx)?;
    let mut state = SyncState::fresh();
    for key in data.items.keys() {
        let stamp = state.next()?;
        state.items.insert(*key, stamp);
    }
    for key in data.overlays.keys() {
        let stamp = state.next()?;
        state.overlays.insert(key.clone(), stamp);
    }
    tx.execute(
        "INSERT INTO agenda_sync_meta VALUES(1,?1,?2,0,1,0)",
        params![state.device_id.to_string(), integer(state.next_sequence)?],
    )?;
    save_stamps(tx, &SyncState::default(), &state)?;
    let mut initial = data.clone();
    initial.sync = state;
    deletions::initialize(tx, &mut initial)?;
    Ok(())
}
pub(crate) fn upgrade(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    load_legacy(tx, data)?;
    tx.execute_batch("ALTER TABLE agenda_sync_meta ADD COLUMN next_publication INTEGER NOT NULL DEFAULT 1 CHECK(next_publication>0); ALTER TABLE agenda_sync_meta ADD COLUMN enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1));")?;
    tx.execute_batch("DROP TABLE agenda_sync_pending;")?;
    create_pending(tx)?;
    deletions::initialize(tx, data)
}
fn create_pending(tx: &Transaction<'_>) -> CacheResult<()> {
    tx.execute_batch("CREATE TABLE agenda_sync_pending(id INTEGER PRIMARY KEY CHECK(id=1),attempt TEXT NOT NULL,step INTEGER NOT NULL CHECK(step IN (1,2)),document BLOB,object TEXT,publication INTEGER CHECK(publication>0),registered INTEGER NOT NULL CHECK(registered IN (0,1)));")?;
    Ok(())
}
pub(crate) fn load_legacy(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    load_base(tx, data)?;
    let pending: i64 = tx
        .query_row("SELECT COUNT(*) FROM agenda_sync_pending", [], |r| r.get(0))
        .map_err(|_| CacheError::Corrupt)?;
    if pending != 0 {
        return Err(CacheError::UnsupportedVersion);
    }
    Ok(())
}
pub(crate) fn load(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    load_base(tx, data)?;
    let (publication, enabled): (i64, i64) = tx
        .query_row(
            "SELECT next_publication,enabled FROM agenda_sync_meta WHERE id=1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .map_err(|_| CacheError::Corrupt)?;
    if publication <= 0 || !matches!(enabled, 0 | 1) {
        return Err(CacheError::Corrupt);
    }
    data.sync.next_publication = publication.cast_unsigned();
    data.sync.enabled = enabled == 1;
    deletions::load(tx, data)?;
    load_pending(tx, data)
}
fn load_base(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    let (id, next, epoch): (String, i64, i64) = tx
        .query_row(
            "SELECT device_id,next_sequence,epoch FROM agenda_sync_meta WHERE id=1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|_| CacheError::Corrupt)?;
    let count: i64 = tx
        .query_row("SELECT COUNT(*) FROM agenda_sync_meta", [], |row| {
            row.get(0)
        })
        .map_err(|_| CacheError::Corrupt)?;
    let device_id = device(&id)?;
    if count != 1 || next <= 0 || epoch < 0 {
        return Err(CacheError::Corrupt);
    }
    let mut state = SyncState {
        device_id,
        next_sequence: next.cast_unsigned(),
        next_publication: 1,
        epoch: epoch.cast_unsigned(),
        ..SyncState::default()
    };
    let mut stmt = tx
        .prepare("SELECT kind,key,device_id,sequence FROM agenda_sync_stamps")
        .map_err(|_| CacheError::Corrupt)?;
    let mut rows = stmt.query([]).map_err(|_| CacheError::Corrupt)?;
    while let Some(row) = rows.next().map_err(|_| CacheError::Corrupt)? {
        let kind: i64 = row.get(0).map_err(|_| CacheError::Corrupt)?;
        let key: String = row.get(1).map_err(|_| CacheError::Corrupt)?;
        let id: String = row.get(2).map_err(|_| CacheError::Corrupt)?;
        let sequence: i64 = row.get(3).map_err(|_| CacheError::Corrupt)?;
        let stamp = Stamp {
            device_id: device(&id)?,
            sequence: u64::try_from(sequence).map_err(|_| CacheError::Corrupt)?,
        };
        if stamp.sequence == 0
            || stamp.device_id == device_id && stamp.sequence >= state.next_sequence
        {
            return Err(CacheError::Corrupt);
        }
        match kind {
            1 => {
                let id = Uuid::parse_str(&key).map_err(|_| CacheError::Corrupt)?;
                if id.to_string() != key
                    || !data.items.contains_key(&id)
                    || state.items.insert(id, stamp).is_some()
                {
                    return Err(CacheError::Corrupt);
                }
            }
            2 => {
                if !data.overlays.contains_key(&key) || state.overlays.insert(key, stamp).is_some()
                {
                    return Err(CacheError::Corrupt);
                }
            }
            _ => return Err(CacheError::Corrupt),
        }
    }
    if state.items.len() != data.items.len() || state.overlays.len() != data.overlays.len() {
        return Err(CacheError::Corrupt);
    }
    data.sync = state;
    Ok(())
}
type PendingRow = (
    String,
    i64,
    Option<Vec<u8>>,
    Option<String>,
    Option<i64>,
    i64,
);

fn load_pending(tx: &Transaction<'_>, data: &mut AgendaData) -> CacheResult<()> {
    let length: Option<Option<i64>> = tx
        .query_row(
            "SELECT length(document) FROM agenda_sync_pending WHERE id=1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|_| CacheError::Corrupt)?;
    if let Some(length) = length {
        if length.is_some_and(|length| !(0..=32 * 1024 * 1024).contains(&length)) {
            return Err(CacheError::Corrupt);
        }
        let (attempt, step, bytes, object, publication, registered): PendingRow = tx
            .query_row(
                "SELECT attempt,step,document,object,publication,registered FROM agenda_sync_pending WHERE id=1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?, row.get(5)?)),
            )
            .map_err(|_| CacheError::Corrupt)?;
        if !matches!(registered, 0 | 1)
            || registered == 1 && (step != 2 || object.is_none())
            || object.as_ref().is_some_and(String::is_empty)
        {
            return Err(CacheError::Corrupt);
        }
        if match (step, publication) {
            (1, None) => false,
            (2, Some(sequence)) => {
                sequence <= 0 || sequence.cast_unsigned() >= data.sync.next_publication
            }
            _ => true,
        } {
            return Err(CacheError::Corrupt);
        }
        data.sync.pending = Some(StoredPending {
            id: device(&attempt)?,
            step: match step {
                1 => SyncStep::Directory,
                2 => SyncStep::File,
                _ => return Err(CacheError::Corrupt),
            },
            document: bytes
                .as_deref()
                .map(super::AgendaSyncDocument::decode)
                .transpose()?,
            publication: publication.map(i64::cast_unsigned),
            object,
            registered: registered == 1,
        });
    }
    Ok(())
}
pub(crate) fn save(tx: &Transaction<'_>, before: &SyncState, after: &SyncState) -> CacheResult<()> {
    if before.device_id != after.device_id {
        return Err(CacheError::Corrupt);
    }
    if before.next_sequence != after.next_sequence
        || before.epoch != after.epoch
        || before.next_publication != after.next_publication
        || before.enabled != after.enabled
    {
        tx.execute(
            "UPDATE agenda_sync_meta SET next_sequence=?1,epoch=?2,next_publication=?3,enabled=?4 WHERE id=1",
            params![integer(after.next_sequence)?, integer(after.epoch)?, integer(after.next_publication)?, after.enabled],
        )?;
    }
    if before.pending != after.pending {
        if let Some(pending) = &after.pending {
            let step = match pending.step {
                SyncStep::Directory => 1,
                SyncStep::File => 2,
            };
            tx.execute("INSERT INTO agenda_sync_pending VALUES(1,?1,?2,?3,?4,?5,?6) ON CONFLICT(id) DO UPDATE SET attempt=excluded.attempt,step=excluded.step,document=excluded.document,object=excluded.object,publication=excluded.publication,registered=excluded.registered", params![pending.id.to_string(), step, pending.document.as_ref().map(super::AgendaSyncDocument::encode).transpose()?, pending.object, pending.publication.map(integer).transpose()?, pending.registered])?;
        } else {
            tx.execute("DELETE FROM agenda_sync_pending WHERE id=1", [])?;
        }
    }
    save_stamps(tx, before, after)?;
    deletions::save(tx, before, after)
}
fn save_stamps(tx: &Transaction<'_>, before: &SyncState, after: &SyncState) -> CacheResult<()> {
    let left: std::collections::BTreeMap<_, _> = before
        .items
        .iter()
        .map(|(k, v)| ((1, k.to_string()), *v))
        .chain(before.overlays.iter().map(|(k, v)| ((2, k.clone()), *v)))
        .collect();
    let right: std::collections::BTreeMap<_, _> = after
        .items
        .iter()
        .map(|(k, v)| ((1, k.to_string()), *v))
        .chain(after.overlays.iter().map(|(k, v)| ((2, k.clone()), *v)))
        .collect();
    for (kind, key) in left.keys().filter(|key| !right.contains_key(*key)) {
        tx.execute(
            "DELETE FROM agenda_sync_stamps WHERE kind=?1 AND key=?2",
            params![kind, key],
        )?;
    }
    for ((kind, key), stamp) in &right {
        if left.get(&(*kind, key.clone())) != Some(stamp) {
            tx.execute("INSERT INTO agenda_sync_stamps VALUES(?1,?2,?3,?4) ON CONFLICT(kind,key) DO UPDATE SET device_id=excluded.device_id,sequence=excluded.sequence", params![kind,key,stamp.device_id.to_string(),integer(stamp.sequence)?])?;
        }
    }
    Ok(())
}
fn integer(value: u64) -> CacheResult<i64> {
    i64::try_from(value).map_err(|_| CacheError::Capacity)
}
fn device(raw: &str) -> CacheResult<Uuid> {
    Uuid::parse_str(raw)
        .ok()
        .filter(|v| !v.is_nil() && v.to_string() == raw)
        .ok_or(CacheError::Corrupt)
}
