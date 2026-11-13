use super::*;

#[test]
fn successful_empty_school_lists_do_not_create_missing_scopes_or_failed_refreshes() {
    let (root, cache, agenda) = opened(ACCOUNT);
    let q = query();
    let at = q.now.datetime.timestamp();
    fixture(&cache);
    let (records, _) = crate::agenda::test_fixture::school_fixture();
    for mut record in records {
        match &mut record.payload {
            CachePayload::BykcChosen(value) => value.courses.clear(),
            CachePayload::SpocAssignments(value) => value.assignments.clear(),
            CachePayload::JudgeSummaries(values) => values.clear(),
            CachePayload::CgyyOrders(value) => {
                value.content.clear();
                value.total_elements = 0;
                value.total_pages = 0;
            }
            CachePayload::SigninToday(values) => values.clear(),
            CachePayload::Exams(value) => {
                value.arranged.clear();
                value.not_arranged.clear();
            }
            CachePayload::YgdkOverview(_) => {}
            _ => panic!("只发布学校日程的合成来源"),
        }
        publish(&cache, record.scope.query, record.payload, at);
    }
    publish(
        &cache,
        CacheQuery::ScheduleWeek {
            term: q.term.clone(),
            week: 11,
        },
        CachePayload::Week(WeeklySchedule::default()),
        at,
    );
    let weeks_scope = CacheScope {
        route: q.route,
        query: CacheQuery::ScheduleWeeks {
            term: q.term.clone(),
        },
    };
    let weeks = cache.read(&weeks_scope, at).unwrap().unwrap();
    publish(&cache, weeks_scope.query, weeks.payload, at);

    let result = cache.query_agenda(&agenda, &q).unwrap();
    assert!(result.entries.iter().all(|entry| {
        matches!(&entry.item, AgendaEntryItem::School(item) if item.key.source == "ygdk")
    }));
    assert_eq!(result.sources.len(), 8);
    for source in result.sources {
        assert!(!source.observations.is_empty(), "{:?}", source.feature);
        assert!(source.missing_scopes.is_empty(), "{:?}", source.feature);
        assert_eq!(source.unprojectable_count, 0, "{:?}", source.feature);
        assert!(
            source
                .observations
                .iter()
                .all(|value| value.is_fresh(at, 300))
        );
    }
    drop((agenda, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn incomplete_refresh_preserves_saved_school_items_and_verification_time() {
    let (root, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let q = query();
    let scope = CacheScope {
        route: q.route,
        query: CacheQuery::JudgeSummaries {
            include_expired: false,
        },
    };
    let before = cache
        .read(&scope, q.now.datetime.timestamp())
        .unwrap()
        .unwrap();
    cache
        .repository(|repository| {
            let ticket = repository.begin_read(scope.clone())?;
            repository.publish(
                &ticket,
                CachePayload::JudgeSummaries(Vec::new()),
                q.now.datetime.timestamp(),
                CacheCompleteness::Partial,
            )
        })
        .unwrap();
    let result = cache.query_agenda(&agenda, &q).unwrap();
    let source = result
        .sources
        .iter()
        .find(|source| source.feature == ReadonlyFeature::Judge)
        .unwrap();
    assert_eq!(source.missing_scopes.len(), 0);
    let observation = &source.observations[0];
    assert!(!observation.last_attempt_succeeded);
    assert_eq!(observation.completeness, CacheCompleteness::Complete);
    assert_eq!(observation.fetched_at, before.fetched_at);
    assert_eq!(observation.last_verified_at, before.last_verified_at);
    assert_eq!(observation.last_attempt_at, q.now.datetime.timestamp());
    assert!(!observation.is_fresh(q.now.datetime.timestamp(), 300));
    assert_eq!(
        cache
            .read(&scope, q.now.datetime.timestamp())
            .unwrap()
            .unwrap()
            .payload,
        before.payload
    );
    assert!(result.entries.iter().any(|entry| {
        matches!(&entry.item, AgendaEntryItem::School(item) if item.key.source == "judge")
    }));
    drop((agenda, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn school_query_reports_uncached_week_without_marking_saved_weeks_failed() {
    let (root, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let mut q = query();
    let at = q.now.datetime.timestamp();
    let weeks = vec![
        Week {
            term: q.term.clone(),
            serial_number: 11,
            start_date: "2026-03-23".into(),
            end_date: "2026-03-29".into(),
            ..Default::default()
        },
        Week {
            term: q.term.clone(),
            serial_number: 12,
            start_date: "2026-03-30".into(),
            end_date: "2026-04-05".into(),
            ..Default::default()
        },
    ];
    publish(
        &cache,
        CacheQuery::ScheduleWeeks {
            term: q.term.clone(),
        },
        CachePayload::Weeks(weeks),
        at,
    );
    publish(
        &cache,
        CacheQuery::ScheduleWeek {
            term: q.term.clone(),
            week: 11,
        },
        CachePayload::Week(WeeklySchedule::default()),
        at,
    );
    q.to = d("2026-04-06");
    let result = cache.query_agenda(&agenda, &q).unwrap();
    let schedule = result
        .sources
        .iter()
        .find(|s| s.feature == ReadonlyFeature::Schedule)
        .unwrap();
    assert_eq!(
        schedule.missing_scopes,
        vec![CacheScope {
            route: q.route,
            query: CacheQuery::ScheduleWeek {
                term: q.term.clone(),
                week: 12
            },
        }]
    );
    assert!(
        schedule
            .observations
            .iter()
            .all(|value| value.last_attempt_succeeded)
    );
    drop((agenda, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn school_query_does_not_borrow_another_academic_term() {
    let (root, cache, agenda) = opened(ACCOUNT);
    fixture(&cache);
    let mut q = query();
    q.term = "another-synthetic-term".into();
    let result = cache.query_agenda(&agenda, &q).unwrap();
    for (feature, query) in [
        (
            ReadonlyFeature::Schedule,
            CacheQuery::ScheduleWeeks {
                term: q.term.clone(),
            },
        ),
        (
            ReadonlyFeature::Exam,
            CacheQuery::Exams {
                term: q.term.clone(),
            },
        ),
    ] {
        let source = result
            .sources
            .iter()
            .find(|s| s.feature == feature)
            .unwrap();
        assert_eq!(source.observations.len(), 0);
        assert_eq!(
            source.missing_scopes,
            vec![CacheScope {
                route: q.route,
                query
            }]
        );
    }
    assert!(
        result
            .sources
            .iter()
            .filter(|source| !matches!(
                source.feature,
                ReadonlyFeature::Schedule | ReadonlyFeature::Exam
            ))
            .all(|source| !source.observations.is_empty())
    );
    drop((agenda, cache));
    std::fs::remove_dir_all(root).unwrap();
}
