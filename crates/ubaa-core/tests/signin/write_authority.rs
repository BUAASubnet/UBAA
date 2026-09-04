use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, NetworkState, Result, RouteClient, UbaaClient, UbaaError,
};

const USER_ID: &str = "user-safe";
const SCHEDULE_ID: &str = "schedule-safe";
const SESSION_ID: &str = "session-safe";

pub(super) fn allowed_target_is_rechecked_and_submitted_once_with_separated_identifiers() {
    let scenario = Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")]);
    let (mut client, root) = client_for("allowed", scenario.clone());

    let result = runtime()
        .block_on(client.signin_perform(SCHEDULE_ID))
        .expect("允许目标应提交成功")
        .data;

    assert!(result.success);
    assert_eq!(result.code, 200);
    let requests = scenario.requests();
    assert_eq!(
        paths(&requests),
        vec![
            "/",
            "/eschool/app/user/login_buaa.do",
            "/app/course/get_stu_course_sched.action",
            "/app/common/get_timestamp.action",
            "/eschool/app/course/stu_scan_sign.action",
        ]
    );
    let submit = requests.last().expect("必须存在最终提交");
    let url = url::Url::parse(&submit.url).expect("提交 URL 有效");
    assert_eq!(query(&url, "courseSchedId"), Some(SCHEDULE_ID.into()));
    assert_eq!(query(&url, "timestamp"), Some("1700000000000".into()));
    assert_eq!(String::from_utf8_lossy(&submit.body), "id=user-safe");
    assert_eq!(
        submit.headers.get("sessionId").map(String::as_str),
        Some(SESSION_ID)
    );
    assert!(!submit.url.contains(USER_ID));
    assert!(!String::from_utf8_lossy(&submit.body).contains(SCHEDULE_ID));
    cleanup(root);
}

#[test]
fn denied_unknown_missing_and_malformed_status_never_reach_write_boundary() {
    let cases = [
        ("denied", today_row(SCHEDULE_ID, "signStatus", "1")),
        ("unknown", today_row(SCHEDULE_ID, "signStatus", "2")),
        ("missing", today_without_status(SCHEDULE_ID)),
        (
            "malformed",
            today_row(SCHEDULE_ID, "signStatus", r#""bad""#),
        ),
    ];
    for (name, today) in cases {
        let scenario = Scenario::new([today]);
        let (mut client, root) = client_for(name, scenario.clone());
        let error = runtime()
            .block_on(client.signin_perform(SCHEDULE_ID))
            .expect_err("非允许资格必须安全拒绝");
        assert_ne!(error.code, ErrorCode::OutcomeUnknown);
        assert_eq!(scenario.write_count(), 0, "{name} 不得发出写请求");
        assert_eq!(
            paths(&scenario.requests()),
            vec![
                "/",
                "/eschool/app/user/login_buaa.do",
                "/app/course/get_stu_course_sched.action",
            ]
        );
        cleanup(root);
    }
}

#[test]
fn missing_or_duplicate_exact_target_never_reaches_write_boundary() {
    for (name, today) in [
        (
            "target-missing",
            today_row("other-schedule-safe", "signStatus", "0"),
        ),
        (
            "target-duplicate",
            format!(
                r#"{{"STATUS":"0","result":[{},{}]}}"#,
                row(SCHEDULE_ID, "signStatus", "0"),
                row(SCHEDULE_ID, "signStatus", "0"),
            ),
        ),
    ] {
        let scenario = Scenario::new([today]);
        let (mut client, root) = client_for(name, scenario.clone());
        let error = runtime()
            .block_on(client.signin_perform(SCHEDULE_ID))
            .expect_err("目标必须唯一且精确匹配");
        assert_ne!(error.code, ErrorCode::OutcomeUnknown);
        assert_eq!(scenario.write_count(), 0);
        cleanup(root);
    }
}

#[test]
fn explicit_business_false_is_a_determined_result() {
    for (name, response) in [
        (
            "nested-false",
            r#"{"STATUS":"0","ERRMSG":"签到尚未完成","result":{"stuSignStatus":"0"}}"#,
        ),
        (
            "top-false",
            r#"{"STATUS":1,"ERRMSG":"请重新登录 token=secret-safe@example.test\n","result":{}}"#,
        ),
    ] {
        let scenario = Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")])
            .with_submit(Submit::Response(200, response.into()));
        let (mut client, root) = client_for(name, scenario.clone());
        let result = runtime()
            .block_on(client.signin_perform(SCHEDULE_ID))
            .expect("明确业务失败不是传输错误")
            .data;
        assert!(!result.success);
        assert_eq!(result.code, 400);
        assert_eq!(result.message, "签到未完成");
        assert_eq!(scenario.write_count(), 1);
        cleanup(root);
    }
}

#[test]
fn numeric_and_numeric_string_write_statuses_are_accepted() {
    for (name, response) in [
        (
            "numeric",
            r#"{"STATUS":0,"ERRMSG":"ok","result":{"stuSignStatus":1}}"#,
        ),
        (
            "numeric-string",
            r#"{"STATUS":"200","ERRMSG":"ok","result":{"stuSignStatus":"1"}}"#,
        ),
    ] {
        let scenario = Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")])
            .with_submit(Submit::Response(200, response.into()));
        let (mut client, root) = client_for(name, scenario.clone());
        let result = runtime()
            .block_on(client.signin_perform(SCHEDULE_ID))
            .expect("冻结数字兼容应成功")
            .data;
        assert!(result.success);
        assert_eq!(result.code, 200);
        cleanup(root);
    }
}

#[test]
fn malformed_post_boundary_responses_are_outcome_unknown_and_not_retried() {
    for (name, submit) in [
        ("http", Submit::Response(503, String::new())),
        ("non-json", Submit::Response(200, "not-json".into())),
        (
            "missing-status",
            Submit::Response(
                200,
                r#"{"ERRMSG":"ok","result":{"stuSignStatus":1}}"#.into(),
            ),
        ),
        (
            "missing-result-status",
            Submit::Response(200, r#"{"STATUS":0,"ERRMSG":"ok","result":{}}"#.into()),
        ),
        (
            "top-level-result-only",
            Submit::Response(
                200,
                r#"{"STATUS":0,"ERRMSG":"ok","stuSignStatus":1,"result":{}}"#.into(),
            ),
        ),
        (
            "nested-other-status",
            Submit::Response(
                200,
                r#"{"STATUS":0,"ERRMSG":"ok","result":{"stuSignStatus":2}}"#.into(),
            ),
        ),
        (
            "authentication-redirect",
            Submit::Response(302, String::new()),
        ),
        (
            "authentication-final-url",
            Submit::FinalUrl(
                "https://sso.buaa.edu.cn/login",
                r#"{"STATUS":0,"ERRMSG":"ok","result":{"stuSignStatus":1}}"#.into(),
            ),
        ),
        ("transport", Submit::TransportError),
    ] {
        let scenario =
            Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")]).with_submit(submit);
        let (mut client, root) = client_for(name, scenario.clone());
        let error = runtime()
            .block_on(client.signin_perform(SCHEDULE_ID))
            .expect_err("越过发送边界后的畸形结果必须为未知");
        assert_eq!(error.code, ErrorCode::OutcomeUnknown);
        assert!(!error.retryable);
        assert_eq!(scenario.write_count(), 1, "写请求不得自动重放");
        cleanup(root);
    }
}

#[test]
fn pre_send_failure_keeps_original_error_classification() {
    let scenario =
        Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")]).with_timestamp_error();
    let (mut client, root) = client_for("pre-send-error", scenario.clone());
    let error = runtime()
        .block_on(client.signin_perform(SCHEDULE_ID))
        .expect_err("发送前读取失败应原样返回");
    assert_eq!(error.code, ErrorCode::NetworkError);
    assert_eq!(scenario.write_count(), 0);
    cleanup(root);
}

#[test]
fn route_client_post_send_session_change_preserves_business_false_and_unknown() {
    for (name, response, expected_unknown) in [
        (
            "route-business-false",
            r#"{"STATUS":0,"result":{"stuSignStatus":0}}"#,
            false,
        ),
        ("route-unknown", r#"{"STATUS":0,"result":{}}"#, true),
    ] {
        let root = test_root(name);
        let store = FileSessionStore::new(&root).expect("创建会话存储");
        store.save(&ready_session(1_001)).expect("写入会话");
        let scenario = Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")])
            .with_submit(Submit::Response(200, response.into()));
        let mut client = RouteClient::with_transport(
            ConnectionMode::Direct,
            PostSendMutationTransport {
                inner: scenario.clone(),
                mutation: SessionMutation::Single(store.clone()),
            },
            store,
        )
        .expect("创建单路线客户端");

        let result = runtime().block_on(client.signin_perform(SCHEDULE_ID));

        assert_signin_result(result.map(|value| value.data), expected_unknown, name);
        assert_eq!(scenario.write_count(), 1, "{name}");
        cleanup(root);
    }
}

#[test]
fn ubaa_client_post_send_session_change_preserves_business_false_and_unknown() {
    for (name, response, expected_unknown) in [
        (
            "aggregate-business-false",
            r#"{"STATUS":0,"result":{"stuSignStatus":0}}"#,
            false,
        ),
        ("aggregate-unknown", r#"{"STATUS":0,"result":{}}"#, true),
    ] {
        let root = test_root(name);
        let store = FileSessionStore::new(&root).expect("创建会话存储");
        store
            .save_dual(&DualSessionSnapshot::new(Some(ready_route(1_001)), None))
            .expect("写入双路线会话");
        let scenario = Scenario::new([today_row(SCHEDULE_ID, "signStatus", "0")])
            .with_submit(Submit::Response(200, response.into()));
        let unused = Scenario::new(Vec::<String>::new());
        let mut client = UbaaClient::with_routing(
            PostSendMutationTransport {
                inner: scenario.clone(),
                mutation: SessionMutation::Dual(store.clone()),
            },
            unused.clone(),
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"\n").expect("解析固定路线"),
            NeverProbe,
        )
        .expect("创建聚合客户端");

        let result = runtime()
            .block_on(client.signin_perform(SCHEDULE_ID))
            .map(|value| value.data)
            .map_err(|error| error.error);

        assert_signin_result(result, expected_unknown, name);
        assert_eq!(scenario.write_count(), 1, "{name}");
        assert!(unused.requests().is_empty(), "{name}");
        cleanup(root);
    }
}

fn assert_signin_result(
    result: Result<ubaa_core::facade::SigninActionResult>,
    expected_unknown: bool,
    name: &str,
) {
    if expected_unknown {
        let error = result.expect_err("畸形写后响应必须保持结果未知");
        assert_eq!(
            (error.code, error.retryable),
            (ErrorCode::OutcomeUnknown, false),
            "{name}"
        );
    } else {
        let result = result.expect("明确业务 false 不得被会话冲突覆盖");
        assert!(!result.success, "{name}");
        assert_eq!(result.code, 400, "{name}");
    }
}

fn row(schedule_id: &str, status_key: &str, status_value: &str) -> String {
    format!(
        r#"{{"id":"{schedule_id}","courseName":"脱敏课程","classBeginTime":"08:00","classEndTime":"09:40","{status_key}":{status_value}}}"#,
    )
}

fn today_row(schedule_id: &str, status_key: &str, status_value: &str) -> String {
    format!(
        r#"{{"STATUS":"0","result":[{}]}}"#,
        row(schedule_id, status_key, status_value)
    )
}

fn today_without_status(schedule_id: &str) -> String {
    format!(
        r#"{{"STATUS":"0","result":[{{"id":"{schedule_id}","courseName":"脱敏课程","classBeginTime":"08:00","classEndTime":"09:40"}}]}}"#,
    )
}

fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("创建测试 runtime")
}

fn client_for(name: &str, scenario: Scenario) -> (RouteClient, std::path::PathBuf) {
    let root = test_root(name);
    let store = FileSessionStore::new(&root).expect("创建会话存储");
    store.save(&ready_session(1_001)).expect("写入脱敏会话");
    let client = RouteClient::with_transport(ConnectionMode::Direct, scenario, store)
        .expect("创建签到客户端");
    (client, root)
}

fn test_root(name: &str) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "ubaa-signin-{name}-{}-{:?}",
        std::process::id(),
        std::thread::current().id(),
    ));
    let _ = std::fs::remove_dir_all(&root);
    root
}

fn ready_session(last_activity: i64) -> SessionSnapshot {
    SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity,
    }
}

fn ready_route(last_activity: i64) -> RouteSessionSnapshot {
    RouteSessionSnapshot {
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity,
    }
}

fn cleanup(root: std::path::PathBuf) {
    let _ = std::fs::remove_dir_all(root);
}

fn paths(requests: &[HttpRequest]) -> Vec<String> {
    requests
        .iter()
        .map(|request| {
            url::Url::parse(&request.url)
                .expect("请求 URL 有效")
                .path()
                .to_owned()
        })
        .collect()
}

fn query(url: &url::Url, key: &str) -> Option<String> {
    url.query_pairs()
        .find(|(candidate, _)| candidate == key)
        .map(|(_, value)| value.into_owned())
}

#[derive(Clone)]
struct Scenario {
    state: Arc<Mutex<State>>,
}

struct State {
    requests: Vec<HttpRequest>,
    today: VecDeque<String>,
    submit: Submit,
    timestamp_error: bool,
}

#[derive(Clone)]
enum Submit {
    Response(u16, String),
    FinalUrl(&'static str, String),
    TransportError,
}

impl Scenario {
    fn new(today: impl IntoIterator<Item = String>) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                requests: Vec::new(),
                today: today.into_iter().collect(),
                submit: Submit::Response(
                    200,
                    r#"{"STATUS":0,"ERRMSG":"ok","result":{"stuSignStatus":1}}"#.into(),
                ),
                timestamp_error: false,
            })),
        }
    }

    fn with_submit(self, submit: Submit) -> Self {
        self.state.lock().expect("锁定场景").submit = submit;
        self
    }

    fn with_timestamp_error(self) -> Self {
        self.state.lock().expect("锁定场景").timestamp_error = true;
        self
    }

    fn requests(&self) -> Vec<HttpRequest> {
        self.state.lock().expect("锁定场景").requests.clone()
    }

    fn write_count(&self) -> usize {
        self.requests()
            .iter()
            .filter(|request| {
                url::Url::parse(&request.url)
                    .is_ok_and(|url| url.path().ends_with("stu_scan_sign.action"))
            })
            .count()
    }
}

#[async_trait]
impl HttpTransport for Scenario {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error(ErrorCode::InternalError, "测试 URL 无效"))?
            .path()
            .to_owned();
        let mut state = self.state.lock().expect("锁定场景");
        state.requests.push(request.clone());
        match path.as_str() {
            "/" => Ok(HttpResponse::new(
                200,
                format!("https://iclass.buaa.edu.cn:8346/?loginName={SESSION_ID}"),
                Vec::new(),
            )),
            "/eschool/app/user/login_buaa.do" => Ok(HttpResponse::new(
                200,
                request.url,
                format!(r#"{{"STATUS":"0","result":{{"id":"{USER_ID}"}}}}"#).into_bytes(),
            )),
            "/app/course/get_stu_course_sched.action" => {
                let body = state
                    .today
                    .pop_front()
                    .ok_or_else(|| test_error(ErrorCode::InternalError, "缺少今日课程响应"))?;
                Ok(HttpResponse::new(200, request.url, body.into_bytes()))
            }
            "/app/common/get_timestamp.action" if state.timestamp_error => {
                Err(test_error(ErrorCode::NetworkError, "脱敏发送前网络失败"))
            }
            "/app/common/get_timestamp.action" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"timestamp":"1700000000000"}"#.to_vec(),
            )),
            "/eschool/app/course/stu_scan_sign.action" => match state.submit.clone() {
                Submit::Response(status, body) => {
                    Ok(HttpResponse::new(status, request.url, body.into_bytes()))
                }
                Submit::FinalUrl(final_url, body) => {
                    Ok(HttpResponse::new(200, final_url, body.into_bytes()))
                }
                Submit::TransportError => {
                    Err(test_error(ErrorCode::NetworkError, "脱敏发送后网络失败"))
                }
            },
            _ => Err(test_error(ErrorCode::InternalError, "未预期的签到测试路径")),
        }
    }
}

#[derive(Clone)]
struct PostSendMutationTransport {
    inner: Scenario,
    mutation: SessionMutation,
}

#[derive(Clone)]
enum SessionMutation {
    Single(FileSessionStore),
    Dual(FileSessionStore),
}

impl SessionMutation {
    fn apply(&self) -> Result<()> {
        match self {
            Self::Single(store) => store.save(&ready_session(2_001)),
            Self::Dual(store) => store
                .save_dual(&DualSessionSnapshot::new(Some(ready_route(2_001)), None))
                .map(|_| ()),
        }
    }
}

#[async_trait]
impl HttpTransport for PostSendMutationTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let is_write = url::Url::parse(&request.url)
            .is_ok_and(|url| url.path().ends_with("stu_scan_sign.action"));
        let response = self.inner.execute(request).await?;
        if is_write {
            self.mutation.apply()?;
        }
        Ok(response)
    }
}

struct NeverProbe;

impl GatewayProbe for NeverProbe {
    fn probe(&self, _budget: std::time::Duration) -> NetworkState {
        panic!("固定路线不得执行网关探测")
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
