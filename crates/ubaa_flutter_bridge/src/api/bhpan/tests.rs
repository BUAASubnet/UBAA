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
