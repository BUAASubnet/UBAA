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

#[test]
fn schema4_pending_rows_keep_receipts_and_identity_when_local_content_is_cleared() {
    // 固定旧列格式覆盖目录、未取得对象、已知对象及登记回执，包含清理后的无正文文件。
    for (step, body_retained, object, registered) in [
        (1, true, Some("合成目录"), false),
        (2, true, None, false),
        (2, true, Some("合成文件对象"), false),
        (2, true, Some("合成文件对象"), true),
        (2, false, None, false),
        (2, false, Some("合成文件对象"), false),
        (2, false, Some("合成文件对象"), true),
    ] {
        let root = root();
        let store = AgendaStore::open(&root, ACCOUNT).unwrap();
        store.create(event()).unwrap();
        let original = store.sync_snapshot().unwrap();
        let bytes = body_retained.then(|| original.document().encode().unwrap());
        let attempt = uuid::Uuid::new_v4();
        let publication = (step == 2).then_some(1_i64);
        drop(store);
        let db = Connection::open(root.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
        db.execute("UPDATE agenda_sync_meta SET next_publication=2", [])
            .unwrap();
        db.execute(
            "INSERT INTO agenda_sync_pending(id,attempt,step,document,object,publication,registered) VALUES(1,?1,?2,?3,?4,?5,?6)",
            params![attempt.to_string(), step, bytes, object, publication, registered],
        )
        .unwrap();

        let reopened = AgendaStore::open(&root, ACCOUNT).unwrap();
        let pending = reopened.restore_sync_attempt().unwrap().unwrap();
        assert_eq!(pending.snapshot.attempt, Some(attempt));
        assert_eq!(
            pending.snapshot.publication,
            publication.map(i64::cast_unsigned)
        );
        assert_eq!(pending.retains_body(), body_retained);
        assert_eq!(pending.operation.object(), object);
        assert_eq!(
            pending.confirmable_object(),
            if registered && body_retained {
                object
            } else {
                None
            }
        );
        if body_retained {
            assert_eq!(pending.snapshot.document(), original.document());
        }

        reopened.clear_local_data().unwrap();
        drop(reopened);
        let cleared = AgendaStore::open(&root, ACCOUNT).unwrap();
        let pending = cleared.restore_sync_attempt().unwrap();
        if step == 1 {
            assert!(pending.is_none());
        } else {
            let pending = pending.unwrap();
            assert_eq!(pending.snapshot.attempt, Some(attempt));
            assert_eq!(pending.snapshot.publication, Some(1));
            assert!(!pending.retains_body());
            assert_eq!(pending.operation.object(), object);
            assert_eq!(pending.confirmable_object(), None);
            let row: (String, Option<Vec<u8>>, Option<String>, i64, bool) = db
                .query_row(
                    "SELECT attempt,document,object,publication,registered FROM agenda_sync_pending WHERE id=1",
                    [],
                    |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
                )
                .unwrap();
            assert_eq!(
                row,
                (
                    attempt.to_string(),
                    None,
                    object.map(str::to_owned),
                    1,
                    registered
                )
            );
            let mut next = cleared.sync_snapshot().unwrap();
            assert!(matches!(
                cleared.begin_sync_attempt(&mut next, super::pending::SyncAttempt::Publication),
                Err(crate::cache::CacheError::Superseded)
            ));
        }
    }
}

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
    assert_eq!(version, 4);
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

fn schema3(root: &Path) -> (PathBuf, Connection, AgendaItem) {
    let (path, db, item, _) = legacy(root, true);
    db.execute_batch("CREATE TABLE agenda_sync_meta(id INTEGER PRIMARY KEY CHECK(id=1),device_id TEXT NOT NULL,next_sequence INTEGER NOT NULL CHECK(next_sequence>0),epoch INTEGER NOT NULL CHECK(epoch>=0)); CREATE TABLE agenda_sync_stamps(kind INTEGER NOT NULL CHECK(kind IN (1,2)),key TEXT NOT NULL,device_id TEXT NOT NULL,sequence INTEGER NOT NULL CHECK(sequence>0),PRIMARY KEY(kind,key)); CREATE TABLE agenda_sync_pending(id INTEGER PRIMARY KEY CHECK(id=1),attempt TEXT NOT NULL,step INTEGER NOT NULL CHECK(step IN (1,2)),document BLOB NOT NULL,object TEXT); INSERT INTO agenda_sync_meta VALUES(1,'11111111-1111-4111-8111-111111111111',3,7); INSERT INTO agenda_sync_stamps SELECT 1,id,'11111111-1111-4111-8111-111111111111',1 FROM agenda_items; INSERT INTO agenda_sync_stamps SELECT 2,key,'11111111-1111-4111-8111-111111111111',2 FROM agenda_overlays; UPDATE agenda_meta SET schema_version=3; PRAGMA user_version=3;").unwrap();
    (path, db, item)
}

#[test]
fn schema3_upgrade_keeps_identity_rows_and_defaults_sync_to_off() {
    let root = root();
    let (_, db, item) = schema3(&root);
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert_eq!(store.get(item.id).unwrap(), Some(item));
    let snapshot = store.sync_snapshot().unwrap();
    assert_eq!(
        snapshot.device_id.to_string(),
        "11111111-1111-4111-8111-111111111111"
    );
    assert_eq!(snapshot.epoch, 7);
    assert_eq!(snapshot.document.items[0].sequence, 1);
    assert!(!store.sync_enabled().unwrap());
    let counters: (i64, i64) = db
        .query_row(
            "SELECT next_sequence,next_publication FROM agenda_sync_meta",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(counters, (3, 1));
    store.enable_sync().unwrap();
    assert!(
        AgendaStore::open(&root, ACCOUNT)
            .unwrap()
            .sync_enabled()
            .unwrap()
    );
}

#[test]
fn schema3_unknown_attempt_or_failed_upgrade_preserves_the_original_database() {
    let root = root();
    let (path, db, _) = schema3(&root);
    db.execute_batch("INSERT INTO agenda_sync_pending VALUES(1,'22222222-2222-4222-8222-222222222222',2,X'7B7D',NULL);").unwrap();
    let before = std::fs::read(&path).unwrap();
    assert!(AgendaStore::open(&root, ACCOUNT).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), before);
    db.execute_batch("DELETE FROM agenda_sync_pending; CREATE TRIGGER fail_upgrade BEFORE UPDATE OF schema_version ON agenda_meta BEGIN SELECT RAISE(ABORT,'合成升级写入失败'); END;").unwrap();
    assert!(AgendaStore::open(&root, ACCOUNT).is_err());
    assert_eq!(
        db.pragma_query_value::<i64, _>(None, "user_version", |r| r.get(0))
            .unwrap(),
        3
    );
    assert!(
        db.prepare("SELECT next_publication FROM agenda_sync_meta")
            .is_err()
    );
    assert_eq!(
        db.query_row::<i64, _, _>(
            "SELECT COUNT(*) FROM sqlite_master WHERE name='agenda_sync_deletions'",
            [],
            |r| r.get(0)
        )
        .unwrap(),
        0
    );
}

#[test]
fn deletion_summary_survives_purge_and_reopen_without_retaining_personal_content() {
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    let stale = store.sync_snapshot().unwrap().document;
    store
        .delete(
            id,
            AgendaEditScope::All,
            None,
            t("2026-03-01T00:00:00+08:00"),
        )
        .unwrap();
    let sent = store.sync_snapshot().unwrap();
    store.confirm_sync(&sent, sent.document()).unwrap();
    assert_eq!(
        store
            .purge_tombstones(t("2026-09-02T00:00:00+08:00"))
            .unwrap(),
        1
    );
    drop(store);
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let scope = store.sync_snapshot().unwrap();
    store.merge_sync(&scope, &stale).unwrap();
    assert!(store.get(id).unwrap().is_none());
    let db = Connection::open(root.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
    let count: i64 = db
        .query_row("SELECT COUNT(*) FROM agenda_sync_deletions", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(count, 1);
    assert_eq!(
        db.query_row::<i64, _, _>("SELECT COUNT(*) FROM agenda_items", [], |r| r.get(0))
            .unwrap(),
        0
    );
    assert!(
        db.prepare("SELECT title,notes FROM agenda_sync_deletions")
            .is_err()
    );
}

#[test]
fn clear_local_keeps_device_publication_and_consent_but_scrubs_deletion_summary() {
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    store
        .delete(
            id,
            AgendaEditScope::All,
            None,
            t("2026-03-01T00:00:00+08:00"),
        )
        .unwrap();
    store.enable_sync().unwrap();
    let db = Connection::open(root.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
    db.execute("UPDATE agenda_sync_meta SET next_publication=8", [])
        .unwrap();
    let before = store.sync_snapshot().unwrap();
    assert_eq!(store.clear_local_data().unwrap(), 1);
    let after = store.sync_snapshot().unwrap();
    assert_eq!(after.device_id, before.device_id);
    assert!(store.sync_enabled().unwrap());
    assert_eq!(
        db.query_row::<i64, _, _>("SELECT next_publication FROM agenda_sync_meta", [], |r| r
            .get(0))
            .unwrap(),
        8
    );
    assert_eq!(
        db.query_row::<i64, _, _>("SELECT COUNT(*) FROM agenda_sync_deletions", [], |r| r
            .get(0))
            .unwrap(),
        0
    );
    assert!(store.confirm_sync(&before, before.document()).is_err());
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

#[test]
fn purged_item_uuid_cannot_be_recreated_while_its_deletion_summary_exists() {
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let item = event();
    let id = item.id;
    store.create(item.clone()).unwrap();
    store
        .delete(
            id,
            AgendaEditScope::All,
            None,
            t("2026-03-01T00:00:00+08:00"),
        )
        .unwrap();
    let snapshot = store.sync_snapshot().unwrap();
    store.confirm_sync(&snapshot, snapshot.document()).unwrap();
    store
        .purge_tombstones(t("2026-09-02T00:00:00+08:00"))
        .unwrap();
    assert!(store.get(id).unwrap().is_none());
    assert!(matches!(
        store.create(item),
        Err(crate::cache::CacheError::InvalidInput)
    ));
    assert!(store.get(id).unwrap().is_none());
}
