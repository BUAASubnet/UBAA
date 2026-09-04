use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
    from_webvpn_url, to_webvpn_url,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, LibBookReserveRequest, Result, RouteClient, UbaaError,
};

const AREA_ID: &str = "area-safe";
const SEAT_ID: &str = "seat-safe";
const DAY: &str = "2026-09-04";
const SEGMENT: &str = "segment-safe";
const START_TIME: &str = "08:00";
const END_TIME: &str = "10:00";

#[test]
fn 图书馆预约仅在唯一目标明确允许时新鲜复核并发送一次() {
    let scenario = allowed_scenario();
    let (mut client, root) = client_for("allowed", scenario.clone());

    let result = runtime()
        .block_on(client.libbook_reserve(reserve_request()))
        .expect("唯一且明确允许的座位应预约成功")
        .data;

    assert!(result.success);
    assert_eq!(result.message, "操作成功");
    let requests = scenario.requests();
    assert_eq!(
        paths(&requests),
        [
            "/login",
            "/v4/login/cas",
            "/v4/login/user",
            "/v4/Space/map",
            "/v4/Space/seat",
            "/v4/space/confirm",
        ]
    );
    assert_eq!(scenario.confirm_count(), 1);

    let map = request_for_path(&requests, "/v4/Space/map");
    assert_eq!(json_body(map)["id"], AREA_ID);
    let seats = request_for_path(&requests, "/v4/Space/seat");
    let seats_body = json_body(seats);
    assert_eq!(seats_body["id"], AREA_ID);
    assert_eq!(seats_body["day"], DAY);
    assert_eq!(seats_body["start_time"], START_TIME);
    assert_eq!(seats_body["end_time"], END_TIME);

    let confirm = request_for_path(&requests, "/v4/space/confirm");
    assert_eq!(
        confirm.headers.get("Authorization").map(String::as_str),
        Some("bearerfixture-token")
    );
    let confirm_body = json_body(confirm);
    assert!(
        confirm_body["aesjson"]
            .as_str()
            .is_some_and(|value| !value.is_empty())
    );
    assert!(!String::from_utf8_lossy(&confirm.body).contains(AREA_ID));
    cleanup(root);
}

#[test]
fn 图书馆预约按冻结实现生成_direct_与_webvpn_请求头() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let scenario = allowed_scenario();
        let case = match mode {
            ConnectionMode::Direct => "headers-direct",
            ConnectionMode::WebVpn => "headers-webvpn",
        };
        let (mut client, root) = client_for_mode(case, mode, scenario.clone());

        let result = runtime()
            .block_on(client.libbook_reserve(reserve_request()))
            .expect("两条路线都应以同一冻结头部合同构造请求")
            .data;
        assert!(result.success);

        let requests = scenario.requests();
        let expected_base = match mode {
            ConnectionMode::Direct => "https://booking.lib.buaa.edu.cn".to_owned(),
            ConnectionMode::WebVpn => {
                to_webvpn_url("https://booking.lib.buaa.edu.cn").expect("生成脱敏 WebVPN 基地址")
            }
        };
        for path in [
            "/v4/login/user",
            "/v4/Space/map",
            "/v4/Space/seat",
            "/v4/space/confirm",
        ] {
            let request = request_for_path(&requests, path);
            assert_eq!(
                request.headers.get("Accept").map(String::as_str),
                Some("application/json, text/plain, */*"),
                "{mode:?} {path}",
            );
            assert_eq!(
                request.headers.get("User-Agent").map(String::as_str),
                Some(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
                ),
                "{mode:?} {path}",
            );
            assert_eq!(
                request.headers.get("X-Requested-With").map(String::as_str),
                Some("XMLHttpRequest"),
                "{mode:?} {path}",
            );
            assert_eq!(
                request.headers.get("Origin"),
                Some(&expected_base),
                "{mode:?} {path}",
            );
            assert_eq!(
                request.headers.get("Referer"),
                Some(&expected_base),
                "{mode:?} {path}",
            );
        }
        cleanup(root);
    }
}

#[test]
fn 图书馆预约目标日期非首日时仍只使用该日时段() {
    let scenario = Scenario::new(
        [area_detail_dates(
            r#"{"day":"2026-09-03","times":[{"id":"other-segment","start":"08:00","end":"10:00"}]},{"day":"2026-09-04","times":[{"id":"segment-safe","start":"08:00","end":"10:00"}]}"#,
        )],
        [allowed_seats()],
    );
    let (mut client, root) = client_for("target-day-not-first", scenario.clone());

    let result = runtime()
        .block_on(client.libbook_reserve(reserve_request()))
        .expect("目标日期即使不是首日也应按自身时段完成复核")
        .data;

    assert!(result.success);
    assert_eq!(scenario.path_count("/v4/Space/seat"), 1);
    assert_eq!(scenario.confirm_count(), 1);
    cleanup(root);
}

#[test]
fn 图书馆预约拒绝_denied_与_unknown_资格且不越过写边界() {
    let cases = [
        (
            "denied-two",
            seat_response(r#"{"id":"seat-safe","status":2}"#),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "denied-three",
            seat_response(r#"{"id":"seat-safe","status":"3"}"#),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "unknown-missing",
            seat_response(r#"{"id":"seat-safe"}"#),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "unknown-other",
            seat_response(r#"{"id":"seat-safe","status":9}"#),
            ErrorCode::UpstreamChanged,
            false,
        ),
    ];

    for (case, seats, code, retryable) in cases {
        let scenario = Scenario::new([allowed_area_detail()], [seats]);
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_reserve(reserve_request()))
            .expect_err("非 allowed 资格必须安全拒绝");

        assert_eq!((error.code, error.retryable), (code, retryable), "{case}");
        assert_eq!(scenario.path_count("/v4/Space/map"), 1, "{case}");
        assert_eq!(scenario.path_count("/v4/Space/seat"), 1, "{case}");
        assert_eq!(scenario.confirm_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 图书馆预约拒绝缺失或重复的时段与座位目标() {
    let cases = [
        (
            "date-missing",
            area_detail_dates(
                r#"{"day":"2026-09-03","times":[{"id":"segment-safe","start":"08:00","end":"10:00"}]}"#,
            ),
            allowed_seats(),
            ErrorCode::InvalidInput,
            true,
            0,
        ),
        (
            "date-duplicate",
            area_detail_dates(
                r#"{"day":"2026-09-04","times":[{"id":"segment-safe","start":"08:00","end":"10:00"}]},{"day":"2026-09-04","times":[{"id":"segment-safe","start":"08:00","end":"10:00"}]}"#,
            ),
            allowed_seats(),
            ErrorCode::UpstreamChanged,
            false,
            0,
        ),
        (
            "segment-missing",
            area_detail(r#"{"id":"other-segment","start":"08:00","end":"10:00"}"#),
            allowed_seats(),
            ErrorCode::InvalidInput,
            true,
            0,
        ),
        (
            "segment-duplicate",
            area_detail(
                r#"{"id":"segment-safe","start":"08:00","end":"10:00"},{"id":"segment-safe","start":"08:00","end":"10:00"}"#,
            ),
            allowed_seats(),
            ErrorCode::UpstreamChanged,
            false,
            0,
        ),
        (
            "segment-duplicate-with-different-times",
            area_detail(
                r#"{"id":"segment-safe","start":"08:00","end":"10:00"},{"id":"segment-safe","start":"10:00","end":"12:00"}"#,
            ),
            allowed_seats(),
            ErrorCode::UpstreamChanged,
            false,
            0,
        ),
        (
            "seat-missing",
            allowed_area_detail(),
            seat_response(r#"{"id":"other-seat","status":1}"#),
            ErrorCode::InvalidInput,
            true,
            1,
        ),
        (
            "seat-duplicate",
            allowed_area_detail(),
            seat_response(r#"{"id":"seat-safe","status":1},{"id":"seat-safe","status":1}"#),
            ErrorCode::UpstreamChanged,
            false,
            1,
        ),
    ];

    for (case, detail, seats, code, retryable, expected_seat_reads) in cases {
        let scenario = Scenario::new([detail], [seats]);
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_reserve(reserve_request()))
            .expect_err("目标不唯一或不存在时必须安全拒绝");

        assert_eq!((error.code, error.retryable), (code, retryable), "{case}");
        assert_eq!(scenario.path_count("/v4/Space/map"), 1, "{case}");
        assert_eq!(
            scenario.path_count("/v4/Space/seat"),
            expected_seat_reads,
            "{case}"
        );
        assert_eq!(scenario.confirm_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 显式预检通过后提交仍会重新读取并拒绝资格漂移() {
    let scenario = Scenario::new(
        [allowed_area_detail(), allowed_area_detail()],
        [
            seat_response(
                r#"{"id":"seat-safe","name":"阅览\n座位\u0000","no":"0\r01","status":1}"#,
            ),
            seat_response(r#"{"id":"seat-safe","status":2}"#),
        ],
    );
    let (mut client, root) = client_for("fresh-preflight", scenario.clone());
    let request = reserve_request();
    let runtime = runtime();

    let preflight = runtime
        .block_on(client.preflight_libbook_reserve(&request))
        .expect("prepare 阶段的当前目标明确允许")
        .data;
    assert_eq!(preflight.area_id, AREA_ID);
    assert_eq!(preflight.seat_id, SEAT_ID);
    assert_eq!(preflight.seat_name, "阅览座位");
    assert_eq!(preflight.seat_no, "001");
    assert_eq!(preflight.day, DAY);
    assert_eq!(preflight.segment, SEGMENT);
    assert_eq!(preflight.start_time, START_TIME);
    assert_eq!(preflight.end_time, END_TIME);
    let error = runtime
        .block_on(client.libbook_reserve(request))
        .expect_err("commit 不得复用 prepare 阶段的旧资格");

    assert_eq!(
        (error.code, error.retryable),
        (ErrorCode::InvalidInput, true)
    );
    assert_eq!(scenario.path_count("/v4/Space/map"), 2);
    assert_eq!(scenario.path_count("/v4/Space/seat"), 2);
    assert_eq!(scenario.confirm_count(), 0);
    cleanup(root);
}

#[test]
fn 图书馆预约保留确定业务_false_且不重放() {
    let scenario = allowed_scenario().with_submit(Submit::Response(
        200,
        r#"{"code":1,"data":{"success":false,"message":"预约条件已变化"}}"#.into(),
    ));
    let (mut client, root) = client_for("business-false", scenario.clone());

    let result = runtime()
        .block_on(client.libbook_reserve(reserve_request()))
        .expect("明确业务失败应作为确定结果返回")
        .data;

    assert!(!result.success);
    assert_eq!(result.message, "预约条件已变化");
    assert_eq!(scenario.confirm_count(), 1);
    cleanup(root);
}

#[test]
fn 图书馆预约冻结失败消息不得被显式_success_true_覆盖() {
    let scenario = allowed_scenario().with_submit(Submit::Response(
        200,
        r#"{"code":1,"message":"预约失败","data":{"success":true}}"#.into(),
    ));
    let (mut client, root) = client_for("negative-message-conflict", scenario.clone());

    let result = runtime()
        .block_on(client.libbook_reserve(reserve_request()))
        .expect("冻结实现的负面消息必须作为确定业务失败返回")
        .data;

    assert!(!result.success);
    assert_eq!(result.message, "预约失败");
    assert_eq!(scenario.confirm_count(), 1);
    cleanup(root);
}

#[test]
fn 图书馆预约发送后歧义统一为_outcome_unknown_且_confirm_只发送一次() {
    let cases = [
        ("transport", Submit::TransportError),
        ("http", Submit::Response(503, String::new())),
        ("non-json", Submit::Response(200, "not-json".into())),
        (
            "missing-outcome",
            Submit::Response(200, r#"{"data":{"message":"未知"}}"#.into()),
        ),
        (
            "authentication-body",
            Submit::Response(200, r#"{"code":2,"message":"请重新登录"}"#.into()),
        ),
        (
            "authentication-status",
            Submit::Response(302, String::new()),
        ),
        (
            "authentication-final-url",
            Submit::FinalUrl(
                "https://sso.buaa.edu.cn/login",
                r#"{"code":1,"data":{"success":true,"message":"不得采信"}}"#.into(),
            ),
        ),
    ];

    for (case, submit) in cases {
        let scenario = allowed_scenario().with_submit(submit);
        let (mut client, root) = client_for(case, scenario.clone());

        let error = runtime()
            .block_on(client.libbook_reserve(reserve_request()))
            .expect_err("越过发送边界后的歧义必须归为结果未知");

        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::OutcomeUnknown, false),
            "{case}"
        );
        assert_eq!(scenario.confirm_count(), 1, "{case} 最终写不得自动重放");
        cleanup(root);
    }
}

fn reserve_request() -> LibBookReserveRequest {
    LibBookReserveRequest {
        area_id: AREA_ID.into(),
        seat_id: SEAT_ID.into(),
        day: DAY.into(),
        segment: SEGMENT.into(),
        start_time: START_TIME.into(),
        end_time: END_TIME.into(),
    }
}

fn allowed_scenario() -> Scenario {
    Scenario::new([allowed_area_detail()], [allowed_seats()])
}

fn allowed_area_detail() -> String {
    area_detail(r#"{"id":"segment-safe","start":"08:00","end":"10:00"}"#)
}

fn area_detail(times: &str) -> String {
    area_detail_dates(&format!(r#"{{"day":"{DAY}","times":[{times}]}}"#))
}

fn area_detail_dates(dates: &str) -> String {
    format!(
        r#"{{"code":1,"data":{{"area":{{"id":"{AREA_ID}","name":"脱敏分区"}},"date":{{"list":[{dates}]}}}}}}"#,
    )
}

fn allowed_seats() -> String {
    seat_response(r#"{"id":"seat-safe","name":"脱敏座位","no":"001","status":1}"#)
}

fn seat_response(rows: &str) -> String {
    format!(r#"{{"code":1,"data":{{"list":[{rows}]}}}}"#)
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
        "ubaa-libbook-authority-{name}-{}-{:?}",
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
    let direct = from_webvpn_url(&request.url).expect("还原测试请求 URL");
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
    area_details: VecDeque<String>,
    seats: VecDeque<String>,
    submit: Submit,
}

#[derive(Clone)]
enum Submit {
    Response(u16, String),
    FinalUrl(&'static str, String),
    TransportError,
}

impl Scenario {
    fn new(
        area_details: impl IntoIterator<Item = String>,
        seats: impl IntoIterator<Item = String>,
    ) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                requests: Vec::new(),
                area_details: area_details.into_iter().collect(),
                seats: seats.into_iter().collect(),
                submit: Submit::Response(
                    200,
                    r#"{"code":1,"message":"操作成功","data":{"bookInfo":{"id":"booking-safe"}}}"#
                        .into(),
                ),
            })),
        }
    }

    fn with_submit(self, submit: Submit) -> Self {
        self.state.lock().expect("锁定场景").submit = submit;
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

    fn confirm_count(&self) -> usize {
        self.path_count("/v4/space/confirm")
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
            "/v4/Space/map" => {
                let body = state
                    .area_details
                    .pop_front()
                    .ok_or_else(|| test_error(ErrorCode::InternalError, "缺少分区详情响应"))?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            "/v4/Space/seat" => {
                let body = state
                    .seats
                    .pop_front()
                    .ok_or_else(|| test_error(ErrorCode::InternalError, "缺少座位响应"))?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            "/v4/space/confirm" => match state.submit.clone() {
                Submit::Response(status, body) => {
                    Ok(HttpResponse::new(status, request.url, body.into_bytes()))
                }
                Submit::FinalUrl(final_url, body) => {
                    Ok(HttpResponse::new(200, final_url, body.into_bytes()))
                }
                Submit::TransportError => Err(test_error(
                    ErrorCode::NetworkError,
                    "脱敏预约发送后网络失败",
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
