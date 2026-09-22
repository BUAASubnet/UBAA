use super::*;
use crate::cache::{
    CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
    CachedBykcCourse, OfflineRepository,
};
use crate::domain::ConnectionMode;
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT: AtomicU64 = AtomicU64::new(0);
const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn fixture() -> (std::path::PathBuf, OfflineRepository) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-invalidation-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&root).unwrap();
    let repo = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([8; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (root, repo)
}
fn scope(route: ConnectionMode, id: i64) -> CacheScope {
    CacheScope {
        route,
        query: CacheQuery::BykcDetail { course_id: id },
    }
}
fn payload(id: i64) -> CachePayload {
    CachePayload::BykcDetail(CachedBykcCourse {
        id,
        course_name: "合成课程".into(),
        ..Default::default()
    })
}
fn seed(repo: &mut OfflineRepository, route: ConnectionMode, id: i64) {
    let ticket = repo.begin_read(scope(route, id)).unwrap();
    repo.publish(&ticket, payload(id), 100, CacheCompleteness::Complete)
        .unwrap();
}
#[test]
fn 写后精确失效阻止无旧条目的迟到结果_保留其他目标路线和账号() {
    let (root, mut repo) = fixture();
    let mut other = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([8; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    seed(&mut repo, ConnectionMode::Direct, 1);
    seed(&mut repo, ConnectionMode::Direct, 2);
    seed(&mut repo, ConnectionMode::WebVpn, 1);
    let old = other.begin_read(scope(ConnectionMode::Direct, 1)).unwrap();
    let unseen = other
        .begin_read(CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::BykcCourses {
                page: 2,
                size: 20,
                all: false,
            },
        })
        .unwrap();
    let unrelated = other.begin_read(scope(ConnectionMode::Direct, 2)).unwrap();
    let result = repo
        .invalidate(
            ConnectionMode::Direct,
            &CacheInvalidation::Bykc { course_id: 1 },
        )
        .unwrap();
    assert_eq!(result.removed_entries, 1);
    assert_eq!(result.cancelled_reads, 2);
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 1), 200)
            .unwrap()
            .is_none()
    );
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 2), 200)
            .unwrap()
            .is_some()
    );
    assert!(
        repo.read(&scope(ConnectionMode::WebVpn, 1), 200)
            .unwrap()
            .is_some()
    );
    assert!(matches!(
        other.validate_read(&unseen),
        Err(CacheError::Superseded)
    ));
    assert!(matches!(
        other.publish(&old, payload(1), 201, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    ));
    other
        .publish(&unrelated, payload(2), 202, CacheCompleteness::Complete)
        .unwrap();
    seed(&mut repo, ConnectionMode::Direct, 1);
    let mut separate = OfflineRepository::open(
        &root,
        "abcdef0123456789abcdef0123456789",
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    seed(&mut separate, ConnectionMode::Direct, 1);
    repo.invalidate(
        ConnectionMode::Direct,
        &CacheInvalidation::Bykc { course_id: 1 },
    )
    .unwrap();
    assert!(
        separate
            .read(&scope(ConnectionMode::Direct, 1), 203)
            .unwrap()
            .is_some()
    );
    drop((repo, other, separate));
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 持久失效事务失败保留条目和未发送读取资格() {
    let (root, mut repo) = fixture();
    seed(&mut repo, ConnectionMode::Direct, 1);
    let ticket = repo.begin_read(scope(ConnectionMode::Direct, 1)).unwrap();
    repo.db.execute_batch("CREATE TRIGGER synthetic_failure BEFORE DELETE ON requests BEGIN SELECT RAISE(FAIL,'synthetic'); END;").unwrap();
    assert!(
        repo.invalidate(
            ConnectionMode::Direct,
            &CacheInvalidation::Bykc { course_id: 1 }
        )
        .is_err()
    );
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 1), 200)
            .unwrap()
            .is_some()
    );
    repo.validate_read(&ticket).unwrap();
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 各领域失效只撤销相关范围_另一路线和无关日期继续可发布() {
    for (impact, affected, unaffected) in impact_cases() {
        let (root, mut repo) = fixture();
        let old = repo
            .begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query: affected.clone(),
            })
            .unwrap();
        let other = repo
            .begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query: unaffected,
            })
            .unwrap();
        let route = repo
            .begin_read(CacheScope {
                route: ConnectionMode::WebVpn,
                query: affected,
            })
            .unwrap();
        repo.invalidate(ConnectionMode::Direct, &impact).unwrap();
        drop(repo);
        let mut repo = OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([8; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        assert!(matches!(
            repo.validate_read(&old),
            Err(CacheError::Superseded)
        ));
        repo.validate_read(&other).unwrap();
        repo.validate_read(&route).unwrap();
        drop(repo);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn v4迁移保留业务密文和退出状态_旧连接和旧票据均失效() {
    for inactive in [false, true] {
        let (root, mut old) = fixture();
        seed(&mut old, ConnectionMode::Direct, 1);
        let ticket = old.begin_read(scope(ConnectionMode::Direct, 1)).unwrap();
        if inactive {
            old.deactivate().unwrap();
        }
        let before: Vec<u8> = old
            .db
            .query_row("SELECT body FROM entries", [], |r| r.get(0))
            .unwrap();
        old.db.execute_batch("DROP TABLE requests; CREATE TABLE requests(key BLOB PRIMARY KEY, revision INTEGER NOT NULL);").unwrap();
        let key = old.crypto.index(&(&old.account, &ticket.scope)).unwrap();
        old.db
            .execute(
                "INSERT INTO requests VALUES(?1,?2)",
                rusqlite::params![key, ticket.revision],
            )
            .unwrap();
        let revision: i64 = old
            .db
            .query_row("SELECT revision FROM requests", [], |row| row.get(0))
            .unwrap();
        assert_eq!(revision, ticket.revision);
        old.db.pragma_update(None, "user_version", 4).unwrap();
        let mut current = OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([8; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        let after: Vec<u8> = current
            .db
            .query_row("SELECT body FROM entries", [], |r| r.get(0))
            .unwrap();
        assert_eq!(before, after);
        assert!(matches!(
            old.begin_read(scope(ConnectionMode::Direct, 1)),
            Err(CacheError::Superseded)
        ));
        assert!(matches!(
            old.validate_read(&ticket),
            Err(CacheError::Superseded)
        ));
        if inactive {
            assert!(matches!(
                current.invalidate(
                    ConnectionMode::Direct,
                    &CacheInvalidation::Bykc { course_id: 1 }
                ),
                Err(CacheError::Inactive)
            ));
            current.activate().unwrap();
        }
        assert_eq!(
            current
                .read(&scope(ConnectionMode::Direct, 1), 200)
                .unwrap()
                .unwrap()
                .fetched_at,
            100
        );
        let fresh = current
            .begin_read(scope(ConnectionMode::Direct, 1))
            .unwrap();
        let encrypted: Vec<u8> = current
            .db
            .query_row("SELECT scope FROM requests", [], |r| r.get(0))
            .unwrap();
        assert!(serde_json::from_slice::<CacheScope>(&encrypted).is_err());
        current
            .invalidate(
                ConnectionMode::Direct,
                &CacheInvalidation::Bykc { course_id: 1 },
            )
            .unwrap();
        assert!(matches!(
            current.validate_read(&fresh),
            Err(CacheError::Superseded)
        ));
        drop((old, current));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 资源关联分页均失效_缺少资源定位只扩大本领域而不清全库() {
    let (root, mut repo) = fixture();
    let mut tickets = Vec::new();
    for query in [
        CacheQuery::LibBookBookings { page: 1, limit: 10 },
        CacheQuery::LibBookBookings { page: 3, limit: 20 },
        CacheQuery::LibBookLibraries {
            day: "2026-09-22".into(),
        },
        CacheQuery::LibBookAreas {
            premises_id: "library".into(),
            storey_id: Some("floor".into()),
            day: "2026-09-22".into(),
        },
        CacheQuery::LibBookAreaDetail {
            area_id: "area".into(),
        },
        CacheQuery::LibBookSeats {
            area_id: "area".into(),
            day: "2026-09-22".into(),
            start_time: "08:00".into(),
            end_time: "09:00".into(),
        },
    ] {
        tickets.push(
            repo.begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query,
            })
            .unwrap(),
        );
    }
    let preserved = repo
        .begin_read(CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::CgyyOrders { page: 0, size: 20 },
        })
        .unwrap();
    let report = repo
        .invalidate(
            ConnectionMode::Direct,
            &CacheInvalidation::LibBook {
                day: None,
                area_id: None,
            },
        )
        .unwrap();
    assert_eq!(report.cancelled_reads, 6);
    for ticket in tickets {
        assert!(matches!(
            repo.validate_read(&ticket),
            Err(CacheError::Superseded)
        ));
    }
    repo.validate_read(&preserved).unwrap();
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 无效范围和损坏请求索引不能造成部分清除() {
    let (root, mut repo) = fixture();
    seed(&mut repo, ConnectionMode::Direct, 1);
    let ticket = repo.begin_read(scope(ConnectionMode::Direct, 1)).unwrap();
    assert!(matches!(
        repo.invalidate(
            ConnectionMode::Direct,
            &CacheInvalidation::Bykc { course_id: 0 }
        ),
        Err(CacheError::InvalidInput)
    ));
    repo.validate_read(&ticket).unwrap();
    repo.db
        .execute("UPDATE requests SET scope=?1", [vec![1_u8, 2, 3]])
        .unwrap();
    assert!(matches!(
        repo.invalidate(
            ConnectionMode::Direct,
            &CacheInvalidation::Bykc { course_id: 1 }
        ),
        Err(CacheError::Corrupt)
    ));
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 1), 200)
            .unwrap()
            .is_some()
    );
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 损坏请求范围不得续租或发布_不靠失效操作才发现() {
    let (root, mut repo) = fixture();
    let mut ticket = repo.begin_read(scope(ConnectionMode::Direct, 1)).unwrap();
    repo.db
        .execute("UPDATE requests SET scope=?1", [vec![1_u8, 2, 3]])
        .unwrap();
    assert!(matches!(
        repo.validate_read(&ticket),
        Err(CacheError::Corrupt)
    ));
    assert!(matches!(
        repo.renew_read(&mut ticket),
        Err(CacheError::Corrupt)
    ));
    assert!(matches!(
        repo.publish(&ticket, payload(1), 200, CacheCompleteness::Complete),
        Err(CacheError::Corrupt)
    ));
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 无关损坏条目不阻断可识别目标失效_坏条目仍由原单条读取隔离() {
    let (root, mut repo) = fixture();
    seed(&mut repo, ConnectionMode::Direct, 1);
    seed(&mut repo, ConnectionMode::Direct, 2);
    let key = repo
        .crypto
        .index(&(&repo.account, &scope(ConnectionMode::Direct, 2)))
        .unwrap();
    repo.db
        .execute(
            "UPDATE entries SET body=?1 WHERE key=?2",
            rusqlite::params![vec![1_u8, 2, 3], key],
        )
        .unwrap();
    repo.invalidate(
        ConnectionMode::Direct,
        &CacheInvalidation::Bykc { course_id: 1 },
    )
    .unwrap();
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 1), 200)
            .unwrap()
            .is_none()
    );
    assert!(matches!(
        repo.read(&scope(ConnectionMode::Direct, 2), 200),
        Err(CacheError::Corrupt)
    ));
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}

fn impact_cases() -> Vec<(CacheInvalidation, CacheQuery, CacheQuery)> {
    use CacheQuery as Q;
    vec![
        (
            CacheInvalidation::Signin {
                date: "20260922".into(),
            },
            Q::SigninToday {
                date: "20260922".into(),
            },
            Q::SigninToday {
                date: "20260921".into(),
            },
        ),
        (
            CacheInvalidation::LibBook {
                day: Some("2026-09-22".into()),
                area_id: Some("area-a".into()),
            },
            Q::LibBookSeats {
                area_id: "area-a".into(),
                day: "2026-09-22".into(),
                start_time: "08:00".into(),
                end_time: "09:00".into(),
            },
            Q::LibBookSeats {
                area_id: "area-b".into(),
                day: "2026-09-22".into(),
                start_time: "08:00".into(),
                end_time: "09:00".into(),
            },
        ),
        (
            CacheInvalidation::Cgyy {
                site_id: Some(1),
                date: Some("2026-09-22".into()),
                order_id: Some(10),
            },
            Q::CgyyDay {
                site_id: 1,
                date: "2026-09-22".into(),
            },
            Q::CgyyDay {
                site_id: 1,
                date: "2026-09-23".into(),
            },
        ),
        (
            CacheInvalidation::Ygdk { classify_id: 1 },
            Q::YgdkRecords {
                classify_id: 1,
                page: 3,
                size: 20,
            },
            Q::YgdkRecords {
                classify_id: 2,
                page: 3,
                size: 20,
            },
        ),
        (
            CacheInvalidation::Evaluation,
            Q::EvaluationCurrent,
            Q::ScheduleTerms,
        ),
    ]
}
