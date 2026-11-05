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
    assert!(received.items[0].item.deleted_at.is_some());
    assert_eq!(
        received.items[0].item.completions.get(&at.recurrence_id()),
        Some(&None)
    );
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
