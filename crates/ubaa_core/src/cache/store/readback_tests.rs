use super::{readback::*, *};
use crate::cache::CacheQuery;
use crate::domain::{ConnectionMode, TodayClass};

const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn open(root: &Path) -> OfflineRepository {
    OfflineRepository::open(
        root,
        ACCOUNT,
        CacheKey::new([17; 32]),
        CacheLimits::default(),
    )
    .unwrap()
}
fn fixture() -> (PathBuf, OfflineRepository) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-readback-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    std::fs::create_dir_all(&root).unwrap();
    let repo = open(&root);
    (root, repo)
}
fn begin(repo: &mut OfflineRepository) -> WriteReadbackTicket {
    repo.begin_write_readback(
        WriteReadbackOperation::SigninPerform,
        ConnectionMode::Direct,
        1_800_000_000,
    )
    .unwrap()
}
fn scope() -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-09-23".into(),
        },
    }
}

#[test]
fn 进程中断后只恢复加密核对线索且白名单不含意图和目标() {
    let (root, mut repo) = fixture();
    let _in_flight = begin(&mut repo);
    drop(repo);
    let mut reopened = open(&root);
    let hints = reopened.write_readback_hints().unwrap();
    assert_eq!(hints.len(), 1, "重启必须保留可能已发出的显式操作线索");
    let hint = &hints[0];
    assert_eq!(hint.operation, WriteReadbackOperation::SigninPerform);
    assert_eq!(hint.route, ConnectionMode::Direct);
    assert_eq!(hint.started_at, 1_800_000_000);
    let value = serde_json::to_value(hint).unwrap();
    let fields: std::collections::BTreeSet<_> = value
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(
        fields,
        ["id", "operation", "route", "startedAt"]
            .into_iter()
            .collect()
    );
    let bytes = std::fs::read(reopened.path()).unwrap();
    for secret in ["signinPerform", "1800000000", ACCOUNT] {
        assert!(
            !bytes
                .windows(secret.len())
                .any(|window| window == secret.as_bytes())
        );
    }
    let mut contaminated = value;
    contaminated["intentId"] = serde_json::json!("synthetic-forbidden");
    assert!(serde_json::from_value::<WriteReadbackHint>(contaminated).is_err());
    reopened.dismiss_write_readback(&hint.id).unwrap();
    assert!(reopened.write_readback_hints().unwrap().is_empty());
    drop((reopened,));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 确定结果只移除本轮提示且路线不合并() {
    let (root, mut repo) = fixture();
    let first = begin(&mut repo);
    repo.begin_write_readback(
        WriteReadbackOperation::EvaluationSubmitCourses,
        ConnectionMode::WebVpn,
        1_800_000_001,
    )
    .unwrap();
    assert_eq!(repo.write_readback_hints().unwrap().len(), 2);
    repo.finish_write_readback(&first).unwrap();
    let remaining = repo.write_readback_hints().unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].route, ConnectionMode::WebVpn);
    assert_eq!(
        remaining[0].operation,
        WriteReadbackOperation::EvaluationSubmitCourses
    );
    assert_eq!(repo.usage().unwrap().entry_count, 1);
    drop((repo,));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 退出隐藏提示但重登可核对而旧收尾不能删除() {
    let (root, mut repo) = fixture();
    let ticket = begin(&mut repo);
    repo.deactivate().unwrap();
    assert_eq!(repo.write_readback_hints(), Err(CacheError::Inactive));
    assert!(matches!(
        repo.begin_write_readback(
            WriteReadbackOperation::SigninPerform,
            ConnectionMode::Direct,
            1_800_000_001
        ),
        Err(CacheError::Inactive)
    ));
    repo.activate().unwrap();
    assert_eq!(
        repo.finish_write_readback(&ticket),
        Err(CacheError::Superseded)
    );
    assert_eq!(repo.write_readback_hints().unwrap().len(), 1);
    drop((repo,));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 清理撤销提示和旧收尾且另一句柄不能复活() {
    let (root, mut repo) = fixture();
    let ticket = begin(&mut repo);
    let mut old = open(&root);
    repo.clear_for_reopen().unwrap();
    assert!(repo.write_readback_hints().unwrap().is_empty());
    assert_eq!(
        repo.finish_write_readback(&ticket),
        Err(CacheError::Superseded)
    );
    assert_eq!(old.write_readback_hints(), Err(CacheError::Superseded));
    assert_eq!(repo.usage().unwrap().entry_count, 0);
    drop((old, repo));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 随机提示标识与账号作为认证加密绑定() {
    let (root, mut repo) = fixture();
    let ticket = begin(&mut repo);
    let (id, body): (String, Vec<u8>) = repo
        .db
        .query_row("SELECT id,body FROM readback_hints", [], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .unwrap();
    let mut other = OfflineRepository::open(
        &root,
        "abcdef0123456789abcdef0123456789",
        CacheKey::new([17; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    assert!(other.write_readback_hints().unwrap().is_empty());
    assert_eq!(
        other.finish_write_readback(&ticket),
        Err(CacheError::Superseded)
    );
    other
        .db
        .execute(
            "INSERT INTO readback_hints VALUES(?1,?2)",
            params![id, body],
        )
        .unwrap();
    assert_eq!(other.write_readback_hints(), Err(CacheError::Corrupt));
    repo.db
        .execute(
            "UPDATE readback_hints SET id=?1",
            ["00000000000000000000000000000000"],
        )
        .unwrap();
    assert_eq!(repo.write_readback_hints(), Err(CacheError::Corrupt));
    drop((other, repo));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 提示达到上限不淘汰未核实记录且容量计入密文() {
    let (root, mut repo) = fixture();
    for _ in 0..64 {
        begin(&mut repo);
    }
    assert!(matches!(
        repo.begin_write_readback(
            WriteReadbackOperation::SigninPerform,
            ConnectionMode::Direct,
            1_800_000_001
        ),
        Err(CacheError::Capacity)
    ));
    let before = repo.usage().unwrap();
    assert_eq!(before.entry_count, 64);
    assert!(before.content_bytes > 0);
    repo.limits.hard_bytes = before.content_bytes + 10;
    repo.limits.soft_bytes = repo.limits.hard_bytes;
    let read = repo.begin_read(scope()).unwrap();
    assert_eq!(
        repo.publish(
            &read,
            CachePayload::Today(vec![TodayClass::default()]),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Capacity)
    );
    assert_eq!(repo.write_readback_hints().unwrap().len(), 64);
    drop((repo,));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 无效时间标识和硬容量错误不假称保存() {
    let (root, mut repo) = fixture();
    assert!(matches!(
        repo.begin_write_readback(
            WriteReadbackOperation::SigninPerform,
            ConnectionMode::Direct,
            0
        ),
        Err(CacheError::InvalidInput)
    ));
    assert_eq!(
        repo.dismiss_write_readback("synthetic-intent"),
        Err(CacheError::InvalidInput)
    );
    repo.limits.hard_bytes = 64;
    repo.limits.soft_bytes = 64;
    assert!(matches!(
        repo.begin_write_readback(
            WriteReadbackOperation::SigninPerform,
            ConnectionMode::Direct,
            1_800_000_000
        ),
        Err(CacheError::Capacity)
    ));
    assert!(repo.write_readback_hints().unwrap().is_empty());
    drop((repo,));
    std::fs::remove_dir_all(root).unwrap();
}
