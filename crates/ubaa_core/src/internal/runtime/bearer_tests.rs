use super::*;
use std::sync::atomic::AtomicUsize;

#[derive(Clone)]
pub(super) struct BearerTransport(pub(super) Arc<AtomicUsize>);
#[async_trait::async_trait]
impl HttpTransport for BearerTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        assert!(!request.headers.contains_key("Cookie"));
        let mut response = HttpResponse::new(200, request.url, b"{}".to_vec());
        response.headers.insert(
            "Set-Cookie".into(),
            vec!["NAV=forbidden; Path=/; Secure".into()],
        );
        Ok(response)
    }
}

async fn stopped_while_waiting(write: bool, cancel: bool, transfer_cancel: bool) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
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
    let calls = Arc::new(AtomicUsize::new(0));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        BearerTransport(calls.clone()),
        crate::session::FileSessionStore::new(root.join("session")).unwrap(),
    )
    .unwrap();
    runtime
        .set_scoped_cookie("NAV=private; Path=/; Secure", "https://synthetic.invalid")
        .unwrap();
    let transfer = crate::features::bhpan::transfer::BhpanTransfer::new();
    let stop_transfer = transfer.clone();
    let closed = runtime.consumer_closed.clone();
    let control =
        crate::domain::RequiredRecoveryControl::new(std::time::Duration::from_secs(30)).unwrap();
    runtime.set_required_recovery_scope(Some(control.clone()));
    let (start, started) = std::sync::mpsc::sync_channel(0);
    let (locked, wait_locked) = std::sync::mpsc::sync_channel(0);
    let (release, wait_release) = std::sync::mpsc::sync_channel(1);
    let fallback = release.clone();
    let lock_path = root.join("materials.lock");
    let worker = std::thread::spawn(move || {
        started.recv().unwrap();
        let lock = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(lock_path)
            .unwrap();
        lock.lock().unwrap();
        locked.send(()).unwrap();
        wait_release.recv().unwrap();
    });
    let observed = Arc::new(AtomicBool::new(false));
    let hook = observed.clone();
    let mut guard = crate::facade::SharedAccountGuard::new(&root, 1).unwrap();
    guard.wait_hook = Some(Arc::new(move || {
        if !hook.swap(true, Ordering::SeqCst) {
            if transfer_cancel {
                stop_transfer.cancel();
            } else if cancel {
                control.cancel();
            } else {
                closed.store(true, Ordering::SeqCst);
            }
            release.send(()).unwrap();
        }
    }));
    runtime.shared_account = Some(guard);
    let started_once = AtomicBool::new(false);
    let result = runtime
        .request_bearer_only_checked(
            HttpRequest::get("https://synthetic.invalid/bearer"),
            write,
            |_| {
                if !started_once.swap(true, Ordering::SeqCst) {
                    start.send(()).unwrap();
                    wait_locked.recv().unwrap();
                }
                transfer.ensure_active()
            },
        )
        .await;
    if !observed.load(Ordering::SeqCst) {
        fallback.send(()).unwrap();
    }
    worker.join().unwrap();
    let sent = calls.load(Ordering::SeqCst);
    let crossed = runtime.take_non_idempotent_boundary_crossed();
    drop(runtime);
    std::fs::remove_dir_all(root).unwrap();
    assert!(
        observed.load(Ordering::SeqCst),
        "请求必须在发送前等待材料锁"
    );
    assert!(result.is_err());
    assert_eq!(sent, 0);
    assert!(!crossed);
}

#[tokio::test]
async fn bearer读取等待材料锁后关闭保持零发送() {
    stopped_while_waiting(false, false, false).await;
}
#[tokio::test]
async fn bearer写入等待材料锁后关闭保持零发送() {
    stopped_while_waiting(true, false, false).await;
}
#[tokio::test]
async fn bearer写入等待材料锁后取消保持零发送() {
    stopped_while_waiting(true, true, false).await;
}

#[tokio::test]
async fn bearer请求隔离导航cookie且已到期写入零发送() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/integration/runtime_tests")
        .join(uuid::Uuid::new_v4().to_string());
    let calls = Arc::new(AtomicUsize::new(0));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        BearerTransport(calls.clone()),
        crate::session::FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    runtime
        .request_bearer_only(HttpRequest::get("https://synthetic.invalid/bearer"), false)
        .await
        .unwrap();
    assert!(
        runtime
            .cookie_value("NAV", "https://synthetic.invalid")
            .unwrap()
            .is_none()
    );
    runtime.set_required_recovery_scope(Some(
        crate::domain::RequiredRecoveryControl::new(std::time::Duration::ZERO).unwrap(),
    ));
    assert_eq!(
        runtime
            .request_bearer_only(HttpRequest::get("https://synthetic.invalid/bearer"), true)
            .await
            .unwrap_err()
            .code,
        ErrorCode::Timeout
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(!runtime.take_non_idempotent_boundary_crossed());
    drop(runtime);
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn bearer等待材料锁时取消文件任务必须在发送前重新核对() {
    stopped_while_waiting(true, false, true).await;
}
