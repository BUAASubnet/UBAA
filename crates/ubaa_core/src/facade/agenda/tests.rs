use super::*;

#[test]
fn cached_export_uses_existing_projection_and_preserves_route_evidence() {
    let (root, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    local(&agenda);
    let q = query();
    let queried = cache.query_agenda(&agenda, &q).unwrap();
    let result = cache.export_agenda_ics(&agenda, &q, true).unwrap();
    assert_eq!(result.sources, queried.sources);
    assert!(
        result
            .sources
            .iter()
            .flat_map(|s| &s.observations)
            .all(|o| o.scope.route == ConnectionMode::Direct)
    );
    assert_eq!(
        result.snapshot.exported_count + result.snapshot.skipped_unknown_time_count,
        queried.entries.len()
    );
    assert!(result.snapshot.exported_count > 1);
    assert!(
        result
            .sources
            .iter()
            .flat_map(|s| &s.observations)
            .any(|o| !o.is_fresh(q.now.datetime.timestamp(), 0))
    );
    let mut other_route = q.clone();
    other_route.route = ConnectionMode::WebVpn;
    let missing = cache
        .export_agenda_ics(&agenda, &other_route, true)
        .unwrap();
    assert_eq!(missing.snapshot.exported_count, 2);
    assert!(missing.sources.iter().all(|s| s.observations.is_empty()));
    cache.deactivate().unwrap();
    assert!(cache.export_agenda_ics(&agenda, &q, true).is_err());
    // 缓存失效不影响独立本机导出。
    assert_eq!(
        agenda
            .export_local_ics(&crate::facade::AgendaExportOptions {
                from: q.from,
                to: q.to,
                generated_at: q.now,
                include_hidden: false,
                include_completed: true,
            })
            .unwrap()
            .exported_count,
        2
    );
    drop((agenda, cache));
    std::fs::remove_dir_all(root).unwrap();
}
use crate::facade::*;
use std::path::PathBuf;
const ACCOUNT: &str = "00000000000000000000000000000001";
#[test]
fn no_school_cache_still_queries_known_account_local_agenda() {
    let (root, cache, agenda) = opened(ACCOUNT);
    local(&agenda);
    drop(cache);
    let mut q = query();
    q.term.clear();
    let result = agenda.query_local_agenda(&q).unwrap();
    assert!(!result.entries.is_empty());
    assert!(
        result
            .entries
            .iter()
            .all(|e| matches!(e.item, AgendaEntryItem::Local(_)))
    );
    assert_eq!(result.sources.len(), 8);
    assert!(result.sources.iter().all(|s| s.observations.is_empty()));
    assert_eq!(
        result.sources.last().unwrap().semester_imported,
        Some(false)
    );
    agenda.deactivate().unwrap();
    assert_eq!(agenda.query_local_agenda(&q), Err(CacheError::Inactive));
    drop(agenda);
    std::fs::remove_dir_all(root).unwrap();
}
fn t(raw: &str) -> AgendaTime {
    AgendaTime::new(raw.parse().unwrap())
}
fn d(raw: &str) -> NaiveDate {
    raw.parse().unwrap()
}
fn opened(account: &str) -> (PathBuf, OfflineCache, AgendaStore) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_plaintext/query_tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let root = root.canonicalize().unwrap();
    let cache = OfflineCache::open(
        &root,
        account,
        "synthetic-identity",
        CacheKey::new([1; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let agenda = AgendaStore::open(&root, account).unwrap();
    (root, cache, agenda)
}
fn query() -> AgendaQuery {
    AgendaQuery::new(
        ConnectionMode::Direct,
        "synthetic-term".into(),
        d("2026-03-23"),
        d("2026-03-30"),
        t("2026-03-24T12:00:00+08:00"),
    )
}
fn publish(cache: &OfflineCache, query: CacheQuery, payload: CachePayload, fetched_at: i64) {
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query,
    };
    cache
        .repository(|r| {
            let ticket = r.begin_read(scope)?;
            r.publish(&ticket, payload, fetched_at, CacheCompleteness::Complete)
        })
        .unwrap();
}
fn fixture(cache: &OfflineCache) {
    let (records, _) = crate::agenda::test_fixture::school_fixture();
    for record in records {
        publish(cache, record.scope.query, record.payload, record.fetched_at);
    }
    publish(
        cache,
        CacheQuery::SpocSelection,
        CachePayload::SpocSelection {
            term: "synthetic-term".into(),
        },
        1_774_324_500,
    );
    publish(
        cache,
        CacheQuery::YgdkOverviewSelection {
            week_start: "2026-03-23".into(),
        },
        CachePayload::YgdkOverviewSelection {
            classify_id: 3,
            term_id: Some(1),
        },
        1_774_324_500,
    );
    publish(
        cache,
        CacheQuery::ScheduleWeeks {
            term: "synthetic-term".into(),
        },
        CachePayload::Weeks(vec![Week {
            term: "synthetic-term".into(),
            serial_number: 11,
            start_date: "2026-03-23".into(),
            end_date: "2026-03-29".into(),
            ..Default::default()
        }]),
        1_774_324_500,
    );
}
fn local(agenda: &AgendaStore) {
    let mut item = AgendaItem::new(
        AgendaContent {
            kind: AgendaKind::Task,
            title: "本机重复待办".into(),
            location: None,
            notes: None,
            color: None,
            start: None,
            end: None,
            all_day: false,
            due: Some(t("2026-03-24T12:25:00+08:00")),
        },
        t("2026-03-23T00:00:00+08:00"),
    );
    item.rrule = Some("FREQ=DAILY;COUNT=2".into());
    agenda.create(item).unwrap();
}
#[test]
fn merged_query_expands_local_and_school_with_overlay_and_availability() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    local(&agenda);
    let mut q = query();
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(result.entries.len(), 9);
    assert_eq!(result.entries[3].title(), "本机重复待办");
    assert_eq!(result.sources.len(), 8);
    let schedule = result
        .sources
        .iter()
        .find(|s| s.feature == ReadonlyFeature::Schedule)
        .unwrap();
    assert_eq!(schedule.semester_imported, Some(false));
    assert_eq!(schedule.missing_scopes.len(), 1);
    let spoc = result
        .entries
        .iter()
        .find_map(|e| match &e.item {
            AgendaEntryItem::School(v) if v.key.source == "spoc" => Some(v.clone()),
            _ => None,
        })
        .unwrap();
    let now = q.now;
    agenda
        .set_overlay(
            SchoolAgendaOverlay {
                key: spoc.key.clone(),
                completed_at: Some(now),
                completion_override: true,
                hidden: true,
                note: Some("本地备注".into()),
                updated_at: now,
                deleted_at: None,
                locally_modified: true,
            },
            now,
        )
        .unwrap();
    assert_eq!(cache.query_agenda(&agenda, &q).unwrap().entries.len(), 8);
    q.include_hidden = true;
    let result = cache.query_agenda(&agenda, &q).unwrap();
    let entry = result
        .entries
        .iter()
        .find(|e| matches!(&e.item, AgendaEntryItem::School(v) if v.key == spoc.key))
        .unwrap();
    assert!(entry.completed && entry.hidden);
    assert_eq!(entry.note.as_deref(), Some("本地备注"));
    assert!(matches!(&entry.item, AgendaEntryItem::School(v) if !v.upstream_status.completed()));
    agenda.clear_overlay(&spoc.key, now).unwrap();
    assert_eq!(
        cache.query_agenda(&agenda, &query()).unwrap().entries.len(),
        9
    );
}
#[test]
fn submitted_school_item_can_reopen_locally_without_changing_upstream() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::SpocTerm {
            term: "synthetic-term".into(),
        },
    };
    let mut record = cache
        .read(&scope, query().now.datetime.timestamp())
        .unwrap()
        .unwrap();
    if let CachePayload::SpocAssignments(v) = &mut record.payload {
        v.assignments[0].submission_status = SpocSubmissionStatus::Submitted;
        v.assignments[0].submission_status_text = "已提交".into();
    }
    publish(&cache, scope.query, record.payload, record.fetched_at + 1);
    let q = query();
    let before = cache.query_agenda(&agenda, &q).unwrap();
    let key = before
        .entries
        .iter()
        .find_map(|e| match &e.item {
            AgendaEntryItem::School(v) if v.key.source == "spoc" => {
                assert!(e.completed);
                assert!(!v.home_todo);
                Some(v.key.clone())
            }
            _ => None,
        })
        .unwrap();
    agenda
        .set_overlay(
            SchoolAgendaOverlay {
                key: key.clone(),
                completed_at: None,
                completion_override: true,
                hidden: false,
                note: None,
                updated_at: q.now,
                deleted_at: None,
                locally_modified: true,
            },
            q.now,
        )
        .unwrap();
    let result = cache.query_agenda(&agenda, &q).unwrap();
    let entry = result
        .entries
        .iter()
        .find(|e| matches!(&e.item, AgendaEntryItem::School(v) if v.key == key))
        .unwrap();
    assert!(!entry.completed);
    assert!(matches!(&entry.item, AgendaEntryItem::School(v) if v.upstream_status.completed()));
    agenda.clear_overlay(&key, q.now).unwrap();
    assert!(
        cache
            .query_agenda(&agenda, &q)
            .unwrap()
            .entries
            .iter()
            .any(|e| e.completed && matches!(&e.item, AgendaEntryItem::School(v) if v.key == key))
    );
}
#[test]
fn query_rejects_cross_account_logout_and_bad_ranges_and_keeps_routes_separate() {
    let (root, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    local(&agenda);
    let foreign = AgendaStore::open(&root, "00000000000000000000000000000002").unwrap();
    assert_eq!(
        cache.query_agenda(&foreign, &query()),
        Err(CacheError::InvalidInput)
    );
    let mut q = query();
    q.route = ConnectionMode::WebVpn;
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(result.entries.len(), 2);
    assert!(result.sources.iter().all(|s| s.observations.is_empty()));
    q.from = q.to;
    assert_eq!(
        cache.query_agenda(&agenda, &q),
        Err(CacheError::InvalidInput)
    );
    agenda.deactivate().unwrap();
    assert_eq!(
        cache.query_agenda(&agenda, &query()),
        Err(CacheError::Inactive)
    );
    agenda.activate().unwrap();
    cache.deactivate().unwrap();
    assert_eq!(
        cache.query_agenda(&agenda, &query()),
        Err(CacheError::Inactive)
    );
}
#[test]
fn missing_cached_page_and_stale_observation_are_reported_without_network() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let q = query();
    let scope = CacheScope {
        route: q.route,
        query: CacheQuery::CgyyOrders { page: 0, size: 20 },
    };
    let mut record = cache
        .read(&scope, q.now.datetime.timestamp())
        .unwrap()
        .unwrap();
    if let CachePayload::CgyyOrders(page) = &mut record.payload {
        page.total_pages = 2;
        page.total_elements = 21;
    }
    publish(&cache, scope.query, record.payload, record.fetched_at);
    let result = cache.query_agenda(&agenda, &q).unwrap();
    let room = result
        .sources
        .iter()
        .find(|s| s.feature == ReadonlyFeature::Cgyy)
        .unwrap();
    assert_eq!(
        room.missing_scopes[0].query,
        CacheQuery::CgyyOrders { page: 1, size: 20 }
    );
    let source = &room.observations[0];
    assert_eq!(source.fetched_at, record.fetched_at);
    assert!(!source.is_fresh(q.now.datetime.timestamp(), 1));
    assert!(!source.is_fresh(record.fetched_at - 1, 3600));
    assert_eq!(agenda.unsynced_count().unwrap(), 0);
}
#[test]
fn imported_semester_projects_only_requested_dates_and_keeps_original_freshness() {
    let (_, cache, agenda) = opened(ACCOUNT);
    let q = query();
    let week = Week {
        term: q.term.clone(),
        serial_number: 11,
        start_date: "2026-03-23".into(),
        end_date: "2026-03-29".into(),
        ..Default::default()
    };
    let semester = CachedSemesterSchedule::new(
        q.term.clone(),
        vec![Term {
            item_code: q.term.clone(),
            ..Default::default()
        }],
        vec![week],
        [(
            11,
            WeeklySchedule {
                arranged_list: vec![
                    CourseClass {
                        course_code: "synthetic-course".into(),
                        course_serial_no: Some("01".into()),
                        course_name: "周二课程".into(),
                        day_of_week: Some(2),
                        begin_section: Some(1),
                        end_section: Some(2),
                        ..Default::default()
                    },
                    CourseClass {
                        course_code: "other-course".into(),
                        course_name: "周一课程".into(),
                        day_of_week: Some(1),
                        begin_section: Some(3),
                        end_section: Some(4),
                        ..Default::default()
                    },
                ],
                ..Default::default()
            },
        )]
        .into(),
        100,
    )
    .unwrap();
    cache
        .repository(|r| {
            let ticket = r.begin_read(CacheScope {
                route: q.route,
                query: CacheQuery::ImportedSchedules,
            })?;
            r.publish_imported_semester(&ticket, semester)
        })
        .unwrap();
    let mut q = q;
    q.from = d("2026-03-24");
    q.to = d("2026-03-25");
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(result.entries.len(), 2);
    assert_eq!(result.entries[0].title(), "周二课程");
    let key = match &result.entries[0].item {
        AgendaEntryItem::School(v) => v.key.clone(),
        AgendaEntryItem::Local(_) => panic!("课程来源"),
    };
    agenda
        .set_overlay(
            SchoolAgendaOverlay {
                key,
                completed_at: Some(q.now),
                completion_override: true,
                hidden: false,
                note: None,
                updated_at: q.now,
                deleted_at: None,
                locally_modified: true,
            },
            q.now,
        )
        .unwrap();
    let overlaid = cache.query_agenda(&agenda, &q).unwrap();
    assert!(overlaid.entries[0].completed);
    assert!(!overlaid.entries[1].completed);
    let state = result
        .sources
        .iter()
        .find(|s| s.feature == ReadonlyFeature::Schedule)
        .unwrap();
    assert_eq!(state.semester_imported, Some(true));
    assert!(state.missing_scopes.is_empty());
    assert!(state.observations.iter().all(|s| s.fetched_at == 100));
    q.from = d("2026-03-30");
    q.to = d("2026-04-01");
    assert!(cache.query_agenda(&agenda, &q).unwrap().entries.is_empty());
}
#[test]
fn ordinary_week_cache_uses_real_dates_and_reports_partial_import_coverage() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let q = query();
    let schedule = WeeklySchedule {
        arranged_list: vec![CourseClass {
            course_code: "local-week-course".into(),
            course_name: "本周缓存课程".into(),
            begin_section: Some(1),
            end_section: Some(2),
            day_of_week: Some(2),
            ..Default::default()
        }],
        ..Default::default()
    };
    publish(
        &cache,
        CacheQuery::ScheduleWeek {
            term: q.term.clone(),
            week: 11,
        },
        CachePayload::Week(schedule.clone()),
        100,
    );
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert!(result.entries.iter().any(|e| e.title() == "本周缓存课程"));
    let source = result
        .sources
        .iter()
        .find(|s| s.feature == ReadonlyFeature::Schedule)
        .unwrap();
    assert_eq!(source.semester_imported, Some(false));
    assert!(source.missing_scopes.is_empty());
    let mut invalid = schedule;
    invalid.arranged_list[0].day_of_week = None;
    publish(
        &cache,
        CacheQuery::ScheduleWeek {
            term: q.term.clone(),
            week: 11,
        },
        CachePayload::Week(invalid),
        101,
    );
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert!(!result.entries.iter().any(|e| e.title() == "本周缓存课程"));
    assert_eq!(
        result
            .sources
            .iter()
            .find(|s| s.feature == ReadonlyFeature::Schedule)
            .unwrap()
            .unprojectable_count,
        1
    );
}
#[test]
fn date_range_keeps_intersecting_periods_and_excludes_deadline_at_end() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    local(&agenda);
    let mut q = query();
    q.from = d("2026-03-25");
    q.to = d("2026-03-26");
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(
        result
            .entries
            .iter()
            .map(AgendaEntry::title)
            .collect::<Vec<_>>(),
        ["明天考试", "本机重复待办"]
    );
    let mut task = AgendaItem::new(
        AgendaContent {
            kind: AgendaKind::Task,
            title: "无日期事项".into(),
            location: None,
            notes: None,
            color: None,
            start: None,
            end: None,
            all_day: false,
            due: None,
        },
        q.now,
    );
    task.content.notes = Some("本地说明".into());
    agenda.create(task).unwrap();
    let bykc = CachedBykcChosen {
        semester_start: "2026-03-01".into(),
        semester_end: "2026-07-01".into(),
        courses: vec![CachedBykcChosenCourse {
            course_id: 102,
            course_name: "跨日事项".into(),
            course_start_date: Some("2026-03-24 23:00".into()),
            course_end_date: Some("2026-03-25 01:00".into()),
            ..Default::default()
        }],
    };
    publish(
        &cache,
        CacheQuery::BykcChosen,
        CachePayload::BykcChosen(bykc),
        100,
    );
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(
        result
            .entries
            .iter()
            .map(AgendaEntry::title)
            .collect::<Vec<_>>(),
        ["无日期事项", "跨日事项", "明天考试", "本机重复待办"]
    );
    assert_eq!(result.entries[0].note.as_deref(), Some("本地说明"));
}
#[test]
fn query_uses_exam_midnight_sort_without_changing_unknown_start() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let q = query();
    let scope = CacheScope {
        route: q.route,
        query: CacheQuery::Exams {
            term: q.term.clone(),
        },
    };
    let mut record = cache
        .read(&scope, q.now.datetime.timestamp())
        .unwrap()
        .unwrap();
    if let CachePayload::Exams(v) = &mut record.payload {
        v.arranged[0].exam_date = Some("2026-03-24".into());
        v.arranged[0].start_time = None;
        v.arranged[0].end_time = Some("12:00".into());
    }
    publish(&cache, scope.query, record.payload, 2);
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(result.entries[0].title(), "明天考试");
    assert_eq!(
        result.entries[0].sort_time(),
        Some(t("2026-03-24T00:00:00+08:00"))
    );
    assert_eq!(
        result.entries[0].timing(),
        AgendaTiming::Period {
            start: None,
            end: Some(t("2026-03-24T12:00:00+08:00"))
        }
    );
}
#[test]
fn separate_sections_do_not_mask_an_unprojectable_course() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let q = query();
    publish(
        &cache,
        CacheQuery::ScheduleWeek {
            term: q.term.clone(),
            week: 11,
        },
        CachePayload::Week(WeeklySchedule {
            arranged_list: vec![
                CourseClass {
                    course_code: "known-course".into(),
                    course_name: "已知课程".into(),
                    begin_section: Some(1),
                    end_section: Some(2),
                    day_of_week: Some(2),
                    ..Default::default()
                },
                CourseClass {
                    course_name: "缺课程代码".into(),
                    begin_section: Some(3),
                    end_section: Some(4),
                    day_of_week: Some(2),
                    ..Default::default()
                },
            ],
            ..Default::default()
        }),
        100,
    );
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert_eq!(
        result
            .entries
            .iter()
            .filter(|e| e.title() == "已知课程")
            .count(),
        2
    );
    assert_eq!(
        result
            .sources
            .iter()
            .find(|s| s.feature == ReadonlyFeature::Schedule)
            .unwrap()
            .unprojectable_count,
        1
    );
}
#[test]
fn ambiguous_keys_are_reported_and_do_not_apply_an_overlay_to_a_different_item() {
    let (_, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let q = query();
    let scope = CacheScope {
        route: q.route,
        query: CacheQuery::SpocTerm {
            term: q.term.clone(),
        },
    };
    let mut record = cache
        .read(&scope, q.now.datetime.timestamp())
        .unwrap()
        .unwrap();
    if let CachePayload::SpocAssignments(v) = &mut record.payload {
        let mut second = v.assignments[0].clone();
        second.course_name = "冲突课程".into();
        v.assignments.push(second);
    }
    agenda
        .set_overlay(
            SchoolAgendaOverlay {
                key: SchoolAgendaKey {
                    source: "spoc".into(),
                    upstream_id: "s-a".into(),
                },
                completed_at: Some(q.now),
                completion_override: true,
                hidden: false,
                note: None,
                updated_at: q.now,
                deleted_at: None,
                locally_modified: true,
            },
            q.now,
        )
        .unwrap();
    publish(&cache, scope.query, record.payload, 2);
    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert!(
        !result
            .entries
            .iter()
            .any(|e| matches!(&e.item, AgendaEntryItem::School(v) if v.key.source=="spoc"))
    );
    assert_eq!(
        result
            .sources
            .iter()
            .find(|s| s.feature == ReadonlyFeature::Spoc)
            .unwrap()
            .unprojectable_count,
        2
    );
}
