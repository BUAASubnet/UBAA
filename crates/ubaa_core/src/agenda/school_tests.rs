use super::*;
use crate::{cache::*, domain::agenda::*, domain::*};
use chrono::Duration;
fn t(raw: &str) -> AgendaTime {
    AgendaTime::new(raw.parse().unwrap())
}
fn d(raw: &str) -> chrono::NaiveDate {
    raw.parse().unwrap()
}
fn fixture() -> (Vec<CacheRecord>, SchoolAgendaContext) {
    let (records, now) = super::test_fixture::school_fixture();
    (
        records,
        SchoolAgendaContext {
            now,
            current_week: Some(Week {
                term: "synthetic-term".into(),
                serial_number: 11,
                cur_week: true,
                start_date: "2026-03-23".into(),
                end_date: "2026-03-29".into(),
                ..Default::default()
            }),
            ygdk: YgdkAgendaSettings::default(),
        },
    )
}
fn home(records: &[CacheRecord], context: &SchoolAgendaContext) -> Vec<SchoolAgendaItem> {
    project_school_agenda(records, context)
        .unwrap()
        .into_iter()
        .filter(|v| v.home_todo)
        .collect()
}
#[test]
fn home_fixture_preserves_mixed_order_navigation_and_exact_times() {
    let (records, ctx) = fixture();
    let rows = home(&records, &ctx);
    assert_eq!(
        rows.iter()
            .map(|v| v.key.source.as_str())
            .collect::<Vec<_>>(),
        ["bykc", "signin", "judge", "spoc", "cgyy", "exam", "ygdk"]
    );
    assert_eq!(
        rows[0].navigation,
        AgendaNavigation::Bykc { course_id: 101 }
    );
    assert_eq!(
        rows[2].navigation,
        AgendaNavigation::Judge {
            course_id: "j-c".into(),
            assignment_id: "j-a".into()
        }
    );
    assert_eq!(rows[2].status_label, "待完成");
    assert_eq!(
        rows[3].timing,
        AgendaTiming::Deadline(t("2026-03-24T12:30:00+08:00"))
    );
    assert_eq!(rows[5].subtitle, "合成考场 · 座位 12");
    assert_eq!(
        rows[6].timing,
        AgendaTiming::Deadline(t("2026-03-29T23:59:59+08:00"))
    );
    assert_eq!(rows[1].status_label, "状态待更新");
}
#[test]
fn urgency_is_strictly_future_and_at_most_48_hours() {
    let now = t("2026-10-25T12:00:00+08:00");
    for (seconds, soon) in [
        (0, false),
        (1, true),
        (172_800, true),
        (172_801, false),
        (-1, false),
    ] {
        let time = AgendaTime::new(now.datetime + Duration::seconds(seconds));
        assert_eq!(AgendaTiming::Deadline(time).is_soon_at(now), soon);
        assert_eq!(
            AgendaTiming::Period {
                start: Some(time),
                end: None
            }
            .is_soon_at(now),
            soon
        );
    }
    assert!(
        !AgendaTiming::AllDay {
            from: d("2026-10-26"),
            to: d("2026-10-27")
        }
        .is_soon_at(now)
    );
    assert!(
        !AgendaTiming::Period {
            start: None,
            end: Some(now)
        }
        .is_soon_at(now)
    );
}
#[test]
fn bykc_room_boundaries_and_raw_cancellation_states_match_home() {
    let (mut records, ctx) = fixture();
    if let CachePayload::BykcChosen(v) = &mut records[0].payload {
        v.courses[0].course_end_date = Some("2026-03-24 12:00".into());
    }
    if let CachePayload::CgyyOrders(v) = &mut records[3].payload {
        v.content[0].reservation_end_date = Some("2026-03-24 12:00".into());
    }
    let rows = home(&records, &ctx);
    assert!(rows.iter().any(|v| v.key.source == "bykc"));
    assert!(!rows.iter().any(|v| v.key.source == "cgyy"));
    for (status, check) in [(Some(2), Some(2)), (Some(1), Some(-1))] {
        if let CachePayload::CgyyOrders(v) = &mut records[3].payload {
            v.content[0].reservation_end_date = Some("2026-03-24 15:00".into());
            v.content[0].order_status = status;
            v.content[0].check_status = check;
        }
        assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "cgyy"));
        assert!(
            project_school_agenda(&records, &ctx)
                .unwrap()
                .iter()
                .any(|v| v.upstream_status
                    == SchoolAgendaStatus::Cgyy {
                        order_status: status,
                        check_status: check
                    })
        );
    }
}
#[test]
fn signin_today_and_ten_minute_window_never_restore_write_authority() {
    let (mut records, ctx) = fixture();
    let original = records[4].clone();
    for (start, end, status, visible) in [
        ("12:10", "13:00", Some(0), true),
        ("12:11", "13:00", Some(0), false),
        ("11:00", "12:00", Some(0), false),
        ("12:05", "13:00", None, false),
        ("25:00", "26:00", Some(0), false),
    ] {
        records[4] = original.clone();
        if let CachePayload::SigninToday(v) = &mut records[4].payload {
            v[0].class_begin_time = start.into();
            v[0].class_end_time = end.into();
            v[0].sign_status = status;
        }
        assert_eq!(
            home(&records, &ctx)
                .iter()
                .any(|v| v.key.source == "signin"),
            visible
        );
    }
    records[4] = original;
    records[4].scope.query = CacheQuery::SigninToday {
        date: "20260323".into(),
    };
    assert!(
        !home(&records, &ctx)
            .iter()
            .any(|v| v.key.source == "signin")
    );
}
#[test]
fn spoc_and_judge_use_status_and_deadline_without_progress_inference() {
    let (mut records, ctx) = fixture();
    for (status, start, due, visible) in [
        (
            SpocSubmissionStatus::Unsubmitted,
            None,
            "2026-03-24 12:01",
            true,
        ),
        (
            SpocSubmissionStatus::Submitted,
            None,
            "2026-03-24 12:01",
            false,
        ),
        (
            SpocSubmissionStatus::Unknown,
            None,
            "2026-03-24 12:01",
            false,
        ),
        (
            SpocSubmissionStatus::Unsubmitted,
            Some("2026-03-24 12:01"),
            "2026-03-24 13:00",
            false,
        ),
        (
            SpocSubmissionStatus::Unsubmitted,
            None,
            "2026-03-24 12:00",
            false,
        ),
        (
            SpocSubmissionStatus::Unsubmitted,
            None,
            "2026-03-99 12:00",
            false,
        ),
    ] {
        if let CachePayload::SpocAssignments(v) = &mut records[1].payload {
            v.assignments[0].submission_status = status;
            v.assignments[0].start_time = start.map(str::to_string);
            v.assignments[0].due_time = Some(due.into());
        }
        assert_eq!(
            home(&records, &ctx).iter().any(|v| v.key.source == "spoc"),
            visible
        );
    }
    for (status, visible) in [
        (JudgeSubmissionStatus::Partial, true),
        (JudgeSubmissionStatus::Unsubmitted, true),
        (JudgeSubmissionStatus::Submitted, false),
        (JudgeSubmissionStatus::Unknown, false),
    ] {
        if let CachePayload::JudgeSummaries(v) = &mut records[2].payload {
            v[0].submission_status = status;
            v[0].submitted_count = 999;
        }
        assert_eq!(
            home(&records, &ctx).iter().any(|v| v.key.source == "judge"),
            visible
        );
    }
}
#[test]
fn exam_arrangement_unknown_time_and_strict_end_boundary() {
    let (mut records, mut ctx) = fixture();
    if let CachePayload::Exams(v) = &mut records[5].payload {
        let base = v.arranged[0].clone();
        v.arranged = [
            ("明天考试", "2026-03-25", Some("09:00"), Some("11:00")),
            ("已结束", "2026-03-24", Some("08:00"), Some("10:00")),
            ("进行中", "2026-03-24", Some("11:00"), Some("13:00")),
            ("日期错误", "2026-02-30", Some("13:00"), Some("15:00")),
            ("时间待定", "2026-03-26", None, None),
        ]
        .into_iter()
        .map(|(title, date, start, end)| Exam {
            course_name: title.into(),
            task_id: Some(title.into()),
            exam_date: Some(date.into()),
            start_time: start.map(str::to_string),
            end_time: end.map(str::to_string),
            ..base.clone()
        })
        .collect();
        v.not_arranged.push(Exam {
            course_name: "未安排".into(),
            ..base
        });
    }
    let rows = home(&records, &ctx)
        .into_iter()
        .filter(|v| v.key.source == "exam")
        .collect::<Vec<_>>();
    assert_eq!(
        rows.iter().map(|v| v.title.as_str()).collect::<Vec<_>>(),
        ["进行中", "明天考试", "时间待定"]
    );
    assert_eq!(rows[0].status_label, "考试中");
    assert!(matches!(rows[2].timing, AgendaTiming::AllDay { .. }));
    ctx.now = t("2026-03-24T13:00:00+08:00");
    assert!(home(&records, &ctx).iter().any(|v| v.title == "进行中"));
    ctx.now = t("2026-03-24T13:00:01+08:00");
    assert!(!home(&records, &ctx).iter().any(|v| v.title == "进行中"));
}
#[test]
fn ygdk_preferences_thresholds_and_partial_evidence_match_home() {
    let (records, ctx) = fixture();
    for number in [10, 11, 14, 15] {
        let mut ctx = ctx.clone();
        ctx.current_week.as_mut().unwrap().serial_number = number;
        assert_eq!(
            home(&records, &ctx).iter().any(|v| v.key.source == "ygdk"),
            (11..=14).contains(&number)
        );
    }
    for settings in [
        YgdkAgendaSettings {
            enabled: false,
            ..Default::default()
        },
        YgdkAgendaSettings {
            week_done: true,
            ..Default::default()
        },
        YgdkAgendaSettings {
            term_done: true,
            ..Default::default()
        },
    ] {
        let mut ctx = ctx.clone();
        ctx.ygdk = settings;
        assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "ygdk"));
    }
    for (week, term, complete) in [
        (None, 15, true),
        (Some(4), 15, true),
        (Some(3), 16, true),
        (Some(0), 0, false),
    ] {
        let mut records = records.clone();
        if let CachePayload::YgdkOverview(v) = &mut records[6].payload {
            v.summary.week_count = week;
            v.summary.term_count = term;
        }
        records[6].completeness = if complete {
            CacheCompleteness::Complete
        } else {
            CacheCompleteness::Partial
        };
        assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "ygdk"));
    }
}
#[test]
fn equal_times_keep_source_order_and_wrong_views_are_not_sources() {
    let (mut records, ctx) = fixture();
    if let CachePayload::SpocAssignments(v) = &mut records[1].payload {
        v.assignments[0].due_time = Some("2026-03-24 12:20".into());
    }
    records.reverse();
    let rows = home(&records, &ctx);
    let tasks = rows
        .iter()
        .filter(|v| ["spoc", "judge"].contains(&v.key.source.as_str()))
        .map(|v| v.key.source.as_str())
        .collect::<Vec<_>>();
    assert_eq!(tasks, ["spoc", "judge"]);
    for r in &mut records {
        if matches!(r.scope.query, CacheQuery::BykcChosen) {
            r.scope.query = CacheQuery::BykcDetail { course_id: 101 };
        }
    }
    assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "bykc"));
}
#[test]
fn exam_fractional_end_uses_existing_finish_rule_without_inventing_known_endpoint() {
    let (mut records, mut ctx) = fixture();
    if let CachePayload::Exams(v) = &mut records[5].payload {
        v.arranged[0].exam_date = Some("2026-03-24".into());
        v.arranged[0].end_time = Some("13:00:00.500".into());
    }
    ctx.now = t("2026-03-24T13:00:01+08:00");
    assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "exam"));
}
#[test]
fn old_ygdk_period_and_non_ascii_time_cannot_become_current_reminders() {
    let (mut records, ctx) = fixture();
    if let CacheQuery::YgdkOverviewPeriod { week_start, .. } = &mut records[6].scope.query {
        *week_start = "2026-03-16".into();
    }
    assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "ygdk"));
    if let CachePayload::SpocAssignments(v) = &mut records[1].payload {
        v.assignments[0].due_time = Some("٢٠٢٦-٠٣-٢٥ ١٢:٣٠".into());
    }
    assert!(!home(&records, &ctx).iter().any(|v| v.key.source == "spoc"));
}
#[test]
fn signin_key_survives_time_changes_and_exam_occurrence_key_tracks_time() {
    let (mut records, ctx) = fixture();
    let before = project_school_agenda(&records, &ctx).unwrap();
    if let CachePayload::Exams(v) = &mut records[5].payload {
        v.arranged[0].start_time = Some("10:00".into());
    }
    if let CachePayload::SigninToday(v) = &mut records[4].payload {
        v[0].class_begin_time = "12:00".into();
    }
    let after = project_school_agenda(&records, &ctx).unwrap();
    assert_eq!(
        before
            .iter()
            .find(|v| v.key.source == "signin")
            .unwrap()
            .key,
        after.iter().find(|v| v.key.source == "signin").unwrap().key
    );
    assert_ne!(
        before.iter().find(|v| v.key.source == "exam").unwrap().key,
        after.iter().find(|v| v.key.source == "exam").unwrap().key
    );
}

#[test]
fn exams_sharing_a_task_id_keep_separate_dates_and_keys() {
    let (mut records, ctx) = fixture();
    if let CachePayload::Exams(v) = &mut records[5].payload {
        let mut second = v.arranged[0].clone();
        second.exam_date = Some("2026-03-26".into());
        v.arranged.push(second);
    }
    let exams = home(&records, &ctx)
        .into_iter()
        .filter(|v| v.key.source == "exam")
        .collect::<Vec<_>>();
    assert_eq!(exams.len(), 2);
    assert_ne!(exams[0].key, exams[1].key);
}
#[test]
fn conflicting_stable_keys_are_not_arbitrarily_merged() {
    let (mut records, ctx) = fixture();
    if let CachePayload::SpocAssignments(v) = &mut records[1].payload {
        let mut second = v.assignments[0].clone();
        second.submission_status = SpocSubmissionStatus::Submitted;
        v.assignments.push(second);
    }
    assert!(
        !project_school_agenda(&records, &ctx)
            .unwrap()
            .iter()
            .any(|v| v.key.source == "spoc")
    );
}
#[test]
fn exam_with_unknown_start_sorts_at_midnight_without_inventing_start() {
    let (mut records, ctx) = fixture();
    if let CachePayload::Exams(v) = &mut records[5].payload {
        v.arranged[0].exam_date = Some("2026-03-24".into());
        v.arranged[0].start_time = None;
        v.arranged[0].end_time = Some("12:00".into());
    }
    let items = home(&records, &ctx);
    assert_eq!(items[0].key.source, "exam");
    assert_eq!(
        items[0].timing,
        AgendaTiming::Period {
            start: None,
            end: Some(t("2026-03-24T12:00:00+08:00"))
        }
    );
    assert!(!items[0].timing.is_soon_at(ctx.now));
}
