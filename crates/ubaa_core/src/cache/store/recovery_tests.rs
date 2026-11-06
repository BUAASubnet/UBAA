use super::*;
use crate::cache::CacheQuery;
use crate::domain::ConnectionMode;
use std::sync::atomic::{AtomicU64, Ordering};

const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";

fn fixture() -> (PathBuf, OfflineRepository, CacheScope) {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/cold_start_superseded/cache_recovery_tests")
        .join(format!(
            "{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
    std::fs::create_dir_all(&root).unwrap();
    let repository = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (
        root,
        repository,
        CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::SpocSelection,
        },
    )
}

fn selection(term: &str) -> CachePayload {
    CachePayload::SpocSelection { term: term.into() }
}

#[test]
fn 同查询跨路线提交后旧读取可复用完整结果且不能迟到发布() {
    let (root, mut repository, scope) = fixture();
    let old = repository.begin_read(scope.clone()).unwrap();
    let newer = repository
        .begin_read(CacheScope {
            route: ConnectionMode::WebVpn,
            ..scope
        })
        .unwrap();
    repository
        .publish(
            &newer,
            selection("新学期"),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
    let (unchanged, recovered) = repository.recover_readonly_scan(&old).unwrap();
    let recovered = recovered.unwrap();
    assert_eq!(recovered.payload, selection("新学期"));
    assert_eq!(recovered.scope.route, ConnectionMode::WebVpn);
    assert_eq!(recovered.revision, newer.revision);
    assert_eq!(unchanged.revision, old.revision);
    assert_eq!(
        repository.publish(&old, selection("旧学期"), 101, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    );
    drop(repository);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 同查询较新读取在途时原子分配重读票据且旧票据不能发布() {
    let (root, mut repository, scope) = fixture();
    let old = repository.begin_read(scope.clone()).unwrap();
    let newer = repository.begin_read(scope).unwrap();
    let (retry, recovered) = repository.recover_readonly_scan(&old).unwrap();
    assert!(recovered.is_none());
    assert!(retry.revision > newer.revision);
    repository.validate_read(&retry).unwrap();
    assert_eq!(repository.validate_read(&old), Err(CacheError::Superseded));
    assert_eq!(
        repository.validate_read(&newer),
        Err(CacheError::Superseded)
    );
    drop(repository);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 已有新完整结果但更新请求在途时仍分配重读而不复用旧提交() {
    let (root, mut repository, scope) = fixture();
    let old = repository.begin_read(scope.clone()).unwrap();
    let completed = repository.begin_read(scope.clone()).unwrap();
    repository
        .publish(
            &completed,
            selection("已完成学期"),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
    let pending = repository.begin_read(scope).unwrap();
    let (retry, recovered) = repository.recover_readonly_scan(&old).unwrap();
    assert!(recovered.is_none());
    assert!(retry.revision > pending.revision);
    repository.validate_read(&retry).unwrap();
    drop(repository);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 希冀摘要完整提交可复用而部分提交需要重读() {
    for completeness in [CacheCompleteness::Complete, CacheCompleteness::Partial] {
        let (root, mut repository, mut scope) = fixture();
        scope.query = CacheQuery::JudgeSummaries {
            include_expired: false,
        };
        let old = repository.begin_read(scope.clone()).unwrap();
        let newer = repository.begin_read(scope).unwrap();
        repository
            .publish(
                &newer,
                CachePayload::JudgeSummaries(Vec::new()),
                100,
                completeness,
            )
            .unwrap();
        let (retry, recovered) = repository.recover_readonly_scan(&old).unwrap();
        if completeness == CacheCompleteness::Complete {
            assert_eq!(
                recovered.unwrap().payload,
                CachePayload::JudgeSummaries(Vec::new())
            );
            assert_eq!(retry.revision, old.revision);
        } else {
            assert!(recovered.is_none());
            assert!(retry.revision > newer.revision);
            repository.validate_read(&retry).unwrap();
        }
        drop(repository);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 无同键替代证据和已经消费的原票据均不恢复() {
    let (root, mut repository, scope) = fixture();
    let old = repository.begin_read(scope.clone()).unwrap();
    assert!(matches!(
        repository.recover_readonly_scan(&old),
        Err(CacheError::Superseded)
    ));
    repository
        .publish(&old, selection("原学期"), 100, CacheCompleteness::Complete)
        .unwrap();
    assert!(matches!(
        repository.recover_readonly_scan(&old),
        Err(CacheError::Superseded)
    ));
    let old = repository.begin_read(scope.clone()).unwrap();
    let newer = repository.begin_read(scope).unwrap();
    repository.record_failure(&newer, 101).unwrap();
    assert!(matches!(
        repository.recover_readonly_scan(&old),
        Err(CacheError::Superseded)
    ));
    drop(repository);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 清理退出重开和账号变化后即使有新提交也不能恢复旧票据() {
    for reason in 0..5 {
        let (root, mut repository, scope) = fixture();
        let mut old = repository.begin_read(scope.clone()).unwrap();
        match reason {
            0 => repository.clear().unwrap(),
            1 => {
                repository.deactivate().unwrap();
                assert!(matches!(
                    repository.recover_readonly_scan(&old),
                    Err(CacheError::Inactive)
                ));
                repository.activate().unwrap();
            }
            2 => {
                repository.clear_for_reopen().unwrap();
            }
            3 => old.account = "abcdef0123456789abcdef0123456789".into(),
            _ => {
                let database = repository.path().to_owned();
                drop(repository);
                std::fs::remove_file(database).unwrap();
                repository = OfflineRepository::open(
                    &root,
                    ACCOUNT,
                    CacheKey::new([9; 32]),
                    CacheLimits::default(),
                )
                .unwrap();
            }
        }
        let newer = repository.begin_read(scope).unwrap();
        repository
            .publish(
                &newer,
                selection("新学期"),
                100,
                CacheCompleteness::Complete,
            )
            .unwrap();
        assert!(matches!(
            repository.recover_readonly_scan(&old),
            Err(CacheError::Superseded)
        ));
        drop(repository);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 重开清理后旧仓库句柄不能为新请求恢复旧票据() {
    let (root, mut repository, scope) = fixture();
    let old = repository.begin_read(scope.clone()).unwrap();
    let mut replacement = OfflineRepository::open(
        &root,
        ACCOUNT,
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    replacement.clear_for_reopen().unwrap();
    let newer = replacement.begin_read(scope).unwrap();
    assert!(matches!(
        repository.recover_readonly_scan(&old),
        Err(CacheError::Superseded)
    ));
    replacement.validate_read(&newer).unwrap();
    drop((repository, replacement));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 学校写入影响的查询在失效和较新读取后仍不能恢复旧票据() {
    let (root, mut repository, mut scope) = fixture();
    scope.query = CacheQuery::EvaluationCurrent;
    let old = repository.begin_read(scope.clone()).unwrap();
    repository
        .invalidate(
            ConnectionMode::Direct,
            &super::invalidation::CacheInvalidation::Evaluation,
        )
        .unwrap();
    let newer = repository.begin_read(scope).unwrap();
    assert!(matches!(
        repository.recover_readonly_scan(&old),
        Err(CacheError::Superseded)
    ));
    repository.validate_read(&newer).unwrap();
    drop(repository);
    std::fs::remove_dir_all(root).unwrap();
}
