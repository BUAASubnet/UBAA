use super::*;
use crate::domain::ConnectionMode;
use crate::domain::{JudgeAssignmentDetail, JudgeAssignmentSummary, Term, WeeklySchedule};
use std::sync::atomic::{AtomicU64, Ordering};

const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn timestamp(value: &str) -> i64 {
    chrono::DateTime::parse_from_rfc3339(value)
        .unwrap()
        .timestamp()
}
fn repository() -> (PathBuf, OfflineRepository) {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = std::env::temp_dir().join(format!(
        "ubaa-retention-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&root).unwrap();
    let repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (root, repo)
}
fn scope(query: super::super::CacheQuery) -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query,
    }
}
fn detail(id: &str, due: Option<&str>) -> (CacheScope, CachePayload) {
    (
        scope(super::super::CacheQuery::JudgeDetail {
            course_id: "1".into(),
            assignment_id: id.into(),
        }),
        CachePayload::JudgeDetail(Box::new(JudgeAssignmentDetail {
            course_id: "1".into(),
            assignment_id: id.into(),
            due_time: due.map(Into::into),
            title: "合成作业".repeat(20),
            ..Default::default()
        })),
    )
}
fn put(repo: &mut OfflineRepository, scope: CacheScope, payload: CachePayload, now: i64) {
    let ticket = repo.begin_read(scope).unwrap();
    repo.publish(&ticket, payload, now, CacheCompleteness::Complete)
        .unwrap();
}
fn bytes(repo: &OfflineRepository) -> u64 {
    repo.db
        .query_row(
            "SELECT COALESCE(SUM(length(body)),0) FROM entries",
            [],
            |r| r.get::<_, i64>(0),
        )
        .unwrap()
        .try_into()
        .unwrap()
}
#[test]
fn 压力时重新判断九十天且不以近期访问保护已结束旧详情() {
    let (root, mut repo) = repository();
    let now = timestamp("2026-09-22T04:00:00Z");
    let (old, old_data) = detail("1", Some("2026-04-01 12:00:00"));
    let (recent, recent_data) = detail("2", Some("2026-09-01 12:00:00"));
    let (active, active_data) = detail("3", Some("2027-01-01 12:00:00"));
    put(
        &mut repo,
        old.clone(),
        old_data,
        timestamp("2026-04-02T04:00:00Z"),
    );
    put(&mut repo, recent.clone(), recent_data, now - 100);
    put(&mut repo, active.clone(), active_data.clone(), now - 50);
    repo.read(&old, now).unwrap();
    let total = bytes(&repo);
    repo.limits = CacheLimits {
        soft_bytes: total - 1,
        hard_bytes: total + 1000,
    };
    put(&mut repo, active.clone(), active_data, now);
    assert!(repo.read(&old, now).unwrap().is_none());
    assert!(repo.read(&recent, now).unwrap().is_some());
    assert!(repo.read(&active, now).unwrap().is_some());
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 硬限额不能由历史详情挤掉活跃任务且失败事务保留原内容() {
    let (root, mut repo) = repository();
    let now = timestamp("2026-09-22T04:00:00Z");
    let (active, data) = detail("1", Some("2027-01-01 12:00:00"));
    put(&mut repo, active.clone(), data.clone(), now);
    let total = bytes(&repo);
    repo.limits = CacheLimits {
        soft_bytes: total,
        hard_bytes: total + 100,
    };
    let (old, old_data) = detail("2", Some("2026-01-01 12:00:00"));
    let ticket = repo.begin_read(old.clone()).unwrap();
    assert_eq!(
        repo.publish(&ticket, old_data, now, CacheCompleteness::Complete),
        Err(CacheError::Capacity)
    );
    assert_eq!(repo.read(&active, now).unwrap().unwrap().payload, data);
    assert!(repo.read(&old, now).unwrap().is_none());
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 规范时间边界未知日期和旧开始时间不等于已结束() {
    use super::retention::{Context, Priority, classify};
    let now = timestamp("2026-09-22T04:00:00Z");
    let context = Context::default();
    for (due, expected) in [
        (Some("2026-09-22 12:00:00"), Priority::Active),
        (Some("2026-09-22 11:59:59"), Priority::Recent),
        (Some("2026-06-24 12:00:00"), Priority::Recent),
        (Some("2026-06-24 11:59:59"), Priority::Expired),
        (Some("2026-99-99 00:00:00"), Priority::Ordinary),
        (None, Priority::Ordinary),
    ] {
        let (scope, payload) = detail("1", due);
        let record = CacheRecord {
            scope,
            payload,
            fetched_at: now,
            last_attempt_at: now,
            last_verified_at: now,
            last_attempt_succeeded: true,
            revision: 1,
            completeness: CacheCompleteness::Complete,
        };
        assert_eq!(classify(&record, &context, now), expected);
    }
}
#[test]
fn 当前学期只使用同路线唯一新鲜选择且索引不因旧课程而降为过期() {
    use super::retention::{Context, Priority, classify};
    let (root, mut repo) = repository();
    let now = timestamp("2026-09-22T04:00:00Z");
    put(
        &mut repo,
        scope(super::super::CacheQuery::ScheduleTerms),
        CachePayload::Terms(vec![Term {
            item_code: "term-a".into(),
            selected: true,
            ..Default::default()
        }]),
        now,
    );
    let context = Context::load(&repo.db, &repo.crypto, ACCOUNT, now).unwrap();
    let record = CacheRecord {
        scope: scope(super::super::CacheQuery::ScheduleWeek {
            term: "term-a".into(),
            week: 1,
        }),
        payload: CachePayload::Week(WeeklySchedule::default()),
        fetched_at: now,
        last_attempt_at: now,
        last_verified_at: now,
        last_attempt_succeeded: true,
        revision: 1,
        completeness: CacheCompleteness::Complete,
    };
    assert_eq!(classify(&record, &context, now), Priority::Active);
    let mut other = record.clone();
    other.scope.route = ConnectionMode::WebVpn;
    assert_eq!(classify(&other, &context, now), Priority::Stable);
    let stale = Context::load(&repo.db, &repo.crypto, ACCOUNT, now + 86401).unwrap();
    assert_eq!(classify(&record, &stale, now + 86401), Priority::Stable);
    other.scope = scope(super::super::CacheQuery::JudgeCourseReview {
        course_id: "1".into(),
    });
    other.payload = CachePayload::JudgeCourseReview(super::super::JudgeCourseReview {
        index_revision: 1,
        index_checked_at: now,
        next_index_check_at: now + 86400,
        all_items_historical: true,
        summaries: vec![JudgeAssignmentSummary {
            due_time: Some("2020-01-01 00:00:00".into()),
            ..Default::default()
        }],
    });
    assert_eq!(classify(&other, &context, now), Priority::Stable);
    put(
        &mut repo,
        scope(super::super::CacheQuery::ScheduleTerms),
        CachePayload::Terms(vec![
            Term {
                item_code: "term-a".into(),
                selected: true,
                ..Default::default()
            },
            Term {
                selected: true,
                ..Default::default()
            },
        ]),
        now,
    );
    let ambiguous = Context::load(&repo.db, &repo.crypto, ACCOUNT, now).unwrap();
    assert_eq!(classify(&record, &ambiguous, now), Priority::Stable);
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

fn record(query: super::super::CacheQuery, payload: CachePayload, now: i64) -> CacheRecord {
    CacheRecord {
        scope: scope(query),
        payload,
        fetched_at: now,
        last_attempt_at: now,
        last_verified_at: now,
        last_attempt_succeeded: true,
        revision: 1,
        completeness: CacheCompleteness::Complete,
    }
}
#[test]
fn 同页旧项之后有未来订单仍整体保护且未知日期不冒充过期() {
    use super::retention::{Context, Priority, classify};
    use crate::cache::{CacheQuery, CachedLibBookBooking, CachedLibBookBookingsPage};
    let now = timestamp("2026-09-22T04:00:00Z");
    let context = Context::default();
    let mut value = record(
        CacheQuery::LibBookBookings { page: 1, limit: 20 },
        CachePayload::LibBookBookings(CachedLibBookBookingsPage {
            bookings: vec![
                CachedLibBookBooking {
                    day: "2020-01-01".into(),
                    ..Default::default()
                },
                CachedLibBookBooking {
                    day: "2026-09-23".into(),
                    ..Default::default()
                },
            ],
            page: 1,
            limit: 20,
            total: 2,
        }),
        now,
    );
    assert_eq!(classify(&value, &context, now), Priority::Active);
    let CachePayload::LibBookBookings(ref mut page) = value.payload else {
        unreachable!()
    };
    page.bookings[1].day = "未知日期".into();
    assert_eq!(classify(&value, &context, now), Priority::Recent);
    value.last_verified_at = now + 3600;
    assert_eq!(classify(&value, &context, now), Priority::Recent);
}
#[test]
fn 没有学期索引的未来考试与当日签到也优先保留() {
    use super::retention::{Context, Priority, classify};
    use crate::cache::CacheQuery;
    let now = timestamp("2026-09-22T04:00:00Z");
    let context = Context::default();
    let value = record(
        CacheQuery::Exams {
            term: "actual-term".into(),
        },
        CachePayload::Exams(crate::domain::ExamArrangement {
            arranged: vec![crate::domain::Exam {
                exam_date: Some("2026-10-01".into()),
                ..Default::default()
            }],
            not_arranged: vec![],
        }),
        now,
    );
    assert_eq!(classify(&value, &context, now), Priority::Active);
    let mut value = record(
        CacheQuery::SigninToday {
            date: "2026-09-22".into(),
        },
        CachePayload::SigninToday(vec![]),
        now,
    );
    assert_eq!(classify(&value, &context, now), Priority::Active);
    value.scope.query = CacheQuery::SigninToday {
        date: "2026-09-21".into(),
    };
    assert_eq!(classify(&value, &context, now), Priority::Expired);
}
#[test]
fn 分配新密文前先回收且插入失败回滚已回收内容() {
    let (root, mut repo) = repository();
    let now = timestamp("2026-09-22T04:00:00Z");
    let (old, old_data) = detail("1", Some("2020-01-01 12:00:00"));
    put(&mut repo, old.clone(), old_data.clone(), now);
    let total = bytes(&repo);
    repo.limits = CacheLimits {
        soft_bytes: total + 100,
        hard_bytes: total + 200,
    };
    // 如果仍先INSERT后淘汰，该触发器会拒绝；只验证事务执行顺序，不冒称真实磁盘满。
    repo.db.execute_batch("CREATE TRIGGER require_room BEFORE INSERT ON entries WHEN (SELECT COUNT(*) FROM entries)>0 BEGIN SELECT RAISE(ABORT,'synthetic'); END;").unwrap();
    let (active, active_data) = detail("2", Some("2027-01-01 12:00:00"));
    put(&mut repo, active.clone(), active_data.clone(), now);
    assert!(repo.read(&old, now).unwrap().is_none());
    assert!(repo.read(&active, now).unwrap().is_some());
    repo.db.execute_batch("DROP TRIGGER require_room; CREATE TRIGGER fail_insert BEFORE INSERT ON entries BEGIN SELECT RAISE(ABORT,'synthetic'); END;").unwrap();
    let (new, new_data) = detail("3", Some("2027-01-02 12:00:00"));
    let ticket = repo.begin_read(new.clone()).unwrap();
    assert_eq!(
        repo.publish(&ticket, new_data, now, CacheCompleteness::Complete),
        Err(CacheError::Unavailable)
    );
    assert_eq!(
        repo.read(&active, now).unwrap().unwrap().payload,
        active_data
    );
    assert!(repo.read(&new, now).unwrap().is_none());
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 学期切换以即将提交的新索引判断旧课表而不被旧索引锁死容量() {
    use crate::cache::CacheQuery;
    let (root, mut repo) = repository();
    let now = timestamp("2026-09-22T04:00:00Z");
    let terms = scope(CacheQuery::ScheduleTerms);
    put(
        &mut repo,
        terms.clone(),
        CachePayload::Terms(vec![Term {
            item_code: "old".into(),
            selected: true,
            ..Default::default()
        }]),
        now,
    );
    let week = scope(CacheQuery::ScheduleWeek {
        term: "old".into(),
        week: 1,
    });
    put(
        &mut repo,
        week.clone(),
        CachePayload::Week(WeeklySchedule {
            arranged_list: vec![crate::domain::CourseClass {
                course_name: "旧课表".repeat(100),
                ..Default::default()
            }],
            ..Default::default()
        }),
        now,
    );
    let total = bytes(&repo);
    repo.limits = CacheLimits {
        soft_bytes: total,
        hard_bytes: total + 10,
    };
    put(
        &mut repo,
        terms.clone(),
        CachePayload::Terms(vec![Term {
            item_code: "new".into(),
            item_name: "新学期".repeat(40),
            selected: true,
            ..Default::default()
        }]),
        now,
    );
    assert!(repo.read(&terms, now).unwrap().is_some());
    assert!(repo.read(&week, now).unwrap().is_none());
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
