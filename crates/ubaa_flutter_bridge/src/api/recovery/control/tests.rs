use super::*;
use async_trait::async_trait;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use std::time::Duration;
use ubaa_core::facade::testing::{
    FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport, RouteConfig,
    SessionSnapshot, SessionStore,
};

struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: Duration) -> core::NetworkState {
        panic!("固定路线禁止探测");
    }
}

#[derive(Default)]
struct Gate {
    started: tokio::sync::Notify,
    requests: AtomicUsize,
    dropped: AtomicUsize,
}

struct Pending(Arc<Gate>);
impl Drop for Pending {
    fn drop(&mut self) {
        self.0.dropped.fetch_add(1, Ordering::SeqCst);
    }
}

#[derive(Clone)]
struct Transport(Arc<Gate>);
#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, _: HttpRequest) -> core::Result<HttpResponse> {
        self.0.requests.fetch_add(1, Ordering::SeqCst);
        self.0.started.notify_one();
        let _pending = Pending(self.0.clone());
        std::future::pending().await
    }
}

struct Fixture {
    bridge: BridgeClient,
    gate: Arc<Gate>,
    root: std::path::PathBuf,
}
impl Fixture {
    async fn new() -> Self {
        let root = std::env::temp_dir()
            .join("ubaa-required-recovery-bridge")
            .join(uuid::Uuid::new_v4().simple().to_string());
        let bridge = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let store = FileSessionStore::new(&root).unwrap();
        store
            .save(&SessionSnapshot {
                mode: core::ConnectionMode::Direct,
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1001,
            })
            .unwrap();
        let gate = Arc::<Gate>::default();
        *bridge.inner.lock().await = Some(
            core::UbaaClient::with_routing(
                Transport(gate.clone()),
                Transport(gate.clone()),
                store,
                RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
                NeverProbe,
            )
            .unwrap(),
        );
        Self { bridge, gate, root }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

#[tokio::test]
async fn 锁排队期间取消和期限到达都零网络返回() {
    for deadline in [false, true] {
        let fixture = Box::pin(Fixture::new()).await;
        let held = fixture.bridge.inner.lock().await;
        let control = BridgeRequiredRecoveryControl::new(if deadline { 40 } else { 2000 }).unwrap();
        let mut call = Box::pin(
            fixture
                .bridge
                .recover_required_session_controlled(BridgeRecoveryFeature::Schedule, &control),
        );
        tokio::select! {
            biased;
            result = &mut call => panic!("锁应保持排队：{result:?}"),
            () = tokio::task::yield_now() => {},
        }
        if !deadline {
            control.cancel();
        }
        let error = tokio::time::timeout(Duration::from_millis(250), call)
            .await
            .expect("不释放锁也必须有界返回")
            .unwrap_err();
        assert_eq!(
            error.code,
            if deadline {
                BridgeErrorCode::Timeout
            } else {
                BridgeErrorCode::OperationConflict
            }
        );
        assert_eq!(fixture.gate.requests.load(Ordering::SeqCst), 0);
        drop(held);
        fixture.bridge.dispose().await.unwrap();
    }
}

#[tokio::test]
async fn 取消永挂传输后恢复和销毁均有界且传输确实释放() {
    let fixture = Box::pin(Fixture::new()).await;
    let control = BridgeRequiredRecoveryControl::new(2000).unwrap();
    let mut call = Box::pin(
        fixture
            .bridge
            .recover_required_session_controlled(BridgeRecoveryFeature::Schedule, &control),
    );
    tokio::select! {
        () = fixture.gate.started.notified() => {},
        result = &mut call => panic!("合成请求应挂起：{result:?}"),
    }
    control.cancel();
    let error = tokio::time::timeout(Duration::from_millis(250), call)
        .await
        .expect("恢复必须有界返回")
        .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(fixture.gate.dropped.load(Ordering::SeqCst), 1);
    tokio::time::timeout(Duration::from_millis(250), fixture.bridge.dispose())
        .await
        .expect("销毁必须有界返回")
        .unwrap();
    assert_eq!(fixture.gate.requests.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn 受控恢复保留写意图冲突且控制柄不能重复使用() {
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    let fixture = Box::pin(Fixture::new()).await;
    fixture.bridge.write_intents.lock().await.insert(
        "synthetic".into(),
        PendingEntry {
            request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
            expires_at: i64::MAX,
            resolved_route: BridgeConnectionMode::Direct,
            conflict_key: "synthetic".into(),
        },
    );
    let control = BridgeRequiredRecoveryControl::new(2000).unwrap();
    let error = fixture
        .bridge
        .login_required_route_controlled(
            BridgeConnectionMode::Direct,
            "fixture-user".into(),
            "synthetic-password".into(),
            &control,
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    fixture.bridge.write_intents.lock().await.clear();
    let error = tokio::time::timeout(
        Duration::from_millis(250),
        fixture
            .bridge
            .recover_required_session_controlled(BridgeRecoveryFeature::Schedule, &control),
    )
    .await
    .expect("重复控制柄必须在网络前拒绝")
    .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(fixture.gate.requests.load(Ordering::SeqCst), 0);
    fixture.bridge.dispose().await.unwrap();
}
