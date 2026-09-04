use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::facade::{ErrorCode, ErrorKind, Result, UbaaError};

use super::*;
use crate::api::write::commit::finish_commit_success;
use crate::api::write::support::map_cgyy_cancel_preflight_error;
use crate::api::write::{BridgeCgyyCancelOrderRequest, BridgeWriteOperation};

const ORDER_ID: i32 = 42;

#[test]
fn 场馆取消core意外返回false时bridge固定失败关闭() {
    let error = finish_commit_success(
        BridgeWriteOperation::CgyyCancelOrder,
        BridgeConnectionMode::Direct,
        false,
        "不应暴露的普通失败文案".to_owned(),
        None,
    )
    .expect_err("场馆取消 false 不能成为普通 commit 结果");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert_eq!(error.kind, BridgeErrorKind::Upstream);
    assert!(!error.retryable);
    assert_eq!(error.message, "场馆订单取消响应未确认成功");
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
}

#[test]
fn 场馆取消错误在bridge边界保持发送阶段并固定脱敏文案() {
    let authority = map_cgyy_cancel_preflight_error(RoutedError {
        error: UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "RAW-UPSTREAM phone=PRIVATE token=PRIVATE",
        ),
        resolution: None,
    });
    assert_eq!(authority.code, BridgeErrorCode::UpstreamChanged);
    assert_eq!(authority.message, "场馆订单取消资格核对响应无效");

    let pre_send = map_commit_error(
        BridgeWriteOperation::CgyyCancelOrder,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "fixture pre-send network error",
            ),
            resolution: None,
        },
    );
    assert_eq!(pre_send.code, BridgeErrorCode::NetworkError);
    assert!(pre_send.retryable);

    let post_send = map_commit_error(
        BridgeWriteOperation::CgyyCancelOrder,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                false,
                "RAW-UPSTREAM phone=PRIVATE token=PRIVATE",
            ),
            resolution: None,
        },
    );
    assert_eq!(post_send.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!post_send.retryable);
    for forbidden in ["RAW-UPSTREAM", "phone", "token", "PRIVATE"] {
        assert!(!post_send.message.contains(forbidden));
    }
}

#[tokio::test]
async fn 场馆取消准备读取fresh权威并只保存canonical订单目标() {
    let root = test_root("prepare-cgyy-cancel");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyCancelTransport::new([allowed_detail_body()], []);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("fresh authority Allowed 应签发意图");

    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::CgyyCancelOrder
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert!(intent.target_summary.contains(&ORDER_ID.to_string()));
    assert!(!intent.target_summary.chars().any(char::is_control));
    let intents = client.write_intents.lock().await;
    let stored = intents.get(&intent.intent_id).expect("保存一次性意图");
    let PendingWrite::CgyyCancel(request) = &stored.request else {
        panic!("意图必须只保存场馆取消 action");
    };
    assert_eq!(request.order_id, ORDER_ID);
    assert_eq!(stored.conflict_key, format!("cgyy-cancel:{ORDER_ID}"));
    drop(intents);
    assert_eq!(direct.detail_count(), 1);
    assert_eq!(direct.cancel_count(), 0);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消非法订单编号在网络前拒绝且不保存意图() {
    let root = test_root("invalid-cgyy-cancel");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyCancelTransport::new([], []);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    for order_id in [0, -1] {
        let error = client
            .prepare_cgyy_cancel_order(BridgeCgyyCancelOrderRequest { order_id })
            .await
            .expect_err("非正订单编号不得进入 Core");
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);
    }
    assert!(client.write_intents.lock().await.is_empty());
    assert!(direct.requests().is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消准备对denied与unknown失败关闭且隐藏上游正文() {
    let cases = [
        (
            "denied",
            detail_body(2, 1),
            BridgeErrorCode::OperationConflict,
            true,
        ),
        (
            "unknown",
            detail_body(1, 0),
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
        (
            "mismatch",
            detail_body_for(99, 1, 1),
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
    ];

    for (label, detail, code, retryable) in cases {
        let root = test_root(&format!("prepare-cgyy-cancel-{label}"));
        let _ = std::fs::remove_dir_all(&root);
        let store = seed_sessions(&root, true, false);
        let direct = CgyyCancelTransport::new([detail], []);
        let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
        install_core(
            &client,
            store,
            "[route]\ndefault = \"direct\"\n",
            direct.clone(),
            MockTransport::new([]),
        )
        .await;

        let error = client
            .prepare_cgyy_cancel_order(cancel_request())
            .await
            .expect_err("非 Allowed 权威不得签发意图");

        assert_eq!(error.code, code, "case={label}");
        assert_eq!(error.retryable, retryable, "case={label}");
        for forbidden in ["RAW-UPSTREAM", "phone", "token"] {
            assert!(!error.message.contains(forbidden), "case={label}");
        }
        assert!(client.write_intents.lock().await.is_empty());
        assert_eq!(direct.detail_count(), 1);
        assert_eq!(direct.cancel_count(), 0);
        client.dispose().await.expect("销毁 bridge");
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn 场馆取消同一canonical目标不能同时存在两个待确认意图() {
    let root = test_root("duplicate-cgyy-cancel");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyCancelTransport::new([allowed_detail_body(), allowed_detail_body()], []);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("准备首个取消意图");
    let error = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect_err("同一目标的第二个意图必须冲突");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    assert_eq!(direct.detail_count(), 2);
    assert_eq!(direct.cancel_count(), 0);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消commit重新fresh复核后恰好发送一次且意图只消费一次() {
    let root = test_root("commit-cgyy-cancel-once");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyCancelTransport::new(
        [allowed_detail_body(), allowed_detail_body()],
        [(200, success_body())],
    );
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("准备取消意图");

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("明确成功应返回安全结果");

    assert!(result.success);
    assert_eq!(result.message, "场馆订单已取消");
    assert!(!result.outcome_unknown);
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    assert!(result.cgyy_receipt.is_none());
    assert_eq!(direct.detail_count(), 2);
    assert_eq!(direct.cancel_count(), 1);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("一次性意图不得重用");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.cancel_count(), 1);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消commit只解析一次权威路线并把最终发送绑定到intent路线() {
    let root = test_root("commit-cgyy-cancel-atomic-route");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let direct = CgyyCancelTransport::new(
        [allowed_detail_body(), allowed_detail_body()],
        [(200, success_body())],
    );
    let webvpn = MockTransport::new([]);
    let probe = SequenceProbe::new([
        NetworkState::Campus,
        NetworkState::Campus,
        NetworkState::OffCampus,
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    let core = UbaaClient::with_routing_and_probe_ttl(
        direct.clone(),
        webvpn.clone(),
        store,
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").expect("解析 Auto 路线"),
        probe,
        Duration::ZERO,
    )
    .expect("创建可控 TTL 的测试 Core client");
    *client.inner.lock().await = Some(core);
    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("首次权威解析为 Direct 时应准备取消意图");

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("commit 的唯一权威解析仍为 Direct 时必须在 Direct 完成发送");

    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(direct.detail_count(), 2);
    assert_eq!(direct.cancel_count(), 1);
    assert!(
        webvpn.requests().expect("读取 WebVPN 请求").is_empty(),
        "禁止的第三次解析不得把场馆取消发送到 WebVPN"
    );
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消commit路线变化由core在任何http前拒绝并返回实际路线() {
    let root = test_root("commit-cgyy-cancel-route-mismatch");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let direct = CgyyCancelTransport::new([allowed_detail_body()], []);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("准备 Direct 取消意图");
    let commit_direct = MockTransport::new([]);
    let commit_webvpn = MockTransport::new([]);
    install_core(
        &client,
        store,
        "[route]\ndefault = \"webvpn\"\n",
        commit_direct.clone(),
        commit_webvpn.clone(),
    )
    .await;

    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("实际路线已变为 WebVPN 时必须消费并拒绝 Direct 意图");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::WebVpn));
    assert!(
        commit_direct
            .requests()
            .expect("读取 Direct 请求")
            .is_empty()
    );
    assert!(
        commit_webvpn
            .requests()
            .expect("读取 WebVPN 请求")
            .is_empty()
    );
    assert_eq!(direct.cancel_count(), 0);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消双回读在auto已转路后仍只命中intent固定路线() {
    let root = test_root("cgyy-cancel-pinned-readback");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let direct = CgyyCancelTransport::new(
        [
            allowed_detail_body(),
            allowed_detail_body(),
            detail_body(2, 1),
        ],
        [(200, success_body())],
    );
    let webvpn = MockTransport::new([]);
    let probe = MutableProbe::new(NetworkState::Campus);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    let core = UbaaClient::with_routing_and_probe_ttl(
        direct.clone(),
        webvpn.clone(),
        store,
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").expect("解析 Auto 路线"),
        probe.clone(),
        Duration::ZERO,
    )
    .expect("创建可控 TTL 的测试 Core client");
    *client.inner.lock().await = Some(core);
    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("Campus 下准备 Direct 取消意图");
    client
        .commit_write(intent.intent_id)
        .await
        .expect("Campus 下在 Direct 完成取消");
    probe.set(NetworkState::OffCampus);
    let current_auto_route = {
        let mut guard = client.inner.lock().await;
        guard
            .as_mut()
            .expect("Core client 仍有效")
            .resolve_route_for_feature(ubaa_core::facade::ReadonlyFeature::Cgyy)
            .expect("Auto 路线应可重新解析")
            .mode
    };
    assert_eq!(
        current_auto_route,
        ubaa_core::facade::ConnectionMode::WebVpn
    );

    let orders = client
        .cgyy_orders_on_route(BridgeConnectionMode::Direct, 0, 20)
        .await
        .expect("列表回读必须固定在 intent Direct 路线");
    let detail = client
        .cgyy_order_detail_on_route(BridgeConnectionMode::Direct, ORDER_ID)
        .await
        .expect("详情回读必须固定在 intent Direct 路线");

    assert_eq!(orders.pinned_route, BridgeConnectionMode::Direct);
    assert_eq!(detail.pinned_route, BridgeConnectionMode::Direct);
    assert_eq!(orders.data.content.len(), 1);
    assert_eq!(orders.data.content[0].id, ORDER_ID);
    assert_eq!(
        orders.data.content[0]
            .cancelled_target
            .as_ref()
            .map(|target| target.order_id),
        Some(ORDER_ID)
    );
    assert_eq!(detail.data.id, ORDER_ID);
    assert_eq!(
        detail
            .data
            .cancelled_target
            .as_ref()
            .map(|target| target.order_id),
        Some(ORDER_ID)
    );
    assert_eq!(direct.detail_count(), 3);
    assert_eq!(direct.orders_count(), 1);
    assert!(
        webvpn.requests().expect("读取 WebVPN 请求").is_empty(),
        "Auto 后续已转为 WebVPN 也不得改写 intent 固定回读路线"
    );
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消commit前资格漂移会消费意图且不发送最终post() {
    let root = test_root("commit-cgyy-cancel-drift");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyCancelTransport::new([allowed_detail_body(), detail_body(2, 1)], []);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("准备取消意图");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("commit fresh authority 漂移必须拒绝");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert_eq!(direct.detail_count(), 2);
    assert_eq!(direct.cancel_count(), 0);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格漂移后意图已经消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 场馆取消最终发送后歧义保持outcome_unknown且绝不重放或泄漏正文() {
    let root = test_root("commit-cgyy-cancel-unknown");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = CgyyCancelTransport::new(
        [allowed_detail_body(), allowed_detail_body()],
        [(200, unknown_body())],
    );
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_cgyy_cancel_order(cancel_request())
        .await
        .expect("准备取消意图");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("发送后歧义必须保持未知结果");

    assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
    for forbidden in ["RAW-UPSTREAM", "phone", "token", "PRIVATE"] {
        assert!(!error.message.contains(forbidden));
    }
    assert_eq!(direct.detail_count(), 2);
    assert_eq!(direct.cancel_count(), 1);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("未知结果后的意图不得重用");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.cancel_count(), 1);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

fn cancel_request() -> BridgeCgyyCancelOrderRequest {
    BridgeCgyyCancelOrderRequest { order_id: ORDER_ID }
}

fn allowed_detail_body() -> String {
    detail_body(1, 1)
}

fn detail_body(order_status: i32, check_status: i32) -> String {
    detail_body_for(ORDER_ID, order_status, check_status)
}

fn detail_body_for(order_id: i32, order_status: i32, check_status: i32) -> String {
    format!(
        r#"{{"code":200,"message":"RAW-UPSTREAM phone=PRIVATE token=PRIVATE","data":{{"id":{order_id},"orderStatus":{order_status},"checkStatus":{check_status},"reservationStartDate":"2999-09-05 12:00:00","reservationEndDate":"2999-09-05 13:00:00"}}}}"#
    )
}

fn success_body() -> String {
    r#"{"code":200,"message":"RAW-UPSTREAM phone=PRIVATE token=PRIVATE"}"#.into()
}

fn unknown_body() -> String {
    r#"{"code":500,"message":"RAW-UPSTREAM phone=PRIVATE token=PRIVATE"}"#.into()
}

fn cancelled_orders_body() -> String {
    format!(
        r#"{{"code":200,"data":{{"content":[{{"id":{ORDER_ID},"orderStatus":2,"checkStatus":1}}],"totalElements":1,"totalPages":1,"size":20,"number":0}}}}"#
    )
}

#[derive(Clone)]
struct CgyyCancelTransport {
    state: Arc<Mutex<CgyyCancelState>>,
}

struct CgyyCancelState {
    detail_bodies: VecDeque<String>,
    cancel_responses: VecDeque<(u16, String)>,
    requests: Vec<HttpRequest>,
}

impl CgyyCancelTransport {
    fn new(
        detail_bodies: impl IntoIterator<Item = String>,
        cancel_responses: impl IntoIterator<Item = (u16, String)>,
    ) -> Self {
        Self {
            state: Arc::new(Mutex::new(CgyyCancelState {
                detail_bodies: detail_bodies.into_iter().collect(),
                cancel_responses: cancel_responses.into_iter().collect(),
                requests: Vec::new(),
            })),
        }
    }

    fn requests(&self) -> Vec<HttpRequest> {
        self.state.lock().expect("锁定请求").requests.clone()
    }

    fn path_count(&self, expected: &str) -> usize {
        self.requests()
            .iter()
            .filter(|request| request_path(request) == expected)
            .count()
    }

    fn detail_count(&self) -> usize {
        self.path_count(&format!("/venue-zhjs-server/api/orders/{ORDER_ID}"))
    }

    fn cancel_count(&self) -> usize {
        self.path_count(&format!(
            "/venue-zhjs-server/api/orders/new/cancel/{ORDER_ID}"
        ))
    }

    fn orders_count(&self) -> usize {
        self.path_count("/venue-zhjs-server/api/orders/mine")
    }
}

#[async_trait]
impl HttpTransport for CgyyCancelTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = request_path(&request).to_owned();
        let mut state = self.state.lock().expect("锁定场馆取消 bridge 场景");
        state.requests.push(request.clone());
        match path.as_str() {
            "/venue-zhjs-server/sso/manageLogin" => {
                let mut response = HttpResponse::new(200, request.url, Vec::new());
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec!["sso_buaa_zhjs_token=sso-fixture; Path=/".into()],
                );
                Ok(response)
            }
            "/venue-zhjs-server/api/login" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"access-fixture"}}}"#.to_vec(),
            )),
            path if path == format!("/venue-zhjs-server/api/orders/{ORDER_ID}") => {
                let body = state
                    .detail_bodies
                    .pop_front()
                    .ok_or_else(missing_response)?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            "/venue-zhjs-server/api/orders/mine" => Ok(HttpResponse::new(
                200,
                request.url,
                cancelled_orders_body().into_bytes(),
            )),
            path if path == format!("/venue-zhjs-server/api/orders/new/cancel/{ORDER_ID}") => {
                assert_eq!(request.method, ubaa_core::facade::testing::HttpMethod::Post);
                assert!(request.body.is_empty());
                let (status, body) = state
                    .cancel_responses
                    .pop_front()
                    .ok_or_else(missing_response)?;
                Ok(HttpResponse::new(status, request.url, body.into_bytes()))
            }
            _ => Err(missing_response()),
        }
    }
}

fn request_path(request: &HttpRequest) -> &str {
    request
        .url
        .split_once('?')
        .map_or(request.url.as_str(), |(path, _)| path)
        .strip_prefix("https://cgyy.buaa.edu.cn")
        .unwrap_or_default()
}

fn missing_response() -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        "缺少脱敏场馆取消响应",
    )
}

#[derive(Clone)]
struct SequenceProbe {
    states: Arc<Mutex<VecDeque<NetworkState>>>,
}

impl SequenceProbe {
    fn new(states: impl IntoIterator<Item = NetworkState>) -> Self {
        Self {
            states: Arc::new(Mutex::new(states.into_iter().collect())),
        }
    }
}

impl GatewayProbe for SequenceProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.states
            .lock()
            .expect("锁定路线探测序列")
            .pop_front()
            .expect("场馆取消不得超出允许的权威路线解析次数")
    }
}

#[derive(Clone)]
struct MutableProbe {
    state: Arc<Mutex<NetworkState>>,
}

impl MutableProbe {
    fn new(state: NetworkState) -> Self {
        Self {
            state: Arc::new(Mutex::new(state)),
        }
    }

    fn set(&self, state: NetworkState) {
        *self.state.lock().expect("锁定可变路线探测状态") = state;
    }
}

impl GatewayProbe for MutableProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        *self.state.lock().expect("锁定可变路线探测状态")
    }
}
