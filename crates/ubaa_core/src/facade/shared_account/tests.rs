use super::*;
use crate::domain::agenda::{AgendaContent, AgendaItem, AgendaKind, AgendaTime};
use crate::facade::{AgendaStore, CacheError, CacheKey, CacheLimits, OfflineCache};
use std::io::{BufRead, Write};
use std::process::{Command, Stdio};
const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn root() -> PathBuf {
    let p = std::env::temp_dir().join(format!(
        "ubaa-shared-{}-{}",
        std::process::id(),
        uuid::Uuid::new_v4()
    ));
    std::fs::create_dir_all(&p).unwrap();
    std::fs::write(p.join("materials.lock"), "").unwrap();
    std::fs::write(p.join("transaction.v1"), "UBAA1:C").unwrap();
    publish(&p, 1);
    p
}
fn publish(root: &Path, generation: u64) {
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .open(root.join("materials.lock"))
        .unwrap();
    lock.lock().unwrap();
    std::fs::write(
        root.join("account-generation.v1"),
        format!("UBAA1:{generation}"),
    )
    .unwrap();
}
fn item() -> AgendaItem {
    AgendaItem::new(
        AgendaContent {
            kind: AgendaKind::Task,
            title: "合成事项".into(),
            location: None,
            notes: None,
            color: None,
            start: None,
            end: None,
            all_day: false,
            due: None,
        },
        AgendaTime::new("2026-11-02T10:00:00+08:00".parse().unwrap()),
    )
}
fn open(root: &Path, generation: u64) -> (AgendaStore, OfflineCache) {
    let guard = SharedAccountGuard::new(root, generation).unwrap();
    (
        AgendaStore::open_shared(root, ACCOUNT, guard.clone()).unwrap(),
        OfflineCache::open_shared(
            root,
            ACCOUNT,
            "synthetic-user",
            CacheKey::new([7; 32]),
            CacheLimits::default(),
            guard,
        )
        .unwrap(),
    )
}
#[test]
fn 普通句柄释放保留另一消费者并且版本撤销永久隔离旧句柄() {
    let root = root();
    let (a, ca) = open(&root, 1);
    let (b, cb) = open(&root, 1);
    drop((a, ca));
    let value = item();
    b.create(value.clone()).unwrap();
    cb.clear().unwrap();
    assert_eq!(b.unsynced_count().unwrap(), 1);
    assert_eq!(cb.usage().unwrap().entry_count, 0);
    publish(&root, 2);
    assert_eq!(b.create(item()), Err(CacheError::Superseded));
    assert_eq!(cb.clear(), Err(CacheError::Superseded));
    let (current, _) = open(&root, 2);
    assert_eq!(current.get(value.id).unwrap(), Some(value));
    assert_eq!(current.unsynced_count().unwrap(), 1);
    publish(&root, 1); // 旧句柄在观察撤销后不能因版本倒退恢复。
    assert_eq!(b.unsynced_count(), Err(CacheError::Superseded));
    drop((b, cb, current));
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 材料锁前排队的真实事务在外部撤销后不提交() {
    let root = root();
    let (store, cache) = open(&root, 1);
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .open(root.join("materials.lock"))
        .unwrap();
    lock.lock().unwrap();
    let entered = std::sync::Barrier::new(2);
    let entered = Arc::new(entered);
    let worker = Arc::clone(&entered);
    let t = std::thread::spawn(move || {
        worker.wait();
        let a = store.create(item());
        let b = cache.clear();
        (a, b)
    });
    entered.wait();
    std::fs::write(root.join("account-generation.v1"), "UBAA1:2").unwrap();
    drop(lock);
    let (a, b) = t.join().unwrap();
    assert_eq!(a, Err(CacheError::Superseded));
    assert_eq!(b, Err(CacheError::Superseded));
    let (current, _) = open(&root, 2);
    assert_eq!(current.unsynced_count().unwrap(), 0);
    drop(current);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 未完成材料事务和损坏版本均拒绝实际存储且保留记录() {
    for value in ["损坏", "UBAA1:2"] {
        let root = root();
        let (store, _) = open(&root, 1);
        let value_item = item();
        store.create(value_item.clone()).unwrap();
        std::fs::write(root.join("account-generation.v1"), value).unwrap();
        assert_eq!(store.create(item()), Err(CacheError::Superseded));
        assert_eq!(
            AgendaStore::open(&root, ACCOUNT)
                .unwrap()
                .get(value_item.id)
                .unwrap(),
            Some(value_item)
        );
        drop(store);
        std::fs::remove_dir_all(root).unwrap();
    }
    let root = root();
    let (store, _) = open(&root, 1);
    std::fs::write(root.join("transaction.v1"), "UBAA1:B").unwrap();
    assert_eq!(store.create(item()), Err(CacheError::Superseded));
    drop(store);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 子进程材料与真实存储工作器() {
    let Ok(root) = std::env::var("UBAA_SYNTHETIC_SHARED_ROOT") else {
        return;
    };
    let root = PathBuf::from(root);
    let (store, cache) = open(&root, 1);
    let mode = std::env::var("UBAA_SYNTHETIC_SHARED_MODE").unwrap();
    let _permit = if mode == "hold" {
        Some(
            SharedAccountGuard::new(&root, 1)
                .unwrap()
                .acquire()
                .unwrap(),
        )
    } else {
        None
    };
    println!("SYNTHETIC_READY");
    std::io::stdout().flush().unwrap();
    let mut line = String::new();
    std::io::stdin().read_line(&mut line).unwrap();
    if mode == "work" {
        store.create(item()).unwrap();
        cache.clear().unwrap();
        assert_eq!(cache.usage().unwrap().entry_count, 0);
    }
    drop((store, cache));
}
fn child(
    root: &Path,
    mode: &str,
) -> (
    std::process::Child,
    std::io::BufReader<std::process::ChildStdout>,
) {
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "facade::shared_account::tests::子进程材料与真实存储工作器",
            "--nocapture",
        ])
        .env("UBAA_SYNTHETIC_SHARED_ROOT", root)
        .env("UBAA_SYNTHETIC_SHARED_MODE", mode)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .unwrap();
    let mut lines = std::io::BufReader::new(child.stdout.take().unwrap());
    let mut line = String::new();
    loop {
        assert!(lines.read_line(&mut line).unwrap() > 0);
        if line.contains("SYNTHETIC_READY") {
            break;
        }
        line.clear();
    }
    (child, lines)
}
#[test]
fn 真实双进程普通关闭和崩溃不破坏另一消费者() {
    for crashed in [false, true] {
        let root = root();
        let (mut a, _a_output) = child(&root, if crashed { "hold" } else { "close" });
        let (mut b, _b_output) = child(&root, "work");
        if crashed {
            a.kill().unwrap();
            a.wait().unwrap();
        } else {
            a.stdin.as_mut().unwrap().write_all(b"CLOSE\n").unwrap();
            assert!(a.wait().unwrap().success());
        }
        b.stdin.as_mut().unwrap().write_all(b"GO\n").unwrap();
        assert!(b.wait().unwrap().success());
        let (store, cache) = open(&root, 1);
        assert_eq!(store.unsynced_count().unwrap(), 1);
        assert_eq!(cache.usage().unwrap().entry_count, 0);
        drop((store, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}
