use super::tests::root;
use crate::{
    agenda::{
        AgendaStore,
        tests::{ACCOUNT, event, t},
    },
    domain::agenda::{AgendaEditScope, AgendaItem, SchoolAgendaKey, SchoolAgendaOverlay},
};
use rusqlite::{Connection, params};
use std::path::{Path, PathBuf};
fn legacy(root: &Path, active: bool) -> (PathBuf, Connection, AgendaItem, SchoolAgendaOverlay) {
    let dir = root.join("agenda");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(format!("{ACCOUNT}.sqlite"));
    let db = Connection::open(&path).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
    }
    db.execute_batch("CREATE TABLE agenda_meta(id INTEGER PRIMARY KEY CHECK(id=1),schema_version INTEGER NOT NULL,account_alias TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN (0,1))); CREATE TABLE agenda_items(id TEXT PRIMARY KEY NOT NULL,body TEXT NOT NULL); CREATE TABLE agenda_overlays(key TEXT PRIMARY KEY NOT NULL,body TEXT NOT NULL); PRAGMA user_version=2;").unwrap();
    db.execute(
        "INSERT INTO agenda_meta VALUES(1,2,?1,?2)",
        params![ACCOUNT, i64::from(active)],
    )
    .unwrap();
    let mut item = event();
    item.rrule = Some("FREQ=DAILY;COUNT=3".into());
    item.exdates.insert(t("2026-02-01T09:00:00+08:00"));
    let overlay = SchoolAgendaOverlay {
        key: SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: "legacy-task".into(),
        },
        completed_at: None,
        completion_override: true,
        hidden: true,
        note: Some("已有schema2备注".into()),
        updated_at: item.updated_at,
        deleted_at: None,
        locally_modified: true,
    };
    db.execute(
        "INSERT INTO agenda_items VALUES(?1,?2)",
        params![item.id.to_string(), serde_json::to_string(&item).unwrap()],
    )
    .unwrap();
    db.execute(
        "INSERT INTO agenda_overlays VALUES(?1,?2)",
        params![
            serde_json::to_string(&(
                overlay.key.source.as_str(),
                overlay.key.upstream_id.as_str()
            ))
            .unwrap(),
            serde_json::to_string(&overlay).unwrap()
        ],
    )
    .unwrap();
    (path, db, item, overlay)
}
#[test]
fn valid_schema2_upgrade_preserves_actual_rows_and_shared_same_second_sequence() {
    let root = root();
    let (_, db, item, overlay) = legacy(&root, true);
    let before: String = db
        .query_row("SELECT body FROM agenda_items", [], |r| r.get(0))
        .unwrap();
    let first = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert_eq!(first.get(item.id).unwrap().unwrap(), item);
    assert_eq!(first.overlay(&overlay.key).unwrap().unwrap(), overlay);
    let after: String = db
        .query_row("SELECT body FROM agenda_items", [], |r| r.get(0))
        .unwrap();
    assert_eq!(after, before);
    let version: i64 = db
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .unwrap();
    assert_eq!(version, 3);
    let sent = first.sync_snapshot().unwrap();
    let second = AgendaStore::open(&root, ACCOUNT).unwrap();
    let mut value = item.content.clone();
    value.title = "另一个消费者的同秒修改".into();
    second
        .edit(
            item.id,
            AgendaEditScope::All,
            None,
            value.clone(),
            item.rrule.clone(),
            item.updated_at,
        )
        .unwrap();
    let current = second.sync_snapshot().unwrap();
    assert_eq!(
        sent.document().items[0].device_id,
        current.document().items[0].device_id
    );
    assert!(current.document().items[0].sequence > sent.document().items[0].sequence);
    first.confirm_sync(&sent, sent.document()).unwrap();
    assert_eq!(second.get(item.id).unwrap().unwrap().content, value);
    assert_eq!(second.unsynced_count().unwrap(), 1);
}
#[test]
fn upgrade_write_failure_rolls_back_new_tables_metadata_and_existing_records() {
    let root = root();
    let (_, db, item, _) = legacy(&root, true);
    let before: String = db
        .query_row("SELECT body FROM agenda_items", [], |r| r.get(0))
        .unwrap();
    db.execute_batch("CREATE TRIGGER fail_upgrade BEFORE UPDATE OF schema_version ON agenda_meta BEGIN SELECT RAISE(ABORT,'合成升级写入失败'); END;").unwrap();
    assert!(AgendaStore::open(&root, ACCOUNT).is_err());
    let version: i64 = db
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .unwrap();
    assert_eq!(version, 2);
    let schema: i64 = db
        .query_row("SELECT schema_version FROM agenda_meta", [], |r| r.get(0))
        .unwrap();
    assert_eq!(schema, 2);
    let count: i64 = db.query_row("SELECT COUNT(*) FROM sqlite_master WHERE name IN ('agenda_sync_meta','agenda_sync_stamps','agenda_sync_pending')",[],|r|r.get(0)).unwrap();
    assert_eq!(count, 0);
    let after: String = db
        .query_row("SELECT body FROM agenda_items", [], |r| r.get(0))
        .unwrap();
    assert_eq!(after, before);
    db.execute_batch("DROP TRIGGER fail_upgrade").unwrap();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert_eq!(store.get(item.id).unwrap().unwrap(), item);
}
#[test]
fn inactive_schema2_upgrade_retains_logout_and_corrupt_schema2_is_untouched() {
    let root = root();
    let (_, db, item, _) = legacy(&root, false);
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert!(store.sync_snapshot().is_err());
    let active: i64 = db
        .query_row("SELECT active FROM agenda_meta", [], |r| r.get(0))
        .unwrap();
    assert_eq!(active, 0);
    store.activate().unwrap();
    assert_eq!(store.get(item.id).unwrap().unwrap(), item);
    let other = super::tests::root();
    let (path, db, _, _) = legacy(&other, true);
    db.execute("UPDATE agenda_items SET body='无效JSON'", [])
        .unwrap();
    let before = std::fs::read(&path).unwrap();
    assert!(AgendaStore::open(&other, ACCOUNT).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), before);
    let version: i64 = db
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .unwrap();
    assert_eq!(version, 2);
}
