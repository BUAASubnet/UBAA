//! Core 持久库共用的 `SQLite` 打开参数。

use rusqlite::{Connection, OpenFlags};
use std::{path::Path, time::Duration};

pub(crate) fn open(path: &Path, mode: OpenFlags) -> rusqlite::Result<Connection> {
    let db = Connection::open_with_flags(
        path,
        mode | OpenFlags::SQLITE_OPEN_NO_MUTEX | OpenFlags::SQLITE_OPEN_NOFOLLOW,
    )?;
    db.busy_timeout(Duration::from_millis(250))?;
    Ok(db)
}

pub(crate) fn configure_private_store(db: &Connection) -> rusqlite::Result<()> {
    db.execute_batch("PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY; PRAGMA trusted_schema=OFF;")
}
