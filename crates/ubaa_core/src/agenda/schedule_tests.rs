use super::*;
use crate::{cache::*, domain::agenda::*, domain::*};
fn t(raw: &str) -> AgendaTime {
    AgendaTime::new(raw.parse().unwrap())
}
fn record(query: CacheQuery, payload: CachePayload) -> CacheRecord {
    CacheRecord {
        scope: CacheScope {
            route: ConnectionMode::Direct,
            query,
        },
        payload,
        fetched_at: 1,
        last_attempt_at: 1,
        last_verified_at: 1,
        last_attempt_succeeded: true,
        revision: 1,
        completeness: CacheCompleteness::Complete,
    }
}
fn data() -> (Vec<CacheRecord>, SchoolAgendaContext) {
    let weeks = vec![Week {
        term: "term".into(),
        serial_number: 18,
        start_date: "2026-12-28".into(),
        end_date: "2027-01-03".into(),
        ..Default::default()
    }];
    let courses = vec![
        CourseClass {
            course_code: "course-a".into(),
            course_serial_no: Some("01".into()),
            course_name: "周一课程".into(),
            day_of_week: Some(1),
            begin_section: Some(1),
            end_section: Some(2),
            begin_time: Some("08:20".into()),
            end_time: Some("09:55".into()),
            ..Default::default()
        },
        CourseClass {
            course_code: "course-b".into(),
            course_name: "跨年周五课程".into(),
            day_of_week: Some(5),
            begin_section: Some(14),
            end_section: Some(14),
            ..Default::default()
        },
    ];
    (
        vec![
            record(
                CacheQuery::ScheduleWeeks {
                    term: "term".into(),
                },
                CachePayload::Weeks(weeks),
            ),
            record(
                CacheQuery::ScheduleWeek {
                    term: "term".into(),
                    week: 18,
                },
                CachePayload::Week(WeeklySchedule {
                    arranged_list: courses,
                    section_times: vec![SectionTime {
                        section: 1,
                        start: Some("08:30".into()),
                        end: Some("09:15".into()),
                    }],
                    ..Default::default()
                }),
            ),
        ],
        SchoolAgendaContext {
            now: t("2026-12-28T00:00:00+08:00"),
            current_week: None,
            ygdk: YgdkAgendaSettings::default(),
        },
    )
}
#[test]
fn course_dates_cross_year_and_use_calendar_but_keep_raw_graduate_times() {
    let (records, ctx) = data();
    let items = project_school_agenda(&records, &ctx).unwrap();
    assert_eq!(items.len(), 3);
    assert_eq!(
        items[0].timing,
        AgendaTiming::Period {
            start: Some(t("2026-12-28T08:00:00+08:00")),
            end: Some(t("2026-12-28T08:45:00+08:00"))
        }
    );
    assert_eq!(
        items[2].timing,
        AgendaTiming::Period {
            start: Some(t("2027-01-01T21:30:00+08:00")),
            end: Some(t("2027-01-01T22:15:00+08:00"))
        }
    );
    assert_eq!(
        items[0].upstream_status,
        SchoolAgendaStatus::Schedule {
            begin_time: Some("08:20".into()),
            end_time: Some("09:55".into())
        }
    );
    assert_eq!(
        items[0].key.upstream_id,
        "[\"term\",\"course-a\",\"01\",18,1,1]"
    );
}
#[test]
fn unknown_weekday_conflicting_weeks_and_invalid_dates_cannot_claim_empty_day() {
    let (records, ctx) = data();
    for variant in 0..3 {
        let mut records = records.clone();
        match variant {
            0 => {
                if let CachePayload::Week(v) = &mut records[1].payload {
                    v.arranged_list[1].day_of_week = None;
                }
            }
            1 => {
                if let CachePayload::Weeks(v) = &mut records[0].payload {
                    v.push(v[0].clone());
                }
            }
            _ => {
                if let CachePayload::Weeks(v) = &mut records[0].payload {
                    v[0].start_date = "2026-02-30".into();
                }
            }
        }
        assert_eq!(project_school_agenda(&records, &ctx).unwrap().len(), 0);
    }
}
#[test]
fn section_after_calendar_uses_explicit_then_unique_course_boundaries() {
    let (mut records, ctx) = data();
    if let CachePayload::Week(v) = &mut records[1].payload {
        v.arranged_list.truncate(1);
        let c = &mut v.arranged_list[0];
        c.begin_section = Some(15);
        c.end_section = Some(15);
        c.begin_time = Some("22:30".into());
        c.end_time = Some("23:15".into());
    }
    let before = project_school_agenda(&records, &ctx).unwrap();
    assert_eq!(
        before[0].timing.sort_time(),
        Some(t("2026-12-28T22:30:00+08:00"))
    );
    if let CachePayload::Week(v) = &mut records[1].payload {
        v.section_times = vec![SectionTime {
            section: 15,
            start: Some("22:40".into()),
            end: Some("23:25".into()),
        }];
    }
    let explicit = project_school_agenda(&records, &ctx).unwrap();
    assert_eq!(
        explicit[0].timing.sort_time(),
        Some(t("2026-12-28T22:40:00+08:00"))
    );
    if let CachePayload::Week(v) = &mut records[1].payload {
        v.section_times.push(SectionTime {
            section: 15,
            start: Some("22:50".into()),
            end: Some("23:35".into()),
        });
    }
    let conflicting = project_school_agenda(&records, &ctx).unwrap();
    assert!(matches!(conflicting[0].timing, AgendaTiming::AllDay { .. }));
    assert!(!conflicting[0].timing.is_soon_at(ctx.now));
}
#[test]
fn weekly_cache_date_strings_use_existing_semester_normalization() {
    let (mut records, ctx) = data();
    if let CachePayload::Weeks(weeks) = &mut records[0].payload {
        weeks[0].start_date = "2026-12-28 00:00:00".into();
        weeks[0].end_date = "2027-1-3T00:00:00".into();
    }
    assert_eq!(project_school_agenda(&records, &ctx).unwrap().len(), 3);
}
#[test]
fn reversed_period_outside_calendar_stays_unknown_like_home_course_period() {
    let (mut records, ctx) = data();
    if let CachePayload::Week(v) = &mut records[1].payload {
        v.arranged_list.truncate(1);
        v.arranged_list[0].begin_section = Some(15);
        v.arranged_list[0].end_section = Some(15);
        v.section_times = vec![SectionTime {
            section: 15,
            start: Some("23:00".into()),
            end: Some("22:00".into()),
        }];
    }
    let rows = project_school_agenda(&records, &ctx).unwrap();
    assert!(matches!(rows[0].timing, AgendaTiming::AllDay { .. }));
    assert!(!rows[0].timing.is_soon_at(ctx.now));
}
#[test]
fn consecutive_sections_are_separate_occurrences_with_distinct_overlay_keys() {
    let (records, ctx) = data();
    let items = project_school_agenda(&records, &ctx).unwrap();
    assert_eq!(items.len(), 3);
    assert_eq!(
        items[0].timing,
        AgendaTiming::Period {
            start: Some(t("2026-12-28T08:00:00+08:00")),
            end: Some(t("2026-12-28T08:45:00+08:00"))
        }
    );
    assert_eq!(
        items[1].timing,
        AgendaTiming::Period {
            start: Some(t("2026-12-28T08:50:00+08:00")),
            end: Some(t("2026-12-28T09:35:00+08:00"))
        }
    );
    assert_ne!(items[0].key, items[1].key);
    assert!(matches!(
        items[1].navigation,
        AgendaNavigation::Schedule { section: 2, .. }
    ));
}
#[test]
fn excessive_section_expansion_returns_capacity_instead_of_partial_success() {
    let (mut records, ctx) = data();
    if let CachePayload::Week(v) = &mut records[1].payload {
        v.arranged_list.truncate(1);
        v.arranged_list[0].end_section = Some(i32::from(u16::MAX) + 1);
    }
    assert_eq!(
        project_school_agenda(&records, &ctx),
        Err(CacheError::Capacity)
    );
}
