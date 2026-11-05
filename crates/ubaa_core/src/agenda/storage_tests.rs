use super::tests::{ACCOUNT, event, root, t};
use super::*;
use crate::domain::agenda::*;
use crate::facade::CacheError;
use rusqlite::Connection;
use std::path::Path;
fn open(root: &Path) -> AgendaStore {
    AgendaStore::open(root, ACCOUNT).unwrap()
}
fn path(root: &Path) -> std::path::PathBuf {
    root.join("agenda").join(format!("{ACCOUNT}.sqlite"))
}
fn overlay(now: AgendaTime) -> SchoolAgendaOverlay {
    SchoolAgendaOverlay {
        key: SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: "synthetic-assignment".into(),
        },
        completed_at: None,
        completion_override: false,
        hidden: false,
        note: Some("合成覆盖备注".into()),
        updated_at: now,
        deleted_at: None,
        locally_modified: true,
    }
}
#[test]
fn sqlite_stores_each_item_and_overlay_as_readable_plaintext_rows() {
    let root = root();
    let store = open(&root);
    let item = event();
    let id = item.id;
    store.create(item.clone()).unwrap();
    let now = t("2026-02-01T00:00:00+08:00");
    let value = overlay(now);
    store.set_overlay(value.clone(), now).unwrap();
    let db = Connection::open(path(&root)).unwrap();
    let raw: String = db
        .query_row(
            "SELECT body FROM agenda_items WHERE id=?1",
            [id.to_string()],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(serde_json::from_str::<AgendaItem>(&raw).unwrap(), item);
    let raw: String = db
        .query_row("SELECT body FROM agenda_overlays", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        serde_json::from_str::<SchoolAgendaOverlay>(&raw).unwrap(),
        value
    );
    let (schema, active): (i64, i64) = db
        .query_row(
            "SELECT schema_version,active FROM agenda_meta WHERE id=1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!((schema, active), (3, 1));
}
#[test]
fn existing_version_zero_database_is_rejected_without_initialization() {
    let root = root();
    let dir = root.join("agenda");
    std::fs::create_dir(&dir).unwrap();
    let db = Connection::open(path(&root)).unwrap();
    db.execute_batch(
        "CREATE TABLE foreign_data(body TEXT); INSERT INTO foreign_data VALUES('合成原文件');",
    )
    .unwrap();
    drop(db);
    private_file(&path(&root));
    let before = std::fs::read(path(&root)).unwrap();
    assert!(AgendaStore::open(&root, ACCOUNT).is_err());
    assert_eq!(std::fs::read(path(&root)).unwrap(), before);
}
fn private_file(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)).unwrap();
        std::fs::set_permissions(
            path.parent().unwrap(),
            std::fs::Permissions::from_mode(0o700),
        )
        .unwrap();
    }
}
#[test]
fn changing_one_record_does_not_rewrite_others_or_metadata() {
    let root = root();
    let store = open(&root);
    let item = event();
    let id = item.id;
    store.create(item.clone()).unwrap();
    store.create(event()).unwrap();
    let now = t("2026-02-01T00:00:00+08:00");
    let first = overlay(now);
    let mut second = first.clone();
    second.key.upstream_id = "other-assignment".into();
    store.set_overlay(first.clone(), now).unwrap();
    store.set_overlay(second, now).unwrap();
    let db = Connection::open(path(&root)).unwrap();
    db.execute_batch("CREATE TABLE audit(kind TEXT,identity TEXT);
        CREATE TRIGGER item_update AFTER UPDATE ON agenda_items BEGIN INSERT INTO audit VALUES('item',NEW.id); END;
        CREATE TRIGGER item_insert AFTER INSERT ON agenda_items BEGIN INSERT INTO audit VALUES('item',NEW.id); END;
        CREATE TRIGGER item_delete AFTER DELETE ON agenda_items BEGIN INSERT INTO audit VALUES('item',OLD.id); END;
        CREATE TRIGGER overlay_update AFTER UPDATE ON agenda_overlays BEGIN INSERT INTO audit VALUES('overlay',NEW.key); END;
        CREATE TRIGGER overlay_insert AFTER INSERT ON agenda_overlays BEGIN INSERT INTO audit VALUES('overlay',NEW.key); END;
        CREATE TRIGGER overlay_delete AFTER DELETE ON agenda_overlays BEGIN INSERT INTO audit VALUES('overlay',OLD.key); END;
        CREATE TRIGGER metadata_update AFTER UPDATE ON agenda_meta BEGIN INSERT INTO audit VALUES('meta','1'); END;").unwrap();
    store.complete(id, item.content.start, true, now).unwrap();
    assert!(
        store
            .get(id)
            .unwrap()
            .unwrap()
            .completions
            .values()
            .next()
            .unwrap()
            .is_some()
    );
    let entries = db
        .prepare("SELECT kind,identity FROM audit")
        .unwrap()
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(entries, vec![("item".into(), id.to_string())]);
    let mut changed = first;
    changed.note = Some("已更新备注".into());
    store.set_overlay(changed, now).unwrap();
    assert_eq!(
        db.query_row("SELECT count(*) FROM audit", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        2
    );
    let kind: String = db
        .query_row(
            "SELECT kind FROM audit ORDER BY rowid DESC LIMIT 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(kind, "overlay");
}
#[test]
fn failed_split_rolls_back_old_series_update_and_new_series_insert() {
    let root = root();
    let store = open(&root);
    let mut item = event();
    item.id = uuid::Uuid::from_u128(1);
    item.rrule = Some("FREQ=DAILY;COUNT=5".into());
    store.create(item.clone()).unwrap();
    let db = Connection::open(path(&root)).unwrap();
    db.execute_batch("CREATE TRIGGER reject_successor BEFORE INSERT ON agenda_items BEGIN SELECT RAISE(ABORT,'合成写入失败'); END;").unwrap();
    let mut next = item.content.clone();
    next.start = Some(t("2026-02-02T11:00:00+08:00"));
    next.end = Some(t("2026-02-02T12:00:00+08:00"));
    assert!(
        store
            .edit(
                item.id,
                AgendaEditScope::ThisAndFuture,
                Some(t("2026-02-02T09:00:00+08:00")),
                next,
                item.rrule.clone(),
                t("2026-02-03T00:00:00+08:00")
            )
            .is_err()
    );
    assert_eq!(store.get(item.id).unwrap(), Some(item));
    assert_eq!(
        db.query_row("SELECT count(*) FROM agenda_items", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        1
    );
}
#[test]
fn aggregate_over_sixteen_mib_remains_readable_and_record_limit_is_atomic() {
    let root = root();
    let store = open(&root);
    let mut item = event();
    item.rrule = Some("FREQ=DAILY;COUNT=400".into());
    let start = item.content.start.unwrap();
    for n in 0..150 {
        let at = AgendaTime::new(start.datetime + chrono::Duration::days(n));
        let mut content = item.content.clone();
        content.notes = Some("测".repeat(20_000));
        item.overrides.insert(at.recurrence_id(), content);
    }
    store.create(item.clone()).unwrap();
    let mut second = item.clone();
    second.id = uuid::Uuid::new_v4();
    store.create(second.clone()).unwrap();
    let db = Connection::open(path(&root)).unwrap();
    let size: i64 = db
        .query_row(
            "SELECT sum(length(CAST(body AS BLOB))) FROM agenda_items",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(size > 16 * 1024 * 1024);
    drop(store);
    let store = open(&root);
    assert_eq!(store.get(item.id).unwrap(), Some(item.clone()));
    assert_eq!(store.get(second.id).unwrap(), Some(second));
    let mut oversized = item.clone();
    oversized.id = uuid::Uuid::new_v4();
    for n in 150..300 {
        let at = AgendaTime::new(start.datetime + chrono::Duration::days(n));
        let content = oversized.overrides.values().next().unwrap().clone();
        oversized.overrides.insert(at.recurrence_id(), content);
    }
    assert_eq!(store.create(oversized), Err(CacheError::Capacity));
    assert_eq!(store.get(item.id).unwrap(), Some(item));
    assert_eq!(
        db.query_row("SELECT count(*) FROM agenda_items", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        2
    );
}
#[test]
fn old_unknown_empty_and_broken_files_are_preserved_without_changing_journal() {
    for version in [0, 1, 999, 2, -1] {
        let root = root();
        std::fs::create_dir(root.join("agenda")).unwrap();
        if version == -1 {
            std::fs::write(path(&root), b"synthetic broken database").unwrap();
        } else if version == 0 {
            std::fs::write(path(&root), []).unwrap();
        } else {
            let db = Connection::open(path(&root)).unwrap();
            db.execute_batch("CREATE TABLE agenda_state(id INTEGER PRIMARY KEY,body BLOB); INSERT INTO agenda_state VALUES(1,zeroblob(64));").unwrap();
            db.pragma_update(None, "user_version", version).unwrap();
            let _: String = db
                .pragma_query_value(None, "journal_mode", |r| r.get(0))
                .unwrap();
            db.pragma_update(None, "journal_mode", "WAL").unwrap();
        }
        private_file(&path(&root));
        let before = std::fs::read(path(&root)).unwrap();
        let error = AgendaStore::open(&root, ACCOUNT)
            .err()
            .expect("拒绝旧或未知格式");
        assert_eq!(
            error,
            if version == 2 || version == -1 {
                CacheError::Corrupt
            } else {
                CacheError::UnsupportedVersion
            }
        );
        assert_eq!(std::fs::read(path(&root)).unwrap(), before);
        if version > 0 {
            let db = Connection::open_with_flags(
                path(&root),
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )
            .unwrap();
            let mode: String = db
                .pragma_query_value(None, "journal_mode", |r| r.get(0))
                .unwrap();
            assert_eq!(mode, "wal");
        }
    }
}
#[test]
fn damaged_record_and_wrong_account_metadata_are_rejected_without_repair() {
    let root = root();
    let store = open(&root);
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    let other = "00000000000000000000000000000002";
    let other_path = root.join("agenda").join(format!("{other}.sqlite"));
    std::fs::copy(path(&root), &other_path).unwrap();
    private_file(&other_path);
    let before = std::fs::read(&other_path).unwrap();
    assert_eq!(
        AgendaStore::open(&root, other).err(),
        Some(CacheError::Corrupt)
    );
    assert_eq!(std::fs::read(other_path).unwrap(), before);
    let db = Connection::open(path(&root)).unwrap();
    db.execute(
        "UPDATE agenda_items SET body='broken json' WHERE id=?1",
        [id.to_string()],
    )
    .unwrap();
    drop(db);
    let before = std::fs::read(path(&root)).unwrap();
    assert_eq!(store.get(id), Err(CacheError::Corrupt));
    assert_eq!(
        AgendaStore::open(&root, ACCOUNT).err(),
        Some(CacheError::Corrupt)
    );
    assert_eq!(std::fs::read(path(&root)).unwrap(), before);
}
#[cfg(unix)]
#[test]
fn private_permissions_and_symlink_rejection_protect_plaintext_files() {
    use std::os::unix::fs::{PermissionsExt, symlink};
    let root = root();
    let store = open(&root);
    store.create(event()).unwrap();
    assert_eq!(
        std::fs::metadata(root.join("agenda"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o700
    );
    assert_eq!(
        std::fs::metadata(path(&root)).unwrap().permissions().mode() & 0o777,
        0o600
    );
    let target = root.join("protected-target");
    std::fs::write(&target, b"unchanged synthetic target").unwrap();
    for suffix in ["-journal", "-wal", "-shm"] {
        let link = std::path::PathBuf::from(format!("{}{suffix}", path(&root).display()));
        symlink(&target, &link).unwrap();
        assert_eq!(
            AgendaStore::open(&root, ACCOUNT).err(),
            Some(CacheError::Unavailable)
        );
        std::fs::remove_file(link).unwrap();
    }
    std::fs::set_permissions(path(&root), std::fs::Permissions::from_mode(0o644)).unwrap();
    assert_eq!(
        AgendaStore::open(&root, ACCOUNT).err(),
        Some(CacheError::Unavailable)
    );
    private_file(&path(&root));
    drop(store);
    std::fs::remove_file(path(&root)).unwrap();
    symlink(&target, path(&root)).unwrap();
    assert_eq!(
        AgendaStore::open(&root, ACCOUNT).err(),
        Some(CacheError::Unavailable)
    );
    assert_eq!(
        std::fs::read(target).unwrap(),
        b"unchanged synthetic target"
    );
    let linked = root.join("linked-root");
    symlink(&root, &linked).unwrap();
    assert_eq!(
        AgendaStore::open(&linked, ACCOUNT).err(),
        Some(CacheError::Unavailable)
    );
    let parent = root.join("other-root");
    std::fs::create_dir(&parent).unwrap();
    symlink(root.join("agenda"), parent.join("agenda")).unwrap();
    assert_eq!(
        AgendaStore::open(&parent, ACCOUNT).err(),
        Some(CacheError::Unavailable)
    );
}

#[test]
fn entered_transaction_commits_or_rolls_back_before_deactivation() {
    use std::sync::mpsc;
    use std::time::Duration;
    for fail in [false, true] {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/agenda_1c_a_write_fence/core_tests")
            .join(uuid::Uuid::new_v4().to_string());
        std::fs::create_dir_all(&root).unwrap();
        let root = root.canonicalize().unwrap();
        let store = open(&root);
        let item = event();
        let id = item.id;
        let writer = store.clone();
        let (entered_tx, entered_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let writing = std::thread::spawn(move || {
            // access 的闭包只在 IMMEDIATE 事务取得锁并校验 active 后调用。
            writer.access(true, true, |data| {
                entered_tx.send(()).unwrap();
                release_rx.recv_timeout(Duration::from_secs(10)).unwrap();
                data.items.insert(id, item);
                if fail {
                    Err(CacheError::Unavailable)
                } else {
                    Ok(())
                }
            })
        });
        entered_rx.recv_timeout(Duration::from_secs(10)).unwrap();
        let closer = store.clone();
        let (started_tx, started_rx) = mpsc::channel();
        let (closed_tx, closed_rx) = mpsc::channel();
        let closing = std::thread::spawn(move || {
            started_tx.send(()).unwrap();
            let result = closer.deactivate();
            closed_tx.send(()).unwrap();
            result
        });
        started_rx.recv_timeout(Duration::from_secs(10)).unwrap();
        assert!(matches!(
            closed_rx.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        release_tx.send(()).unwrap();
        assert_eq!(writing.join().unwrap().is_err(), fail);
        closing.join().unwrap().unwrap();
        assert!(matches!(store.get(id), Err(CacheError::Inactive)));
        drop(store);
        // 独立连接检查实际事务提交或回滚，以及持久退出标记。
        let db = Connection::open(path(&root)).unwrap();
        let rows: i64 = db
            .query_row("SELECT count(*) FROM agenda_items", [], |r| r.get(0))
            .unwrap();
        let active: i64 = db
            .query_row("SELECT active FROM agenda_meta", [], |r| r.get(0))
            .unwrap();
        assert_eq!(rows, i64::from(!fail));
        assert_eq!(active, 0);
        drop(db);
        let reopened = open(&root);
        reopened.activate().unwrap();
        assert_eq!(reopened.get(id).unwrap().is_some(), !fail);
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }
}
