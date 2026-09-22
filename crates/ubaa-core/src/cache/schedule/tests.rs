use super::*;
use crate::cache::{
    CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope, OfflineRepository,
};
use crate::domain::{ConnectionMode, CourseClass, Term, Week, WeeklySchedule};
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT: AtomicU64 = AtomicU64::new(0);
const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn root() -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "ubaa-imported-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&root).unwrap();
    root
}
fn semester(term: &str, date: &str, name: &str, fetched_at: i64) -> CachedSemesterSchedule {
    CachedSemesterSchedule::new(
        term.into(),
        vec![Term {
            item_code: term.into(),
            ..Default::default()
        }],
        vec![Week {
            term: term.into(),
            start_date: format!("{date} 00:00:00"),
            end_date: date.into(),
            serial_number: 1,
            ..Default::default()
        }],
        [(
            1,
            WeeklySchedule {
                code: "synthetic-student-code".into(),
                arranged_list: vec![CourseClass {
                    course_name: name.into(),
                    day_of_week: Some(2),
                    ..Default::default()
                }],
                ..Default::default()
            },
        )]
        .into(),
        fetched_at,
    )
    .unwrap()
}
fn scope() -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ImportedSchedules,
    }
}
#[test]
fn 完整导入重开保留各学期与原时间_普通周查询不能成为整学期() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    for (term, date, time) in [("a", "2026-09-22", 100), ("b", "2026-09-29", 200)] {
        let ticket = repo.begin_read(scope()).unwrap();
        repo.publish_imported_semester(&ticket, semester(term, date, term, time))
            .unwrap();
    }
    drop(repo);
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let value = repo
        .read_imported_schedule(
            ConnectionMode::Direct,
            CacheQuery::ScheduleWeek {
                term: "a".into(),
                week: 1,
            },
            300,
        )
        .unwrap()
        .unwrap();
    assert_eq!(value.fetched_at, 100);
    assert!(matches!(value.payload, CachePayload::Week(_)));
    assert!(
        repo.read_imported_schedule(
            ConnectionMode::WebVpn,
            CacheQuery::ScheduleWeek {
                term: "a".into(),
                week: 1
            },
            300
        )
        .unwrap()
        .is_none()
    );
    assert!(
        repo.read_imported_schedule(
            ConnectionMode::Direct,
            CacheQuery::ScheduleWeek {
                term: "a".into(),
                week: 2
            },
            300
        )
        .unwrap()
        .is_none()
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 缺周错学期重复周日期不明时拒绝构建完整导入() {
    let good = semester("a", "2026-09-22", "合成课程", 100);
    for variant in 0..5 {
        let mut weeks = good.weeks.clone();
        let mut schedules = good.schedules.clone();
        match variant {
            0 => {
                schedules.clear();
            }
            1 => weeks[0].term = "b".into(),
            2 => weeks.push(weeks[0].clone()),
            3 => weeks[0].start_date = "未知".into(),
            _ => weeks[0].end_date = "2026-10-22".into(),
        }
        assert!(
            CachedSemesterSchedule::new("a".into(), good.terms.clone(), weeks, schedules, 100)
                .is_err()
        );
    }
    assert_eq!(good.weeks[0].start_date, "2026-09-22");
    assert_eq!(good.schedules[&1].code, "synthetic-student-code");
}
#[test]
fn 不覆盖日期和未知星期不能显示无课_真实空周可以() {
    let mut value = semester("a", "2026-09-22", "合成课程", 100);
    assert!(value.today("2026-09-23").unwrap().is_none());
    assert_eq!(value.today("2026-09-22").unwrap().unwrap().len(), 1);
    value.schedules.get_mut(&1).unwrap().arranged_list[0].day_of_week = None;
    assert!(value.today("2026-09-22").unwrap().is_none());
    value.schedules.get_mut(&1).unwrap().arranged_list.clear();
    assert!(value.today("2026-09-22").unwrap().unwrap().is_empty());
}
#[test]
fn 新导入失败和迟到发布不能覆盖旧快照() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let old = repo.begin_read(scope()).unwrap();
    repo.publish_imported_semester(&old, semester("a", "2026-09-22", "旧课程", 100))
        .unwrap();
    let stale = repo.begin_read(scope()).unwrap();
    let current = repo.begin_read(scope()).unwrap();
    assert_eq!(
        repo.publish_imported_semester(&stale, semester("a", "2026-09-22", "迟到", 200)),
        Err(CacheError::Superseded)
    );
    let mut invalid = semester("a", "2026-09-22", "不完整", 200);
    invalid.schedules.clear();
    assert_eq!(
        repo.publish_imported_semester(&current, invalid),
        Err(CacheError::InvalidInput)
    );
    let value = repo
        .read_imported_schedule(
            ConnectionMode::Direct,
            CacheQuery::ScheduleToday {
                date: "2026-09-22".into(),
            },
            300,
        )
        .unwrap()
        .unwrap();
    assert_eq!(value.fetched_at, 100);
    assert!(matches!(value.payload,CachePayload::Today(items) if items[0].biz_name=="旧课程"));
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 普通缓存容量压力不能淘汰明确导入的学期() {
    let root = root();
    let limits = CacheLimits {
        soft_bytes: 4000,
        hard_bytes: 5000,
    };
    let mut repo = OfflineRepository::open(&root, ACCOUNT, CacheKey::new([7; 32]), limits).unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish_imported_semester(
        &ticket,
        semester("a", "2026-09-22", &"预留".repeat(400), 100),
    )
    .unwrap();
    let now = chrono::NaiveDate::from_ymd_opt(2026, 9, 22)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp();
    let today = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-09-22".into(),
        },
    };
    let incoming = repo.begin_read(today).unwrap();
    assert_eq!(
        repo.publish(
            &incoming,
            CachePayload::Today(vec![TodayClass {
                biz_name: "更新".repeat(500),
                ..Default::default()
            }]),
            now,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Capacity)
    );
    assert!(repo.read(&scope(), now).unwrap().is_some());
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 日期规范化不接受冻结规则之外的年或符号() {
    let value = semester("a", "2026-09-22", "合成", 100);
    for invalid in ["26-09-22", "+2026-09-22", "2026-009-22"] {
        let mut weeks = value.weeks.clone();
        weeks[0].start_date = invalid.into();
        assert!(
            CachedSemesterSchedule::new(
                "a".into(),
                value.terms.clone(),
                weeks,
                value.schedules.clone(),
                100
            )
            .is_err(),
            "{invalid}"
        );
    }
}
#[test]
fn 跨学期重叠选择开学更晚的覆盖_没有覆盖不返回空() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let mut earlier = semester("a", "2026-09-21", "旧学期", 100);
    earlier.weeks[0].end_date = "2026-09-27".into();
    let mut later = semester("b", "2026-09-22", "新学期", 200);
    later.weeks[0].end_date = "2026-09-28".into();
    for value in [later, earlier] {
        let ticket = repo.begin_read(scope()).unwrap();
        repo.publish_imported_semester(&ticket, value).unwrap();
    }
    let result = repo
        .read_imported_schedule(
            ConnectionMode::Direct,
            CacheQuery::ScheduleToday {
                date: "2026-09-22".into(),
            },
            300,
        )
        .unwrap()
        .unwrap();
    assert!(matches!(result.payload,CachePayload::Today(items) if items[0].biz_name=="新学期"));
    assert_eq!(result.fetched_at, 200);
    assert!(
        repo.read_imported_schedule(
            ConnectionMode::Direct,
            CacheQuery::ScheduleToday {
                date: "2026-10-01".into()
            },
            300
        )
        .unwrap()
        .is_none()
    );
    let weekly = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleWeek {
            term: "c".into(),
            week: 1,
        },
    };
    let ticket = repo.begin_read(weekly.clone()).unwrap();
    repo.publish(
        &ticket,
        CachePayload::Week(WeeklySchedule::default()),
        300,
        CacheCompleteness::Complete,
    )
    .unwrap();
    assert!(
        repo.read_imported_schedule(ConnectionMode::Direct, weekly.query, 300)
            .unwrap()
            .is_none()
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn v3升级保留内容和退出状态_旧连接不能参与新格式回收() {
    for inactive in [false, true] {
        let root = root();
        let mut old = OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([7; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        let scope = CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::ScheduleWeek {
                term: "a".into(),
                week: 1,
            },
        };
        let ticket = old.begin_read(scope.clone()).unwrap();
        old.publish(
            &ticket,
            CachePayload::Week(WeeklySchedule::default()),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
        if inactive {
            old.deactivate().unwrap();
        }
        let db = rusqlite::Connection::open(old.path()).unwrap();
        db.pragma_update(None, "user_version", 3).unwrap();
        drop(db);
        let mut current = OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([7; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        assert!(matches!(old.read(&scope, 200), Err(CacheError::Superseded)));
        if inactive {
            assert!(matches!(
                current.read(&scope, 200),
                Err(CacheError::Inactive)
            ));
            current.activate().unwrap();
        }
        assert_eq!(current.read(&scope, 200).unwrap().unwrap().fetched_at, 100);
        let db = rusqlite::Connection::open(current.path()).unwrap();
        assert_eq!(
            db.pragma_query_value(None, "user_version", |row| row.get::<_, u32>(0))
                .unwrap(),
            crate::cache::CACHE_SCHEMA_VERSION
        );
        drop(db);
        drop(current);
        drop(old);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 退出栅栏优先于不完整导入_失效任务不能继续使用仓库() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.deactivate().unwrap();
    let mut value = semester("a", "2026-09-22", "合成", 100);
    value.schedules.clear();
    assert_eq!(
        repo.publish_imported_semester(&ticket, value),
        Err(CacheError::Inactive)
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 空教学周不能作为覆盖完整的学期覆盖旧导入() {
    let value = semester("a", "2026-09-22", "合成", 100);
    assert!(
        CachedSemesterSchedule::new("a".into(), value.terms, Vec::new(), BTreeMap::new(), 200)
            .is_err()
    );
}

#[test]
fn 教学周当前标记按覆盖日期计算但不刷新取得时间() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish_imported_semester(&ticket, semester("a", "2026-09-22", "合成", 100))
        .unwrap();
    let now = chrono::NaiveDate::from_ymd_opt(2026, 9, 22)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_utc()
        .timestamp();
    for (time, expected) in [(now, true), (now + 86_400, false)] {
        let value = repo
            .read_imported_schedule(
                ConnectionMode::Direct,
                CacheQuery::ScheduleWeeks { term: "a".into() },
                time,
            )
            .unwrap()
            .unwrap();
        assert!(matches!(value.payload, CachePayload::Weeks(weeks) if weeks[0].cur_week==expected));
        assert_eq!(value.fetched_at, 100);
    }
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 导入投影保留单周和周次索引的实际取得时间() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let value = semester("a", "2026-09-22", "合成", 200)
        .with_observations((110, 10), [(1, (120, 11))].into())
        .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish_imported_semester(&ticket, value).unwrap();
    for (query, time) in [
        (
            CacheQuery::ScheduleWeek {
                term: "a".into(),
                week: 1,
            },
            120,
        ),
        (CacheQuery::ScheduleWeeks { term: "a".into() }, 110),
        (
            CacheQuery::ScheduleToday {
                date: "2026-09-22".into(),
            },
            120,
        ),
    ] {
        assert_eq!(
            repo.read_imported_schedule(ConnectionMode::Direct, query, 300)
                .unwrap()
                .unwrap()
                .fetched_at,
            time
        );
    }
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 导入学期索引保留原取得时间和修订_不冒充最终周完成时间() {
    let root = root();
    let mut repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let value = semester("term", "2026-09-22", "合成课程", 999)
        .with_observations((110, 10), [(1, (120, 11))].into())
        .unwrap()
        .with_terms_observation((100, 9))
        .unwrap();
    let ticket = repo.begin_read(scope()).unwrap();
    repo.publish_imported_semester(&ticket, value).unwrap();
    let index = repo
        .read_imported_schedule(ConnectionMode::Direct, CacheQuery::ScheduleTerms, 1000)
        .unwrap()
        .unwrap();
    assert_eq!(index.fetched_at, 100);
    assert_eq!(index.revision, 9);
    assert!(matches!(index.payload, CachePayload::Terms(values) if values[0].item_code == "term"));
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 本地当前周按校园跨日边界计算_不使用终端时区或旧布尔值() {
    let mut weeks = vec![
        Week {
            term: "term".into(),
            serial_number: 1,
            start_date: "2026-09-07".into(),
            end_date: "2026-09-13".into(),
            cur_week: true,
            ..Default::default()
        },
        Week {
            term: "term".into(),
            serial_number: 2,
            start_date: "2026-09-14".into(),
            end_date: "2026-09-20".into(),
            ..Default::default()
        },
    ];
    let before = chrono::DateTime::parse_from_rfc3339("2026-09-13T15:59:59Z")
        .unwrap()
        .timestamp();
    CachedSemesterSchedule::project_week_dates("term", &mut weeks, before).unwrap();
    assert_eq!(
        weeks.iter().map(|week| week.cur_week).collect::<Vec<_>>(),
        [true, false]
    );
    CachedSemesterSchedule::project_week_dates("term", &mut weeks, before + 1).unwrap();
    assert_eq!(
        weeks.iter().map(|week| week.cur_week).collect::<Vec<_>>(),
        [false, true]
    );
    CachedSemesterSchedule::project_week_dates("term", &mut weeks, before + 8 * 86400).unwrap();
    assert!(weeks.iter().all(|week| !week.cur_week));
}
