use crate::facade::*;
use chrono::{Duration, NaiveDate, Utc};
use icalendar::{Calendar, Component, DatePerhapsTime, EventLike, TodoStatus};

fn t(raw: &str) -> AgendaTime {
    AgendaTime::new(raw.parse().unwrap())
}
fn d(raw: &str) -> NaiveDate {
    raw.parse().unwrap()
}
fn now() -> AgendaTime {
    t("2026-04-01T12:00:00+08:00")
}
fn store() -> AgendaStore {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_1d_export_fix/test_data")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    AgendaStore::open(&root, "11111111111111111111111111111111").unwrap()
}
fn options() -> AgendaExportOptions {
    AgendaExportOptions {
        from: d("2026-03-01"),
        to: d("2026-04-01"),
        generated_at: now(),
        include_hidden: false,
        include_completed: true,
    }
}
fn event() -> AgendaItem {
    let mut item = super::super::tests::event();
    item.content.start = Some(t("2026-03-01T09:00:00+08:00"));
    item.content.end = Some(t("2026-03-01T10:00:00+08:00"));
    item
}
fn parse(result: &AgendaExportResult) -> Calendar {
    // 解析后的类型、实际时刻与完成状态断言与序列化文本快照无关。
    result.ics.parse().unwrap()
}

fn only_uid(store: &AgendaStore) -> String {
    let calendar = parse(&store.export_local_ics(&options()).unwrap());
    assert_eq!(calendar.components.len(), 1);
    calendar
        .events()
        .filter_map(|e| e.get_uid())
        .chain(calendar.todos().filter_map(|e| e.get_uid()))
        .next()
        .unwrap()
        .into()
}

#[test]
fn single_event_uid_survives_timed_and_all_day_moves() {
    for scope in [AgendaEditScope::This, AgendaEditScope::All] {
        for all_day in [false, true] {
            let store = store();
            let mut item = event();
            if all_day {
                item.content.all_day = true;
                item.content.start = Some(t("2026-03-03T00:00:00+08:00"));
                item.content.end = Some(t("2026-03-04T00:00:00+08:00"));
            }
            store.create(item.clone()).unwrap();
            let uid = only_uid(&store);
            let mut content = item.content.clone();
            content.start.as_mut().unwrap().datetime += Duration::days(1);
            content.end.as_mut().unwrap().datetime += Duration::days(1);
            store
                .edit(
                    item.id,
                    scope,
                    item.content.start,
                    content.clone(),
                    None,
                    now(),
                )
                .unwrap();
            let calendar = parse(&store.export_local_ics(&options()).unwrap());
            let moved = calendar.events().next().unwrap();
            assert_eq!(store.get(item.id).unwrap().unwrap().content, content);
            assert_eq!(moved.get_uid(), Some(uid.as_str()));
            assert_eq!(
                moved.get_start().unwrap(),
                if all_day {
                    DatePerhapsTime::Date(d("2026-03-04"))
                } else {
                    DatePerhapsTime::from(content.start.unwrap().datetime.with_timezone(&Utc))
                }
            );
        }
    }
}

#[test]
fn single_task_uid_survives_assigning_moving_and_removing_due_date() {
    for scope in [AgendaEditScope::This, AgendaEditScope::All] {
        let store = store();
        let mut item = event();
        item.content.kind = AgendaKind::Task;
        item.content.start = None;
        item.content.end = None;
        store.create(item.clone()).unwrap();
        let uid = only_uid(&store);
        for due in [
            Some(t("2026-03-03T12:00:00+08:00")),
            Some(t("2026-03-04T12:00:00+08:00")),
            None,
        ] {
            let at = item.content.due;
            item.content.due = due;
            store
                .edit(item.id, scope, at, item.content.clone(), None, now())
                .unwrap();
            let calendar = parse(&store.export_local_ics(&options()).unwrap());
            let task = calendar.todos().next().unwrap();
            assert_eq!(task.get_uid(), Some(uid.as_str()));
            assert_eq!(
                task.get_due(),
                due.map(|t| DatePerhapsTime::from(t.datetime.with_timezone(&Utc)))
            );
            assert_eq!(store.get(item.id).unwrap().unwrap().id, item.id);
        }
    }
}

#[test]
fn recurrence_conversion_uses_distinct_occurrences_and_restores_single_identity() {
    let store = store();
    let item = event();
    store.create(item.clone()).unwrap();
    let single_uid = only_uid(&store);
    store
        .edit(
            item.id,
            AgendaEditScope::All,
            None,
            item.content.clone(),
            Some("FREQ=DAILY;COUNT=2".into()),
            now(),
        )
        .unwrap();
    let repeated = parse(&store.export_local_ics(&options()).unwrap());
    let uids: std::collections::BTreeSet<_> =
        repeated.events().map(|e| e.get_uid().unwrap()).collect();
    assert_eq!(uids.len(), 2);
    assert!(!uids.contains(single_uid.as_str()));
    store
        .edit(
            item.id,
            AgendaEditScope::All,
            None,
            item.content,
            None,
            now(),
        )
        .unwrap();
    assert_eq!(only_uid(&store), single_uid);
    store.create(event()).unwrap();
    let distinct = parse(&store.export_local_ics(&options()).unwrap());
    let uids: std::collections::BTreeSet<_> =
        distinct.events().map(|e| e.get_uid().unwrap()).collect();
    assert_eq!(uids.len(), 2);
}

#[test]
fn recurrence_snapshot_keeps_original_identity_after_move_and_exclusion() {
    let store = store();
    let mut item = event();
    item.rrule = Some("FREQ=DAILY;COUNT=4".into());
    let id = item.id;
    store.create(item.clone()).unwrap();
    let before = parse(&store.export_local_ics(&options()).unwrap());
    let before_move = before
        .events()
        .find(|e| e.property_value("X-UBAA-RECURRENCE-ID") == Some("2026-03-03T09:00:00+08:00"))
        .unwrap()
        .get_uid()
        .unwrap();
    store
        .delete(
            id,
            AgendaEditScope::This,
            Some(t("2026-03-02T09:00:00+08:00")),
            now(),
        )
        .unwrap();
    let mut content = item.content;
    content.start = Some(t("2026-03-08T11:00:00+08:00"));
    content.end = Some(t("2026-03-08T12:00:00+08:00"));
    store
        .edit(
            id,
            AgendaEditScope::This,
            Some(t("2026-03-03T09:00:00+08:00")),
            content,
            None,
            now(),
        )
        .unwrap();
    store
        .complete(id, Some(t("2026-03-03T09:00:00+08:00")), true, now())
        .unwrap();
    let result = store.export_local_ics(&options()).unwrap();
    let calendar = parse(&result);
    assert_eq!(result.exported_count, 3);
    let moved = calendar
        .events()
        .find(|e| e.property_value("X-UBAA-COMPLETED") == Some("TRUE"))
        .unwrap();
    assert_eq!(moved.get_uid(), Some(before_move));
    assert_eq!(
        calendar
            .events()
            .map(|e| e.get_uid().unwrap())
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        3
    );
    assert_eq!(
        moved.get_start(),
        Some(DatePerhapsTime::from(
            t("2026-03-08T11:00:00+08:00").datetime.with_timezone(&Utc)
        ))
    );
    assert_eq!(
        moved.property_value("X-UBAA-RECURRENCE-ID"),
        Some("2026-03-03T09:00:00+08:00")
    );
    assert!(calendar.events().all(
        |e| e.property_value("RRULE").is_none() && e.property_value("RECURRENCE-ID").is_none()
    ));
    let mut narrow = options();
    narrow.from = d("2026-03-08");
    narrow.to = d("2026-03-09");
    assert_eq!(
        parse(&store.export_local_ics(&narrow).unwrap())
            .events()
            .next()
            .unwrap()
            .get_uid(),
        moved.get_uid()
    );
}

#[test]
fn date_end_is_exclusive_and_datetime_preserves_campus_instant() {
    let store = store();
    let item = event();
    store.create(item.clone()).unwrap();
    let mut all_day = event();
    all_day.content.all_day = true;
    all_day.content.start = Some(t("2026-03-02T00:00:00+08:00"));
    all_day.content.end = Some(t("2026-03-04T00:00:00+08:00"));
    store.create(all_day).unwrap();
    let result = store.export_local_ics(&options()).unwrap();
    let calendar = parse(&result);
    let timed = calendar
        .events()
        .find(|e| {
            e.get_start()
                == Some(DatePerhapsTime::from(
                    item.content.start.unwrap().datetime.with_timezone(&Utc),
                ))
        })
        .unwrap();
    assert_eq!(
        timed.get_end(),
        Some(DatePerhapsTime::from(
            item.content.end.unwrap().datetime.with_timezone(&Utc)
        ))
    );
    assert_eq!(
        timed.get_created(),
        Some(item.created_at.datetime.with_timezone(&Utc))
    );
    assert_eq!(
        timed.get_last_modified(),
        Some(item.updated_at.datetime.with_timezone(&Utc))
    );
    assert_eq!(
        timed.get_timestamp(),
        Some(now().datetime.with_timezone(&Utc))
    );
    let all_day = calendar
        .events()
        .find(|e| e.get_start() == Some(DatePerhapsTime::Date(d("2026-03-02"))))
        .unwrap();
    assert_eq!(
        all_day.get_end(),
        Some(DatePerhapsTime::Date(d("2026-03-04")))
    );
    let mut narrow = options();
    narrow.from = d("2026-03-04");
    assert_eq!(store.export_local_ics(&narrow).unwrap().exported_count, 0);
}

#[test]
fn due_and_undated_tasks_do_not_invent_start_and_filter_completed() {
    let store = store();
    let mut task = event();
    task.content.kind = AgendaKind::Task;
    task.content.start = None;
    task.content.end = None;
    task.content.due = Some(t("2026-03-02T23:59:59+08:00"));
    task.rrule = Some("FREQ=DAILY;COUNT=2".into());
    store.create(task.clone()).unwrap();
    store
        .complete(task.id, task.content.due, true, now())
        .unwrap();
    let mut undated = task.clone();
    undated.id = uuid::Uuid::new_v4();
    undated.content.due = None;
    undated.rrule = None;
    store.create(undated).unwrap();
    let calendar = parse(&store.export_local_ics(&options()).unwrap());
    assert_eq!(calendar.todos().count(), 3);
    assert!(calendar.todos().all(|e| e.get_start().is_none()));
    let done = calendar
        .todos()
        .find(|e| e.get_status() == Some(TodoStatus::Completed))
        .unwrap();
    assert_eq!(
        done.get_completed(),
        Some(now().datetime.with_timezone(&Utc))
    );
    assert_eq!(
        done.get_due(),
        Some(DatePerhapsTime::from(
            task.content.due.unwrap().datetime.with_timezone(&Utc)
        ))
    );
    assert_eq!(
        calendar.todos().filter(|e| e.get_due().is_none()).count(),
        1
    );
    let mut o = options();
    o.include_completed = false;
    assert_eq!(store.export_local_ics(&o).unwrap().exported_count, 2);
}

#[test]
fn chinese_text_roundtrip_cannot_inject_components_and_lines_are_utf8_octets() {
    let store = store();
    let mut item = event();
    let text = format!(
        "{}\\路径,分号;换行\nEND:VEVENT\nBEGIN:VTODO",
        "中文🙂".repeat(60)
    );
    item.content.title = text.clone();
    item.content.notes = Some(text.clone());
    item.content.location = Some("中文地点,甲;乙\\丙".into());
    store.create(item).unwrap();
    let result = store.export_local_ics(&options()).unwrap();
    assert!(
        result
            .ics
            .split("\r\n")
            .all(|line| line.len() <= 75 && !line.contains(['\r', '\n']))
    );
    let calendar = parse(&result);
    assert_eq!(calendar.events().count(), 1);
    assert_eq!(calendar.todos().count(), 0);
    let e = calendar.events().next().unwrap();
    assert_eq!(e.get_summary(), Some(text.as_str()));
    assert_eq!(e.get_description(), Some(text.as_str()));
    assert_eq!(e.get_location(), Some("中文地点,甲;乙\\丙"));
}

#[test]
fn folding_preserves_spaces_and_escaped_text_at_utf8_boundaries() {
    let store = store();
    let mut expected = std::collections::BTreeSet::new();
    for prefix in 58..=78 {
        let mut item = event();
        // 让普通空格、多字节字符和转义序列分别跨过首行及续行边界。
        let text = format!(
            "{}  中文🙂\\n\\,;\r\n{}  尾部 ",
            "a".repeat(prefix),
            "🙂中 ".repeat(18)
        );
        item.content.title = text.clone();
        item.content.location = Some(text.clone());
        item.content.notes = Some(text.clone());
        store.create(item).unwrap();
        expected.insert(text.replace("\r\n", "\n"));
    }
    let result = store.export_local_ics(&options()).unwrap();
    assert!(result.ics.ends_with("END:VCALENDAR\r\n"));
    assert!(
        result
            .ics
            .split("\r\n")
            .all(|line| line.len() <= 75 && !line.contains(['\r', '\n']))
    );
    let parsed = parse(&result);
    let mut actual = std::collections::BTreeSet::new();
    for e in parsed.events() {
        let summary = e.get_summary().unwrap();
        assert_eq!(e.get_description(), Some(summary));
        assert_eq!(e.get_location(), Some(summary));
        actual.insert(summary.to_owned());
    }
    assert_eq!(actual, expected);
}

#[test]
fn near_limit_notes_roundtrip_with_long_continuations() {
    let store = store();
    let mut item = event();
    let notes = format!("{} 尾部 ", "中文🙂\\,;\n ".repeat(4368));
    assert!((63_000..=65_536).contains(&notes.len()));
    item.content.notes = Some(notes.clone());
    store.create(item).unwrap();
    let result = store.export_local_ics(&options()).unwrap();
    assert!(result.ics.split("\r\n").all(|line| line.len() <= 75));
    let parsed = parse(&result);
    assert_eq!(
        parsed.events().next().unwrap().get_description(),
        Some(notes.as_str())
    );
}

#[test]
fn export_rejects_bad_time_control_characters_and_inactive_store() {
    let store = store();
    let mut item = event();
    item.content.title = "合成\0正文".into();
    store.create(item).unwrap();
    assert_eq!(
        store.export_local_ics(&options()),
        Err(CacheError::InvalidInput)
    );
    let mut o = options();
    o.to = o.from;
    assert_eq!(store.export_local_ics(&o), Err(CacheError::InvalidInput));
    o = options();
    o.generated_at.datetime += Duration::nanoseconds(1);
    assert_eq!(store.export_local_ics(&o), Err(CacheError::InvalidInput));
    store.deactivate().unwrap();
    assert_eq!(
        store.export_local_ics(&options()),
        Err(CacheError::Inactive)
    );
}

fn school(id: &str, timing: AgendaTiming) -> SchoolAgendaItem {
    SchoolAgendaItem {
        key: SchoolAgendaKey {
            source: "spoc".into(),
            upstream_id: id.into(),
        },
        timing,
        sort_time: None,
        title: "合成学校事项".into(),
        subtitle: String::new(),
        location: None,
        status_label: "上游已提交".into(),
        upstream_status: SchoolAgendaStatus::Spoc {
            status: SpocSubmissionStatus::Submitted,
            text: "已提交".into(),
        },
        navigation: AgendaNavigation::Spoc {
            assignment_id: id.into(),
        },
        home_todo: false,
    }
}
#[test]
fn school_local_completion_is_separate_from_upstream_and_unknown_times_are_skipped() {
    let store = store();
    let due = AgendaTiming::Deadline(t("2026-03-02T09:00:00+08:00"));
    let original = school("same-id", due.clone());
    store
        .set_overlay(
            SchoolAgendaOverlay {
                key: original.key.clone(),
                completed_at: None,
                completion_override: true,
                hidden: true,
                note: Some("本机重新挂起".into()),
                updated_at: now(),
                deleted_at: None,
                locally_modified: true,
            },
            now(),
        )
        .unwrap();
    let unknown = vec![
        school(
            "end-only",
            AgendaTiming::Period {
                start: None,
                end: Some(t("2026-03-02T10:00:00+08:00")),
            },
        ),
        school(
            "start-only",
            AgendaTiming::Period {
                start: Some(t("2026-03-02T10:00:00+08:00")),
                end: None,
            },
        ),
        school(
            "placeholder",
            AgendaTiming::AllDay {
                from: d("2026-03-02"),
                to: d("2026-03-03"),
            },
        ),
        school("unknown", AgendaTiming::Undated),
    ];
    let mut all = unknown;
    all.push(original.clone());
    let result = store.export_with_school(&options(), all.clone()).unwrap();
    assert_eq!(
        (result.exported_count, result.skipped_unknown_time_count),
        (0, 4)
    );
    let mut o = options();
    o.include_hidden = true;
    o.include_completed = false;
    let result = store.export_with_school(&o, all).unwrap();
    let calendar = parse(&result);
    let todo = calendar.todos().next().unwrap();
    assert_eq!(todo.get_status(), Some(TodoStatus::NeedsAction));
    assert_eq!(
        todo.property_value("X-UBAA-UPSTREAM-COMPLETED"),
        Some("TRUE")
    );
    assert_eq!(todo.get_description(), Some("本机重新挂起"));
    assert!(todo.get_completed().is_none());
    assert!(todo.get_last_modified().is_none());
    let uid = todo.get_uid().unwrap();
    let mut different_source = original.clone();
    different_source.key.source = "judge".into();
    let other = parse(
        &store
            .export_with_school(&options(), vec![different_source])
            .unwrap(),
    );
    assert_ne!(other.todos().next().unwrap().get_uid(), Some(uid));
    store.clear_overlay(&original.key, now()).unwrap();
    let upstream = parse(
        &store
            .export_with_school(&options(), vec![original.clone()])
            .unwrap(),
    );
    assert_eq!(
        upstream.todos().next().unwrap().get_status(),
        Some(TodoStatus::Completed)
    );
    assert!(upstream.todos().next().unwrap().get_completed().is_none());
}

#[test]
fn note_only_overlay_does_not_supply_school_completion_timestamp() {
    let store = store();
    let original = school(
        "note-only",
        AgendaTiming::Deadline(t("2026-03-02T09:00:00+08:00")),
    );
    // 只写备注且携带非生效完成字段时，不能导出为学校的完成时刻。
    store
        .set_overlay(
            SchoolAgendaOverlay {
                key: original.key.clone(),
                completed_at: Some(now()),
                completion_override: false,
                hidden: false,
                note: None,
                updated_at: now(),
                deleted_at: None,
                locally_modified: true,
            },
            now(),
        )
        .unwrap();
    let note_only = parse(
        &store
            .export_with_school(&options(), vec![original])
            .unwrap(),
    );
    assert!(note_only.todos().next().unwrap().get_completed().is_none());
}

#[test]
fn public_cache_export_retains_availability_and_rejects_another_account() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_1d_export_fix/test_data")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let account = "22222222222222222222222222222222";
    let store = AgendaStore::open(&root, account).unwrap();
    store.create(event()).unwrap();
    let cache = OfflineCache::open(
        &root,
        account,
        "synthetic-only",
        CacheKey::new([3; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let q = AgendaQuery::new(
        ConnectionMode::Direct,
        "synthetic-term".into(),
        options().from,
        options().to,
        now(),
    );
    let result = cache.export_agenda_ics(&store, &q, true).unwrap();
    assert_eq!(result.snapshot.exported_count, 1);
    assert_eq!(result.sources.len(), 8);
    assert!(result.sources.iter().all(|s| s.observations.is_empty()));
    let other = AgendaStore::open(&root, "33333333333333333333333333333333").unwrap();
    assert_eq!(
        cache.export_agenda_ics(&other, &q, true),
        Err(CacheError::InvalidInput)
    );
}

#[test]
fn output_capacity_is_an_error_and_reopening_task_removes_completion_time() {
    let store = store();
    let mut item = event();
    item.content.notes = Some("长".repeat(21_000));
    item.rrule = Some("FREQ=DAILY;COUNT=600".into());
    store.create(item).unwrap();
    let mut wide = options();
    wide.to = d("2028-01-01");
    let started = std::time::Instant::now();
    assert_eq!(store.export_local_ics(&wide), Err(CacheError::Capacity));
    eprintln!(
        "600 次重复、每次 63,000 字节备注的完整导出：{:?}，返回 Capacity，无部分正文",
        started.elapsed()
    );
    let store = self::store();
    let mut task = event();
    task.content.kind = AgendaKind::Task;
    task.content.due = task.content.start.take();
    task.content.end = None;
    store.create(task.clone()).unwrap();
    store
        .complete(task.id, task.content.due, true, now())
        .unwrap();
    let done = parse(&store.export_local_ics(&options()).unwrap());
    store
        .complete(task.id, task.content.due, false, now())
        .unwrap();
    let pending = parse(&store.export_local_ics(&options()).unwrap());
    let done = done.todos().next().unwrap();
    let pending = pending.todos().next().unwrap();
    assert_eq!(done.get_uid(), pending.get_uid());
    assert_eq!(pending.get_status(), Some(TodoStatus::NeedsAction));
    assert!(pending.get_completed().is_none());
}
