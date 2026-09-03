//! 聚合门面的路线选择、诊断和禁止跨路线回退合同。

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::config::RouteConfig;
use ubaa_core::connection::GatewayProbe;
use ubaa_core::domain::{ConnectionMode, RoutePolicy};
use ubaa_core::error::{ErrorCode, ErrorKind, UbaaError};
use ubaa_core::facade::{NetworkState, RouteDiagnostic, RouteResolution, UbaaClient};
use ubaa_core::ports::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{DualSessionSnapshot, FileSessionStore, RouteSessionSnapshot};

const DIRECT_RESOLUTION: RouteResolution = RouteResolution {
    mode: ConnectionMode::Direct,
    policy: RoutePolicy::Direct,
    diagnostic: RouteDiagnostic {
        network: NetworkState::Unknown,
        initial_route: ConnectionMode::Direct,
        mode: ConnectionMode::Direct,
        used_fallback: false,
    },
};

const WEBVPN_RESOLUTION: RouteResolution = RouteResolution {
    mode: ConnectionMode::WebVpn,
    policy: RoutePolicy::WebVpn,
    diagnostic: RouteDiagnostic {
        network: NetworkState::Unknown,
        initial_route: ConnectionMode::WebVpn,
        mode: ConnectionMode::WebVpn,
        used_fallback: false,
    },
};

const AUTO_OFF_CAMPUS_RESOLUTION: RouteResolution = RouteResolution {
    mode: ConnectionMode::WebVpn,
    policy: RoutePolicy::Auto,
    diagnostic: RouteDiagnostic {
        network: NetworkState::OffCampus,
        initial_route: ConnectionMode::WebVpn,
        mode: ConnectionMode::WebVpn,
        used_fallback: false,
    },
};

const NO_EVENTS: &[MatrixEvent] = &[];
const DIRECT_REQUEST: &[MatrixEvent] = &[MatrixEvent::Http(ConnectionMode::Direct)];
const WEBVPN_REQUEST: &[MatrixEvent] = &[MatrixEvent::Http(ConnectionMode::WebVpn)];
const AUTO_WEBVPN_REQUEST: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::OffCampus),
    MatrixEvent::Http(ConnectionMode::WebVpn),
];
const AUTO_WITHOUT_REQUEST: &[MatrixEvent] = &[MatrixEvent::Probe(NetworkState::OffCampus)];

const CASES: [RouteMatrixCase; 12] = [
    RouteMatrixCase {
        name: "direct-ready-success",
        config: "[route]\ndefault = \"direct\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Success,
        expected_resolution: DIRECT_RESOLUTION,
        expected_events: DIRECT_REQUEST,
    },
    RouteMatrixCase {
        name: "direct-ready-failure",
        config: "[route]\ndefault = \"direct\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::NetworkError),
        expected_resolution: DIRECT_RESOLUTION,
        expected_events: DIRECT_REQUEST,
    },
    RouteMatrixCase {
        name: "direct-not-ready-success",
        config: "[route]\ndefault = \"direct\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: false,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: DIRECT_RESOLUTION,
        expected_events: NO_EVENTS,
    },
    RouteMatrixCase {
        name: "direct-not-ready-failure",
        config: "[route]\ndefault = \"direct\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: false,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: DIRECT_RESOLUTION,
        expected_events: NO_EVENTS,
    },
    RouteMatrixCase {
        name: "webvpn-ready-success",
        config: "[route]\ndefault = \"webvpn\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Success,
        expected_resolution: WEBVPN_RESOLUTION,
        expected_events: WEBVPN_REQUEST,
    },
    RouteMatrixCase {
        name: "webvpn-ready-failure",
        config: "[route]\ndefault = \"webvpn\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::NetworkError),
        expected_resolution: WEBVPN_RESOLUTION,
        expected_events: WEBVPN_REQUEST,
    },
    RouteMatrixCase {
        name: "webvpn-not-ready-success",
        config: "[route]\ndefault = \"webvpn\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: false,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: WEBVPN_RESOLUTION,
        expected_events: NO_EVENTS,
    },
    RouteMatrixCase {
        name: "webvpn-not-ready-failure",
        config: "[route]\ndefault = \"webvpn\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: false,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: WEBVPN_RESOLUTION,
        expected_events: NO_EVENTS,
    },
    RouteMatrixCase {
        name: "auto-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Success,
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_WEBVPN_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::NetworkError),
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_WEBVPN_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-not-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: false,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_WITHOUT_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-not-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: false,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_WITHOUT_REQUEST,
    },
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum MatrixEvent {
    Probe(NetworkState),
    Http(ConnectionMode),
}

#[derive(Clone, Copy, Debug)]
enum ScriptedOutcome {
    Success,
    NetworkFailure,
}

#[derive(Clone, Copy, Debug)]
enum ExpectedResult {
    Success,
    Error(ErrorCode),
}

#[derive(Clone, Copy, Debug)]
struct RouteMatrixCase {
    name: &'static str,
    config: &'static str,
    probe_state: NetworkState,
    direct_ready: bool,
    webvpn_ready: bool,
    scripted_outcome: ScriptedOutcome,
    expected_result: ExpectedResult,
    expected_resolution: RouteResolution,
    expected_events: &'static [MatrixEvent],
}

struct MatrixProbe {
    state: NetworkState,
    events: Arc<Mutex<Vec<MatrixEvent>>>,
}

impl GatewayProbe for MatrixProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.events
            .lock()
            .expect("路线矩阵事件锁")
            .push(MatrixEvent::Probe(self.state));
        self.state
    }
}

struct MatrixTransport {
    mode: ConnectionMode,
    outcome: ScriptedOutcome,
    events: Arc<Mutex<Vec<MatrixEvent>>>,
}

#[async_trait]
impl HttpTransport for MatrixTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        self.events
            .lock()
            .expect("路线矩阵事件锁")
            .push(MatrixEvent::Http(self.mode));
        match self.outcome {
            ScriptedOutcome::Success => Ok(HttpResponse::new(
                200,
                request.url,
                r#"{"code":200,"message":"合成评教成功"}"#.as_bytes().to_vec(),
            )),
            ScriptedOutcome::NetworkFailure => Err(UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "合成网络失败",
            )),
        }
    }
}

#[test]
fn 聚合门面路线矩阵保持调用顺序完整诊断且禁止跨路线回退() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("创建测试运行时");

    for case in &CASES {
        assert_route_case(&runtime, case);
    }
}

fn assert_route_case(runtime: &tokio::runtime::Runtime, case: &RouteMatrixCase) {
    let case_name = case.name;
    let root = test_root(case.name);
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).expect("创建测试会话存储");
    store
        .save_dual(&DualSessionSnapshot::new(
            case.direct_ready.then(ready_slot),
            case.webvpn_ready.then(ready_slot),
        ))
        .expect("保存路线矩阵会话");

    let events = Arc::new(Mutex::new(Vec::new()));
    let mut client = UbaaClient::with_routing(
        MatrixTransport {
            mode: ConnectionMode::Direct,
            outcome: case.scripted_outcome,
            events: Arc::clone(&events),
        },
        MatrixTransport {
            mode: ConnectionMode::WebVpn,
            outcome: case.scripted_outcome,
            events: Arc::clone(&events),
        },
        store,
        RouteConfig::parse(case.config).expect("解析测试路线配置"),
        MatrixProbe {
            state: case.probe_state,
            events: Arc::clone(&events),
        },
    )
    .expect("创建聚合客户端");

    let result = runtime.block_on(client.evaluation_submit(vec![serde_json::json!({
        "synthetic": true
    })]));
    let observed_resolution = match (case.expected_result, result) {
        (ExpectedResult::Success, Ok(routed)) => {
            assert_eq!(routed.data.len(), 1, "{case_name}");
            assert!(routed.data[0].success, "{case_name}");
            routed.resolution
        }
        (ExpectedResult::Error(expected_code), Err(error)) => {
            assert_eq!(error.error.code, expected_code, "{case_name}");
            error
                .resolution
                .expect("路线解析后的错误必须携带 resolution")
        }
        (ExpectedResult::Success, Err(error)) => {
            let code = error.error.code;
            panic!("{case_name} 意外失败: {code:?}")
        }
        (ExpectedResult::Error(expected_code), Ok(_)) => {
            panic!("{case_name} 应返回 {expected_code:?}")
        }
    };

    assert_eq!(observed_resolution, case.expected_resolution, "{case_name}");
    let observed_events = events.lock().expect("路线矩阵事件锁");
    assert_eq!(
        observed_events.as_slice(),
        case.expected_events,
        "{case_name}"
    );

    drop(client);
    let _ = std::fs::remove_dir_all(root);
}

fn ready_slot() -> RouteSessionSnapshot {
    RouteSessionSnapshot {
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity: 1_001,
    }
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-route-matrix-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
