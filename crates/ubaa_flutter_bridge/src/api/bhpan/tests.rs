use super::models::BridgeBhpanMutationKind;
use super::*;
use crate::api::client::BridgeErrorCode;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use std::time::Duration;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot,
};
use ubaa_core::facade::{NetworkState, UbaaClient};
struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: Duration) -> NetworkState {
        panic!("固定路线不得探测");
    }
}
#[derive(Clone)]
struct Transport(Arc<AtomicUsize>);
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, r: HttpRequest) -> c::Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        assert!(!r.url.ends_with("/file/delete"), "合成发送边界异常");
        let mut response = HttpResponse::new(200, r.url.clone(), Vec::new());
        if r.url.contains("/anyshare/oauth2/login?") {
            response.status = 302;
            response.headers.insert(
                "Location".into(),
                vec!["/anyshare/oauth2/login/callback".into()],
            );
        } else if r.url.ends_with("/refreshToken") {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["client.oauth2_token=synthetic; Path=/; Secure".into()],
            );
        } else if r.url.ends_with("/owned-doc-lib") {
            response.body = br#"[{"id":"gns://fixture/root","name":"root"}]"#.to_vec();
        }
        Ok(response)
    }
}
#[tokio::test]
async fn 发送后panic保持结果未知且确认不可复用() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/bridge_tests")
        .join(uuid::Uuid::new_v4().to_string());
    let bridge = BridgeClient::open(root.to_string_lossy().into_owned()).unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1001,
            }),
            None,
        ))
        .unwrap();
    let count = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap();
    let core = UbaaClient::with_routing(
        Transport(count.clone()),
        Transport(count.clone()),
        store,
        config,
        NeverProbe,
    )
    .unwrap();
    *bridge.inner.lock().await = Some(core);
    let page = bridge
        .bhpan_read(BridgeBhpanQuery {
            view: BridgeBhpanReadView::PersonalRoot,
            root: None,
            target: None,
            link: None,
            password: None,
        })
        .await
        .unwrap();
    let prepared = bridge
        .bhpan_prepare(BridgeBhpanWrite {
            kind: BridgeBhpanMutationKind::Recycle,
            target: page.items[0].handle.clone(),
            name: None,
            destination: None,
            settings: None,
        })
        .await
        .unwrap();
    assert_eq!(
        bridge
            .bhpan_commit(prepared.handle.clone())
            .await
            .unwrap_err()
            .code,
        BridgeErrorCode::OutcomeUnknown
    );
    let sent = count.load(Ordering::SeqCst);
    assert!(bridge.bhpan_commit(prepared.handle).await.is_err());
    assert_eq!(count.load(Ordering::SeqCst), sent);
    bridge.dispose().await.unwrap();
    drop(bridge);
    std::fs::remove_dir_all(root).unwrap();
}

struct UploadGate {
    entered: tokio::sync::Notify,
    released: tokio::sync::Notify,
}
#[derive(Clone)]
struct UploadTransport {
    base: Transport,
    gate: Arc<UploadGate>,
}
#[async_trait::async_trait]
impl HttpTransport for UploadTransport {
    async fn execute(&self, r: HttpRequest) -> c::Result<HttpResponse> {
        if r.url.ends_with("/predupload") {
            self.gate.entered.notify_one();
            self.gate.released.notified().await;
            return Ok(HttpResponse::new(200, r.url, br#"{"match":true}"#.to_vec()));
        }
        self.base.execute(r).await
    }
}
#[tokio::test]
async fn dispose在等待读取时取消旧上传准备() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/bridge_tests")
        .join(uuid::Uuid::new_v4().to_string());
    let bridge = Arc::new(BridgeClient::open(root.to_string_lossy().into_owned()).unwrap());
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1001,
            }),
            None,
        ))
        .unwrap();
    let count = Arc::new(AtomicUsize::new(0));
    let gate = Arc::new(UploadGate {
        entered: tokio::sync::Notify::new(),
        released: tokio::sync::Notify::new(),
    });
    let transport = UploadTransport {
        base: Transport(count.clone()),
        gate: gate.clone(),
    };
    let core = UbaaClient::with_routing(
        transport.clone(),
        transport,
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    *bridge.inner.lock().await = Some(core);
    let root_item = bridge
        .bhpan_read(BridgeBhpanQuery {
            view: BridgeBhpanReadView::PersonalRoot,
            root: None,
            target: None,
            link: None,
            password: None,
        })
        .await
        .unwrap()
        .items
        .remove(0);
    let path = root.join("upload.fixture");
    std::fs::write(&path, b"hello").unwrap();
    let transfer = Arc::new(BridgeBhpanTransfer::new());
    let preparing_bridge = bridge.clone();
    let preparing_transfer = transfer.clone();
    let preparing = tokio::spawn(async move {
        preparing_bridge
            .bhpan_prepare_fast_upload(
                root_item.handle,
                path.to_string_lossy().into_owned(),
                "notes.txt".into(),
                &preparing_transfer,
            )
            .await
    });
    gate.entered.notified().await;
    let disposing_bridge = bridge.clone();
    let disposing = tokio::spawn(async move { disposing_bridge.dispose().await });
    tokio::time::timeout(Duration::from_secs(2), async {
        while !bridge.is_disposed.load(Ordering::Acquire) {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    gate.released.notify_one();
    assert!(preparing.await.unwrap().is_err());
    disposing.await.unwrap().unwrap();
    assert!(matches!(
        transfer.progress().phase,
        BridgeBhpanTransferPhase::Cancelled
    ));
    drop(bridge);
    std::fs::remove_dir_all(root).unwrap();
}

struct CommitGate {
    released: tokio::sync::Notify,
    lose_response: bool,
}

#[derive(Clone)]
struct CommitTransport {
    writes: Arc<AtomicUsize>,
    gate: Option<Arc<CommitGate>>,
}

#[async_trait::async_trait]
impl HttpTransport for CommitTransport {
    async fn execute(&self, request: HttpRequest) -> c::Result<HttpResponse> {
        if request.url.ends_with("/file/delete") || request.url.ends_with("/document/anonymous") {
            self.writes.fetch_add(1, Ordering::SeqCst);
            if let Some(gate) = &self.gate {
                gate.released.notified().await;
                if gate.lose_response {
                    return Err(c::UbaaError::new(
                        c::ErrorCode::NetworkError,
                        c::ErrorKind::Network,
                        true,
                        "合成提交响应丢失",
                    ));
                }
            }
            return Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"id":"fixture-share"}"#.to_vec(),
            ));
        }
        Transport(Arc::new(AtomicUsize::new(0)))
            .execute(request)
            .await
    }
}

async fn pending_commit(
    kind: BridgeBhpanMutationKind,
    gate: Option<Arc<CommitGate>>,
) -> (BridgeClient, std::path::PathBuf, String, Arc<AtomicUsize>) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/bridge_tests")
        .join(uuid::Uuid::new_v4().to_string());
    let bridge = BridgeClient::open(root.to_string_lossy().into_owned()).unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1001,
            }),
            None,
        ))
        .unwrap();
    let writes = Arc::new(AtomicUsize::new(0));
    let transport = CommitTransport {
        writes: writes.clone(),
        gate,
    };
    let core = UbaaClient::with_routing(
        transport.clone(),
        transport,
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    *bridge.inner.lock().await = Some(core);
    let item = bridge
        .bhpan_read(BridgeBhpanQuery {
            view: BridgeBhpanReadView::PersonalRoot,
            root: None,
            target: None,
            link: None,
            password: None,
        })
        .await
        .unwrap()
        .items
        .remove(0);
    let prepared = bridge
        .bhpan_prepare(BridgeBhpanWrite {
            kind,
            target: item.handle,
            name: None,
            destination: None,
            settings: matches!(kind, BridgeBhpanMutationKind::CreateShare).then(|| {
                models::BridgeBhpanShareSettings {
                    title: "合成分享".into(),
                    expires_at: "1970-01-01T08:00:00+08:00".into(),
                    password: String::new(),
                    limited_times: -1,
                    permissions: vec![models::BridgeBhpanPermission::Display],
                }
            }),
        })
        .await
        .unwrap();
    (bridge, root, prepared.handle, writes)
}

#[tokio::test]
async fn dispose标记生效后排队的文件与分享提交均不发送() {
    for kind in [
        BridgeBhpanMutationKind::Recycle,
        BridgeBhpanMutationKind::CreateShare,
    ] {
        let (bridge, root, handle, writes) = Box::pin(pending_commit(kind, None)).await;
        let held = bridge.inner.lock().await;
        let mut commit = Box::pin(bridge.bhpan_commit(handle));
        assert!(futures_util::poll!(&mut commit).is_pending());
        let mut disposing = Box::pin(bridge.dispose());
        assert!(futures_util::poll!(&mut disposing).is_pending());
        assert!(bridge.is_disposed.load(Ordering::Acquire));
        drop(held);
        let result = commit.await;
        disposing.await.unwrap();
        drop(bridge);
        std::fs::remove_dir_all(root).unwrap();
        assert_eq!(
            writes.load(Ordering::SeqCst),
            0,
            "已释放客户端不得发送排队提交"
        );
        assert_eq!(result.unwrap_err().code, BridgeErrorCode::ClientDisposed);
    }
}

#[tokio::test]
async fn dispose不覆盖已经发送的确定或未知结果() {
    for lose_response in [false, true] {
        let gate = Arc::new(CommitGate {
            released: tokio::sync::Notify::new(),
            lose_response,
        });
        let (bridge, root, handle, writes) = Box::pin(pending_commit(
            BridgeBhpanMutationKind::Recycle,
            Some(gate.clone()),
        ))
        .await;
        let mut commit = Box::pin(bridge.bhpan_commit(handle));
        assert!(futures_util::poll!(&mut commit).is_pending());
        assert_eq!(writes.load(Ordering::SeqCst), 1);
        let mut disposing = Box::pin(bridge.dispose());
        assert!(futures_util::poll!(&mut disposing).is_pending());
        assert!(bridge.is_disposed.load(Ordering::Acquire));
        gate.released.notify_one();
        let result = commit.await;
        disposing.await.unwrap();
        assert_eq!(writes.load(Ordering::SeqCst), 1);
        if lose_response {
            let error = result.unwrap_err();
            assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
            assert!(!error.retryable);
        } else {
            result.unwrap();
        }
        drop(bridge);
        std::fs::remove_dir_all(root).unwrap();
    }
}
