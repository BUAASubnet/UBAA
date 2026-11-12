use super::*;
use crate::{
    agenda::{
        AgendaStore,
        tests::{ACCOUNT, event, t},
    },
    cache::CacheError,
    domain::agenda::{AgendaEditScope, SchoolAgendaKey, SchoolAgendaOverlay},
};
use uuid::Uuid;
pub(super) fn root() -> std::path::PathBuf {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_sync/tests")
        .join(Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    root.canonicalize().unwrap()
}
fn open() -> AgendaStore {
    AgendaStore::open(&root(), ACCOUNT).unwrap()
}

#[test]
fn same_device_same_second_old_receipt_keeps_later_edit_pending() {
    let store = open();
    let first = event();
    let id = first.id;
    let now = first.updated_at;
    store.create(first.clone()).unwrap();
    let sent = store.sync_snapshot().unwrap();
    let mut next = first.content.clone();
    next.title = "同秒保存的新安排".into();
    store
        .edit(id, AgendaEditScope::All, None, next.clone(), None, now)
        .unwrap();
    let current = store.sync_snapshot().unwrap();
    assert_eq!(
        sent.document().items[0].device_id,
        current.document().items[0].device_id
    );
    assert_eq!(
        sent.document().items[0].item.updated_at,
        current.document().items[0].item.updated_at
    );
    assert!(current.document().items[0].sequence > sent.document().items[0].sequence);
    assert_eq!(store.confirm_sync(&sent, sent.document()).unwrap(), 0);
    assert_eq!(store.unsynced_count().unwrap(), 1);
    assert_eq!(store.get(id).unwrap().unwrap().content, next);
    store.merge_sync(&current, sent.document()).unwrap();
    assert_eq!(store.get(id).unwrap().unwrap().content, next);
    assert_eq!(store.unsynced_count().unwrap(), 1);
}
#[test]
fn complete_version_conflict_is_symmetric_and_preserves_local_record() {
    let store = open();
    let first = event();
    let id = first.id;
    store.create(first.clone()).unwrap();
    let snapshot = store.sync_snapshot().unwrap();
    let mut other = snapshot.document().clone();
    other.items[0].item.content.title = "同版本的矛盾正文".into();
    assert!(matches!(
        snapshot.document().merge(&other),
        Err(CacheError::Corrupt)
    ));
    assert!(matches!(
        other.merge(snapshot.document()),
        Err(CacheError::Corrupt)
    ));
    assert!(store.merge_sync(&snapshot, &other).is_err());
    assert_eq!(store.get(id).unwrap().unwrap(), first);
    assert_eq!(store.unsynced_count().unwrap(), 1);
}
#[test]
fn old_lifecycle_cannot_confirm_after_same_account_reactivation() {
    let store = open();
    store.create(event()).unwrap();
    let sent = store.sync_snapshot().unwrap();
    store.deactivate().unwrap();
    store.activate().unwrap();
    assert!(matches!(
        store.confirm_sync(&sent, sent.document()),
        Err(CacheError::Superseded)
    ));
    assert_eq!(store.unsynced_count().unwrap(), 1);
}
#[test]
fn snapshot_roundtrip_preserves_repeat_exceptions_overlay_and_deletion() {
    let store = open();
    let mut item = event();
    let id = item.id;
    item.rrule = Some("FREQ=DAILY;COUNT=5".into());
    item.exdates.insert(t("2026-02-01T09:00:00+08:00"));
    let at = t("2026-02-02T09:00:00+08:00");
    item.overrides
        .insert(at.recurrence_id(), item.content.clone());
    item.completions.insert(at.recurrence_id(), None);
    store.create(item).unwrap();
    let now = t("2026-03-01T00:00:00+08:00");
    store.delete(id, AgendaEditScope::All, None, now).unwrap();
    let overlay = SchoolAgendaOverlay {
        key: SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: "synthetic-task".into(),
        },
        completed_at: None,
        completion_override: true,
        hidden: true,
        note: Some("合成备注".into()),
        updated_at: now,
        deleted_at: None,
        locally_modified: true,
    };
    store.set_overlay(overlay, now).unwrap();
    let sent = store.sync_snapshot().unwrap();
    let received = AgendaSyncDocument::decode(&sent.document().encode().unwrap()).unwrap();
    assert_eq!(&received, sent.document());
    assert!(received.items.is_empty());
    assert_eq!(received.item_deletions[0].id, id);
    let local = store.get(id).unwrap().unwrap();
    assert_eq!(local.completions.get(&at.recurrence_id()), Some(&None));
    assert!(received.overlays[0].overlay.hidden);
}

#[test]
fn same_second_overlay_edit_and_item_aba_keep_new_versions_pending() {
    let store = open();
    let item = event();
    let id = item.id;
    let now = item.updated_at;
    store.create(item.clone()).unwrap();
    let mut value = SchoolAgendaOverlay {
        key: SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: "synthetic-overlay".into(),
        },
        completed_at: None,
        completion_override: true,
        hidden: false,
        note: Some("备注A".into()),
        updated_at: now,
        deleted_at: None,
        locally_modified: true,
    };
    store.set_overlay(value.clone(), now).unwrap();
    let sent = store.sync_snapshot().unwrap();
    value.note = Some("备注B".into());
    store.set_overlay(value.clone(), now).unwrap();
    let mut changed = item.content.clone();
    changed.title = "中间修改".into();
    store
        .edit(id, AgendaEditScope::All, None, changed, None, now)
        .unwrap();
    store
        .edit(
            id,
            AgendaEditScope::All,
            None,
            item.content.clone(),
            None,
            now,
        )
        .unwrap();
    assert_eq!(store.confirm_sync(&sent, sent.document()).unwrap(), 0);
    assert_eq!(store.unsynced_count().unwrap(), 2);
    assert_eq!(store.overlay(&value.key).unwrap().unwrap().note, value.note);
    assert_eq!(store.get(id).unwrap().unwrap().content, item.content);
    let current = store.sync_snapshot().unwrap();
    assert_eq!(
        sent.document().merge(current.document()).unwrap(),
        current.document().merge(sent.document()).unwrap()
    );
    assert_eq!(store.confirm_sync(&current, current.document()).unwrap(), 2);
    assert_eq!(store.unsynced_count().unwrap(), 0);
}
#[test]
fn two_devices_merge_by_time_then_device_and_keep_deletions() {
    let left = open();
    let right = open();
    let item = event();
    let id = item.id;
    left.create(item.clone()).unwrap();
    right.create(item.clone()).unwrap();
    let a = left.sync_snapshot().unwrap();
    let b = right.sync_snapshot().unwrap();
    let ab = a.document().merge(b.document()).unwrap();
    assert_eq!(ab, b.document().merge(a.document()).unwrap());
    let expected_device = a.document().items[0]
        .device_id
        .max(b.document().items[0].device_id);
    assert_eq!(ab.items[0].device_id, expected_device);
    left.merge_sync(&a, b.document()).unwrap();
    let now = t("2026-03-01T00:00:00+08:00");
    left.delete(id, AgendaEditScope::All, None, now).unwrap();
    let deleted = left.sync_snapshot().unwrap();
    right.merge_sync(&b, deleted.document()).unwrap();
    assert!(right.get(id).unwrap().unwrap().deleted_at.is_some());
    assert!(
        right
            .query(
                t("2026-01-01T00:00:00+08:00").datetime.date_naive(),
                t("2026-04-01T00:00:00+08:00").datetime.date_naive()
            )
            .unwrap()
            .is_empty()
    );
}
#[test]
fn unconfirmed_deletion_is_retained_and_confirmed_deletion_expires_strictly_after_180_days() {
    let store = open();
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    let deleted_at = t("2026-03-01T00:00:00+08:00");
    store
        .delete(id, AgendaEditScope::All, None, deleted_at)
        .unwrap();
    let later =
        crate::domain::agenda::AgendaTime::new(deleted_at.datetime + chrono::Duration::days(181));
    assert_eq!(store.purge_tombstones(later).unwrap(), 0);
    let sent = store.sync_snapshot().unwrap();
    store.confirm_sync(&sent, sent.document()).unwrap();
    let exact =
        crate::domain::agenda::AgendaTime::new(deleted_at.datetime + chrono::Duration::days(180));
    assert_eq!(store.purge_tombstones(exact).unwrap(), 0);
    assert_eq!(store.purge_tombstones(later).unwrap(), 1);
    assert!(store.sync_snapshot().unwrap().document().items.is_empty());
}
#[test]
fn mismatching_readback_or_schema_does_not_acknowledge_or_replace_local_records() {
    let store = open();
    let item = event();
    let id = item.id;
    store.create(item.clone()).unwrap();
    let sent = store.sync_snapshot().unwrap();
    let mut readback = sent.document().clone();
    readback.items[0].item.content.title = "读回的其他内容".into();
    assert!(store.confirm_sync(&sent, &readback).is_err());
    readback.schema = 99;
    assert!(matches!(
        store.merge_sync(&sent, &readback),
        Err(CacheError::UnsupportedVersion)
    ));
    assert_eq!(store.get(id).unwrap().unwrap(), item);
    assert_eq!(store.unsynced_count().unwrap(), 1);
}

#[test]
fn purged_synced_deletion_rejects_an_old_device_snapshot() {
    let store = open();
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    let old_device = store.sync_snapshot().unwrap().document().clone();
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
    assert!(store.get(id).unwrap().is_none());
    let current = store.sync_snapshot().unwrap();
    store.merge_sync(&current, &old_device).unwrap();
    assert!(
        store
            .get(id)
            .unwrap()
            .is_none_or(|item| item.deleted_at.is_some()),
        "清理完整删除记录后仍须保留版本摘要，不能复活旧设备记录"
    );
}

#[test]
fn clear_during_finalization_keeps_one_bodyless_attempt_and_rejects_late_confirmation() {
    use std::sync::{Arc, Barrier};
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let db =
        rusqlite::Connection::open(root.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
    db.execute("UPDATE agenda_sync_meta SET next_publication=6", [])
        .unwrap();
    let x = event();
    let id = x.id;
    store.create(x).unwrap();
    let mut p6 = store.sync_snapshot().unwrap();
    store
        .begin_sync_attempt(&mut p6, super::pending::SyncAttempt::Publication)
        .unwrap();
    assert_eq!(p6.publication, Some(6));
    store.confirm_sync(&p6, p6.document()).unwrap();
    store
        .delete(
            id,
            AgendaEditScope::All,
            None,
            t("2026-03-01T00:00:00+08:00"),
        )
        .unwrap();
    let mut p7 = store.sync_snapshot().unwrap();
    store
        .begin_sync_attempt(&mut p7, super::pending::SyncAttempt::Publication)
        .unwrap();
    store
        .record_sync_receipt(
            &p7,
            super::pending::PublicationReceipt::Unknown(Some("合成对象p7".into())),
        )
        .unwrap();
    assert_eq!(p7.publication, Some(7));
    let entered = Arc::new(Barrier::new(2));
    let released = Arc::new(Barrier::new(2));
    let late = {
        let root = root.clone();
        let entered = entered.clone();
        let released = released.clone();
        std::thread::spawn(move || {
            let peer = AgendaStore::open(&root, ACCOUNT).unwrap();
            peer.check_sync_attempt(&p7).unwrap();
            entered.wait();
            released.wait();
            assert!(matches!(
                peer.confirm_sync(&p7, p7.document()),
                Err(CacheError::Superseded)
            ));
        })
    };
    entered.wait();
    store.clear_local_data().unwrap();
    let mut y = event();
    y.id = Uuid::new_v4();
    y.content.title = "清除后新建Y".into();
    store.create(y.clone()).unwrap();
    let scope = store.sync_snapshot().unwrap();
    store.merge_sync(&scope, p6.document()).unwrap();
    let mut p8 = store.sync_snapshot().unwrap();
    let blocked = store.begin_sync_attempt(&mut p8, super::pending::SyncAttempt::Publication);
    released.wait();
    late.join().unwrap();
    assert!(
        matches!(blocked, Err(CacheError::Superseded)),
        "清除不能移除可能已发送的p7限制并允许更高发布"
    );
    let db =
        rusqlite::Connection::open(root.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
    let retained: (i64, Option<Vec<u8>>) = db
        .query_row(
            "SELECT COUNT(*),document FROM agenda_sync_pending",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(retained, (1, None));
    assert_eq!(store.get(y.id).unwrap().unwrap(), y);
}

#[test]
fn compact_deletion_document_excludes_full_content() {
    let store = open();
    let mut item = event();
    item.content.notes = Some("已经删除的完整备注".into());
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
    let document: serde_json::Value =
        serde_json::from_slice(&store.sync_snapshot().unwrap().document().encode().unwrap())
            .unwrap();
    assert!(
        document["items"].as_array().unwrap().is_empty(),
        "删除的事项只能发布紧凑摘要"
    );
    assert_eq!(document["item_deletions"][0]["id"], id.to_string());
    let fields = document["item_deletions"][0].as_object().unwrap();
    assert!(fields.keys().all(|key| {
        ["id", "deleted_at", "updated_at", "device_id", "sequence"].contains(&key.as_str())
    }));
}

#[test]
fn compact_deletion_propagates_after_purge_and_prevents_another_device_reviving_old_data() {
    let source = open();
    let item = event();
    let id = item.id;
    source.create(item).unwrap();
    let old = source.sync_snapshot().unwrap().document;
    source
        .delete(
            id,
            AgendaEditScope::All,
            None,
            t("2026-03-01T00:00:00+08:00"),
        )
        .unwrap();
    let sent = source.sync_snapshot().unwrap();
    source.confirm_sync(&sent, sent.document()).unwrap();
    source
        .purge_tombstones(t("2026-09-02T00:00:00+08:00"))
        .unwrap();
    let deletion = source.sync_snapshot().unwrap().document;
    let peer = open();
    let scope = peer.sync_snapshot().unwrap();
    peer.merge_sync(&scope, &deletion).unwrap();
    let scope = peer.sync_snapshot().unwrap();
    peer.merge_sync(&scope, &old).unwrap();
    assert!(
        peer.get(id)
            .unwrap()
            .is_none_or(|item| item.deleted_at.is_some()),
        "新设备必须从快照取得清理后的删除版本"
    );
}
