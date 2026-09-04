use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
    from_webvpn_url, to_webvpn_url,
};
use ubaa_core::facade::{
    ActionEligibility, ConnectionMode, ErrorCode, ErrorKind, LibBookCancelRequest, Result,
    RouteClient, UbaaError,
};

const BOOKING_ID: &str = "booking-safe";

#[test]
fn 图书馆预约记录只从严格状态派生取消资格() {
    let rows = r#"
        {"id":" allowed ","status":1,"statusName":"已结束仅展示"},
        {"id":"allowed-string","status":"1"},
        {"id":"denied-six","status":6,"statusName":"可以取消仅展示"},
        {"id":"denied-eight","status":"8"},
        {"id":"missing"},
        {"id":"null","status":null},
        {"id":"leading-zero","status":"01"},
        {"id":"plus","status":"+1"},
        {"id":"other","status":2},
        {"id":"   ","status":1}
    "#;
    let scenario = Scenario::new([bookings_response(rows)]);
    let (mut client, root) = client_for("status-matrix", scenario);

    let bookings = runtime()
        .block_on(client.libbook_bookings(2, 10))
        .expect("预约列表应可解析")
        .data
        .bookings;

    let expected = [
        (
            Some(1),
            ActionEligibility::Allowed,
            Some("allowed"),
            "已结束仅展示",
        ),
        (
            Some(1),
            ActionEligibility::Allowed,
            Some("allowed-string"),
            "",
        ),
        (
            Some(6),
            ActionEligibility::Denied,
            Some("denied-six"),
            "可以取消仅展示",
        ),
        (Some(8), ActionEligibility::Denied, Some("denied-eight"), ""),
        (None, ActionEligibility::Unknown, None, ""),
        (None, ActionEligibility::Unknown, None, ""),
        (None, ActionEligibility::Unknown, None, ""),
        (None, ActionEligibility::Unknown, None, ""),
        (Some(2), ActionEligibility::Unknown, None, ""),
        (Some(1), ActionEligibility::Unknown, None, ""),
    ];
    assert_eq!(bookings.len(), expected.len());
    for (booking, (status, eligibility, target, status_name)) in bookings.iter().zip(expected) {
        assert_eq!(booking.status, status, "booking={}", booking.id);
        assert_eq!(
            booking.cancel_eligibility, eligibility,
            "booking={}",
            booking.id
        );
        assert_eq!(
            booking.cancel_target.as_deref(),
            target,
            "booking={}",
            booking.id
        );
        assert_eq!(booking.status_name, status_name, "booking={}", booking.id);
    }
    cleanup(root);
}

#[test]
fn 图书馆取消在任何网络前校验完整本地目标() {
    let cases = [
        (
            "blank-id",
            LibBookCancelRequest {
                booking_id: " \t".into(),
                page: 2,
                limit: 10,
            },
        ),
        (
            "zero-page",
            LibBookCancelRequest {
                booking_id: BOOKING_ID.into(),
                page: 0,
                limit: 10,
            },
        ),
        (
            "negative-page",
            LibBookCancelRequest {
                booking_id: BOOKING_ID.into(),
                page: -1,
                limit: 10,
            },
        ),
        (
            "zero-limit",
            LibBookCancelRequest {
                booking_id: BOOKING_ID.into(),
                page: 2,
                limit: 0,
            },
        ),
    ];

    for (case, request) in cases {
        let scenario = Scenario::new([]);
        let (mut client, root) = client_for(&format!("prepare-{case}"), scenario.clone());
        let error = runtime()
            .block_on(client.preflight_libbook_cancel(&request))
            .expect_err("无效取消目标必须在网络前拒绝");
        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::InvalidInput, false),
            "prepare {case}"
        );
        assert!(scenario.requests().is_empty(), "prepare {case}");
        cleanup(root);

        let scenario = Scenario::new([]);
        let (mut client, root) = client_for(&format!("commit-{case}"), scenario.clone());
        let error = runtime()
            .block_on(client.libbook_cancel_booking(request))
            .expect_err("无效取消目标必须在网络前拒绝");
        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::InvalidInput, false),
            "commit {case}"
        );
        assert!(scenario.requests().is_empty(), "commit {case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消预检只读取_action_所属页并返回安全摘要() {
    let scenario = allowed_scenario();
    let (mut client, root) = client_for("preflight", scenario.clone());

    let preflight = runtime()
        .block_on(client.preflight_libbook_cancel(&cancel_request()))
        .expect("唯一 active 预约应通过预检")
        .data;

    assert_eq!(preflight.booking_id, BOOKING_ID);
    assert_eq!(preflight.booking_name, "脱敏预约");
    assert_eq!(preflight.area_name, "脱敏分区");
    assert_eq!(preflight.seat_no, "001");
    assert_eq!(preflight.day, "2026-09-04");
    assert_eq!(preflight.begin_time, "08:00");
    assert_eq!(preflight.end_time, "10:00");
    let requests = scenario.requests();
    assert_eq!(
        paths(&requests),
        [
            "/login",
            "/v4/login/cas",
            "/v4/login/user",
            "/v4/member/seat"
        ]
    );
    assert_eq!(
        json_body(request_for_path(&requests, "/v4/member/seat")),
        serde_json::json!({"type":"1","page":2,"limit":10})
    );
    assert_eq!(scenario.cancel_count(), 0);
    cleanup(root);
}

#[test]
fn 图书馆取消拒绝缺失_denied_unknown_与重复目标且不越过写边界() {
    let cases = [
        (
            "missing",
            bookings_response(r#"{"id":"other","status":1}"#),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "denied-six",
            bookings_response(&booking_row_with_status("6")),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "denied-eight",
            bookings_response(&booking_row_with_status("\"8\"")),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "unknown-missing-status",
            bookings_response(&format!(r#"{{"id":"{BOOKING_ID}"}}"#)),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "unknown-other-status",
            bookings_response(&booking_row_with_status("2")),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "duplicate",
            bookings_response(&format!(
                "{},{}",
                booking_row_with_status("1"),
                booking_row_with_status("1")
            )),
            ErrorCode::UpstreamChanged,
            false,
        ),
    ];

    for (case, bookings, code, retryable) in cases {
        let scenario = Scenario::new([bookings]);
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect_err("非唯一 allowed 目标必须安全拒绝");

        assert_eq!((error.code, error.retryable), (code, retryable), "{case}");
        assert_eq!(scenario.member_count(), 1, "{case}");
        assert_eq!(scenario.cancel_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消拒绝响应落在不同分页上下文() {
    let cases = [
        (
            "wrong-page",
            paged_bookings_response(&allowed_booking_row(), 1, 10),
        ),
        (
            "wrong-limit",
            paged_bookings_response(&allowed_booking_row(), 2, 20),
        ),
    ];

    for (case, bookings) in cases {
        let scenario = Scenario::new([bookings]);
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect_err("响应分页与 action 上下文不一致时必须安全拒绝");

        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::UpstreamChanged, false),
            "{case}"
        );
        assert_eq!(scenario.member_count(), 1, "{case}");
        assert_eq!(scenario.cancel_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消拒绝缺失畸形非正或冲突的分页权威() {
    let row = allowed_booking_row();
    let cases = [
        (
            "missing",
            format!(r#"{{"code":1,"data":{{"data":[{row}],"total":1}}}}"#),
        ),
        (
            "noncanonical",
            format!(
                r#"{{"code":1,"data":{{"data":[{row}],"current_page":"01","per_page":1,"total":1}}}}"#
            ),
        ),
        (
            "non-positive",
            format!(
                r#"{{"code":1,"data":{{"data":[{row}],"current_page":1,"per_page":0,"total":1}}}}"#
            ),
        ),
        (
            "conflicting-aliases",
            format!(
                r#"{{"code":1,"data":{{"data":[{row}],"current_page":1,"page":2,"per_page":1,"limit":1,"total":1}}}}"#
            ),
        ),
    ];

    for (case, bookings) in cases {
        let scenario = Scenario::new([bookings]);
        let (mut client, root) = client_for(case, scenario.clone());
        let request = LibBookCancelRequest {
            booking_id: BOOKING_ID.into(),
            page: 1,
            limit: 1,
        };

        let error = runtime()
            .block_on(client.libbook_cancel_booking(request))
            .expect_err("分页权威结构不足时必须安全拒绝");

        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::UpstreamChanged, false),
            "{case}"
        );
        assert_eq!(scenario.member_count(), 1, "{case}");
        assert_eq!(scenario.cancel_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消准备与提交的预约列表错误不暴露上游原文() {
    for phase in ["prepare", "commit"] {
        let scenario = Scenario::new([
            r#"{"code":2,"message":"失败\n学号=private token=secret\u0000"}"#.into(),
        ]);
        let (mut client, root) =
            client_for(&format!("unsafe-member-message-{phase}"), scenario.clone());

        let error = if phase == "prepare" {
            runtime()
                .block_on(client.preflight_libbook_cancel(&cancel_request()))
                .expect_err("prepare 的预约列表错误必须安全归约")
        } else {
            runtime()
                .block_on(client.libbook_cancel_booking(cancel_request()))
                .expect_err("commit 的预约列表错误必须安全归约")
        };

        assert_eq!(
            (error.code, error.kind, error.retryable),
            (ErrorCode::UpstreamChanged, ErrorKind::Upstream, false),
            "{phase}"
        );
        assert_eq!(error.message, "图书馆预约取消资格核对响应无效", "{phase}");
        for unsafe_fragment in ["private", "secret", "学号", "token", "\n", "\0"] {
            assert!(
                !error.message.contains(unsafe_fragment),
                "{phase} 暴露了 {unsafe_fragment:?}"
            );
        }
        assert_eq!(scenario.member_count(), 1, "{phase}");
        assert_eq!(scenario.cancel_count(), 0, "{phase}");
        cleanup(root);
    }
}

#[test]
fn 显式取消预检通过后提交仍重新读取并拒绝状态漂移() {
    let scenario = Scenario::new([
        bookings_response(&allowed_booking_row()),
        bookings_response(&booking_row_with_status("6")),
    ]);
    let (mut client, root) = client_for("fresh-preflight", scenario.clone());
    let request = cancel_request();
    let runtime = runtime();

    runtime
        .block_on(client.preflight_libbook_cancel(&request))
        .expect("prepare 阶段应明确允许");
    let error = runtime
        .block_on(client.libbook_cancel_booking(request))
        .expect_err("commit 不得复用 prepare 阶段的旧资格");

    assert_eq!(
        (error.code, error.retryable),
        (ErrorCode::InvalidInput, true)
    );
    assert_eq!(scenario.member_count(), 2);
    assert_eq!(scenario.cancel_count(), 0);
    cleanup(root);
}

#[test]
fn 图书馆取消可在发送前刷新认证但最终请求只发送一次() {
    let scenario = Scenario::new([
        r#"{"code":2,"message":"请重新登录"}"#.into(),
        bookings_response(&allowed_booking_row()),
    ]);
    let (mut client, root) = client_for("pre-send-refresh", scenario.clone());

    let result = runtime()
        .block_on(client.libbook_cancel_booking(cancel_request()))
        .expect("写边界前的只读复核可刷新 bearer")
        .data;

    assert!(result.success);
    assert_eq!(scenario.path_count("/v4/login/user"), 2);
    assert_eq!(scenario.member_count(), 2);
    assert_eq!(scenario.cancel_count(), 1);
    cleanup(root);
}

#[test]
fn 图书馆取消按冻结实现生成_direct_与_webvpn_头部及唯一_wire_字段() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let scenario = allowed_scenario();
        let case = match mode {
            ConnectionMode::Direct => "headers-direct",
            ConnectionMode::WebVpn => "headers-webvpn",
        };
        let (mut client, root) = client_for_mode(case, mode, scenario.clone());

        let result = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect("两条路线应按冻结合同取消")
            .data;

        assert!(result.success);
        assert_eq!(result.message, "图书馆预约已取消");
        let requests = scenario.requests();
        assert_eq!(
            paths(&requests),
            [
                "/login",
                "/v4/login/cas",
                "/v4/login/user",
                "/v4/member/seat",
                "/v4/space/cancel",
            ]
        );
        assert_eq!(scenario.cancel_count(), 1);

        let member = request_for_path(&requests, "/v4/member/seat");
        assert_eq!(
            json_body(member),
            serde_json::json!({"type":"1","page":2,"limit":10})
        );
        let cancel = request_for_path(&requests, "/v4/space/cancel");
        assert_eq!(json_body(cancel), serde_json::json!({"id":BOOKING_ID}));

        let expected_base = match mode {
            ConnectionMode::Direct => "https://booking.lib.buaa.edu.cn".to_owned(),
            ConnectionMode::WebVpn => {
                to_webvpn_url("https://booking.lib.buaa.edu.cn").expect("生成 WebVPN 基址")
            }
        };
        for path in ["/v4/login/user", "/v4/member/seat", "/v4/space/cancel"] {
            let request = request_for_path(&requests, path);
            assert_eq!(
                request.headers.get("Accept").map(String::as_str),
                Some("application/json, text/plain, */*"),
                "{mode:?} {path}"
            );
            assert_eq!(
                request.headers.get("User-Agent").map(String::as_str),
                Some(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
                ),
                "{mode:?} {path}"
            );
            assert_eq!(
                request.headers.get("X-Requested-With").map(String::as_str),
                Some("XMLHttpRequest"),
                "{mode:?} {path}"
            );
            assert_eq!(request.headers.get("Origin"), Some(&expected_base));
            assert_eq!(request.headers.get("Referer"), Some(&expected_base));
            assert_eq!(
                request.headers.get("Content-Type").map(String::as_str),
                Some("application/json")
            );
            if path == "/v4/login/user" {
                assert!(!request.headers.contains_key("Authorization"));
            } else {
                assert_eq!(
                    request.headers.get("Authorization").map(String::as_str),
                    Some("bearerfixture-token")
                );
            }
        }
        cleanup(root);
    }
}

#[test]
fn 图书馆取消只对白名单结果给出固定安全文案() {
    let cases = [
        (
            "success-ignores-raw-fields",
            r#"{"code":1,"message":"取消成功","success":false,"status":0}"#,
            true,
            "图书馆预约已取消",
        ),
        (
            "string-code-success",
            r#"{"code":"0","msg":"取消成功","success":"false"}"#,
            true,
            "图书馆预约已取消",
        ),
        (
            "generic-negative",
            r#"{"code":0,"message":"取消失败，预约号=敏感值\nTOKEN=secret","status":1}"#,
            false,
            "图书馆预约取消未完成",
        ),
    ];

    for (case, body, success, message) in cases {
        let scenario = allowed_scenario().with_cancel(CancelSubmit::Response(200, body.into()));
        let (mut client, root) = client_for(case, scenario.clone());

        let result = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect("冻结 code/message 足以形成确定业务结果")
            .data;

        assert_eq!(result.success, success, "{case}");
        assert_eq!(result.message, message, "{case}");
        assert_eq!(scenario.cancel_count(), 1, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消未知成功文案不能越过白名单且公开错误不含原文() {
    for (case, body) in [
        ("generic-success", r#"{"code":1,"message":"操作成功"}"#),
        (
            "sensitive-suffix",
            r#"{"code":1,"message":"取消成功 token=secret\n预约号=private"}"#,
        ),
    ] {
        let scenario = allowed_scenario().with_cancel(CancelSubmit::Response(200, body.into()));
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect_err("未知成功文案必须归为结果未知");

        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::OutcomeUnknown, false),
            "{case}"
        );
        assert_eq!(
            error.message,
            "图书馆取消结果未知，请刷新预约记录后再决定是否重试"
        );
        assert!(!error.message.contains("secret"));
        assert!(!error.message.contains("private"));
        assert_eq!(scenario.cancel_count(), 1, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消将已知终态映射为固定安全错误() {
    for (case, code, message) in [
        ("ended", 2, "预约已结束，不能取消"),
        ("cancelled", 1, "预约已取消"),
        (
            "missing",
            0,
            "预约记录不存在或已失效，预约号=private，token=secret\\n",
        ),
    ] {
        let body = format!(r#"{{"code":{code},"message":"{message}"}}"#);
        let scenario = allowed_scenario().with_cancel(CancelSubmit::Response(200, body));
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect_err("已知终态应返回确定且稳定的错误");

        assert_eq!(
            (error.code, error.kind, error.retryable),
            (ErrorCode::InvalidInput, ErrorKind::Input, false),
            "{case}"
        );
        assert_eq!(error.message, "图书馆预约已结束、已取消或不存在", "{case}");
        assert!(!error.message.contains("secret"), "{case}");
        assert!(!error.message.contains("private"), "{case}");
        assert_eq!(scenario.cancel_count(), 1, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆取消发送后歧义统一为_outcome_unknown_且不重放() {
    let cases = [
        ("transport", CancelSubmit::TransportError),
        ("http", CancelSubmit::Response(503, String::new())),
        ("redirect", CancelSubmit::Response(302, String::new())),
        (
            "business-redirect",
            CancelSubmit::FinalUrl(
                "https://booking.lib.buaa.edu.cn/h5/index.html",
                r#"{"code":1,"message":"取消成功"}"#.into(),
            ),
        ),
        (
            "authentication-final-url",
            CancelSubmit::FinalUrl(
                "https://sso.buaa.edu.cn/login",
                r#"{"code":1,"message":"取消成功"}"#.into(),
            ),
        ),
        (
            "authentication-body",
            CancelSubmit::Response(200, r#"{"code":2,"message":"请重新登录"}"#.into()),
        ),
        ("non-json", CancelSubmit::Response(200, "not-json".into())),
        (
            "missing-message",
            CancelSubmit::Response(200, r#"{"code":1}"#.into()),
        ),
        (
            "missing-code",
            CancelSubmit::Response(200, r#"{"message":"取消成功"}"#.into()),
        ),
        (
            "noncanonical-code",
            CancelSubmit::Response(200, r#"{"code":"01","message":"取消成功"}"#.into()),
        ),
        (
            "unknown-code-two",
            CancelSubmit::Response(200, r#"{"code":2,"message":"系统繁忙"}"#.into()),
        ),
    ];

    for (case, submit) in cases {
        let scenario = allowed_scenario().with_cancel(submit);
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_cancel_booking(cancel_request()))
            .expect_err("越过发送边界后的歧义必须归为结果未知");

        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::OutcomeUnknown, false),
            "{case}"
        );
        assert_eq!(scenario.cancel_count(), 1, "{case} 最终写不得自动重放");
        cleanup(root);
    }
}

fn cancel_request() -> LibBookCancelRequest {
    LibBookCancelRequest {
        booking_id: BOOKING_ID.into(),
        page: 2,
        limit: 10,
    }
}

fn allowed_scenario() -> Scenario {
    Scenario::new([bookings_response(&allowed_booking_row())])
}

fn allowed_booking_row() -> String {
    format!(
        r#"{{"id":"{BOOKING_ID}","nameMerge":"脱敏预约","name":"脱敏分区","no":"001","day":"2026-09-04","beginTime":"08:00","endTime":"10:00","status":1,"statusName":"待使用"}}"#
    )
}

fn booking_row_with_status(status: &str) -> String {
    format!(r#"{{"id":"{BOOKING_ID}","status":{status}}}"#)
}

fn bookings_response(rows: &str) -> String {
    paged_bookings_response(rows, 2, 10)
}

fn paged_bookings_response(rows: &str, page: i32, limit: i32) -> String {
    format!(
        r#"{{"code":1,"data":{{"data":[{rows}],"total":1,"current_page":{page},"per_page":{limit}}}}}"#
    )
}

fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("创建测试 runtime")
}

fn client_for(name: &str, scenario: Scenario) -> (RouteClient, std::path::PathBuf) {
    client_for_mode(name, ConnectionMode::Direct, scenario)
}

fn client_for_mode(
    name: &str,
    mode: ConnectionMode,
    scenario: Scenario,
) -> (RouteClient, std::path::PathBuf) {
    let root = test_root(name);
    let store = FileSessionStore::new(&root).expect("创建会话存储");
    store.save(&ready_session(mode)).expect("写入脱敏会话");
    let client = RouteClient::with_transport(mode, scenario, store).expect("创建图书馆客户端");
    (client, root)
}

fn test_root(name: &str) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "ubaa-libbook-cancel-authority-{name}-{}-{:?}",
        std::process::id(),
        std::thread::current().id(),
    ));
    let _ = std::fs::remove_dir_all(&root);
    root
}

fn ready_session(mode: ConnectionMode) -> SessionSnapshot {
    SessionSnapshot {
        mode,
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity: 1_001,
    }
}

fn cleanup(root: std::path::PathBuf) {
    let _ = std::fs::remove_dir_all(root);
}

fn paths(requests: &[HttpRequest]) -> Vec<String> {
    requests.iter().map(request_path).collect()
}

fn request_path(request: &HttpRequest) -> String {
    let direct = from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
    url::Url::parse(&direct)
        .expect("请求 URL 有效")
        .path()
        .to_owned()
}

fn request_for_path<'a>(requests: &'a [HttpRequest], path: &str) -> &'a HttpRequest {
    requests
        .iter()
        .find(|request| request_path(request) == path)
        .expect("应存在指定路径请求")
}

fn json_body(request: &HttpRequest) -> serde_json::Value {
    serde_json::from_slice(&request.body).expect("请求正文应为 JSON")
}

#[derive(Clone)]
struct Scenario {
    state: Arc<Mutex<State>>,
}

struct State {
    requests: Vec<HttpRequest>,
    bookings: VecDeque<String>,
    cancel: CancelSubmit,
}

#[derive(Clone)]
enum CancelSubmit {
    Response(u16, String),
    FinalUrl(&'static str, String),
    TransportError,
}

impl Scenario {
    fn new(bookings: impl IntoIterator<Item = String>) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                requests: Vec::new(),
                bookings: bookings.into_iter().collect(),
                cancel: CancelSubmit::Response(200, r#"{"code":1,"message":"取消成功"}"#.into()),
            })),
        }
    }

    fn with_cancel(self, cancel: CancelSubmit) -> Self {
        self.state.lock().expect("锁定场景").cancel = cancel;
        self
    }

    fn requests(&self) -> Vec<HttpRequest> {
        self.state.lock().expect("锁定场景").requests.clone()
    }

    fn path_count(&self, expected: &str) -> usize {
        self.requests()
            .iter()
            .filter(|request| request_path(request) == expected)
            .count()
    }

    fn member_count(&self) -> usize {
        self.path_count("/v4/member/seat")
    }

    fn cancel_count(&self) -> usize {
        self.path_count("/v4/space/cancel")
    }
}

#[async_trait]
impl HttpTransport for Scenario {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = request_path(&request);
        let mut state = self.state.lock().expect("锁定场景");
        state.requests.push(request.clone());
        match path.as_str() {
            "/login" => {
                let mut response = HttpResponse::new(302, request.url, Vec::new());
                response.headers.insert(
                    "Location".into(),
                    vec!["https://booking.lib.buaa.edu.cn/v4/login/cas?ticket=ST-safe".into()],
                );
                Ok(response)
            }
            "/v4/login/cas" => Ok(HttpResponse::new(
                200,
                "https://booking.lib.buaa.edu.cn/h5/index.html#/cas/?cas=cas-safe",
                Vec::new(),
            )),
            "/v4/login/user" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":0,"data":{"member":{"token":"fixture-token"}}}"#.to_vec(),
            )),
            "/v4/member/seat" => {
                let body = state
                    .bookings
                    .pop_front()
                    .ok_or_else(|| test_error(ErrorCode::InternalError, "缺少预约分页响应"))?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            "/v4/space/cancel" => match state.cancel.clone() {
                CancelSubmit::Response(status, body) => {
                    Ok(HttpResponse::new(status, request.url, body.into_bytes()))
                }
                CancelSubmit::FinalUrl(final_url, body) => {
                    Ok(HttpResponse::new(200, final_url, body.into_bytes()))
                }
                CancelSubmit::TransportError => Err(test_error(
                    ErrorCode::NetworkError,
                    "脱敏取消发送后网络失败",
                )),
            },
            _ => Err(test_error(
                ErrorCode::InternalError,
                "未预期的图书馆测试路径",
            )),
        }
    }
}

fn test_error(code: ErrorCode, message: &'static str) -> UbaaError {
    let kind = if code == ErrorCode::NetworkError {
        ErrorKind::Network
    } else {
        ErrorKind::Internal
    };
    UbaaError::new(code, kind, false, message)
}
