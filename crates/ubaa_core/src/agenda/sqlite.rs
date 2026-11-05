//! 日程 schema 4：逐记录明文、发布身份、启用许可与删除摘要。
use super::{operations::overlay_key, recurrence::validate_item, store::AgendaData};
use crate::{
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaItem, AgendaTime, SchoolAgendaOverlay},
};
use rusqlite::{
    Connection, OpenFlags, OptionalExtension, Transaction, TransactionBehavior, params,
};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    time::Duration,
};
use uuid::Uuid;
pub(super) const SCHEMA: i64 = 4;
const RECORD_LIMIT: usize = 16 * 1024 * 1024;

pub(super) fn open(root: &Path, account: &str) -> CacheResult<Connection> {
    let (path, created) = database_path(root, account)?;
    let flags = OpenFlags::SQLITE_OPEN_NO_MUTEX | OpenFlags::SQLITE_OPEN_NOFOLLOW;
    if !created {
        // 先用只读连接检查，旧版、未知版及损坏库不执行配置、建表或写入。
        let mut check =
            Connection::open_with_flags(&path, flags | OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        check.busy_timeout(Duration::from_millis(250))?;
        let tx = check.transaction_with_behavior(TransactionBehavior::Deferred)?;
        load_existing(&tx, account)?;
        let result: String = tx
            .query_row("PRAGMA quick_check(1)", [], |r| r.get(0))
            .map_err(|e| read_error(&e))?;
        if result != "ok" {
            return Err(CacheError::Corrupt);
        }
        tx.commit()?;
    }
    let mut db = Connection::open_with_flags(&path, flags | OpenFlags::SQLITE_OPEN_READ_WRITE)?;
    db.busy_timeout(Duration::from_millis(250))?;
    if created {
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute_batch("CREATE TABLE agenda_meta(id INTEGER PRIMARY KEY CHECK(id=1),schema_version INTEGER NOT NULL,account_alias TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1)));
            CREATE TABLE agenda_items(id TEXT PRIMARY KEY NOT NULL,body TEXT NOT NULL);
            CREATE TABLE agenda_overlays(key TEXT PRIMARY KEY NOT NULL,body TEXT NOT NULL);")?;
        tx.execute(
            "INSERT INTO agenda_meta VALUES(1,?1,?2,1)",
            params![SCHEMA, account],
        )?;
        super::sync::sqlite::initialize(&tx, &AgendaData::default())?;
        tx.pragma_update(None, "user_version", SCHEMA)?;
        tx.commit()?;
    } else {
        // 重新检查打开窗口内的替换或版本变化；仍未执行持久配置。
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let version: i64 = tx.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version == 2 {
            let legacy = load_version(&tx, account, 2)?;
            super::sync::sqlite::initialize(&tx, &legacy)?;
            tx.execute(
                "UPDATE agenda_meta SET schema_version=?1 WHERE id=1",
                [SCHEMA],
            )?;
            tx.pragma_update(None, "user_version", SCHEMA)?;
        } else if version == 3 {
            let mut legacy = load_version(&tx, account, 3)?;
            super::sync::sqlite::upgrade(&tx, &mut legacy)?;
            tx.execute(
                "UPDATE agenda_meta SET schema_version=?1 WHERE id=1",
                [SCHEMA],
            )?;
            tx.pragma_update(None, "user_version", SCHEMA)?;
        }
        load(&tx, account)?;
        tx.commit()?;
    }
    // 不改变已有库的 journal_mode；这些设置只作用于当前连接。
    db.execute_batch("PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY; PRAGMA trusted_schema=OFF;")?;
    Ok(db)
}
pub(super) fn load(tx: &Transaction<'_>, account: &str) -> CacheResult<AgendaData> {
    let mut data = load_version(tx, account, SCHEMA)?;
    super::sync::sqlite::load(tx, &mut data)?;
    Ok(data)
}
fn load_existing(tx: &Transaction<'_>, account: &str) -> CacheResult<AgendaData> {
    let version: i64 = tx
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(|e| read_error(&e))?;
    if version == 2 {
        load_version(tx, account, 2)
    } else if version == 3 {
        let mut data = load_version(tx, account, 3)?;
        super::sync::sqlite::load_legacy(tx, &mut data)?;
        Ok(data)
    } else {
        load(tx, account)
    }
}
fn load_version(tx: &Transaction<'_>, account: &str, expected: i64) -> CacheResult<AgendaData> {
    let version: i64 = tx
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(|e| read_error(&e))?;
    if version != expected {
        return Err(CacheError::UnsupportedVersion);
    }
    let metadata: Option<(i64, String, i64)> = tx
        .query_row(
            "SELECT schema_version,account_alias,active FROM agenda_meta WHERE id=1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()
        .map_err(|e| read_error(&e))?;
    let (schema, alias, active) = metadata.ok_or(CacheError::Corrupt)?;
    let count: i64 = tx
        .query_row("SELECT count(*) FROM agenda_meta", [], |r| r.get(0))
        .map_err(|e| read_error(&e))?;
    if schema != expected || alias != account || !matches!(active, 0 | 1) || count != 1 {
        return Err(CacheError::Corrupt);
    }
    let mut data = AgendaData {
        active: active == 1,
        ..AgendaData::default()
    };
    for (key, body) in rows(
        tx,
        "SELECT id,length(CAST(body AS BLOB)),body FROM agenda_items",
    )? {
        let item: AgendaItem = serde_json::from_str(&body).map_err(|_| CacheError::Corrupt)?;
        if item.id.to_string() != key {
            return Err(CacheError::Corrupt);
        }
        validate_item(&item).map_err(|_| CacheError::Corrupt)?;
        if data.items.insert(item.id, item).is_some() {
            return Err(CacheError::Corrupt);
        }
    }
    for (key, body) in rows(
        tx,
        "SELECT key,length(CAST(body AS BLOB)),body FROM agenda_overlays",
    )? {
        let overlay: SchoolAgendaOverlay =
            serde_json::from_str(&body).map_err(|_| CacheError::Corrupt)?;
        if overlay_key(&overlay.key).map_err(|_| CacheError::Corrupt)? != key
            || !valid_overlay(&overlay)
        {
            return Err(CacheError::Corrupt);
        }
        if data.overlays.insert(key, overlay).is_some() {
            return Err(CacheError::Corrupt);
        }
    }
    Ok(data)
}
fn rows(tx: &Transaction<'_>, sql: &str) -> CacheResult<Vec<(String, String)>> {
    let mut statement = tx.prepare(sql).map_err(|e| read_error(&e))?;
    let mut rows = statement.query([]).map_err(|e| read_error(&e))?;
    let mut result = Vec::new();
    while let Some(row) = rows.next().map_err(|e| read_error(&e))? {
        let size: i64 = row.get(1).map_err(|e| read_error(&e))?;
        if size < 0 || usize::try_from(size).map_or(true, |n| n > RECORD_LIMIT) {
            return Err(CacheError::Capacity);
        }
        result.push((
            row.get(0).map_err(|e| read_error(&e))?,
            row.get(2).map_err(|e| read_error(&e))?,
        ));
    }
    Ok(result)
}
pub(super) fn save(
    tx: &Transaction<'_>,
    before: &AgendaData,
    after: &AgendaData,
) -> CacheResult<()> {
    for (id, item) in &after.items {
        if before.items.get(id) != Some(item) {
            validate_item(item)?;
        }
    }
    for (key, overlay) in &after.overlays {
        if before.overlays.get(key) != Some(overlay)
            && (overlay_key(&overlay.key)? != *key || !valid_overlay(overlay))
        {
            return Err(CacheError::InvalidInput);
        }
    }
    save_rows(
        tx,
        &before.items,
        &after.items,
        "DELETE FROM agenda_items WHERE id=?1",
        "INSERT INTO agenda_items(id,body) VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET body=excluded.body",
        Uuid::to_string,
    )?;
    save_rows(
        tx,
        &before.overlays,
        &after.overlays,
        "DELETE FROM agenda_overlays WHERE key=?1",
        "INSERT INTO agenda_overlays(key,body) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET body=excluded.body",
        Clone::clone,
    )?;
    if before.active != after.active {
        tx.execute(
            "UPDATE agenda_meta SET active=?1 WHERE id=1",
            [i64::from(after.active)],
        )?;
    }
    super::sync::sqlite::save(tx, &before.sync, &after.sync)?;
    Ok(())
}
fn save_rows<K: Ord, V: Eq + serde::Serialize>(
    tx: &Transaction<'_>,
    before: &BTreeMap<K, V>,
    after: &BTreeMap<K, V>,
    delete_sql: &str,
    upsert_sql: &str,
    key: impl Fn(&K) -> String,
) -> CacheResult<()> {
    for id in before.keys().filter(|id| !after.contains_key(*id)) {
        tx.execute(delete_sql, [key(id)])?;
    }
    for (id, value) in after {
        if before.get(id) == Some(value) {
            continue;
        }
        let body = serde_json::to_string(value).map_err(|_| CacheError::InvalidInput)?;
        if body.len() > RECORD_LIMIT {
            return Err(CacheError::Capacity);
        }
        tx.execute(upsert_sql, params![key(id), body])?;
    }
    Ok(())
}
pub(super) fn valid_overlay(v: &SchoolAgendaOverlay) -> bool {
    v.updated_at.valid()
        && v.deleted_at.is_none_or(AgendaTime::valid)
        && v.completed_at.is_none_or(AgendaTime::valid)
        && v.note.as_ref().is_none_or(|s| s.len() <= 65_536)
}
fn read_error(error: &rusqlite::Error) -> CacheError {
    match error.sqlite_error_code() {
        Some(rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked) => {
            CacheError::Unavailable
        }
        _ => CacheError::Corrupt,
    }
}
// 日程独立管理首次创建标记，缓存路径工具会预建文件，无法区分已有空库。
fn database_path(root: &Path, account: &str) -> CacheResult<(PathBuf, bool)> {
    if !root.is_absolute() || account.len() != 32 || !account.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(CacheError::InvalidInput);
    }
    directory(root, false)?;
    let dir = root
        .canonicalize()
        .map_err(|_| CacheError::Unavailable)?
        .join("agenda");
    let builder = fs::DirBuilder::new();
    #[cfg(unix)]
    let mut builder = builder;
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(0o700);
    }
    match builder.create(&dir) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(_) => return Err(CacheError::Unavailable),
    }
    directory(&dir, true)?;
    let path = dir.join(format!("{account}.sqlite"));
    for suffix in ["", "-journal", "-wal", "-shm"] {
        match fs::symlink_metadata(dir.join(format!("{account}.sqlite{suffix}"))) {
            Ok(meta) if !meta.is_file() || meta.file_type().is_symlink() || !private(&meta) => {
                return Err(CacheError::Unavailable);
            }
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
                return Err(CacheError::Unavailable);
            }
            _ => {}
        }
    }
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let created = match options.open(&path) {
        Ok(file) => {
            file.sync_all().map_err(|_| CacheError::Unavailable)?;
            true
        }
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => false,
        Err(_) => return Err(CacheError::Unavailable),
    };
    Ok((path, created))
}
fn directory(path: &Path, require_private: bool) -> CacheResult<()> {
    let meta = fs::symlink_metadata(path).map_err(|_| CacheError::Unavailable)?;
    if !meta.is_dir() || meta.file_type().is_symlink() || (require_private && !private(&meta)) {
        return Err(CacheError::Unavailable);
    }
    Ok(())
}
fn private(meta: &fs::Metadata) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // 最低六位对应组和其他用户权限，必须全部为零。
        meta.permissions().mode().trailing_zeros() >= 6
    }
    #[cfg(not(unix))]
    {
        let _ = meta;
        true
    }
}
