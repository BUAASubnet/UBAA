use super::*;
use crate::error::ErrorCode;
use crate::facade::NetworkState;
use crate::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpMethod, HttpRequest, HttpResponse,
    HttpTransport, RouteConfig, RouteSessionSnapshot,
};
use async_trait::async_trait;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU16, AtomicUsize, Ordering},
};
use std::time::{Duration, Instant};

const PROFILE: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../fixtures/auth/userinfo-success.json"
));

struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: Duration) -> NetworkState {
        panic!("固定路线禁止网关探测");
    }
}

#[derive(Default)]
struct Gate {
    started: tokio::sync::Notify,
    dropped: AtomicUsize,
}

struct PendingGuard(Arc<Gate>);
impl Drop for PendingGuard {
    fn drop(&mut self) {
        self.0.dropped.fetch_add(1, Ordering::SeqCst);
    }
}

#[derive(Clone)]
struct Transport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    halt_at: usize,
    halted: Arc<AtomicBool>,
    gate: Arc<Gate>,
    cancel_on_reply: Option<RequiredRecoveryControl>,
    response_status: Arc<AtomicU16>,
}

#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let index = {
            let mut requests = self.requests.lock().unwrap();
            requests.push(request.clone());
            requests.len()
        };
        if index == self.halt_at && !self.halted.swap(true, Ordering::SeqCst) {
            self.gate.started.notify_one();
            let _guard = PendingGuard(self.gate.clone());
            std::future::pending::<()>().await;
        }
        if let Some(control) = &self.cancel_on_reply {
            control.cancel();
        }
        let body = if request.url.ends_with("/login") && request.method == HttpMethod::Get {
            format!("<form id=\"fm1\"><input name=\"execution\" value=\"synthetic-execution-{index}\"></form>").into_bytes()
        } else if request.url.contains("/api/uc/") {
            PROFILE.to_vec()
        } else {
            b"ok".to_vec()
        };
        Ok(HttpResponse::new(
            self.response_status.load(Ordering::SeqCst),
            request.url,
            body,
        ))
    }
}

struct Fixture {
    client: UbaaClient,
    transport: Transport,
    store: FileSessionStore,
    root: std::path::PathBuf,
}

impl Fixture {
    fn new(halt_at: usize, saved: bool, cancel_on_reply: Option<RequiredRecoveryControl>) -> Self {
        let root = std::env::temp_dir()
            .join("ubaa-required-recovery-core")
            .join(uuid::Uuid::new_v4().simple().to_string());
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        };
        store
            .save_dual(&DualSessionSnapshot::new(
                saved.then_some(slot.clone()),
                Some(slot),
            ))
            .unwrap();
        let transport = Transport {
            requests: Arc::default(),
            halt_at,
            halted: Arc::default(),
            gate: Arc::default(),
            cancel_on_reply,
            response_status: Arc::new(AtomicU16::new(200)),
        };
        let client = UbaaClient::with_routing(
            transport.clone(),
            transport.clone(),
            store.clone(),
            RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
            NeverProbe,
        )
        .unwrap();
        Self {
            client,
            transport,
            store,
            root,
        }
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn input() -> LoginInput {
    LoginInput {
        username: "fixture-user".into(),
        password: super::super::SecretValue::new("synthetic-password"),
    }
}

#[tokio::test]
async fn 每个登录阶段取消都中止传输并清除准备状态且允许后续恢复() {
    for stage in 1..=5 {
        let mut fixture = Fixture::new(stage, false, None);
        let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        let sibling_snapshot = fixture
            .store
            .load_dual_versioned()
            .unwrap()
            .snapshot
            .unwrap()
            .sessions
            .webvpn;
        let sibling_generation = fixture
            .client
            .webvpn_runtime
            .feature_state()
            .lifecycle_generation();
        {
            let mut call = Box::pin(fixture.client.login_required_route_controlled(
                ConnectionMode::Direct,
                input(),
                control.claim().unwrap(),
            ));
            tokio::select! {
                () = fixture.transport.gate.started.notified() => {},
                result = &mut call => panic!("合成调用应挂起：{result:?}"),
            }
            control.cancel();
            let result = tokio::time::timeout(Duration::from_millis(250), call)
                .await
                .expect("取消后必须有界返回");
            assert_eq!(result.unwrap_err().code, ErrorCode::InternalError);
        }
        assert_eq!(fixture.transport.gate.dropped.load(Ordering::SeqCst), 1);
        assert_eq!(fixture.transport.requests.lock().unwrap().len(), stage);
        assert!(!fixture.client.direct_auth.has_pending_login());
        assert_eq!(
            fixture
                .client
                .webvpn_runtime
                .feature_state()
                .lifecycle_generation(),
            sibling_generation
        );
        assert_eq!(
            fixture
                .store
                .load_dual_versioned()
                .unwrap()
                .snapshot
                .unwrap()
                .sessions
                .webvpn,
            sibling_snapshot
        );
        断言中断后重新校验或获取新页面(&mut fixture, stage).await;
    }
}

async fn 断言中断后重新校验或获取新页面(fixture: &mut Fixture, stage: usize) {
    if stage == 5 {
        assert!(
            fixture
                .store
                .load_dual_versioned()
                .unwrap()
                .snapshot
                .unwrap()
                .sessions
                .direct
                .is_some(),
            "已经保存的会话不能因本机取消删除"
        );
        let next = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        fixture
            .client
            .recover_required_session_controlled(ReadonlyFeature::Schedule, next.claim().unwrap())
            .await
            .unwrap();
        assert_eq!(
            fixture
                .transport
                .requests
                .lock()
                .unwrap()
                .iter()
                .filter(|r| r.method == HttpMethod::Post)
                .count(),
            1
        );
    } else {
        let next = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        fixture
            .client
            .login_required_route_controlled(ConnectionMode::Direct, input(), next.claim().unwrap())
            .await
            .unwrap();
        let requests = fixture.transport.requests.lock().unwrap();
        assert_eq!(
            requests[stage].method,
            HttpMethod::Get,
            "中断后先获取新execution"
        );
        assert!(requests[stage].url.ends_with("/login"));
    }
    assert!(
        !fixture
            .transport
            .requests
            .lock()
            .unwrap()
            .iter()
            .any(|r| r.url.ends_with("/logout"))
    );
}

#[tokio::test]
async fn 永挂校验在取消和期限到达后释放传输且保留原会话() {
    for deadline in [false, true] {
        let mut fixture = Fixture::new(1, true, None);
        let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        let mut call = Box::pin(fixture.client.recover_required_session_controlled(
            ReadonlyFeature::Schedule,
            control.claim().unwrap(),
        ));
        tokio::select! {
            () = fixture.transport.gate.started.notified() => {},
            result = &mut call => panic!("合成调用应挂起：{result:?}"),
        }
        if !deadline {
            control.cancel();
        }
        let error = tokio::time::timeout(
            if deadline {
                Duration::from_secs(4)
            } else {
                Duration::from_millis(250)
            },
            call,
        )
        .await
        .expect("校验必须有界返回")
        .unwrap_err();
        assert_eq!(
            error.error.code,
            if deadline {
                ErrorCode::Timeout
            } else {
                ErrorCode::InternalError
            }
        );
        assert!(!error.error.retryable);
        assert_eq!(error.resolution.unwrap().mode, ConnectionMode::Direct);
        assert_eq!(fixture.transport.gate.dropped.load(Ordering::SeqCst), 1);
        assert!(
            fixture
                .store
                .load_dual_versioned()
                .unwrap()
                .snapshot
                .unwrap()
                .sessions
                .direct
                .is_some()
        );
    }
}

#[tokio::test]
async fn 登录页响应交付时撤销会阻止密码提交() {
    let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    let mut fixture = Fixture::new(0, false, Some(control.clone()));
    let result = fixture
        .client
        .login_required_route_controlled(ConnectionMode::Direct, input(), control.claim().unwrap())
        .await;
    assert!(result.is_err());
    let requests = fixture.transport.requests.lock().unwrap();
    assert_eq!(requests.len(), 1);
    assert!(requests.iter().all(|r| r.method == HttpMethod::Get));
}

#[tokio::test]
async fn 控制柄单次使用且零期限在网络前拒绝() {
    let mut fixture = Fixture::new(0, true, None);
    let immediate = RequiredRecoveryControl::new(Duration::ZERO).unwrap();
    assert_eq!(immediate.claim().unwrap_err().code, ErrorCode::Timeout);
    let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    let operation = control.claim().unwrap();
    assert!(control.claim().is_err());
    fixture
        .client
        .recover_required_session_controlled(ReadonlyFeature::Schedule, operation)
        .await
        .unwrap();
    control.cancel();
    let next = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    fixture
        .client
        .recover_required_session_controlled(ReadonlyFeature::Schedule, next.claim().unwrap())
        .await
        .unwrap();
    assert_eq!(fixture.transport.requests.lock().unwrap().len(), 2);
    assert!(RequiredRecoveryControl::new(Duration::from_millis(120_001)).is_err());
}

#[tokio::test]
async fn 普通临时故障保留原会话和业务计划代次() {
    let mut fixture = Fixture::new(0, true, None);
    fixture
        .transport
        .response_status
        .store(503, Ordering::SeqCst);
    let generation = fixture
        .client
        .direct_runtime
        .feature_state()
        .lifecycle_generation();
    let snapshot = fixture.store.load_dual_versioned().unwrap();
    let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    let error = fixture
        .client
        .recover_required_session_controlled(ReadonlyFeature::Schedule, control.claim().unwrap())
        .await
        .unwrap_err();
    assert_eq!(error.error.code, ErrorCode::UpstreamUnavailable);
    assert!(error.error.retryable);
    assert_eq!(
        fixture
            .client
            .direct_runtime
            .feature_state()
            .lifecycle_generation(),
        generation
    );
    assert_eq!(fixture.store.load_dual_versioned().unwrap(), snapshot);
}

#[tokio::test]
async fn 丢弃受控登录也解除范围并在下一次请求新execution() {
    let mut fixture = Fixture::new(2, false, None);
    let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    let mut call = Box::pin(fixture.client.login_required_route_controlled(
        ConnectionMode::Direct,
        input(),
        control.claim().unwrap(),
    ));
    tokio::select! {
        () = fixture.transport.gate.started.notified() => {},
        result = &mut call => panic!("合成请求应挂起：{result:?}"),
    }
    drop(call);
    assert_eq!(fixture.transport.gate.dropped.load(Ordering::SeqCst), 1);
    assert!(!fixture.client.direct_auth.has_pending_login());
    control.cancel();
    let next = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    fixture
        .client
        .login_required_route_controlled(ConnectionMode::Direct, input(), next.claim().unwrap())
        .await
        .unwrap();
    let requests = fixture.transport.requests.lock().unwrap();
    assert_eq!(requests[2].method, HttpMethod::Get);
    assert!(requests[2].url.ends_with("/login"));
}

#[tokio::test]
async fn 登录各阶段到期都中止请求且不发布迟到结果() {
    for stage in 1..=5 {
        let mut fixture = Fixture::new(stage, false, None);
        // 先确认目标请求已挂起，再验证自然到期；为完整并行回归保留准备预算。
        let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        let mut call = Box::pin(fixture.client.login_required_route_controlled(
            ConnectionMode::Direct,
            input(),
            control.claim().unwrap(),
        ));
        tokio::select! {
            () = fixture.transport.gate.started.notified() => {},
            result = &mut call => panic!("应先到达登录阶段 {stage}：{result:?}"),
        }
        let result = tokio::time::timeout(Duration::from_secs(4), call)
            .await
            .expect("登录期限必须有界生效");
        assert_eq!(result.unwrap_err().code, ErrorCode::Timeout);
        assert_eq!(fixture.transport.gate.dropped.load(Ordering::SeqCst), 1);
        assert_eq!(fixture.transport.requests.lock().unwrap().len(), stage);
        assert!(!fixture.client.direct_auth.has_pending_login());
    }
}

#[tokio::test]
async fn 中断收尾遇到会话文件锁竞争仍有限且保留原中断() {
    let mut fixture = Fixture::new(2, false, None);
    let control = RequiredRecoveryControl::new(Duration::from_secs(10)).unwrap();
    let mut call = Box::pin(fixture.client.login_required_route_controlled(
        ConnectionMode::Direct,
        input(),
        control.claim().unwrap(),
    ));
    tokio::select! {
        () = fixture.transport.gate.started.notified() => {},
        result = &mut call => panic!("合成请求应挂起：{result:?}"),
    }
    let locked = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(fixture.root.join(".session.lock"))
        .unwrap();
    locked.try_lock().unwrap();
    let started = Instant::now();
    control.cancel();
    let error = call.await.unwrap_err();
    assert!(
        started.elapsed() < Duration::from_secs(5),
        "文件锁竞争不能无界等待"
    );
    assert_eq!(
        error.kind,
        crate::error::ErrorKind::Input,
        "收尾存储错误不能覆盖取消原因"
    );
    assert_eq!(
        control.interruption_reason(),
        Some(super::super::RequiredRecoveryInterruption::Cancelled)
    );
    assert_eq!(fixture.transport.gate.dropped.load(Ordering::SeqCst), 1);
    locked.unlock().unwrap();
    assert!(!fixture.client.direct_auth.has_pending_login());
}

#[tokio::test]
async fn 外部修订在中断收尾后保持且旧客户端不再请求学校() {
    for drop_call in [false, true] {
        let mut fixture = Fixture::new(2, false, None);
        let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        let mut call = Box::pin(fixture.client.login_required_route_controlled(
            ConnectionMode::Direct,
            input(),
            control.claim().unwrap(),
        ));
        tokio::select! {
            () = fixture.transport.gate.started.notified() => {},
            result = &mut call => panic!("合成请求应挂起：{result:?}"),
        }
        let external = FileSessionStore::new(&fixture.root).unwrap();
        let current = external.load_dual_versioned().unwrap();
        let mut snapshot = current.snapshot.unwrap();
        snapshot.sessions.webvpn.as_mut().unwrap().last_activity = 9001;
        external
            .compare_exchange_dual(current.revision, Some(&snapshot))
            .unwrap();
        let expected = external.load_dual_versioned().unwrap();
        if drop_call {
            drop(call);
        } else {
            control.cancel();
            assert!(call.await.is_err());
        }
        assert_eq!(external.load_dual_versioned().unwrap(), expected);
        assert!(!fixture.client.direct_auth.has_pending_login());
        let requests = fixture.transport.requests.lock().unwrap().len();
        let next = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        let error = fixture
            .client
            .recover_required_session_controlled(ReadonlyFeature::Schedule, next.claim().unwrap())
            .await
            .unwrap_err();
        assert!(error.error.is_session_conflict());
        assert_eq!(fixture.transport.requests.lock().unwrap().len(), requests);
        assert_eq!(external.load_dual_versioned().unwrap(), expected);
    }
}

#[tokio::test]
async fn 固定路线的会话检查撤销优先于同步解析失败() {
    #[derive(Clone)]
    struct CancellingStore {
        control: RequiredRecoveryControl,
        armed: Arc<AtomicBool>,
    }
    impl crate::session::SessionStore for CancellingStore {
        fn load_versioned(&self) -> Result<crate::session::VersionedSession> {
            if self.armed.swap(false, Ordering::SeqCst) {
                self.control.cancel();
                return Err(crate::error::UbaaError::new(
                    ErrorCode::InternalError,
                    crate::error::ErrorKind::Internal,
                    true,
                    "合成会话检查失败",
                ));
            }
            Ok(crate::session::VersionedSession {
                revision: 0,
                snapshot: None,
            })
        }
        fn compare_exchange(
            &self,
            _: u64,
            _: Option<&crate::session::SessionSnapshot>,
        ) -> Result<crate::session::SessionMutation> {
            panic!("解析中断不能修改合成会话");
        }
    }
    // 继续使用 Fixture 的固定 Direct 与 NeverProbe，只在本机所有权检查内撤销。
    let mut fixture = Fixture::new(0, false, None);
    let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
    let store = CancellingStore {
        control: control.clone(),
        armed: Arc::default(),
    };
    fixture.client.direct_runtime = crate::runtime::ClientRuntime::new(
        ConnectionMode::Direct,
        fixture.transport.clone(),
        store.clone(),
    )
    .unwrap();
    store.armed.store(true, Ordering::SeqCst);
    let error = fixture
        .client
        .recover_required_session_controlled(ReadonlyFeature::Schedule, control.claim().unwrap())
        .await
        .unwrap_err();
    assert_eq!(error.error.code, ErrorCode::InternalError);
    assert_eq!(error.error.kind, crate::error::ErrorKind::Input);
    assert!(!error.error.retryable);
    assert!(error.resolution.is_none());
    assert!(!store.armed.load(Ordering::SeqCst));
    assert_eq!(fixture.transport.requests.lock().unwrap().len(), 0);
}
