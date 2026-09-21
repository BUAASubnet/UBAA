use super::*;
use crate::domain::{ConnectionMode, TodayClass};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);
const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";

fn root() -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "ubaa-cache-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
}
fn scope() -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-09-17".into(),
        },
    }
}
fn payload(title: &str) -> CachePayload {
    CachePayload::Today(vec![TodayClass {
        biz_name: title.into(),
        ..Default::default()
    }])
}
fn open(root: &std::path::Path) -> OfflineRepository {
    OfflineRepository::open(
        root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap()
}

#[test]
fn encrypted_content_survives_reopen_without_network_or_plaintext() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish(
        &ticket,
        payload("合成离线课程"),
        100,
        CacheCompleteness::Complete,
    )
    .unwrap();
    drop(repo);
    let mut reopened = open(&root);
    let cached = reopened.read(&scope(), 120).unwrap().unwrap();
    assert_eq!(cached.payload, payload("合成离线课程"));
    assert_eq!(cached.fetched_at, 100);
    assert!(cached.is_fresh(120, 30));
    assert!(!cached.is_fresh(99, 30));
    let bytes = std::fs::read(reopened.path()).unwrap();
    assert!(
        !bytes
            .windows("合成离线课程".len())
            .any(|w| w == "合成离线课程".as_bytes())
    );
    assert!(!bytes.windows(10).any(|w| w == b"2026-09-17"));
    assert!(
        OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([8; 32]),
            CacheLimits::default()
        )
        .is_err()
    );
    drop(reopened);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn exact_date_route_account_and_query_are_isolated() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish(
        &ticket,
        payload("合成课程"),
        100,
        CacheCompleteness::Complete,
    )
    .unwrap();
    let mut other = scope();
    other.route = ConnectionMode::WebVpn;
    assert!(repo.read(&other, 101).unwrap().is_none());
    other = scope();
    other.query = CacheQuery::ScheduleToday {
        date: "2026-09-18".into(),
    };
    assert!(repo.read(&other, 101).unwrap().is_none());
    let mut account = OfflineRepository::open(
        &root,
        "abcdef0123456789abcdef0123456789",
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    assert!(account.read(&scope(), 101).unwrap().is_none());
    drop((repo, account));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn failed_partial_and_late_reads_never_replace_a_successful_set() {
    let root = root();
    let mut repo = open(&root);
    let first = repo.begin_read(scope()).unwrap();
    repo.publish(&first, payload("原课程"), 100, CacheCompleteness::Complete)
        .unwrap();
    let old = repo.begin_read(scope()).unwrap();
    let latest = repo.begin_read(scope()).unwrap();
    repo.record_failure(&latest, 120).unwrap();
    assert_eq!(
        repo.publish(&old, payload("迟到课程"), 110, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    );
    let partial = repo.begin_read(scope()).unwrap();
    assert_eq!(
        repo.publish(
            &partial,
            CachePayload::Today(vec![]),
            130,
            CacheCompleteness::Partial
        )
        .unwrap(),
        CachePublication::Preserved
    );
    let saved = repo.read(&scope(), 131).unwrap().unwrap();
    assert_eq!(saved.payload, payload("原课程"));
    assert_eq!(saved.fetched_at, 100);
    assert_eq!(saved.last_attempt_at, 130);
    let empty = repo.begin_read(scope()).unwrap();
    repo.publish(
        &empty,
        CachePayload::Today(vec![]),
        140,
        CacheCompleteness::Complete,
    )
    .unwrap();
    assert_eq!(
        repo.read(&scope(), 140).unwrap().unwrap().payload,
        CachePayload::Today(vec![])
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn logout_clear_and_another_handle_invalidate_late_publications() {
    let root = root();
    let mut repo = open(&root);
    let old = repo.begin_read(scope()).unwrap();
    let mut second = open(&root);
    second.clear().unwrap();
    assert_eq!(
        repo.publish(&old, payload("旧课程"), 100, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    );
    let pending = second.begin_read(scope()).unwrap();
    second.deactivate().unwrap();
    assert_eq!(
        second.publish(
            &pending,
            payload("旧课程"),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Inactive)
    );
    drop((repo, second));
    let mut reopened = open(&root);
    assert_eq!(reopened.read(&scope(), 110), Err(CacheError::Inactive));
    reopened.activate().unwrap();
    assert!(reopened.read(&scope(), 110).unwrap().is_none());
    drop(reopened);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn capacity_failure_preserves_the_previous_record() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits {
            soft_bytes: 1_024,
            hard_bytes: 2_048,
        },
    )
    .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish(&ticket, payload("课程"), 100, CacheCompleteness::Complete)
        .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            payload(&"课程".repeat(2_000)),
            110,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Capacity)
    );
    assert_eq!(
        repo.read(&scope(), 111).unwrap().unwrap().payload,
        payload("课程")
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn a_failed_attempt_in_the_same_second_is_not_fresh() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish(&ticket, payload("课程"), 100, CacheCompleteness::Complete)
        .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.record_failure(&ticket, 100).unwrap();
    assert!(!repo.read(&scope(), 100).unwrap().unwrap().is_fresh(100, 30));
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn damaged_record_is_isolated_and_another_date_remains_readable() {
    let root = root();
    let mut repo = open(&root);
    let first = repo.begin_read(scope()).unwrap();
    repo.publish(&first, payload("课程"), 100, CacheCompleteness::Complete)
        .unwrap();
    let mut next = scope();
    next.query = CacheQuery::ScheduleToday {
        date: "2026-09-18".into(),
    };
    let second = repo.begin_read(next.clone()).unwrap();
    repo.publish(&second, payload("另一日"), 100, CacheCompleteness::Complete)
        .unwrap();
    let db = rusqlite::Connection::open(repo.path()).unwrap();
    db.execute("UPDATE entries SET body=zeroblob(length(body)) WHERE key=(SELECT key FROM entries ORDER BY rowid LIMIT 1)", []).unwrap();
    assert_eq!(repo.read(&scope(), 101), Err(CacheError::Corrupt));
    assert!(repo.read(&scope(), 101).unwrap().is_none());
    assert_eq!(
        repo.read(&next, 101).unwrap().unwrap().payload,
        payload("另一日")
    );
    drop((db, repo));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn incompatible_version_and_scope_mismatch_never_overwrite_data() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            CachePayload::JudgeCourses(vec![]),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::InvalidInput)
    );
    assert!(repo.read(&scope(), 100).unwrap().is_none());
    let path = repo.path().to_owned();
    drop(repo);
    let db = rusqlite::Connection::open(&path).unwrap();
    db.pragma_update(None, "user_version", 999).unwrap();
    drop(db);
    let before = std::fs::read(&path).unwrap();
    assert!(matches!(
        OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([7; 32]),
            CacheLimits::default()
        ),
        Err(CacheError::UnsupportedVersion)
    ));
    assert_eq!(std::fs::read(path).unwrap(), before);
    std::fs::remove_dir_all(root).unwrap();
}

#[cfg(unix)]
#[test]
fn cache_database_and_journal_symlinks_are_rejected() {
    for suffix in ["", "-journal", "-wal", "-shm"] {
        let root = root();
        let repo = open(&root);
        let path = repo.path().to_owned();
        drop(repo);
        let target = root.join("do-not-touch");
        std::fs::write(&target, b"synthetic").unwrap();
        let link = std::path::PathBuf::from(format!("{}{suffix}", path.display()));
        if suffix.is_empty() {
            std::fs::remove_file(&link).unwrap();
        }
        std::os::unix::fs::symlink(&target, link).unwrap();
        assert!(matches!(
            OfflineRepository::open(
                &root,
                ACCOUNT,
                CacheKey::new([7; 32]),
                CacheLimits::default()
            ),
            Err(CacheError::Unavailable)
        ));
        assert_eq!(std::fs::read(target).unwrap(), b"synthetic");
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn sqlite_disk_full_rolls_back_without_losing_previous_content() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish(&ticket, payload("原课程"), 100, CacheCompleteness::Complete)
        .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    let pages: i64 = repo
        .db
        .pragma_query_value(None, "page_count", |r| r.get(0))
        .unwrap();
    repo.db
        .pragma_update(None, "max_page_count", pages)
        .unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            payload(&"合成大课程".repeat(20_000)),
            110,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Capacity)
    );
    assert_eq!(
        repo.read(&scope(), 111).unwrap().unwrap().payload,
        payload("原课程")
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn another_account_ticket_and_repeated_publication_are_rejected() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    let mut other = OfflineRepository::open(
        &root,
        "abcdef0123456789abcdef0123456789",
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let _ = other.begin_read(scope()).unwrap();
    assert_eq!(
        other.publish(
            &ticket,
            payload("错误账号"),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    repo.publish(&ticket, payload("原课程"), 100, CacheCompleteness::Complete)
        .unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            payload("重复发布"),
            110,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    drop((repo, other));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn encrypted_rows_cannot_be_swapped_between_queries() {
    let root = root();
    let mut repo = open(&root);
    let first = repo.begin_read(scope()).unwrap();
    repo.publish(&first, payload("今日"), 100, CacheCompleteness::Complete)
        .unwrap();
    let mut next = scope();
    next.query = CacheQuery::ScheduleToday {
        date: "2026-09-18".into(),
    };
    let second = repo.begin_read(next.clone()).unwrap();
    repo.publish(&second, payload("次日"), 100, CacheCompleteness::Complete)
        .unwrap();
    repo.db.execute("UPDATE entries SET body=(SELECT body FROM entries ORDER BY rowid LIMIT 1) WHERE rowid=(SELECT MAX(rowid) FROM entries)", []).unwrap();
    assert_eq!(repo.read(&next, 101), Err(CacheError::Corrupt));
    assert_eq!(
        repo.read(&scope(), 101).unwrap().unwrap().payload,
        payload("今日")
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn soft_limit_evicts_old_detail_before_a_saved_schedule() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits {
            soft_bytes: 1_500,
            hard_bytes: 4_000,
        },
    )
    .unwrap();
    let schedule = repo.begin_read(scope()).unwrap();
    repo.publish(&schedule, payload("课表"), 100, CacheCompleteness::Complete)
        .unwrap();
    let detail_scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::JudgeDetail {
            course_id: "1".into(),
            assignment_id: "2".into(),
        },
    };
    let detail = repo.begin_read(detail_scope.clone()).unwrap();
    repo.publish(
        &detail,
        CachePayload::JudgeDetail(Box::new(crate::domain::JudgeAssignmentDetail {
            course_id: "1".into(),
            assignment_id: "2".into(),
            title: "历史作业".repeat(50),
            ..Default::default()
        })),
        101,
        CacheCompleteness::Complete,
    )
    .unwrap();
    let mut next = scope();
    next.query = CacheQuery::ScheduleToday {
        date: "2026-09-18".into(),
    };
    let ticket = repo.begin_read(next.clone()).unwrap();
    repo.publish(&ticket, payload("新课表"), 102, CacheCompleteness::Complete)
        .unwrap();
    assert!(repo.read(&detail_scope, 103).unwrap().is_none());
    assert!(repo.read(&scope(), 103).unwrap().is_some());
    assert!(repo.read(&next, 103).unwrap().is_some());
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn read_ticket_validation_detects_newer_request_and_cross_handle_logout() {
    let root = root();
    let mut first = open(&root);
    let old = first.begin_read(scope()).unwrap();
    first.validate_read(&old).unwrap();
    let mut second = open(&root);
    let latest = second.begin_read(scope()).unwrap();
    assert_eq!(first.validate_read(&old), Err(CacheError::Superseded));
    first.validate_read(&latest).unwrap();
    second.deactivate().unwrap();
    assert_eq!(first.validate_read(&latest), Err(CacheError::Inactive));
    drop(first);
    drop(second);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn scan_lease_renewal_preserves_long_progress_but_cannot_reclaim_superseded_scope() {
    let root = root();
    let mut repository = open(&root);
    let mut parent = repository.begin_read(scope()).unwrap();
    let mut course_review = repository
        .begin_read(CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::JudgeCourseReview {
                course_id: "long-course".into(),
            },
        })
        .unwrap();
    for index in 0..4100 {
        repository.renew_read(&mut parent).unwrap();
        repository.renew_read(&mut course_review).unwrap();
        let child = repository
            .begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query: CacheQuery::JudgeAssignments {
                    course_id: format!("{index}"),
                },
            })
            .unwrap();
        repository
            .publish_guarded(
                &child,
                &parent,
                CachePayload::JudgeAssignments(Vec::new()),
                100,
                CacheCompleteness::Complete,
            )
            .unwrap();
    }
    repository.validate_read(&parent).unwrap();
    repository.validate_read(&course_review).unwrap();
    let replacement = repository.begin_read(scope()).unwrap();
    assert_eq!(
        repository.renew_read(&mut parent),
        Err(CacheError::Superseded)
    );
    repository.validate_read(&replacement).unwrap();
    let child_scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::JudgeAssignments {
            course_id: "late".into(),
        },
    };
    let child = repository.begin_read(child_scope.clone()).unwrap();
    assert_eq!(
        repository.publish_guarded(
            &child,
            &parent,
            CachePayload::JudgeAssignments(Vec::new()),
            200,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    assert!(repository.read(&child_scope, 200).unwrap().is_none());
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn reused_payload_keeps_its_original_source_time_and_new_attempt_time() {
    let root = root();
    let mut repository = open(&root);
    let ticket = repository.begin_read(scope()).unwrap();
    repository
        .publish_observed(
            &ticket,
            payload("合成复用"),
            CacheObservation {
                source_at: 100,
                attempted_at: 200,
            },
            CacheCompleteness::Complete,
        )
        .unwrap();
    let record = repository.read(&scope(), 200).unwrap().unwrap();
    assert_eq!(record.fetched_at, 100);
    assert_eq!(record.last_verified_at, 100);
    assert_eq!(record.last_attempt_at, 200);
    assert!(!record.is_fresh(200, 1000));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 学业范围不串学期周次校区日期() {
    use crate::domain::GradeData;
    let root = root();
    let mut repo = open(&root);
    let queries = [
        CacheQuery::ScheduleWeeks {
            term: "2025-2026-1".into(),
        },
        CacheQuery::ScheduleWeek {
            term: "2025-2026-1".into(),
            week: 1,
        },
        CacheQuery::Exams {
            term: "2025-2026-1".into(),
        },
        CacheQuery::Grades {
            term: "2025-2026-1".into(),
        },
        CacheQuery::Classrooms {
            campus: 1,
            date: "2026-09-22".into(),
        },
    ];
    let payloads = [
        CachePayload::Weeks(vec![]),
        CachePayload::Week(crate::domain::WeeklySchedule::default()),
        CachePayload::Exams(crate::domain::ExamArrangement::default()),
        CachePayload::Grades(GradeData {
            term_code: "2025-2026-1".into(),
            grades: vec![],
        }),
        CachePayload::Classrooms(crate::domain::ClassroomQuery::default()),
    ];
    for (query, payload) in queries.into_iter().zip(payloads) {
        let scope = CacheScope {
            route: ConnectionMode::Direct,
            query,
        };
        let ticket = repo.begin_read(scope.clone()).unwrap();
        repo.publish(&ticket, payload, 100, CacheCompleteness::Complete)
            .unwrap();
    }
    for query in [
        CacheQuery::ScheduleWeeks {
            term: "2025-2026-2".into(),
        },
        CacheQuery::ScheduleWeek {
            term: "2025-2026-1".into(),
            week: 2,
        },
        CacheQuery::Exams {
            term: "2025-2026-2".into(),
        },
        CacheQuery::Grades {
            term: "2025-2026-2".into(),
        },
        CacheQuery::Classrooms {
            campus: 2,
            date: "2026-09-22".into(),
        },
        CacheQuery::Classrooms {
            campus: 1,
            date: "2026-09-23".into(),
        },
    ] {
        assert!(
            repo.read(
                &CacheScope {
                    route: ConnectionMode::Direct,
                    query
                },
                101
            )
            .unwrap()
            .is_none()
        );
    }
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 成绩不能无损保存时保留旧内容() {
    use crate::domain::{Grade, GradeData};
    let root = root();
    let mut repo = open(&root);
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::Grades {
            term: "2025-2026-1".into(),
        },
    };
    let original = repo.begin_read(scope.clone()).unwrap();
    repo.publish(
        &original,
        CachePayload::Grades(GradeData {
            term_code: "2025-2026-1".into(),
            grades: vec![],
        }),
        100,
        CacheCompleteness::Complete,
    )
    .unwrap();
    let ticket = repo.begin_read(scope.clone()).unwrap();
    for (term, credit) in [
        ("2025-2026-2", 2.0),
        ("2025-2026-1", f64::NAN),
        ("2025-2026-1", f64::INFINITY),
    ] {
        assert_eq!(
            repo.publish(
                &ticket,
                CachePayload::Grades(GradeData {
                    term_code: term.into(),
                    grades: vec![Grade {
                        credit: Some(credit),
                        ..Default::default()
                    }]
                }),
                200,
                CacheCompleteness::Complete
            ),
            Err(CacheError::InvalidInput)
        );
    }
    assert_eq!(repo.read(&scope, 201).unwrap().unwrap().fetched_at, 100);
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 退出栅栏优先于无法保存的载荷且不能被当成普通保存失败() {
    let root = root();
    let mut repo = open(&root);
    let ticket = repo.begin_read(scope()).unwrap();
    repo.deactivate().unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            CachePayload::Terms(vec![]),
            200,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Inactive)
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
