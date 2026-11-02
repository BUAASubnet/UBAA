use super::ClientRuntime;
use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, Result};
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::session::FileSessionStore;
use async_trait::async_trait;
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicU64, Ordering},
};
#[derive(Clone)]
struct NoopTransport;
#[async_trait]
impl HttpTransport for NoopTransport {
    async fn execute(&self, _: HttpRequest) -> Result<HttpResponse> {
        panic!("此断言不得发送请求")
    }
}

#[derive(Clone)]
struct SharedRevokingTransport {
    root: std::path::PathBuf,
    calls: Arc<AtomicU64>,
}
#[async_trait]
impl HttpTransport for SharedRevokingTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let lock = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(self.root.join("materials.lock"))
            .unwrap();
        assert!(lock.try_lock().is_ok(), "网络期间不得持有材料锁");
        std::fs::write(self.root.join("account-generation.v1"), "UBAA1:2").unwrap();
        Ok(HttpResponse::new(200, request.url, b"{}".to_vec()))
    }
}
#[tokio::test]
async fn 共享身份在发送后撤销保留结果未知且旧资格不可再次发送() {
    let root = std::env::temp_dir().join(format!("ubaa-shared-write-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&root).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    let calls = Arc::new(AtomicU64::new(0));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        SharedRevokingTransport {
            root: root.clone(),
            calls: calls.clone(),
        },
        FileSessionStore::new(root.join("session")).unwrap(),
    )
    .unwrap();
    runtime.shared_account = Some(crate::facade::SharedAccountGuard::new(&root, 1).unwrap());
    runtime.begin_non_idempotent_operation();
    let first = runtime
        .request_non_idempotent(HttpRequest::get("https://synthetic.invalid/write"))
        .await
        .unwrap_err();
    assert_eq!(first.code, ErrorCode::OutcomeUnknown);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    runtime.begin_non_idempotent_operation();
    let second = runtime
        .request_non_idempotent(HttpRequest::get("https://synthetic.invalid/write"))
        .await
        .unwrap_err();
    assert!(second.is_shared_account_conflict());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    drop(runtime);
    std::fs::remove_dir_all(root).unwrap();
}

#[derive(Clone)]
struct ClosingTransport {
    closed: Arc<AtomicBool>,
    calls: Arc<AtomicU64>,
}
#[async_trait]
impl HttpTransport for ClosingTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.closed.store(true, Ordering::SeqCst);
        Ok(HttpResponse::new(200, request.url, b"{}".to_vec()))
    }
}
#[tokio::test]
async fn 普通关闭只撤销本进程发送资格并区分发送前后终态() {
    let root = std::env::temp_dir().join(format!("ubaa-close-write-{}", uuid::Uuid::new_v4()));
    let calls = Arc::new(AtomicU64::new(0));
    let closed = Arc::new(AtomicBool::new(false));
    let store = FileSessionStore::new(&root).unwrap();
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        ClosingTransport {
            closed: closed.clone(),
            calls: calls.clone(),
        },
        store.clone(),
    )
    .unwrap();
    runtime.consumer_closed = closed.clone();
    runtime.begin_non_idempotent_operation();
    let error = runtime
        .request_non_idempotent(HttpRequest::get("https://synthetic.invalid/write"))
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::OutcomeUnknown);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    runtime.begin_non_idempotent_operation();
    assert!(
        runtime
            .request_non_idempotent(HttpRequest::get("https://synthetic.invalid/write"))
            .await
            .unwrap_err()
            .is_client_closed()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let other = ClientRuntime::new(ConnectionMode::Direct, NoopTransport, store).unwrap();
    assert!(other.ensure_session_revision().is_ok());
    drop((runtime, other));
    std::fs::remove_dir_all(root).unwrap();
}
