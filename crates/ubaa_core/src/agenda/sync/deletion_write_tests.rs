use super::{AgendaSyncDocument, AgendaSyncOverlayDeletion};
use crate::{
    agenda::{
        AgendaStore,
        sync::tests::root,
        tests::{ACCOUNT, t},
    },
    cache::CacheError,
    domain::agenda::{AgendaTime, SchoolAgendaKey, SchoolAgendaOverlay},
};
use uuid::Uuid;

fn key() -> SchoolAgendaKey {
    SchoolAgendaKey {
        source: "spoc".into(),
        upstream_id: "synthetic-deleted-overlay".into(),
    }
}

fn import_deletion(store: &AgendaStore, device_id: Uuid) -> AgendaSyncDocument {
    let deleted_at = t("2026-03-01T10:00:00+08:00");
    let document = AgendaSyncDocument {
        overlay_deletions: vec![AgendaSyncOverlayDeletion {
            key: key(),
            deleted_at,
            updated_at: deleted_at,
            device_id,
            sequence: 9,
        }],
        ..AgendaSyncDocument::default()
    };
    store
        .merge_sync(&store.sync_snapshot().unwrap(), &document)
        .unwrap();
    assert!(store.overlay(&key()).unwrap().is_none());
    document
}

fn overlay(now: AgendaTime, note: &str) -> SchoolAgendaOverlay {
    SchoolAgendaOverlay {
        key: key(),
        completed_at: None,
        completion_override: false,
        hidden: true,
        note: Some(note.into()),
        updated_at: now,
        deleted_at: None,
        locally_modified: true,
    }
}

#[test]
fn imported_deletion_rejects_backward_clock_without_saving_or_advancing_sequence() {
    let store = AgendaStore::open(&root(), ACCOUNT).unwrap();
    import_deletion(&store, Uuid::from_u128(1));
    let before = store.sync_snapshot().unwrap();
    let sequence = store
        .access(true, false, |data| Ok(data.sync.next_sequence))
        .unwrap();
    let now = t("2026-03-01T09:59:59+08:00");
    assert!(matches!(
        store.set_overlay(overlay(now, "倒退时钟的备注"), now),
        Err(CacheError::InvalidInput)
    ));
    assert!(store.overlay(&key()).unwrap().is_none());
    assert_eq!(store.unsynced_count().unwrap(), 0);
    assert_eq!(store.sync_snapshot().unwrap().document(), before.document());
    assert_eq!(
        store
            .access(true, false, |data| Ok(data.sync.next_sequence))
            .unwrap(),
        sequence
    );
}

#[test]
fn imported_deletion_rejects_same_second_when_remote_device_sorts_later() {
    let store = AgendaStore::open(&root(), ACCOUNT).unwrap();
    import_deletion(&store, Uuid::from_u128(u128::MAX));
    let before = store.sync_snapshot().unwrap();
    let now = t("2026-03-01T10:00:00+08:00");
    assert!(matches!(
        store.set_overlay(overlay(now, "同秒但版本较低的备注"), now),
        Err(CacheError::InvalidInput)
    ));
    assert!(store.overlay(&key()).unwrap().is_none());
    assert_eq!(store.sync_snapshot().unwrap().document(), before.document());
}

fn assert_saved_survives_merge(
    store: &AgendaStore,
    deletion: &AgendaSyncDocument,
    now: AgendaTime,
) -> u64 {
    let saved = overlay(now, "确认保存的备注");
    store.set_overlay(saved.clone(), now).unwrap();
    let snapshot = store.sync_snapshot().unwrap();
    assert_eq!(snapshot.document().overlays.len(), 1);
    assert_eq!(snapshot.document().overlays[0].overlay.note, saved.note);
    let sequence = snapshot.document().overlays[0].sequence;
    store.merge_sync(&snapshot, deletion).unwrap();
    assert_eq!(store.overlay(&key()).unwrap().unwrap(), saved);
    assert_eq!(store.unsynced_count().unwrap(), 1);
    sequence
}

#[test]
fn imported_deletion_allows_later_time_and_preserves_overlay_on_merge() {
    let store = AgendaStore::open(&root(), ACCOUNT).unwrap();
    let deletion = import_deletion(&store, Uuid::from_u128(u128::MAX));
    assert_saved_survives_merge(&store, &deletion, t("2026-03-01T10:00:01+08:00"));
}

#[test]
fn imported_deletion_allows_same_second_when_local_device_sorts_later() {
    let store = AgendaStore::open(&root(), ACCOUNT).unwrap();
    let deletion = import_deletion(&store, Uuid::from_u128(1));
    assert_saved_survives_merge(&store, &deletion, t("2026-03-01T10:00:00+08:00"));
}

#[test]
fn imported_own_deletion_allows_same_second_using_persisted_later_sequence() {
    let path = root();
    let store = AgendaStore::open(&path, ACCOUNT).unwrap();
    let device_id = store
        .access(true, false, |data| Ok(data.sync.device_id))
        .unwrap();
    let deletion = import_deletion(&store, device_id);
    drop(store);
    let store = AgendaStore::open(&path, ACCOUNT).unwrap();
    let now = t("2026-03-01T10:00:00+08:00");
    let sequence = assert_saved_survives_merge(&store, &deletion, now);
    assert!(sequence > deletion.overlay_deletions[0].sequence);
    store
        .set_overlay(overlay(now, "同秒再次编辑的备注"), now)
        .unwrap();
    assert!(store.sync_snapshot().unwrap().document().overlays[0].sequence > sequence);
}
