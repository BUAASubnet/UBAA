use super::*;
use crate::cache::{CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope};
use crate::domain::{ConnectionMode, TodayClass};
fn fixture() -> (std::path::PathBuf, OfflineRepository, CacheScope) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-cache-manage-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    std::fs::create_dir_all(&root).unwrap();
    let repo = OfflineRepository::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-09-22".into(),
        },
    };
    (root, repo, scope)
}
fn seed(repo: &mut OfflineRepository, scope: CacheScope) {
    let ticket = repo.begin_read(scope).unwrap();
    repo.publish(
        &ticket,
        CachePayload::Today(vec![TodayClass {
            biz_name: "合成".repeat(10000),
            ..Default::default()
        }]),
        100,
        CacheCompleteness::Complete,
    )
    .unwrap();
}
#[test]
fn 用量不解密正文且清理回收空间并保持账号活动() {
    let (root, mut repo, scope) = fixture();
    seed(&mut repo, scope.clone());
    let before = repo.usage().unwrap();
    assert_eq!(before.entry_count, 1);
    assert!(before.content_bytes > 10000);
    assert!(before.database_bytes >= before.content_bytes);
    let mut other = OfflineRepository::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let old = other.begin_read(scope.clone()).unwrap();
    let result = repo.clear_for_reopen().unwrap();
    assert!(result.compacted);
    assert!(result.maintenance_error.is_none());
    let after = result.usage.unwrap();
    assert_eq!(after.entry_count, 0);
    assert_eq!(after.content_bytes, 0);
    assert!(after.database_bytes < before.database_bytes);
    assert!(repo.begin_read(scope.clone()).is_ok());
    assert!(matches!(
        other.begin_read(scope.clone()),
        Err(CacheError::Superseded)
    ));
    assert_eq!(other.activate(), Err(CacheError::Superseded));
    assert_eq!(
        other.publish(
            &old,
            CachePayload::Today(vec![]),
            200,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    drop((repo, other));
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn 清理事务失败不推进代次且不丢旧数据() {
    let (root, mut repo, scope) = fixture();
    seed(&mut repo, scope.clone());
    repo.db.execute_batch("CREATE TRIGGER reject_clear BEFORE DELETE ON entries BEGIN SELECT RAISE(ABORT, 'synthetic'); END;").unwrap();
    assert!(repo.clear_for_reopen().is_err());
    assert_eq!(repo.usage().unwrap().entry_count, 1);
    assert!(repo.read(&scope, 120).unwrap().is_some());
    drop(repo);
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn 清除提交后的压缩失败明确返回且旧数据确实已删除() {
    let (root, mut repo, scope) = fixture();
    seed(&mut repo, scope.clone());
    let result = repo
        .clear_with_maintenance(|_| Err(CacheError::Capacity))
        .unwrap();
    assert!(!result.compacted);
    assert_eq!(result.maintenance_error, Some(CacheError::Capacity));
    assert_eq!(result.usage.unwrap().entry_count, 0);
    assert!(repo.read(&scope, 120).unwrap().is_none());
    assert!(repo.begin_read(scope).is_ok());
    drop(repo);
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn 用量统计不需要解析业务密文() {
    let (root, mut repo, scope) = fixture();
    seed(&mut repo, scope);
    repo.db
        .execute("UPDATE entries SET body=?1", [vec![0_u8; 71]])
        .unwrap();
    let usage = repo.usage().unwrap();
    assert_eq!(usage.entry_count, 1);
    assert_eq!(usage.content_bytes, 71);
    drop(repo);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 旧开发格式一律拒绝且普通打开不改原库() {
    for version in [1, 2, 3, 4, 5, 6, 99] {
        let (root, mut repo, scope) = fixture();
        seed(&mut repo, scope);
        let path = repo.path().to_owned();
        repo.db
            .pragma_update(None, "user_version", version)
            .unwrap();
        drop(repo);
        let before = std::fs::read(&path).unwrap();
        assert!(
            matches!(
                OfflineRepository::open(
                    &root,
                    "0123456789abcdef0123456789abcdef",
                    CacheKey::new([9; 32]),
                    CacheLimits::default(),
                ),
                Err(CacheError::UnsupportedVersion)
            ),
            "开发格式 {version} 需要用户显式重建"
        );
        assert_eq!(std::fs::read(&path).unwrap(), before);
        let recovery = OfflineRepository::clear_or_rebuild(
            &root,
            "0123456789abcdef0123456789abcdef",
            CacheKey::new([9; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        assert_eq!(recovery.repository.unwrap().usage().unwrap().entry_count, 0);
        std::fs::remove_dir_all(root).unwrap();
    }
}
