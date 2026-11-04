use super::*;
use crate::domain::agenda::*;
use chrono::{NaiveDate, NaiveTime, Weekday};
pub(super) fn t(raw: &str) -> AgendaTime {
    AgendaTime::new(raw.parse().unwrap())
}
fn d(raw: &str) -> NaiveDate {
    raw.parse().unwrap()
}
#[test]
fn 清除在同一事务核对另一句柄新增的未同步数量() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let alias = "0123456789abcdef0123456789abcdef";
    let one = AgendaStore::open(&root, alias).unwrap();
    let two = AgendaStore::open(&root, alias).unwrap();
    let first = event();
    let second = event();
    one.create(first.clone()).unwrap();
    let observed = one.unsynced_count().unwrap();
    two.create(second.clone()).unwrap();
    assert_eq!(
        one.clear_local_data_if_unsynced(observed),
        Err(crate::cache::CacheError::InvalidInput)
    );
    assert!(one.get(first.id).unwrap().is_some());
    assert!(two.get(second.id).unwrap().is_some());
    assert_eq!(one.clear_local_data_if_unsynced(2).unwrap(), 2);
    assert_eq!(two.unsynced_count().unwrap(), 0);
    drop((one, two));
    std::fs::remove_dir_all(root).unwrap();
}
pub(super) fn event() -> AgendaItem {
    AgendaItem::new(
        AgendaContent {
            kind: AgendaKind::Event,
            title: "合成日程".into(),
            location: None,
            notes: None,
            color: None,
            start: Some(t("2026-01-31T09:00:00+08:00")),
            end: Some(t("2026-01-31T10:00:00+08:00")),
            all_day: false,
            due: None,
        },
        t("2026-01-01T00:00:00+08:00"),
    )
}
#[test]
fn monthly_skips_nonexistent_dates_and_keeps_shanghai() {
    let mut item = event();
    item.rrule = Some("FREQ=MONTHLY;COUNT=3".into());
    let rows = expand_agenda(&item, d("2026-01-01"), d("2026-06-01")).unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| r.content.start.unwrap().datetime.date_naive())
            .collect::<Vec<_>>(),
        vec![d("2026-01-31"), d("2026-03-31"), d("2026-05-31")]
    );
    assert!(
        rows.iter()
            .all(|r| r.content.start.unwrap().timezone == chrono_tz::Asia::Shanghai)
    );
}
#[test]
fn teaching_even_weeks_and_holiday() {
    let rule = teaching_week_rule(
        d("2026-02-23"),
        1,
        8,
        TeachingWeekPattern::Even,
        Weekday::Wed,
        NaiveTime::from_hms_opt(9, 0, 0).unwrap(),
        &[d("2026-03-18")],
    )
    .unwrap();
    let mut item = event();
    let duration = item.content.end.unwrap().datetime - item.content.start.unwrap().datetime;
    item.content.start = Some(rule.start);
    item.content.end = Some(AgendaTime::new(rule.start.datetime + duration));
    item.rrule = Some(rule.rrule);
    item.exdates = rule.exdates;
    let rows = expand_agenda(&item, d("2026-02-01"), d("2026-05-01")).unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| r.content.start.unwrap().datetime.date_naive())
            .collect::<Vec<_>>(),
        vec![d("2026-03-04"), d("2026-04-01"), d("2026-04-15")]
    );
}
pub(super) fn root() -> std::path::PathBuf {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_plaintext/tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    root.canonicalize().unwrap()
}
pub(super) const ACCOUNT: &str = "00000000000000000000000000000001";
#[test]
fn persistent_account_data_survives_reopen() {
    let root = root();
    let item = event();
    let id = item.id;
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    store.create(item.clone()).unwrap();
    drop(store);
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert_eq!(store.get(id).unwrap(), Some(item));
}
fn opened() -> AgendaStore {
    AgendaStore::open(&root(), ACCOUNT).unwrap()
}
fn repeated() -> AgendaItem {
    let mut i = event();
    i.rrule = Some("FREQ=DAILY;COUNT=5".into());
    i
}
#[test]
fn future_split_preserves_count_and_completion() {
    let store = opened();
    let item = repeated();
    let id = item.id;
    store.create(item.clone()).unwrap();
    store
        .complete(
            id,
            Some(t("2026-02-03T09:00:00+08:00")),
            true,
            t("2026-02-03T10:00:00+08:00"),
        )
        .unwrap();
    let mut content = item.content.clone();
    content.start = Some(t("2026-02-02T11:00:00+08:00"));
    content.end = Some(t("2026-02-02T12:00:00+08:00"));
    content.title = "后半段".into();
    let new = store
        .edit(
            id,
            AgendaEditScope::ThisAndFuture,
            Some(t("2026-02-02T09:00:00+08:00")),
            content,
            item.rrule,
            t("2026-02-04T00:00:00+08:00"),
        )
        .unwrap()
        .unwrap();
    let rows = store.query(d("2026-01-01"), d("2026-03-01")).unwrap();
    assert_eq!(rows.len(), 5);
    assert!(
        store
            .get(id)
            .unwrap()
            .unwrap()
            .rrule
            .unwrap()
            .contains("UNTIL=20260202T005959Z")
    );
    assert_eq!(rows.iter().filter(|r| r.item_id == new).count(), 3);
    assert!(
        rows.iter()
            .find(|r| r.recurrence_id == "2026-02-03T11:00:00+08:00")
            .unwrap()
            .completed_at
            .is_some()
    );
}
#[test]
fn single_edit_moves_into_query_single_delete_excludes_and_all_delete_tombstones() {
    let store = opened();
    let item = repeated();
    let id = item.id;
    store.create(item.clone()).unwrap();
    let mut content = item.content.clone();
    content.start = Some(t("2026-01-15T09:00:00+08:00"));
    content.end = Some(t("2026-01-15T11:00:00+08:00"));
    store
        .edit(
            id,
            AgendaEditScope::This,
            Some(t("2026-02-01T09:00:00+08:00")),
            content,
            item.rrule,
            t("2026-02-05T00:00:00+08:00"),
        )
        .unwrap();
    let rows = store.query(d("2026-01-15"), d("2026-01-16")).unwrap();
    assert_eq!(rows.len(), 1);
    assert!(rows[0].overridden);
    store
        .delete(
            id,
            AgendaEditScope::This,
            Some(t("2026-02-01T09:00:00+08:00")),
            t("2026-02-06T00:00:00+08:00"),
        )
        .unwrap();
    assert!(
        store
            .query(d("2026-01-15"), d("2026-01-16"))
            .unwrap()
            .is_empty()
    );
    store
        .delete(
            id,
            AgendaEditScope::All,
            None,
            t("2026-02-07T00:00:00+08:00"),
        )
        .unwrap();
    assert!(store.get(id).unwrap().unwrap().deleted_at.is_some());
    assert!(
        store
            .query(d("2026-01-01"), d("2026-03-01"))
            .unwrap()
            .is_empty()
    );
}
#[test]
fn overlay_reopen_uses_local_incomplete_and_clear_is_tombstone() {
    let store = opened();
    let now = t("2026-02-01T00:00:00+08:00");
    let key = SchoolAgendaKey {
        source: "spoc".into(),
        upstream_id: "synthetic-1".into(),
    };
    let overlay = SchoolAgendaOverlay {
        key: key.clone(),
        completed_at: None,
        completion_override: true,
        hidden: false,
        note: Some("本地重新挂起".into()),
        updated_at: now,
        deleted_at: None,
        locally_modified: false,
    };
    store.set_overlay(overlay, now).unwrap();
    let value = store.overlay(&key).unwrap().unwrap();
    assert!(!value.effective_completed(true));
    assert!(value.locally_modified);
    store
        .clear_overlay(&key, t("2026-02-02T00:00:00+08:00"))
        .unwrap();
    let value = store.overlay(&key).unwrap().unwrap();
    assert!(value.deleted_at.is_some());
    assert!(value.effective_completed(true));
}
#[test]
fn tombstones_keep_unsynced_and_purge_only_synced_after_180_days() {
    let store = opened();
    let deleted = t("2026-02-01T00:00:00+08:00");
    for synced in [false, true] {
        let item = event();
        let id = item.id;
        store.create(item).unwrap();
        store
            .delete(id, AgendaEditScope::All, None, deleted)
            .unwrap();
        let key = SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: format!("synthetic-{synced}"),
        };
        store.clear_overlay(&key, deleted).unwrap();
        if synced {
            // 同步确认尚无生产入口，仅在合成存储中准备已确认状态。
            store
                .access(true, true, |data| {
                    data.items.get_mut(&id).unwrap().locally_modified = false;
                    for overlay in data.overlays.values_mut() {
                        if overlay.key == key {
                            overlay.locally_modified = false;
                        }
                    }
                    Ok(())
                })
                .unwrap();
        }
    }
    let cutoff = AgendaTime::new(deleted.datetime + chrono::Duration::days(180));
    assert_eq!(store.purge_tombstones(cutoff).unwrap(), 0);
    assert_eq!(
        store
            .purge_tombstones(AgendaTime::new(
                cutoff.datetime + chrono::Duration::seconds(1)
            ))
            .unwrap(),
        2
    );
    assert_eq!(store.unsynced_count().unwrap(), 2);
    assert_eq!(
        store
            .purge_tombstones(t("2030-01-01T00:00:00+08:00"))
            .unwrap(),
        0
    );
    store
        .access(true, false, |data| {
            assert_eq!(data.items.len(), 1);
            assert_eq!(data.overlays.len(), 1);
            assert!(
                data.items
                    .values()
                    .all(|v| v.locally_modified && v.deleted_at.is_some())
            );
            assert!(
                data.overlays
                    .values()
                    .all(|v| v.locally_modified && v.deleted_at.is_some())
            );
            Ok(())
        })
        .unwrap();
}
#[test]
fn accounts_routes_logout_and_cache_rebuild_are_independent() {
    use crate::facade::{
        CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
        ConnectionMode, OfflineRepository,
    };
    let root = root();
    let item = event();
    let id = item.id;
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    store.create(item.clone()).unwrap();
    let second = AgendaStore::open(&root, "00000000000000000000000000000002").unwrap();
    assert!(second.get(id).unwrap().is_none());
    let mut cache = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([1; 32]),
        CacheLimits {
            soft_bytes: 1024,
            hard_bytes: 4096 * 8,
        },
    )
    .unwrap();
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let ticket = cache
            .begin_read(CacheScope {
                route,
                query: CacheQuery::ScheduleToday {
                    date: "2026-01-31".into(),
                },
            })
            .unwrap();
        cache
            .publish(
                &ticket,
                CachePayload::Today(Vec::new()),
                1,
                CacheCompleteness::Complete,
            )
            .unwrap();
        assert!(store.get(id).unwrap().is_some());
    }
    cache.deactivate().unwrap();
    store.deactivate().unwrap();
    let reopened = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert_eq!(reopened.get(id), Err(CacheError::Inactive));
    store.activate().unwrap();
    assert_eq!(reopened.get(id).unwrap(), Some(item));
    cache.activate().unwrap();
    cache.clear_for_reopen().unwrap();
    OfflineRepository::clear_or_rebuild(
        &root,
        ACCOUNT,
        CacheKey::new([1; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    assert!(reopened.get(id).unwrap().is_some());
    assert_eq!(store.unsynced_count().unwrap(), 1);
    assert_eq!(store.clear_local_data().unwrap(), 1);
    assert!(reopened.get(id).unwrap().is_none());
}
#[test]
fn failed_update_is_atomic_and_independent_connections_do_not_lose_updates() {
    let root = root();
    let item = repeated();
    let id = item.id;
    let first = AgendaStore::open(&root, ACCOUNT).unwrap();
    let second = AgendaStore::open(&root, ACCOUNT).unwrap();
    first.create(item.clone()).unwrap();
    let mut bad = item.content.clone();
    bad.title.clear();
    assert!(
        first
            .edit(
                id,
                AgendaEditScope::All,
                None,
                bad,
                None,
                t("2026-02-01T00:00:00+08:00")
            )
            .is_err()
    );
    assert_eq!(first.get(id).unwrap(), Some(item));
    let other = event();
    let other_id = other.id;
    second.create(other).unwrap();
    first
        .complete(
            id,
            Some(t("2026-02-01T09:00:00+08:00")),
            true,
            t("2026-02-02T00:00:00+08:00"),
        )
        .unwrap();
    assert!(first.get(other_id).unwrap().is_some());
    first
        .complete(
            id,
            Some(t("2026-02-01T09:00:00+08:00")),
            false,
            t("2026-02-03T00:00:00+08:00"),
        )
        .unwrap();
    let rows = second.query(d("2026-02-01"), d("2026-02-02")).unwrap();
    assert!(rows[0].completed_at.is_none());
}
#[test]
fn all_day_exclusive_end_and_modern_dst_dates() {
    let mut item = event();
    item.content.start = Some(t("2026-03-07T00:00:00+08:00"));
    item.content.end = Some(t("2026-03-09T00:00:00+08:00"));
    item.content.all_day = true;
    item.rrule = Some("FREQ=WEEKLY;COUNT=3".into());
    assert_eq!(
        expand_agenda(&item, d("2026-03-08"), d("2026-03-09"))
            .unwrap()
            .len(),
        1
    );
    assert!(
        expand_agenda(&item, d("2026-03-09"), d("2026-03-10"))
            .unwrap()
            .is_empty()
    );
    let rows = expand_agenda(&item, d("2026-03-01"), d("2026-03-31")).unwrap();
    assert_eq!(rows.len(), 3);
    assert!(
        rows.iter()
            .all(|r| r.content.start.unwrap().datetime.offset().local_minus_utc() == 8 * 3600)
    );
}
#[test]
fn exdate_until_and_override_moved_outside_range() {
    let mut item = repeated();
    item.rrule = Some("FREQ=DAILY;UNTIL=20260202T010000Z".into());
    item.exdates.insert(t("2026-02-01T09:00:00+08:00"));
    let mut moved = item.content.clone();
    moved.start = Some(t("2026-03-01T09:00:00+08:00"));
    moved.end = Some(t("2026-03-01T10:00:00+08:00"));
    item.overrides
        .insert("2026-02-02T09:00:00+08:00".into(), moved);
    assert_eq!(
        expand_agenda(&item, d("2026-01-31"), d("2026-02-03"))
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        expand_agenda(&item, d("2026-03-01"), d("2026-03-02"))
            .unwrap()
            .len(),
        1
    );
}
#[test]
fn teaching_odd_every_and_range_validation() {
    let time = NaiveTime::from_hms_opt(9, 0, 0).unwrap();
    for (pattern, expected) in [
        (TeachingWeekPattern::Odd, 2),
        (TeachingWeekPattern::Every, 3),
    ] {
        let rule =
            teaching_week_rule(d("2026-02-23"), 1, 3, pattern, Weekday::Mon, time, &[]).unwrap();
        let mut item = event();
        item.content.end = Some(AgendaTime::new(
            rule.start.datetime + chrono::Duration::hours(1),
        ));
        item.content.start = Some(rule.start);
        item.rrule = Some(rule.rrule);
        assert_eq!(
            expand_agenda(&item, d("2026-02-01"), d("2026-04-01"))
                .unwrap()
                .len(),
            expected
        );
    }
    assert!(
        teaching_week_rule(
            d("2026-02-24"),
            1,
            3,
            TeachingWeekPattern::Every,
            Weekday::Mon,
            time,
            &[]
        )
        .is_err()
    );
    assert!(
        teaching_week_rule(
            d("2026-02-23"),
            1,
            1,
            TeachingWeekPattern::Even,
            Weekday::Mon,
            time,
            &[]
        )
        .is_err()
    );
}
#[test]
fn future_delete_and_first_occurrence_split() {
    let store = opened();
    let item = repeated();
    let id = item.id;
    store.create(item.clone()).unwrap();
    store
        .delete(
            id,
            AgendaEditScope::ThisAndFuture,
            Some(t("2026-02-02T09:00:00+08:00")),
            t("2026-02-04T00:00:00+08:00"),
        )
        .unwrap();
    assert_eq!(
        store.query(d("2026-01-01"), d("2026-03-01")).unwrap().len(),
        2
    );
    let content = item.content.clone();
    let new = store
        .edit(
            id,
            AgendaEditScope::ThisAndFuture,
            item.content.start,
            content,
            Some("FREQ=WEEKLY;COUNT=2".into()),
            t("2026-02-05T00:00:00+08:00"),
        )
        .unwrap()
        .unwrap();
    assert!(store.get(id).unwrap().unwrap().deleted_at.is_some());
    assert!(store.get(new).unwrap().is_some());
    assert_eq!(
        store.query(d("2026-01-01"), d("2026-03-01")).unwrap().len(),
        2
    );
}
#[test]
fn undated_task_completion_and_invalid_occurrence_rejected() {
    let store = opened();
    let mut item = event();
    item.content.kind = AgendaKind::Task;
    item.content.start = None;
    item.content.end = None;
    let id = item.id;
    store.create(item).unwrap();
    store
        .complete(id, None, true, t("2026-02-01T00:00:00+08:00"))
        .unwrap();
    assert!(
        store.query(d("2026-01-01"), d("2026-01-02")).unwrap()[0]
            .completed_at
            .is_some()
    );
    let item = repeated();
    let id = item.id;
    store.create(item).unwrap();
    assert!(
        store
            .complete(
                id,
                Some(t("2026-02-01T10:00:00+08:00")),
                true,
                t("2026-02-01T00:00:00+08:00")
            )
            .is_err()
    );
    store
        .delete(
            id,
            AgendaEditScope::This,
            Some(t("2026-02-01T09:00:00+08:00")),
            t("2026-02-01T00:00:00+08:00"),
        )
        .unwrap();
    assert!(
        store
            .complete(
                id,
                Some(t("2026-02-01T09:00:00+08:00")),
                true,
                t("2026-02-02T00:00:00+08:00")
            )
            .is_err()
    );
}
#[test]
fn editing_undated_and_single_items_keeps_completion() {
    let store = opened();
    let mut item = event();
    item.content.kind = AgendaKind::Task;
    item.content.start = None;
    item.content.end = None;
    let id = item.id;
    store.create(item.clone()).unwrap();
    let now = t("2026-02-01T00:00:00+08:00");
    store.complete(id, None, true, now).unwrap();
    item.content.title = "修改标题".into();
    store
        .edit(id, AgendaEditScope::All, None, item.content, None, now)
        .unwrap();
    assert!(
        store.query(d("2026-01-01"), d("2026-01-02")).unwrap()[0]
            .completed_at
            .is_some()
    );
    let item = event();
    let id = item.id;
    store.create(item.clone()).unwrap();
    store.complete(id, item.content.start, true, now).unwrap();
    let mut content = item.content.clone();
    content.start = Some(t("2026-02-01T09:00:00+08:00"));
    content.end = Some(t("2026-02-01T10:00:00+08:00"));
    store
        .edit(
            id,
            AgendaEditScope::This,
            item.content.start,
            content,
            None,
            now,
        )
        .unwrap();
    assert!(
        store.query(d("2026-02-01"), d("2026-02-02")).unwrap()[0]
            .completed_at
            .is_some()
    );
}
#[test]
fn future_split_until_moves_last_occurrence_with_anchor() {
    let store = opened();
    let mut item = repeated();
    item.rrule = Some("FREQ=DAILY;UNTIL=20260204T010000Z".into());
    let id = item.id;
    store.create(item.clone()).unwrap();
    let mut content = item.content.clone();
    content.start = Some(t("2026-02-02T11:00:00+08:00"));
    content.end = Some(t("2026-02-02T12:00:00+08:00"));
    store
        .edit(
            id,
            AgendaEditScope::ThisAndFuture,
            Some(t("2026-02-02T09:00:00+08:00")),
            content,
            item.rrule,
            t("2026-02-05T00:00:00+08:00"),
        )
        .unwrap();
    assert_eq!(
        store.query(d("2026-01-01"), d("2026-03-01")).unwrap().len(),
        5
    );
}
#[test]
fn range_limits_invalid_timezone_and_overlay_key_collision() {
    let mut item = event();
    item.rrule = Some("FREQ=SECONDLY".into());
    assert_eq!(
        expand_agenda(&item, d("2026-01-31"), d("2026-02-02")),
        Err(crate::facade::CacheError::Capacity)
    );
    let mut item = event();
    item.content.start.as_mut().unwrap().timezone = chrono_tz::UTC;
    assert!(opened().create(item).is_err());
    let store = opened();
    let now = t("2026-02-01T00:00:00+08:00");
    for (source, id, hidden) in [("a:b", "c", true), ("a", "b:c", false)] {
        let key = SchoolAgendaKey {
            source: source.into(),
            upstream_id: id.into(),
        };
        store
            .set_overlay(
                SchoolAgendaOverlay {
                    key: key.clone(),
                    completed_at: Some(now),
                    completion_override: true,
                    hidden,
                    note: None,
                    updated_at: now,
                    deleted_at: None,
                    locally_modified: false,
                },
                now,
            )
            .unwrap();
        let v = store.overlay(&key).unwrap().unwrap();
        assert_eq!(v.hidden, hidden);
        assert!(v.effective_completed(false));
    }
    assert_eq!(store.unsynced_count().unwrap(), 2);
}
#[test]
fn note_only_overlay_keeps_upstream_completion() {
    let now = t("2026-02-01T00:00:00+08:00");
    let overlay = SchoolAgendaOverlay {
        key: SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: "note-only".into(),
        },
        completed_at: None,
        completion_override: false,
        hidden: false,
        note: Some("只加备注".into()),
        updated_at: now,
        deleted_at: None,
        locally_modified: true,
    };
    assert!(overlay.effective_completed(true));
}
#[test]
fn concurrent_connections_commit_both_items() {
    let root = root();
    let first = AgendaStore::open(&root, ACCOUNT).unwrap();
    let second = AgendaStore::open(&root, ACCOUNT).unwrap();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));
    let handles = [first, second]
        .into_iter()
        .map(|store| {
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                barrier.wait();
                store.create(event()).unwrap();
            })
        })
        .collect::<Vec<_>>();
    for handle in handles {
        handle.join().unwrap();
    }
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    assert_eq!(
        store.query(d("2026-01-01"), d("2026-03-01")).unwrap().len(),
        2
    );
}
#[test]
fn eviction_of_old_readonly_data_keeps_agenda() {
    use crate::facade::{
        CacheCompleteness, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
        ConnectionMode, OfflineRepository, TodayClass,
    };
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    let mut cache = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([1; 32]),
        CacheLimits {
            soft_bytes: 1024,
            hard_bytes: 32768,
        },
    )
    .unwrap();
    let old = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-01-01".into(),
        },
    };
    let ticket = cache.begin_read(old.clone()).unwrap();
    cache
        .publish(
            &ticket,
            CachePayload::Today(vec![TodayClass {
                biz_name: "合成事项".repeat(200),
                place: None,
                time: None,
                short_name: None,
            }]),
            1,
            CacheCompleteness::Complete,
        )
        .unwrap();
    let current = CacheScope {
        route: ConnectionMode::WebVpn,
        query: CacheQuery::ScheduleToday {
            date: "2026-10-01".into(),
        },
    };
    let ticket = cache.begin_read(current).unwrap();
    cache
        .publish(
            &ticket,
            CachePayload::Today(Vec::new()),
            t("2026-10-01T00:00:00+08:00").datetime.timestamp(),
            CacheCompleteness::Complete,
        )
        .unwrap();
    assert!(
        cache
            .read(&old, t("2026-10-01T00:00:00+08:00").datetime.timestamp())
            .unwrap()
            .is_none()
    );
    assert!(store.get(id).unwrap().is_some());
}
#[test]
fn assigning_and_removing_due_date_preserves_single_task_completion() {
    let store = opened();
    let mut item = event();
    item.content.kind = AgendaKind::Task;
    item.content.start = None;
    item.content.end = None;
    let id = item.id;
    store.create(item.clone()).unwrap();
    let now = t("2026-02-01T00:00:00+08:00");
    store.complete(id, None, true, now).unwrap();
    item.content.due = Some(t("2026-02-02T12:00:00+08:00"));
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
    assert!(
        store.query(d("2026-02-01"), d("2026-02-03")).unwrap()[0]
            .completed_at
            .is_some()
    );
    item.content.due = None;
    store
        .edit(id, AgendaEditScope::All, None, item.content, None, now)
        .unwrap();
    assert!(
        store.query(d("2026-02-01"), d("2026-02-03")).unwrap()[0]
            .completed_at
            .is_some()
    );
}
#[test]
fn override_at_exclusive_query_end_is_returned_once() {
    let mut item = event();
    item.content.start = Some(t("2026-02-01T00:00:00+08:00"));
    item.content.end = Some(t("2026-02-01T01:00:00+08:00"));
    item.rrule = Some("FREQ=DAILY;COUNT=2".into());
    let mut content = item.content.clone();
    content.start = Some(t("2026-01-31T12:00:00+08:00"));
    content.end = Some(t("2026-01-31T13:00:00+08:00"));
    item.overrides
        .insert("2026-02-01T00:00:00+08:00".into(), content);
    assert_eq!(
        expand_agenda(&item, d("2026-01-31"), d("2026-02-01"))
            .unwrap()
            .len(),
        1
    );
}
#[test]
fn all_day_date_until_uses_shanghai_and_survives_split() {
    let store = opened();
    let mut item = event();
    item.content.start = Some(t("2026-03-01T00:00:00+08:00"));
    item.content.end = Some(t("2026-03-02T00:00:00+08:00"));
    item.content.all_day = true;
    item.rrule = Some("FREQ=DAILY;UNTIL=20260304".into());
    let id = item.id;
    store.create(item.clone()).unwrap();
    assert_eq!(
        store.query(d("2026-03-01"), d("2026-03-10")).unwrap().len(),
        4
    );
    let mut content = item.content.clone();
    content.start = Some(t("2026-03-04T00:00:00+08:00"));
    content.end = Some(t("2026-03-05T00:00:00+08:00"));
    store
        .edit(
            id,
            AgendaEditScope::ThisAndFuture,
            Some(t("2026-03-03T00:00:00+08:00")),
            content,
            item.rrule,
            t("2026-03-06T00:00:00+08:00"),
        )
        .unwrap();
    assert_eq!(
        store.query(d("2026-03-01"), d("2026-03-10")).unwrap().len(),
        4
    );
}
#[test]
fn unknown_schema_rejects_open_handles_and_does_not_change_journal_mode() {
    use crate::facade::CacheError;
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    let path = root.join("agenda").join(format!("{ACCOUNT}.sqlite"));
    let db = rusqlite::Connection::open(&path).unwrap();
    db.pragma_update(None, "user_version", 999).unwrap();
    let mode: String = db
        .pragma_query_value(None, "journal_mode", |r| r.get(0))
        .unwrap();
    assert_eq!(mode, "delete");
    assert_eq!(store.unsynced_count(), Err(CacheError::UnsupportedVersion));
    db.pragma_update(None, "journal_mode", "WAL").unwrap();
    assert!(matches!(
        AgendaStore::open(&root, ACCOUNT),
        Err(CacheError::UnsupportedVersion)
    ));
    let mode: String = db
        .pragma_query_value(None, "journal_mode", |r| r.get(0))
        .unwrap();
    assert_eq!(mode, "wal");
}
