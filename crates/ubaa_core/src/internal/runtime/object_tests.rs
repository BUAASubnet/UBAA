use super::*;
use crate::domain::{ConnectionMode, RequiredRecoveryControl, bhpan::BhpanTransferPhase};
use std::time::Duration;

enum Stop {
    Deadline,
    Cancel,
    Closed,
}
async fn stops_after_materials(stop: Stop) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/integration/runtime_tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        super::super::bearer_tests::BearerTransport(Arc::default()),
        crate::session::FileSessionStore::new(root.join("session")).unwrap(),
    )
    .unwrap();
    let transfer = BhpanTransfer::new();
    transfer.set(BhpanTransferPhase::Uploading, 0, 5);
    let control = RequiredRecoveryControl::new(if matches!(stop, Stop::Deadline) {
        Duration::from_secs(1)
    } else {
        Duration::from_secs(30)
    })
    .unwrap();
    let (locked, ready) = std::sync::mpsc::sync_channel(0);
    let (release, wait_release) = std::sync::mpsc::sync_channel(1);
    let path = root.join("materials.lock");
    let wait = control.clone();
    let cancel = transfer.clone();
    let closed = runtime.consumer_closed.clone();
    let worker = std::thread::spawn(move || {
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)
            .unwrap();
        file.lock().unwrap();
        locked.send(()).unwrap();
        wait_release.recv().unwrap();
        match stop {
            Stop::Deadline => {
                while wait.check().is_ok() {
                    std::thread::sleep(Duration::from_millis(10));
                }
            }
            Stop::Cancel => cancel.cancel(),
            Stop::Closed => closed.store(true, Ordering::SeqCst),
        }
        drop(file);
    });
    ready.recv().unwrap();
    let mut guard = crate::facade::SharedAccountGuard::new(&root, 1).unwrap();
    let release_sent = AtomicBool::new(false);
    guard.wait_hook = Some(Arc::new(move || {
        if !release_sent.swap(true, Ordering::SeqCst) {
            release.send(()).unwrap();
        }
    }));
    runtime.shared_account = Some(guard);
    let check = control.clone();
    let observer = crate::facade::with_operation_control(move || check.check(), async {
        runtime.object_observer(&transfer)
    })
    .await;
    control.check().unwrap();
    let result = observer.check();
    if result.is_ok() {
        observer.advance(5);
    }
    worker.join().unwrap();
    assert!(result.is_err(), "材料锁释放后必须复核原控制资格");
    assert_eq!(transfer.progress().bytes, 0);
    drop(observer);
    drop(runtime);
    std::fs::remove_dir_all(root).unwrap();
}
#[tokio::test]
async fn 流块等待材料锁跨过原期限后拒绝当前块且不推进进度() {
    stops_after_materials(Stop::Deadline).await;
}
#[tokio::test]
async fn 流块等待材料锁期间取消文件任务后不推进当前块() {
    stops_after_materials(Stop::Cancel).await;
}
#[tokio::test]
async fn 流块等待材料锁期间释放客户端后不推进当前块() {
    stops_after_materials(Stop::Closed).await;
}
