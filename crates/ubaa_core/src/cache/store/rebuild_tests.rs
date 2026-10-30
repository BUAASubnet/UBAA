use super::*;
use crate::cache::{CacheQuery, CacheRecovery};
use crate::domain::ConnectionMode;
use std::sync::atomic::{AtomicU64, Ordering};
const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn fixture() -> (PathBuf, OfflineRepository, CacheScope) {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = std::env::temp_dir().join(format!(
        "ubaa-rebuild-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&root).unwrap();
    let repo = open(&root);
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-09-22".into(),
        },
    };
    (root, repo, scope)
}
fn open(root: &Path) -> OfflineRepository {
    OfflineRepository::open(
        root,
        ACCOUNT,
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap()
}
fn rebuild(root: &Path) -> CacheResult<CacheRecovery> {
    OfflineRepository::clear_or_rebuild(
        root,
        ACCOUNT,
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
}
#[test]
fn 新数据库不能接受旧数据库同计数的票据() {
    let (root, mut old, scope) = fixture();
    let ticket = old.begin_read(scope.clone()).unwrap();
    let path = old.path().to_owned();
    drop(old);
    std::fs::remove_file(path).unwrap();
    let mut new = open(&root);
    let _ = new.begin_read(scope).unwrap();
    assert_eq!(
        new.publish(
            &ticket,
            CachePayload::Today(vec![]),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    drop(new);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 严重损坏仅重建本账号且旧连接不能重建迟到内容() {
    let (root, mut old, scope) = fixture();
    let ticket = old.begin_read(scope.clone()).unwrap();
    std::fs::write(root.join("session.json"), b"synthetic-session-sentinel").unwrap();
    let other_account = "fedcba9876543210fedcba9876543210";
    let other = OfflineRepository::open(
        &root,
        other_account,
        CacheKey::new([7; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let other_path = other.path().to_owned();
    drop(other);
    let other_bytes = std::fs::read(&other_path).unwrap();
    std::fs::write(old.path(), b"synthetic broken sqlite header").unwrap();
    assert!(matches!(
        OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([9; 32]),
            CacheLimits::default()
        ),
        Err(CacheError::Corrupt)
    ));
    let outcome = rebuild(&root).unwrap();
    assert!(outcome.report.maintenance_error.is_none());
    let mut new = outcome.repository.unwrap();
    assert_eq!(new.usage().unwrap().entry_count, 0);
    let _ = new.begin_read(scope.clone()).unwrap();
    assert_eq!(
        new.publish(
            &ticket,
            CachePayload::Today(vec![]),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    assert!(old.begin_read(scope).is_err());
    assert_eq!(
        std::fs::read(root.join("session.json")).unwrap(),
        b"synthetic-session-sentinel"
    );
    assert_eq!(std::fs::read(other_path).unwrap(), other_bytes);
    drop((old, new));
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 普通打开未知版本不修改而显式重建可以重新使用() {
    let (root, repo, _) = fixture();
    repo.db.pragma_update(None, "user_version", 99).unwrap();
    let path = repo.path().to_owned();
    drop(repo);
    let before = std::fs::read(&path).unwrap();
    assert!(matches!(
        OfflineRepository::open(
            &root,
            ACCOUNT,
            CacheKey::new([9; 32]),
            CacheLimits::default()
        ),
        Err(CacheError::UnsupportedVersion)
    ));
    assert_eq!(std::fs::read(&path).unwrap(), before);
    let outcome = rebuild(&root).unwrap();
    let mut repo = outcome.repository.unwrap();
    assert_eq!(
        repo.db
            .pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
            .unwrap(),
        crate::cache::CACHE_SCHEMA_VERSION
    );
    assert_eq!(repo.usage().unwrap().entry_count, 0);
    drop(repo);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 其他读取连接持锁时重建失败不清空原库() {
    let (root, repo, _) = fixture();
    repo.db.pragma_update(None, "user_version", 99).unwrap();
    repo.db
        .execute_batch("BEGIN; SELECT * FROM control;")
        .unwrap();
    let path = repo.path().to_owned();
    let before = std::fs::read(&path).unwrap();
    assert!(rebuild(&root).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), before);
    repo.db.execute_batch("ROLLBACK;").unwrap();
    drop(repo);
    assert!(rebuild(&root).unwrap().repository.is_some());
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 清空后初始化失败明确返回无可用仓库而不冒称旧内容保留() {
    let (root, repo, _) = fixture();
    repo.db.pragma_update(None, "user_version", 99).unwrap();
    drop(repo);
    let result = OfflineRepository::clear_or_rebuild_with(
        &root,
        ACCOUNT,
        CacheKey::new([9; 32]),
        CacheLimits::default(),
        |_, _, _, _| Err(CacheError::Capacity),
    )
    .unwrap();
    assert!(result.repository.is_none());
    assert_eq!(result.report.maintenance_error, Some(CacheError::Capacity));
    assert!(result.report.compacted);
    assert_eq!(open(&root).usage().unwrap().entry_count, 0);
    std::fs::remove_dir_all(root).unwrap();
}
