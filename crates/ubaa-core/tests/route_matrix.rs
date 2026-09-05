//! 聚合门面的路线选择、诊断和禁止跨路线回退合同。

mod support;

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot, from_webvpn_url,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, EvaluationCourseOutcome, EvaluationSubmitCoursesRequest,
    EvaluationSubmitTarget, NetworkState, Result, RouteDiagnostic, RoutePolicy, RouteResolution,
    UbaaClient, UbaaError,
};

use support::source_tokens::{count_sequence, function_body, rust_files_below, rust_tokens};

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

const AUTO_CAMPUS_RESOLUTION: RouteResolution = RouteResolution {
    mode: ConnectionMode::Direct,
    policy: RoutePolicy::Auto,
    diagnostic: RouteDiagnostic {
        network: NetworkState::Campus,
        initial_route: ConnectionMode::Direct,
        mode: ConnectionMode::Direct,
        used_fallback: false,
    },
};

const AUTO_UNKNOWN_RESOLUTION: RouteResolution = RouteResolution {
    mode: ConnectionMode::Direct,
    policy: RoutePolicy::Auto,
    diagnostic: RouteDiagnostic {
        network: NetworkState::Unknown,
        initial_route: ConnectionMode::Direct,
        mode: ConnectionMode::Direct,
        used_fallback: false,
    },
};

const NO_EVENTS: &[MatrixEvent] = &[];
const DIRECT_REQUEST: &[MatrixEvent] = &[
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
];
const DIRECT_FAILURE: &[MatrixEvent] = &[MatrixEvent::Http(ConnectionMode::Direct)];
const WEBVPN_REQUEST: &[MatrixEvent] = &[
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
];
const WEBVPN_FAILURE: &[MatrixEvent] = &[MatrixEvent::Http(ConnectionMode::WebVpn)];
const AUTO_WEBVPN_REQUEST: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::OffCampus),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
    MatrixEvent::Http(ConnectionMode::WebVpn),
];
const AUTO_WEBVPN_FAILURE: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::OffCampus),
    MatrixEvent::Http(ConnectionMode::WebVpn),
];
const AUTO_OFF_CAMPUS_WITHOUT_REQUEST: &[MatrixEvent] =
    &[MatrixEvent::Probe(NetworkState::OffCampus)];
const AUTO_CAMPUS_REQUEST: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::Campus),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
];
const AUTO_CAMPUS_FAILURE: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::Campus),
    MatrixEvent::Http(ConnectionMode::Direct),
];
const AUTO_CAMPUS_WITHOUT_REQUEST: &[MatrixEvent] = &[MatrixEvent::Probe(NetworkState::Campus)];
const AUTO_UNKNOWN_REQUEST: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::Unknown),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
    MatrixEvent::Http(ConnectionMode::Direct),
];
const AUTO_UNKNOWN_FAILURE: &[MatrixEvent] = &[
    MatrixEvent::Probe(NetworkState::Unknown),
    MatrixEvent::Http(ConnectionMode::Direct),
];
const AUTO_UNKNOWN_WITHOUT_REQUEST: &[MatrixEvent] = &[MatrixEvent::Probe(NetworkState::Unknown)];

const CASES: [RouteMatrixCase; 20] = [
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
        expected_events: DIRECT_FAILURE,
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
        expected_events: WEBVPN_FAILURE,
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
        name: "auto-off-campus-ready-success",
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
        name: "auto-off-campus-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::NetworkError),
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_WEBVPN_FAILURE,
    },
    RouteMatrixCase {
        name: "auto-off-campus-not-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: false,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_OFF_CAMPUS_WITHOUT_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-off-campus-not-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::OffCampus,
        direct_ready: true,
        webvpn_ready: false,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_OFF_CAMPUS_RESOLUTION,
        expected_events: AUTO_OFF_CAMPUS_WITHOUT_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-campus-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Campus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Success,
        expected_resolution: AUTO_CAMPUS_RESOLUTION,
        expected_events: AUTO_CAMPUS_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-campus-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Campus,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::NetworkError),
        expected_resolution: AUTO_CAMPUS_RESOLUTION,
        expected_events: AUTO_CAMPUS_FAILURE,
    },
    RouteMatrixCase {
        name: "auto-campus-not-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Campus,
        direct_ready: false,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_CAMPUS_RESOLUTION,
        expected_events: AUTO_CAMPUS_WITHOUT_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-campus-not-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Campus,
        direct_ready: false,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_CAMPUS_RESOLUTION,
        expected_events: AUTO_CAMPUS_WITHOUT_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-unknown-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Unknown,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Success,
        expected_resolution: AUTO_UNKNOWN_RESOLUTION,
        expected_events: AUTO_UNKNOWN_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-unknown-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Unknown,
        direct_ready: true,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::NetworkError),
        expected_resolution: AUTO_UNKNOWN_RESOLUTION,
        expected_events: AUTO_UNKNOWN_FAILURE,
    },
    RouteMatrixCase {
        name: "auto-unknown-not-ready-success",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Unknown,
        direct_ready: false,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::Success,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_UNKNOWN_RESOLUTION,
        expected_events: AUTO_UNKNOWN_WITHOUT_REQUEST,
    },
    RouteMatrixCase {
        name: "auto-unknown-not-ready-failure",
        config: "[route]\ndefault = \"auto\"\n",
        probe_state: NetworkState::Unknown,
        direct_ready: false,
        webvpn_ready: true,
        scripted_outcome: ScriptedOutcome::NetworkFailure,
        expected_result: ExpectedResult::Error(ErrorCode::AuthenticationRequired),
        expected_resolution: AUTO_UNKNOWN_RESOLUTION,
        expected_events: AUTO_UNKNOWN_WITHOUT_REQUEST,
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
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.events
            .lock()
            .expect("路线矩阵事件锁")
            .push(MatrixEvent::Http(self.mode));
        match self.outcome {
            ScriptedOutcome::Success => {
                let direct_url =
                    from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
                let url = url::Url::parse(&direct_url).expect("路线矩阵合成 URL");
                let body = match url.path() {
                    "/pjxt/cas" => String::new(),
                    "/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks" => {
                        r#"{"code":200,"result":{"list":[{"rwid":"route-task"}]}}"#.into()
                    }
                    "/pjxt/evaluationMethodSix/getQuestionnaireListToTask" => {
                        r#"{"code":200,"result":[{"wjid":"route-form","msid":"route-mode"}]}"#
                            .into()
                    }
                    "/pjxt/evaluationMethodSix/getRequiredReviewsData" => serde_json::json!({
                        "code": 200,
                        "result": [{
                            "kcdm":"route-course", "bpdm":"route-teacher",
                            "kcmc":"路线课程", "bpmc":"路线教师", "ypjcs":0,
                            "xypjcs":1, "sxz":"student-kind", "pjrdm":"reviewer",
                            "pjrmc":"评价人", "rwh":"route-row", "xn":"2026", "xq":"1",
                            "xnxq":"2026-2027-1", "yxsfktjst":"0"
                        }]
                    })
                    .to_string(),
                    "/pjxt/evaluationMethodSix/reviseQuestionnairePattern" => {
                        r#"{"code":200}"#.into()
                    }
                    "/pjxt/evaluationMethodSix/getQuestionnaireTopic" => serde_json::json!({
                        "code":200,
                        "result":[{
                            "pjmap":{},
                            "pjxtWjWjbReturnEntity":{"wjzblist":[{"tklist":[{
                                "tmlx":"1", "tmid":"route-question",
                                "tmxxlist":[{"tmxxid":"route-option"}]
                            }]}]},
                            "pjxtPjjgPjjgckb":[{
                                "wjssrwid":"route-assignment", "bprdm":"route-teacher",
                                "bprmc":"路线教师", "kcdm":"route-course", "kcmc":"路线课程",
                                "pjid":"route-evaluation", "pjlx":"2", "pjrdm":"reviewer",
                                "pjrjsdm":"student-role", "pjrxm":"评价人",
                                "xnxq":"2026-2027-1"
                            }]
                        }]
                    })
                    .to_string(),
                    "/pjxt/evaluationMethodSix/submitSaveEvaluation" => r#"{"code":200}"#.into(),
                    path => panic!("路线矩阵出现未预期路径：{path}"),
                };
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
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

#[test]
fn 聚合门面只保留唯一运行时选择器和路线算法() {
    let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let facade_dir = manifest_dir.join("src/facade");

    let observed = audited_route_usage(&facade_dir);
    let shared_route_execution_reuse = assert_cgyy_cancel_atomic_route_boundary(&facade_dir)
        + assert_ygdk_submit_atomic_route_boundary(&facade_dir)
        + assert_evaluation_submit_atomic_route_boundary(&facade_dir);
    assert!(observed.entry_points > 0, "必须发现 facade 业务入口");
    assert_eq!(
        observed.entry_points,
        observed.resolve_operation + observed.caller_pinned,
        "每个公开异步业务入口必须恰好选择 routed 或 caller-pinned 路线语义"
    );
    assert_eq!(
        observed.entry_points,
        observed.runtime_for + observed.route_parts_for + shared_route_execution_reuse,
        "每个业务入口必须只取得一次对应路线槽位"
    );
    assert_eq!(
        observed.entry_points,
        observed.finish_routed + observed.finish_caller_pinned + shared_route_execution_reuse,
        "每个公开异步业务入口都必须经过统一收尾"
    );
    assert_eq!(
        observed.caller_pinned, 5,
        "只允许 Cgyy 与 Ygdk 各两项、Evaluation 一项回读固定路线"
    );
    assert_eq!(observed.caller_pinned, observed.finish_caller_pinned);
    assert_caller_pinned_route_boundaries(&facade_dir);
    assert_route_slot_boundaries(&facade_dir);
    assert_route_algorithm_is_unique(manifest_dir);
}

fn assert_cgyy_cancel_atomic_route_boundary(facade_dir: &std::path::Path) -> usize {
    let tokens = rust_tokens(&source(&facade_dir.join("write/reservations.rs")));
    let entry_points = ["cgyy_cancel_order", "cgyy_cancel_order_if_route_matches"];
    for entry_point in entry_points {
        let body = function_body(&tokens, entry_point)
            .unwrap_or_else(|| panic!("定位场馆取消入口：{entry_point}"));
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            1,
            "{entry_point} 必须只做一次权威路线解析"
        );
        assert_eq!(
            count_sequence(body, &["cgyy_cancel_order_resolved", "("]),
            1,
            "{entry_point} 必须复用同一个已解析路线执行器"
        );
    }
    let executor =
        function_body(&tokens, "cgyy_cancel_order_resolved").expect("定位场馆取消已解析路线执行器");
    assert_eq!(
        count_sequence(executor, &["resolve_operation", "("]),
        0,
        "最终发送执行器不得再次解析路线"
    );
    assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
    assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    // 两个公开入口共用一个执行器，源码静态计数会比调用语义少一个
    // runtime/finish；这里显式登记并由上方逐函数约束防止抵消漏检。
    entry_points.len() - 1
}

fn assert_ygdk_submit_atomic_route_boundary(facade_dir: &std::path::Path) -> usize {
    let tokens = rust_tokens(&source(&facade_dir.join("write/campus.rs")));
    let entry_points = ["ygdk_submit", "ygdk_submit_if_route_matches"];
    for entry_point in entry_points {
        let body = function_body(&tokens, entry_point)
            .unwrap_or_else(|| panic!("定位阳光打卡提交入口：{entry_point}"));
        assert_eq!(
            count_sequence(body, &["validate_ygdk_submit_pre_route", "("]),
            1,
            "{entry_point} 必须在路线解析前完整校验本地输入"
        );
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            1,
            "{entry_point} 必须只做一次权威路线解析"
        );
        assert_eq!(
            count_sequence(body, &["ygdk_submit_resolved", "("]),
            1,
            "{entry_point} 必须复用同一个已解析路线执行器"
        );
    }
    let atomic = function_body(&tokens, "ygdk_submit_if_route_matches")
        .expect("定位阳光打卡 expected-route 原子入口");
    assert_eq!(
        count_sequence(
            atomic,
            &["resolution", ".", "mode", "!", "=", "expected_route"]
        ),
        1,
        "阳光打卡原子入口必须在执行器前比较唯一解析路线"
    );
    let executor =
        function_body(&tokens, "ygdk_submit_resolved").expect("定位阳光打卡已解析路线执行器");
    assert_eq!(
        count_sequence(executor, &["resolve_operation", "("]),
        0,
        "阳光打卡最终发送执行器不得再次解析路线"
    );
    assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
    assert_eq!(
        count_sequence(executor, &["begin_non_idempotent_operation", "("]),
        1
    );
    assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    entry_points.len() - 1
}

fn assert_evaluation_submit_atomic_route_boundary(facade_dir: &std::path::Path) -> usize {
    let tokens = rust_tokens(&source(&facade_dir.join("write/evaluation.rs")));
    let entry_points = [
        "evaluation_submit_courses",
        "evaluation_submit_courses_if_route_matches",
    ];
    for entry_point in entry_points {
        let body = function_body(&tokens, entry_point)
            .unwrap_or_else(|| panic!("定位评教提交入口：{entry_point}"));
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            1,
            "{entry_point} 必须只做一次权威路线解析"
        );
        assert_eq!(
            count_sequence(body, &["evaluation_submit_courses_resolved", "("]),
            1,
            "{entry_point} 必须复用同一个已解析路线执行器"
        );
    }
    let atomic = function_body(&tokens, "evaluation_submit_courses_if_route_matches")
        .expect("定位评教 expected-route 原子入口");
    assert_eq!(
        count_sequence(
            atomic,
            &["resolution", ".", "mode", "!", "=", "expected_route"]
        ),
        1,
        "评教原子入口必须在 authority 前比较唯一解析路线"
    );
    let executor = function_body(&tokens, "evaluation_submit_courses_resolved")
        .expect("定位评教已解析路线执行器");
    assert_eq!(
        count_sequence(executor, &["resolve_operation", "("]),
        0,
        "评教最终发送执行器不得再次解析路线"
    );
    assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
    assert_eq!(
        count_sequence(executor, &["begin_non_idempotent_operation", "("]),
        1
    );
    assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    entry_points.len() - 1
}

fn assert_caller_pinned_route_boundaries(facade_dir: &std::path::Path) {
    for (relative, helper) in [
        ("read/services.rs", "cgyy_orders_on_route"),
        ("read/services.rs", "cgyy_order_detail_on_route"),
        ("read/services.rs", "ygdk_overview_on_route"),
        ("read/services.rs", "ygdk_records_on_route"),
        ("read/evaluation.rs", "evaluation_all_on_route"),
    ] {
        let tokens = rust_tokens(&source(&facade_dir.join(relative)));
        let body = function_body(&tokens, helper)
            .unwrap_or_else(|| panic!("定位 caller-pinned 读取入口：{helper}"));
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            0,
            "{helper} 不得重新解析策略或 Auto 路线"
        );
        assert_eq!(
            count_sequence(body, &["guard_caller_pinned_route", "("]),
            1,
            "{helper} 必须校验固定路线会话"
        );
        assert_eq!(
            count_sequence(body, &["runtime_for", "("]),
            1,
            "{helper} 必须只取得一次固定路线 runtime"
        );
        assert_eq!(
            count_sequence(body, &["finish_caller_pinned", "("]),
            1,
            "{helper} 必须以 caller-pinned 语义收尾"
        );
    }
}

fn audited_route_usage(facade_dir: &std::path::Path) -> RouteUsage {
    let mut observed = RouteUsage::default();
    for path in ["read", "write"]
        .into_iter()
        .flat_map(|name| rust_files_below(&facade_dir.join(name)))
    {
        let tokens = rust_tokens(&source(&path));
        let relative = path.strip_prefix(facade_dir).unwrap_or(&path).display();
        assert!(
            count_sequence(&tokens, &["match", "resolution", ".", "mode"]) == 0,
            "{relative} 不得自行选择路线 runtime"
        );
        for field in [
            "direct_runtime",
            "direct_auth",
            "webvpn_runtime",
            "webvpn_auth",
        ] {
            assert_eq!(
                count_sequence(&tokens, &[field]),
                0,
                "{relative} 不得绕过唯一路线槽位访问 {field}"
            );
        }
        observed.add(route_usage(&tokens));
    }
    observed
}

fn assert_route_slot_boundaries(facade_dir: &std::path::Path) {
    let routing_tokens = rust_tokens(&source(&facade_dir.join("routing.rs")));
    let runtime_for = function_body(&routing_tokens, "runtime_for").expect("定位 runtime_for");
    assert_eq!(
        count_sequence(runtime_for, &["self", ".", "route_parts_for", "("]),
        1
    );
    let route_parts =
        function_body(&routing_tokens, "route_parts_for").expect("定位 route_parts_for");
    for field in [
        "direct_runtime",
        "direct_auth",
        "webvpn_runtime",
        "webvpn_auth",
    ] {
        assert_eq!(
            count_sequence(route_parts, &["self", ".", field]),
            1,
            "route_parts_for 必须且只能映射一次 {field}"
        );
    }

    let auth_tokens = rust_tokens(&source(&facade_dir.join("auth.rs")));
    for helper in ["prepare_route", "login_route", "auth_status_route"] {
        let body = function_body(&auth_tokens, helper)
            .unwrap_or_else(|| panic!("定位认证路线 helper：{helper}"));
        assert_eq!(
            count_sequence(body, &["self", ".", "route_parts_for", "("]),
            1,
            "{helper} 必须委托唯一 runtime/auth 槽位选择器"
        );
        for field in [
            "direct_runtime",
            "direct_auth",
            "webvpn_runtime",
            "webvpn_auth",
        ] {
            assert_eq!(
                count_sequence(body, &[field]),
                0,
                "{helper} 不得绕过 route_parts_for 访问 {field}"
            );
        }
    }
}

fn assert_route_algorithm_is_unique(manifest_dir: &std::path::Path) {
    let connection_tokens = rust_tokens(&source(&manifest_dir.join("src/connection.rs")));
    let policy_mapping = [
        "RoutePolicy",
        ":",
        ":",
        "Direct",
        "=",
        ">",
        "ConnectionMode",
        ":",
        ":",
        "Direct",
    ];
    let auto_mapping = ["auto_route_override", ".", "unwrap_or", "("];
    let shared_resolver =
        function_body(&connection_tokens, "resolve_route").expect("定位共享路线算法");
    assert_eq!(count_sequence(shared_resolver, &policy_mapping), 1);
    assert_eq!(count_sequence(shared_resolver, &auto_mapping), 1);

    let (policy_mapping_count, auto_mapping_count) = rust_files_below(&manifest_dir.join("src"))
        .into_iter()
        .fold((0, 0), |(policy_total, auto_total), path| {
            let tokens = rust_tokens(&source(&path));
            (
                policy_total + count_sequence(&tokens, &policy_mapping),
                auto_total + count_sequence(&tokens, &auto_mapping),
            )
        });
    assert_eq!(
        policy_mapping_count, 1,
        "RoutePolicy 只能由 connection::resolve_route 解释一次"
    );
    assert_eq!(auto_mapping_count, 1, "Auto 三态算法只能有一个物理实现");
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct RouteUsage {
    entry_points: usize,
    resolve_operation: usize,
    caller_pinned: usize,
    runtime_for: usize,
    route_parts_for: usize,
    finish_routed: usize,
    finish_caller_pinned: usize,
}

impl RouteUsage {
    fn add(&mut self, other: Self) {
        self.entry_points += other.entry_points;
        self.resolve_operation += other.resolve_operation;
        self.caller_pinned += other.caller_pinned;
        self.runtime_for += other.runtime_for;
        self.route_parts_for += other.route_parts_for;
        self.finish_routed += other.finish_routed;
        self.finish_caller_pinned += other.finish_caller_pinned;
    }
}

fn route_usage(tokens: &[String]) -> RouteUsage {
    RouteUsage {
        entry_points: count_sequence(tokens, &["pub", "async", "fn"]),
        resolve_operation: count_sequence(tokens, &["resolve_operation", "("]),
        caller_pinned: count_sequence(tokens, &["guard_caller_pinned_route", "("]),
        runtime_for: count_sequence(tokens, &["runtime_for", "("]),
        route_parts_for: count_sequence(tokens, &["route_parts_for", "("]),
        finish_routed: count_sequence(tokens, &["finish_routed", "("])
            + count_sequence(tokens, &["finish_routed_write", "("]),
        finish_caller_pinned: count_sequence(tokens, &["finish_caller_pinned", "("]),
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

    let result = runtime.block_on(client.evaluation_submit_courses(
        EvaluationSubmitCoursesRequest {
            targets: vec![EvaluationSubmitTarget {
                rwid: "route-task".into(),
                wjid: "route-form".into(),
                kcdm: "route-course".into(),
                bpdm: Some("route-teacher".into()),
            }],
        },
    ));
    let observed_resolution = match (case.expected_result, result) {
        (ExpectedResult::Success, Ok(routed)) => {
            assert_eq!(routed.data.items.len(), 1, "{case_name}");
            assert_eq!(
                routed.data.items[0].outcome,
                EvaluationCourseOutcome::Success,
                "{case_name}"
            );
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

fn source(path: &std::path::Path) -> String {
    std::fs::read_to_string(path).unwrap_or_else(|error| panic!("读取 {}: {error}", path.display()))
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-route-matrix-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}
