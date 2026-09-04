use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    BykcActionResult, ConnectionMode, ErrorCode, ErrorKind, FeatureResult, NetworkState, Result,
    RouteClient, UbaaClient, UbaaError,
};

const SELECT_ALLOWED: &str = r#"{"status":"0","data":{"id":42,"courseName":"可选课程","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":1,"courseMaxCount":10,"selected":false}}"#;
const DESELECT_ALLOWED: &str = r#"{"status":"0","data":{"id":42,"courseName":"可退课程","courseStartDate":"2999-01-01 00:00:00","selected":true}}"#;

#[derive(Clone, Copy, Debug)]
enum CourseWrite {
    Select,
    Deselect,
}

impl CourseWrite {
    fn suffix(self) -> &'static str {
        match self {
            Self::Select => "select",
            Self::Deselect => "deselect",
        }
    }

    fn write_path(self) -> &'static str {
        match self {
            Self::Select => "/sscv/choseCourse",
            Self::Deselect => "/sscv/delChosenCourse",
        }
    }

    fn perform(
        self,
        runtime: &tokio::runtime::Runtime,
        client: &mut RouteClient,
    ) -> Result<FeatureResult<BykcActionResult>> {
        runtime.block_on(async {
            match self {
                Self::Select => client.bykc_select_course(42).await,
                Self::Deselect => client.bykc_deselect_course(42).await,
            }
        })
    }
}

#[test]
fn 博雅课程写边界拒绝_denied_unknown_和错配目标且不发送写请求() {
    let cases = [
        (
            CourseWrite::Select,
            "denied",
            r#"{"status":"0","data":{"id":42,"courseName":"已选课程","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":1,"courseMaxCount":10,"selected":true}}"#,
            ErrorCode::InvalidInput,
            true,
        ),
        (
            CourseWrite::Select,
            "unknown",
            r#"{"status":"0","data":{"id":42,"courseName":"缺失选中状态","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":1,"courseMaxCount":10}}"#,
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            CourseWrite::Select,
            "string-capacity",
            r#"{"status":"0","data":{"id":42,"courseName":"字符串容量","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":"1","courseMaxCount":"10","selected":false}}"#,
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            CourseWrite::Select,
            "mismatched",
            r#"{"status":"0","data":{"id":43,"courseName":"错配课程","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":1,"courseMaxCount":10,"selected":false}}"#,
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            CourseWrite::Deselect,
            "denied",
            r#"{"status":"0","data":{"id":42,"courseName":"未选课程","selected":false}}"#,
            ErrorCode::InvalidInput,
            true,
        ),
        (
            CourseWrite::Deselect,
            "unknown",
            r#"{"status":"0","data":{"id":42,"courseName":"缺失开课时间","selected":true}}"#,
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            CourseWrite::Deselect,
            "mismatched",
            r#"{"status":"0","data":{"id":43,"courseName":"错配课程","courseStartDate":"2999-01-01 00:00:00","selected":true}}"#,
            ErrorCode::UpstreamChanged,
            false,
        ),
    ];
    for (action, case, detail, code, retryable) in cases {
        let (root, paths, result) = exercise(
            action,
            case,
            detail,
            r#"{"status":"0","data":{"message":"不得发送"}}"#,
        );
        let error = result.expect_err("未获明确授权时必须拒绝");
        assert_eq!((error.code, error.retryable), (code, retryable), "{case}");
        assert_eq!(paths, ["/sscv/cas/login", "/sscv/queryCourseById"]);
        assert!(!paths.iter().any(|path| path == action.write_path()));
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn 博雅课程写边界仅在资格明确允许时按精确序列提交() {
    for (action, detail, response) in [
        (
            CourseWrite::Select,
            SELECT_ALLOWED,
            r#"{"status":"0","data":{"message":"ok"}}"#,
        ),
        (
            CourseWrite::Deselect,
            DESELECT_ALLOWED,
            r#"{"status":"0","data":{"courseCurrentCount":null,"message":"ok"}}"#,
        ),
    ] {
        let (root, paths, result) = exercise(action, "allowed", detail, response);
        assert_eq!(result.expect("资格明确允许时应提交").data.message, "ok");
        assert_eq!(
            paths,
            [
                "/sscv/cas/login",
                "/sscv/queryCourseById",
                action.write_path()
            ]
        );
        assert_eq!(
            paths
                .iter()
                .filter(|path| path.as_str() == action.write_path())
                .count(),
            1
        );
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn 博雅课程写前核对拒绝宽松信封且不发送写请求() {
    for (action, allowed) in [
        (CourseWrite::Select, SELECT_ALLOWED),
        (CourseWrite::Deselect, DESELECT_ALLOWED),
    ] {
        let data = serde_json::from_str::<serde_json::Value>(allowed).unwrap()["data"].clone();
        for (case, detail) in [
            (
                "missing-status",
                serde_json::json!({"success":true,"data":data.clone()}),
            ),
            (
                "numeric-status",
                serde_json::json!({"status":0,"success":true,"data":data.clone()}),
            ),
            (
                "nonzero-status",
                serde_json::json!({"status":"1","success":true,"data":data.clone()}),
            ),
            (
                "result-only",
                serde_json::json!({"status":"0","result":data.clone()}),
            ),
        ] {
            let (root, paths, result) = exercise(
                action,
                case,
                &detail.to_string(),
                r#"{"status":"0","data":{"message":"不得发送"}}"#,
            );
            let error = result.expect_err("宽松信封不得成为写资格证据");
            assert_eq!(error.code, ErrorCode::UpstreamChanged, "{action:?}/{case}");
            assert_eq!(paths, ["/sscv/cas/login", "/sscv/queryCourseById"]);
            let _ = std::fs::remove_dir_all(root);
        }
    }
}

#[test]
fn 博雅课程写已发送后_data_形状无效时结果未知() {
    for (action, detail) in [
        (CourseWrite::Select, SELECT_ALLOWED),
        (CourseWrite::Deselect, DESELECT_ALLOWED),
    ] {
        for (case, response) in [
            (
                "wrong-type",
                r#"{"status":"0","data":{"courseCurrentCount":"bad"}}"#,
            ),
            (
                "overflow",
                r#"{"status":"0","data":{"courseCurrentCount":2147483648}}"#,
            ),
            ("missing", r#"{"status":"0"}"#),
            ("null", r#"{"status":"0","data":null}"#),
            ("scalar", r#"{"status":"0","data":7}"#),
        ] {
            let (root, paths, result) = exercise(action, case, detail, response);
            let error = result.expect_err("课程动作结果必须符合 typed DTO");
            assert_eq!(
                (error.code, error.retryable),
                (ErrorCode::OutcomeUnknown, false)
            );
            assert_eq!(
                paths,
                [
                    "/sscv/cas/login",
                    "/sscv/queryCourseById",
                    action.write_path()
                ]
            );
            let _ = std::fs::remove_dir_all(root);
        }
    }
}

#[test]
fn route_client_发送后会话变化不得覆盖确定结果或结果未知() {
    for (case, response, expected_error) in [
        (
            "confirmed",
            r#"{"status":"0","data":{"message":"ok"}}"#,
            None,
        ),
        (
            "outcome-unknown",
            r#"{"status":"0"}"#,
            Some((ErrorCode::OutcomeUnknown, false)),
        ),
    ] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-bykc-route-post-send-mutation-{case}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).unwrap();
        store.save(&ready_session(1_001)).unwrap();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let mut client = RouteClient::with_transport(
            ConnectionMode::Direct,
            PostSendMutationTransport {
                inner: CourseActionTransport {
                    requests: Arc::clone(&requests),
                    detail: SELECT_ALLOWED.as_bytes().to_vec(),
                    response: response.as_bytes().to_vec(),
                },
                mutation: PostSendSessionMutation::Single(store.clone()),
            },
            store,
        )
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let result = runtime.block_on(client.bykc_select_course(42));

        assert_write_result(result.map(|value| value.data), expected_error, case);
        assert_eq!(write_count(&requests, "/sscv/choseCourse"), 1, "{case}");
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn ubaa_client_发送后会话变化保持确定结果或结果未知() {
    for (case, response, expected_error) in [
        (
            "confirmed",
            r#"{"status":"0","data":{"message":"ok"}}"#,
            None,
        ),
        (
            "outcome-unknown",
            r#"{"status":"0"}"#,
            Some((ErrorCode::OutcomeUnknown, false)),
        ),
    ] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-bykc-routed-post-send-mutation-{case}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).unwrap();
        store
            .save_dual(&DualSessionSnapshot::new(Some(ready_route(1_001)), None))
            .unwrap();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let unused_requests = Arc::new(Mutex::new(Vec::new()));
        let mut client = UbaaClient::with_routing(
            PostSendMutationTransport {
                inner: CourseActionTransport {
                    requests: Arc::clone(&requests),
                    detail: SELECT_ALLOWED.as_bytes().to_vec(),
                    response: response.as_bytes().to_vec(),
                },
                mutation: PostSendSessionMutation::Dual(store.clone()),
            },
            CourseActionTransport {
                requests: Arc::clone(&unused_requests),
                detail: SELECT_ALLOWED.as_bytes().to_vec(),
                response: response.as_bytes().to_vec(),
            },
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
            NeverProbe,
        )
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let result = runtime
            .block_on(client.bykc_select_course(42))
            .map(|value| value.data)
            .map_err(|error| error.error);

        assert_write_result(result, expected_error, case);
        assert_eq!(write_count(&requests, "/sscv/choseCourse"), 1, "{case}");
        assert!(unused_requests.lock().unwrap().is_empty(), "{case}");
        let _ = std::fs::remove_dir_all(root);
    }
}

fn assert_write_result(
    result: Result<BykcActionResult>,
    expected_error: Option<(ErrorCode, bool)>,
    case: &str,
) {
    match expected_error {
        None => assert_eq!(result.expect("确定响应不得被会话冲突覆盖").message, "ok"),
        Some(expected) => {
            let error = result.expect_err("不确定响应必须保留结果未知语义");
            assert_eq!((error.code, error.retryable), expected, "{case}");
        }
    }
}

fn write_count(requests: &Arc<Mutex<Vec<HttpRequest>>>, path: &str) -> usize {
    requests
        .lock()
        .unwrap()
        .iter()
        .filter(|request| url::Url::parse(&request.url).is_ok_and(|url| url.path() == path))
        .count()
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

fn exercise(
    action: CourseWrite,
    case: &str,
    detail: &str,
    response: &str,
) -> (
    std::path::PathBuf,
    Vec<String>,
    Result<FeatureResult<BykcActionResult>>,
) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-bykc-core-authority-{}-{case}-{}",
        action.suffix(),
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        CourseActionTransport {
            requests: Arc::clone(&requests),
            detail: detail.as_bytes().to_vec(),
            response: response.as_bytes().to_vec(),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = action.perform(&runtime, &mut client);
    let paths = requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    (root, paths, result)
}

#[derive(Clone)]
struct CourseActionTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    detail: Vec<u8>,
    response: Vec<u8>,
}

#[async_trait]
impl HttpTransport for CourseActionTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        self.requests.lock().unwrap().push(request.clone());
        let body = match path.as_str() {
            "/sscv/cas/login" => {
                return Ok(HttpResponse::new(
                    302,
                    "https://bykc.buaa.edu.cn/sscv/cas/login?token=token-safe",
                    Vec::new(),
                ));
            }
            "/sscv/queryCourseById" => self.detail.clone(),
            "/sscv/choseCourse" | "/sscv/delChosenCourse" => self.response.clone(),
            _ => return Err(test_error("unexpected bykc course action path")),
        };
        Ok(HttpResponse::new(200, request.url, body))
    }
}

#[derive(Clone)]
struct PostSendMutationTransport {
    inner: CourseActionTransport,
    mutation: PostSendSessionMutation,
}

#[derive(Clone)]
enum PostSendSessionMutation {
    Single(FileSessionStore),
    Dual(FileSessionStore),
}

impl PostSendSessionMutation {
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
        let is_write =
            url::Url::parse(&request.url).is_ok_and(|url| url.path() == "/sscv/choseCourse");
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

fn test_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}
