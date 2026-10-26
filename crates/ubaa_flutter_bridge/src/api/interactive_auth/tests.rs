use super::*;
use async_trait::async_trait;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
use ubaa_core::facade::testing::{
    FileSessionStore, HttpMethod, HttpRequest, HttpResponse, HttpTransport,
};
use ubaa_core::facade::{Result, UbaaClient};

const PAGE: &str = r#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-bridge-execution"></form><script>config.captcha = { type: 'image', id: 'synthetic-bridge-id' }</script>"#;
// 测试内合成的 1×1 RGBA PNG，像素固定为 [17, 83, 149, 255]。
const PNG: &[u8] = &[
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0,
    0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 16, 12, 158, 250, 31, 0, 3,
    107, 1, 249, 64, 176, 47, 135, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

#[derive(Clone)]
struct Transport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    gate: Option<Arc<Gate>>,
}
struct Gate {
    started: tokio::sync::Notify,
    released: tokio::sync::Notify,
}

#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let image = request.url.contains("/captcha?");
        if image && let Some(gate) = &self.gate {
            gate.started.notify_one();
            gate.released.notified().await;
        }
        Ok(HttpResponse::new(
            200,
            request.url,
            if image {
                PNG.to_vec()
            } else {
                PAGE.as_bytes().to_vec()
            },
        ))
    }
}

struct Fixture {
    bridge: Arc<BridgeClient>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    root: std::path::PathBuf,
}

impl Fixture {
    async fn new(gate: Option<Arc<Gate>>) -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "ubaa-bridge-interactive-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let bridge = Arc::new(BridgeClient::open(root.to_string_lossy().into_owned()).unwrap());
        let requests = Arc::new(Mutex::new(Vec::new()));
        let direct = Transport {
            requests: requests.clone(),
            gate,
        };
        let webvpn = Transport {
            requests: requests.clone(),
            gate: None,
        };
        let core =
            UbaaClient::with_transports(direct, webvpn, FileSessionStore::new(&root).unwrap())
                .unwrap();
        *bridge.auth_control.write().unwrap() = core.interactive_login_cancellation();
        *bridge.inner.lock().await = Some(core);
        Self {
            bridge,
            requests,
            root,
        }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

#[tokio::test]
async fn synchronous_cancel_does_not_wait_for_network_lock_or_start_queued_prepare() {
    let fixture = Fixture::new(None).await;
    let login = fixture
        .bridge
        .begin_interactive_login("synthetic-bridge-account".into())
        .unwrap();
    let locked = fixture.bridge.inner.lock().await;
    let bridge = fixture.bridge.clone();
    let pending = tokio::spawn(async move { bridge.prepare_interactive_login(&login).await });
    tokio::task::yield_now().await;
    fixture.bridge.cancel_interactive_login();
    drop(locked);
    assert_eq!(
        pending.await.unwrap().unwrap_err().code,
        super::super::client::BridgeErrorCode::InvalidInput
    );
    assert!(fixture.requests.lock().unwrap().is_empty());
}

#[tokio::test]
async fn late_image_cannot_escape_after_synchronous_cancel() {
    let gate = Arc::new(Gate {
        started: tokio::sync::Notify::new(),
        released: tokio::sync::Notify::new(),
    });
    let fixture = Fixture::new(Some(gate.clone())).await;
    let login = fixture
        .bridge
        .begin_interactive_login("synthetic-bridge-account".into())
        .unwrap();
    let bridge = fixture.bridge.clone();
    let pending = tokio::spawn(async move { bridge.prepare_interactive_login(&login).await });
    gate.started.notified().await;
    fixture.bridge.cancel_interactive_login();
    gate.released.notify_one();
    assert_eq!(
        pending.await.unwrap().unwrap_err().code,
        super::super::client::BridgeErrorCode::InvalidInput
    );
    assert_eq!(fixture.requests.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn dispose_revokes_before_waiting_for_network_and_is_terminal() {
    let gate = Arc::new(Gate {
        started: tokio::sync::Notify::new(),
        released: tokio::sync::Notify::new(),
    });
    let fixture = Fixture::new(Some(gate.clone())).await;
    let login = fixture
        .bridge
        .begin_interactive_login("synthetic-bridge-account".into())
        .unwrap();
    let bridge = fixture.bridge.clone();
    let pending = tokio::spawn(async move { bridge.prepare_interactive_login(&login).await });
    gate.started.notified().await;
    let bridge = fixture.bridge.clone();
    let disposal = tokio::spawn(async move { bridge.dispose().await });
    tokio::task::yield_now().await;
    assert!(
        fixture
            .bridge
            .begin_interactive_login("synthetic-next-account".into())
            .is_err()
    );
    gate.released.notify_one();
    assert!(pending.await.unwrap().is_err());
    disposal.await.unwrap().unwrap();
    assert_eq!(fixture.requests.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn dedicated_frames_and_debug_do_not_expand_ordinary_login_contract() {
    let fixture = Fixture::new(None).await;
    let ordinary = fixture.bridge.prepare_login().await.unwrap();
    assert!(
        ordinary
            .routes
            .iter()
            .all(|route| route.error.as_ref().unwrap().code == "upstream_changed")
    );
    let failed = fixture
        .bridge
        .login(
            "synthetic-bridge-account".into(),
            "synthetic-bridge-password".into(),
        )
        .await
        .unwrap();
    assert_eq!(failed.readiness, BridgeLoginReadiness::NoneReady);
    assert_eq!(fixture.requests.lock().unwrap().len(), 4);
    assert!(
        fixture
            .requests
            .lock()
            .unwrap()
            .iter()
            .all(|request| request.method == HttpMethod::Get && !request.url.contains("/captcha?"))
    );
    let login = fixture
        .bridge
        .begin_interactive_login("synthetic-bridge-account".into())
        .unwrap();
    let interactive = fixture
        .bridge
        .prepare_interactive_login(&login)
        .await
        .unwrap();
    assert_eq!(interactive.routes.len(), 2);
    let frame = interactive.routes[0].frame.as_ref().unwrap();
    assert_eq!((frame.width, frame.height), (1, 1));
    assert_eq!(frame.rgba, [17, 83, 149, 255]);
    let answer = BridgeCaptchaAnswer {
        challenge: interactive.routes[0].challenge.as_ref().unwrap().clone(),
        answer: "synthetic-bridge-answer".into(),
    };
    let debug = format!("{login:?} {interactive:?} {frame:?} {answer:?}");
    for value in [
        "synthetic-bridge-account",
        "synthetic-bridge-answer",
        "synthetic-bridge-id",
        "synthetic-bridge-execution",
        "17, 83, 149",
    ] {
        assert!(!debug.contains(value));
    }
    assert_eq!(fixture.bridge.contract_version(), 42);
}

#[tokio::test]
async fn foreign_handles_and_cancelled_route_challenges_never_send_answers() {
    let fixture = Fixture::new(None).await;
    let foreign = Fixture::new(None).await;
    let login = fixture
        .bridge
        .begin_interactive_login("synthetic-bridge-account".into())
        .unwrap();
    assert!(
        foreign
            .bridge
            .prepare_interactive_login(&login)
            .await
            .is_err()
    );
    assert!(foreign.requests.lock().unwrap().is_empty());
    let prepared = fixture
        .bridge
        .prepare_interactive_login(&login)
        .await
        .unwrap();
    let challenge = prepared.routes[0].challenge.as_ref().unwrap().clone();
    challenge.cancel();
    let before = fixture.requests.lock().unwrap().len();
    assert!(
        fixture
            .bridge
            .submit_interactive_login(
                &login,
                "synthetic-bridge-account".into(),
                "synthetic-bridge-password".into(),
                vec![BridgeCaptchaAnswer {
                    challenge,
                    answer: "synthetic-bridge-answer".into()
                }]
            )
            .await
            .is_err()
    );
    assert_eq!(fixture.requests.lock().unwrap().len(), before);
}
