use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Barrier, Mutex};

use super::super::cookies::StoredCookie;
use super::FileSessionStore;

use super::super::types::{DualSessionMutation, DualSessionSnapshot, RouteSessionSnapshot};

#[test]
fn dual_versioned_load_never_pairs_a_snapshot_with_a_later_revision() {
    let root = test_root("dual-versioned-consistency");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let initial = dual_snapshot_for_revision(1);
    assert_eq!(
        store.compare_exchange_dual(0, Some(&initial)).unwrap(),
        DualSessionMutation::Applied { revision: 1 }
    );

    let start = Arc::new(Barrier::new(2));
    let writer_done = Arc::new(AtomicBool::new(false));
    let read_count = Arc::new(AtomicU64::new(0));
    let mismatch = Arc::new(Mutex::new(None));

    let writer = {
        let root = root.clone();
        let start = Arc::clone(&start);
        let writer_done = Arc::clone(&writer_done);
        std::thread::spawn(move || {
            let store = FileSessionStore::new(root).unwrap();
            start.wait();
            for expected_revision in 1..=128 {
                if writer_done.load(Ordering::Acquire) {
                    break;
                }
                let next_revision = expected_revision + 1;
                let replacement = dual_snapshot_for_revision(next_revision);
                assert_eq!(
                    retry_busy(
                        || store.compare_exchange_dual(expected_revision, Some(&replacement))
                    ),
                    DualSessionMutation::Applied {
                        revision: next_revision
                    }
                );
                std::thread::yield_now();
            }
            writer_done.store(true, Ordering::Release);
        })
    };

    let reader = {
        let root = root.clone();
        let start = Arc::clone(&start);
        let writer_done = Arc::clone(&writer_done);
        let read_count = Arc::clone(&read_count);
        let mismatch = Arc::clone(&mismatch);
        std::thread::spawn(move || {
            let store = FileSessionStore::new(root).unwrap();
            start.wait();
            loop {
                let loaded = retry_busy(|| store.load_dual_versioned());
                read_count.fetch_add(1, Ordering::Relaxed);
                let marker = loaded
                    .snapshot
                    .as_ref()
                    .and_then(DualSessionSnapshot::direct)
                    .expect("the writer always keeps a direct slot")
                    .authenticated_at;
                if marker != i64::try_from(loaded.revision).expect("test revision fits in i64") {
                    *mismatch.lock().unwrap() = Some((marker, loaded.revision));
                    writer_done.store(true, Ordering::Release);
                    break;
                }
                if writer_done.load(Ordering::Acquire) {
                    break;
                }
                std::thread::yield_now();
            }
        })
    };

    writer.join().unwrap();
    reader.join().unwrap();
    assert!(read_count.load(Ordering::Relaxed) > 0);
    assert_eq!(
        *mismatch.lock().unwrap(),
        None,
        "snapshot and revision must be read during one lock interval"
    );
    let loaded = store.load_dual_versioned().unwrap();
    let next_revision = loaded.revision.checked_add(1).unwrap();
    assert_eq!(
        store
            .compare_exchange_dual(
                loaded.revision,
                Some(&dual_snapshot_for_revision(next_revision)),
            )
            .unwrap(),
        DualSessionMutation::Applied {
            revision: next_revision
        }
    );
    let _ = std::fs::remove_dir_all(root);
}

// 新的两秒锁预算允许竞争者显式返回资源忙；只重试尚未取得锁的本地操作。
// 不跳过任何成功读取的快照/修订匹配断言，也不接受其他错误。
fn retry_busy<T>(mut action: impl FnMut() -> crate::error::Result<T>) -> T {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
    loop {
        match action() {
            Ok(value) => return value,
            Err(error) => {
                assert_eq!(
                    error.initialization_failure(),
                    Some(crate::error::InitializationFailure::ResourceBusy)
                );
                assert!(
                    std::time::Instant::now() < deadline,
                    "合成竞争必须最终取得进展"
                );
            }
        }
    }
}

fn dual_snapshot_for_revision(revision: u64) -> DualSessionSnapshot {
    let marker = i64::try_from(revision).expect("test revision fits in i64");
    DualSessionSnapshot::new(
        Some(RouteSessionSnapshot {
            cookies: vec![StoredCookie::fixture("REVISION", revision.to_string())],
            authenticated_at: marker,
            last_activity: marker,
        }),
        None,
    )
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-session-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
