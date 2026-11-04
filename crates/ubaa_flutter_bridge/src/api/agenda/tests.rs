use super::models::{BridgeAgendaFailure, BridgeAgendaKind};
use super::school::{BridgeAgendaFeature, BridgeAgendaTiming, BridgeAgendaTimingKind};
use super::*;
const ACCOUNT: &str = "00000000000000000000000000000001";
fn t(v: &str) -> BridgeAgendaTime {
    BridgeAgendaTime {
        rfc3339: v.into(),
        timezone: "Asia/Shanghai".into(),
    }
}
fn now() -> BridgeAgendaTime {
    t("2026-03-24T12:00:00+08:00")
}
fn draft() -> BridgeAgendaDraft {
    BridgeAgendaDraft {
        content: BridgeAgendaContent {
            kind: BridgeAgendaKind::Event,
            title: "合成系列".into(),
            location: Some("合成教室".into()),
            notes: None,
            color: None,
            start: Some(t("2026-03-24T08:00:00+08:00")),
            end: Some(t("2026-03-24T09:00:00+08:00")),
            all_day: false,
            due: None,
        },
        rrule: Some("FREQ=DAILY;COUNT=3".into()),
        exdates: vec![],
    }
}
fn q() -> BridgeAgendaQuery {
    BridgeAgendaQuery {
        route: crate::api::client::BridgeConnectionMode::Direct,
        term: "synthetic".into(),
        from: "2026-03-23".into(),
        to: "2026-03-30".into(),
        now: now(),
        include_hidden: false,
        ygdk_enabled: true,
        ygdk_week_done: false,
        ygdk_term_done: false,
    }
}
async fn open() -> (std::path::PathBuf, BridgeAgendaStore) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_1c_a/bridge_tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let root = root.canonicalize().unwrap();
    let handle = BridgeAgendaStore::open(root.to_string_lossy().into(), ACCOUNT.into())
        .await
        .unwrap();
    (root, handle)
}
#[tokio::test]
async fn typed_roundtrip_moved_occurrence_overlay_and_logout() {
    let (root, h) = open().await;
    let item = h.create(draft(), now()).await.unwrap();
    assert_eq!(h.get(item.id.clone()).await.unwrap(), Some(item.clone()));
    let mut moved = item.content.clone();
    moved.start = Some(t("2026-03-28T08:00:00+08:00"));
    moved.end = Some(t("2026-03-28T09:00:00+08:00"));
    h.edit(
        item.id.clone(),
        BridgeAgendaEditScope::This,
        Some(t("2026-03-25T08:00:00+08:00")),
        moved,
        None,
        now(),
    )
    .await
    .unwrap();
    h.complete(
        item.id.clone(),
        Some(t("2026-03-25T08:00:00+08:00")),
        true,
        now(),
    )
    .await
    .unwrap();
    let rows = h.query_local(q()).await.unwrap();
    let occurrence = rows
        .entries
        .iter()
        .filter_map(|e| e.local.as_ref())
        .find(|e| e.overridden)
        .unwrap();
    assert_eq!(occurrence.recurrence_id, "2026-03-25T08:00:00+08:00");
    assert_eq!(
        occurrence.content.start.as_ref().unwrap().rfc3339,
        "2026-03-28T08:00:00+08:00"
    );
    let key = BridgeSchoolAgendaKey {
        source: "judge".into(),
        upstream_id: "synthetic".into(),
    };
    h.set_overlay(
        BridgeAgendaOverlayDraft {
            key: key.clone(),
            completed_at: None,
            completion_override: true,
            hidden: true,
            note: Some("本机备注".into()),
        },
        now(),
    )
    .await
    .unwrap();
    let overlay = h.overlay(key.clone()).await.unwrap().unwrap();
    assert!(overlay.value.completion_override);
    assert!(overlay.value.hidden);
    assert_eq!(overlay.value.completed_at, None);
    assert_eq!(h.unsynced_count().await.unwrap(), 2);
    h.clear_overlay(key.clone(), now()).await.unwrap();
    assert!(h.overlay(key).await.unwrap().unwrap().deleted_at.is_some());
    h.deactivate().await.unwrap();
    assert_eq!(
        h.get(item.id.clone()).await.unwrap_err().failure,
        BridgeAgendaFailure::Inactive
    );
    h.activate().await.unwrap();
    assert!(h.get(item.id).await.unwrap().is_some());
    assert_eq!(h.clear_local_data().await.unwrap(), 2);
    drop(h);
    std::fs::remove_dir_all(root).unwrap();
}
#[tokio::test]
async fn invalid_uuid_time_date_rrule_are_stable_and_do_not_write() {
    let (root, h) = open().await;
    assert_eq!(
        h.get("invalid".into()).await.unwrap_err().failure,
        BridgeAgendaFailure::InvalidInput
    );
    for bad in ["2026-03-24T12:00:00Z", "2026-03-24T12:00:00.1+08:00", "bad"] {
        assert_eq!(
            h.create(draft(), t(bad)).await.unwrap_err().failure,
            BridgeAgendaFailure::InvalidInput
        );
    }
    let mut query = q();
    query.from = "2026-02-30".into();
    assert_eq!(
        h.query_local(query).await.unwrap_err().failure,
        BridgeAgendaFailure::InvalidInput
    );
    let mut value = draft();
    value.rrule = Some("FREQ=INVALID".into());
    assert_eq!(
        h.create(value, now()).await.unwrap_err().failure,
        BridgeAgendaFailure::InvalidInput
    );
    assert_eq!(h.unsynced_count().await.unwrap(), 0);
    drop(h);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn unknown_endpoints_and_allday_preserve_shape() {
    let value: BridgeAgendaTiming = core::AgendaTiming::Period {
        start: None,
        end: Some(core::AgendaTime::new(
            "2026-03-24T12:00:00+08:00".parse().unwrap(),
        )),
    }
    .into();
    assert_eq!(value.kind, BridgeAgendaTimingKind::Period);
    assert_eq!(value.start, None);
    assert!(value.end.is_some());
    let value: BridgeAgendaTiming = core::AgendaTiming::AllDay {
        from: "2026-03-24".parse().unwrap(),
        to: "2026-03-25".parse().unwrap(),
    }
    .into();
    assert_eq!(value.from.as_deref(), Some("2026-03-24"));
    assert_eq!(value.to.as_deref(), Some("2026-03-25"));
    assert!(value.start.is_none());
}
#[tokio::test]
async fn merged_query_keeps_raw_status_overlay_route_and_cache_failure_separate() {
    let (root, h) = open().await;
    h.create(draft(), now()).await.unwrap();
    let cache = school_cache(&root);
    let result = h.query_with_cache(&cache, q()).await.unwrap();
    let school = result
        .entries
        .iter()
        .find_map(|e| e.school.as_ref())
        .unwrap();
    assert!(school.upstream_status.completed);
    let key = school.key.clone();
    h.set_overlay(
        BridgeAgendaOverlayDraft {
            key,
            completed_at: None,
            completion_override: true,
            hidden: true,
            note: Some("保留原始状态".into()),
        },
        now(),
    )
    .await
    .unwrap();
    assert!(
        h.query_with_cache(&cache, q())
            .await
            .unwrap()
            .entries
            .iter()
            .all(|e| e.school.is_none())
    );
    let mut query = q();
    query.include_hidden = true;
    let result = h.query_with_cache(&cache, query).await.unwrap();
    let entry = result.entries.iter().find(|e| e.school.is_some()).unwrap();
    assert!(!entry.completed);
    assert!(entry.hidden);
    assert!(entry.soon);
    assert!(entry.school.as_ref().unwrap().upstream_status.completed);
    assert_eq!(
        entry
            .school
            .as_ref()
            .unwrap()
            .navigation
            .assignment_id
            .as_deref(),
        Some("synthetic-work")
    );
    assert!(
        result
            .sources
            .iter()
            .find(|s| s.feature == BridgeAgendaFeature::Spoc)
            .unwrap()
            .observations[0]
            .last_attempt_succeeded
    );
    let mut vpn = q();
    vpn.route = crate::api::client::BridgeConnectionMode::WebVpn;
    assert_eq!(
        h.query_with_cache(&cache, vpn).await.unwrap().entries.len(),
        3
    );
    cache.cache.deactivate().unwrap();
    let fallback = h.query_with_cache(&cache, q()).await.unwrap();
    assert_eq!(
        fallback.school_cache_failure,
        Some(crate::api::offline::BridgeCacheFailure::Inactive)
    );
    assert_eq!(fallback.entries.len(), 3);
    let other = BridgeOfflineCache {
        cache: core::OfflineCache::open(
            &root,
            "00000000000000000000000000000002",
            "other",
            core::CacheKey::new([4; 32]),
            core::CacheLimits::default(),
        )
        .unwrap(),
    };
    let mut empty_term = q();
    empty_term.term.clear();
    assert_eq!(
        h.query_with_cache(&other, empty_term)
            .await
            .unwrap_err()
            .failure,
        BridgeAgendaFailure::InvalidInput
    );
    drop(other);
    drop(cache);
    drop(h);
    std::fs::remove_dir_all(root).unwrap();
}
#[tokio::test]
async fn edits_and_deletes_three_scopes_and_teaching_weeks() {
    let (root, h) = open().await;
    let item = h.create(draft(), now()).await.unwrap();
    let mut content = item.content.clone();
    content.title = "整个系列".into();
    h.edit(
        item.id.clone(),
        BridgeAgendaEditScope::All,
        None,
        content.clone(),
        item.rrule.clone(),
        now(),
    )
    .await
    .unwrap();
    let next = h
        .edit(
            item.id.clone(),
            BridgeAgendaEditScope::ThisAndFuture,
            Some(t("2026-03-25T08:00:00+08:00")),
            content,
            item.rrule,
            now(),
        )
        .await
        .unwrap()
        .unwrap();
    assert_ne!(next, item.id);
    h.delete(
        next.clone(),
        BridgeAgendaEditScope::This,
        Some(t("2026-03-24T08:00:00+08:00")),
        now(),
    )
    .await
    .unwrap();
    h.delete(
        next,
        BridgeAgendaEditScope::ThisAndFuture,
        Some(t("2026-03-25T08:00:00+08:00")),
        now(),
    )
    .await
    .unwrap();
    h.delete(item.id.clone(), BridgeAgendaEditScope::All, None, now())
        .await
        .unwrap();
    assert!(h.get(item.id).await.unwrap().unwrap().deleted_at.is_some());
    let rule = agenda_teaching_week_rule(BridgeTeachingWeekInput {
        monday: "2026-02-23".into(),
        first: 1,
        last: 3,
        pattern: BridgeTeachingWeekPattern::Odd,
        weekday: 1,
        hour: 8,
        minute: 0,
        second: 0,
        skips: vec!["2026-03-09".into()],
    })
    .await
    .unwrap();
    assert_eq!(rule.start.rfc3339, "2026-02-23T08:00:00+08:00");
    assert_eq!(rule.exdates.len(), 1);
    drop(h);
    std::fs::remove_dir_all(root).unwrap();
}

fn school_cache(root: &std::path::Path) -> BridgeOfflineCache {
    let mut repository = core::OfflineRepository::open(
        root,
        ACCOUNT,
        core::CacheKey::new([3; 32]),
        core::CacheLimits::default(),
    )
    .unwrap();
    for (query, payload) in [
        (
            core::CacheQuery::SpocSelection,
            core::CachePayload::SpocSelection {
                term: "synthetic".into(),
            },
        ),
        (
            core::CacheQuery::SpocTerm {
                term: "synthetic".into(),
            },
            core::CachePayload::SpocAssignments(core::SpocAssignments {
                term_code: "synthetic".into(),
                assignments: vec![core::SpocAssignmentSummary {
                    assignment_id: "synthetic-work".into(),
                    title: "合成作业".into(),
                    due_time: Some("2026-03-25 12:00:00".into()),
                    submission_status: core::SpocSubmissionStatus::Submitted,
                    submission_status_text: "已提交".into(),
                    ..Default::default()
                }],
                ..Default::default()
            }),
        ),
    ] {
        let ticket = repository
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query,
            })
            .unwrap();
        repository
            .publish(
                &ticket,
                payload,
                1_774_324_800,
                core::CacheCompleteness::Complete,
            )
            .unwrap();
    }
    drop(repository);
    BridgeOfflineCache {
        cache: core::OfflineCache::open(
            root,
            ACCOUNT,
            "synthetic",
            core::CacheKey::new([3; 32]),
            core::CacheLimits::default(),
        )
        .unwrap(),
    }
}

#[tokio::test]
async fn export_snapshot_preserves_occurrences_and_rejects_logout() {
    let (root, h) = open().await;
    h.create(draft(), now()).await.unwrap();
    let result = h.export_ics(q(), true).await.unwrap();
    assert_eq!(result.exported_count, 3);
    assert!(result.ics.contains("BEGIN:VEVENT\r\n"));
    let cache = school_cache(&root);
    assert_eq!(
        h.export_with_cache(&cache, q(), true)
            .await
            .unwrap()
            .exported_count,
        4
    );
    assert_eq!(
        h.export_with_cache(&cache, q(), false)
            .await
            .unwrap()
            .exported_count,
        3
    );
    let mut vpn = q();
    vpn.route = crate::api::client::BridgeConnectionMode::WebVpn;
    assert_eq!(
        h.export_with_cache(&cache, vpn, true)
            .await
            .unwrap()
            .exported_count,
        3
    );
    cache.cache.deactivate().unwrap();
    assert_eq!(
        h.export_with_cache(&cache, q(), true)
            .await
            .unwrap_err()
            .failure,
        BridgeAgendaFailure::Inactive
    );
    drop(cache);
    h.deactivate().await.unwrap();
    assert_eq!(
        h.export_ics(q(), true).await.unwrap_err().failure,
        BridgeAgendaFailure::Inactive
    );
    drop(h);
    std::fs::remove_dir_all(root).unwrap();
}
