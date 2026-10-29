use super::*;
use crate::domain::ConnectionMode;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::sync::Notify;

#[derive(Clone)]
struct Transport(Arc<AtomicUsize>);
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        let mut response = HttpResponse::new(200, request.url, Vec::new());
        response.headers.insert(
            "Set-Cookie".into(),
            vec!["BUSINESS=fixture; Path=/; Secure".into()],
        );
        Ok(response)
    }
}

#[test]
fn 读取实例保留自己的业务状态且不覆盖持久会话或主写客户端() {
    let root = std::env::temp_dir().join(format!("ubaa-readonly-runtime-{}", std::process::id()));
    let store = FileSessionStore::new(&root).unwrap();
    store
        .compare_exchange(
            store.load_versioned().unwrap().revision,
            Some(&SessionSnapshot {
                mode: ConnectionMode::Direct,
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1001,
            }),
        )
        .unwrap();
    let requests = Arc::new(AtomicUsize::new(0));
    let mut parent = ClientRuntime::new(
        ConnectionMode::Direct,
        Transport(requests.clone()),
        store.clone(),
    )
    .unwrap();
    let mut first = parent.fork_parallel_readonly();
    let mut second = parent.fork_parallel_readonly();
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let before = std::fs::read(store.path()).unwrap();
    executor
        .block_on(first.request(HttpRequest::get("https://example.test/read")))
        .unwrap();
    first.refresh_authentication(&mut || {}).unwrap();
    second.refresh_authentication(&mut || {}).unwrap();
    assert_eq!(std::fs::read(store.path()).unwrap(), before);
    assert_eq!(
        first
            .cookie_value("BUSINESS", "https://example.test/read")
            .unwrap()
            .as_deref(),
        Some("fixture")
    );
    assert!(
        parent
            .cookie_value("BUSINESS", "https://example.test/read")
            .unwrap()
            .is_none()
    );
    assert!(
        second
            .cookie_value("BUSINESS", "https://example.test/read")
            .unwrap()
            .is_none()
    );
    assert!(!Arc::ptr_eq(
        &first.feature_state(),
        &parent.feature_state()
    ));
    parent.refresh_authentication(&mut || {}).unwrap();
    assert!(first.synchronize_readonly(&parent));
    first.ensure_session_revision().unwrap();
    assert!(
        first
            .cookie_value("BUSINESS", "https://example.test/read")
            .unwrap()
            .is_some()
    );
    let before = std::fs::read(store.path()).unwrap();
    let error =
        executor
            .block_on(first.request_non_idempotent(HttpRequest::post(
                "https://example.test/write",
                Vec::new(),
            )))
            .unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidInput);
    assert!(first.ensure_primary_client().is_err());
    assert_eq!(requests.load(Ordering::SeqCst), 1);
    first.clear_with(|| {}).unwrap();
    assert_eq!(std::fs::read(store.path()).unwrap(), before);
    assert!(!second.synchronize_readonly(&parent));
    let error = executor
        .block_on(second.request(HttpRequest::get("https://example.test/late")))
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(requests.load(Ordering::SeqCst), 1);
    std::fs::remove_dir_all(root).unwrap();
}

#[derive(Clone, Default)]
struct DelayedTransport {
    started: Arc<Notify>,
    finish: Arc<Notify>,
}
#[async_trait::async_trait]
impl HttpTransport for DelayedTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.started.notify_one();
        self.finish.notified().await;
        Ok(HttpResponse::new(200, request.url, b"synthetic".to_vec()))
    }
}

#[test]
fn 主会话失效后在途响应不能返回为成功() {
    let root = std::env::temp_dir().join(format!("ubaa-readonly-late-{}", std::process::id()));
    let transport = DelayedTransport::default();
    let mut parent = ClientRuntime::new(
        ConnectionMode::WebVpn,
        transport.clone(),
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let mut worker = parent.fork_parallel_readonly();
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    executor.block_on(async {
        let mut request =
            std::pin::pin!(worker.request(HttpRequest::get("https://example.test/read")));
        std::future::poll_fn(|context| {
            assert!(
                request.as_mut().poll(context).is_pending(),
                "请求应等待响应"
            );
            std::task::Poll::Ready(())
        })
        .await;
        transport.started.notified().await;
        parent.clear_memory();
        transport.finish.notify_one();
        assert_eq!(
            request.await.unwrap_err().code,
            ErrorCode::AuthenticationRequired
        );
    });
    std::fs::remove_dir_all(root).unwrap();
}
