use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, Result, RouteClient, UbaaError, YgdkClockinSubmitRequest,
    YgdkPhotoUpload, YgdkSubmitTarget,
};

fn valid_submit_request() -> YgdkClockinSubmitRequest {
    YgdkClockinSubmitRequest {
        target: YgdkSubmitTarget {
            classify_id: 1,
            item_id: 2,
        },
        start_time: "2026-04-01 08:00".into(),
        end_time: "2026-04-01 09:00".into(),
        place: Some("操场".into()),
        share_to_square: false,
        photo: YgdkPhotoUpload {
            file_name: "p.jpg".into(),
            mime_type: "image/jpeg".into(),
            bytes: b"JPEG".to_vec(),
        },
    }
}

#[test]
fn 概览统计和学期请求失败仍按冻结实现返回基础数据() {
    let root = std::env::temp_dir().join(format!("ubaa-ygdk-optional-{}", std::process::id()));
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
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, YgdkOptionalTransport, store).unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let overview = runtime.block_on(client.ygdk_overview()).unwrap().data;
    assert_eq!(overview.default_item_name, "跑步");
    assert_eq!(overview.summary.term_count, 0);
    assert!(overview.summary.term_id.is_none());
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 阳光打卡写链按冻结顺序完成登录概览上传和提交() {
    let root = std::env::temp_dir().join(format!("ubaa-ygdk-write-{}", std::process::id()));
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
        YgdkWriteTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let request = valid_submit_request();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime.block_on(client.ygdk_submit(request)).unwrap().data;
    assert!(result.success);

    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    assert_eq!(
        paths,
        vec![
            "/uc/api/oauth/index",
            "/api/Front/Clockin/User/campusAppLogin",
            "/api/Front/Clockin/Classify/getList",
            "/api/Front/Clockin/Item/getList",
            "/api/Front/Clockin/Clockin/getCount",
            "/api/Front/Clockin/Term/get",
            "/api/Front/Upload/File/post",
            "/api/Front/Clockin/Clockin/clockin",
        ]
    );
    let upload = &requests[6];
    let upload_body = String::from_utf8_lossy(&upload.body);
    let content_type = upload.headers.get("Content-Type").expect("上传 MIME");
    let boundary = content_type
        .strip_prefix("multipart/form-data; boundary=")
        .expect("上传 boundary 参数");
    assert_ne!(boundary, "ubaa-ygdk-boundary");
    assert!(boundary.bytes().all(|value| value.is_ascii_alphanumeric()));
    assert!(upload_body.starts_with(&format!("--{boundary}\r\n")));
    assert!(upload_body.ends_with(&format!("\r\n--{boundary}--\r\n")));
    assert!(upload_body.contains("name=\"uid\"\r\n\r\n7"));
    assert!(upload_body.contains("name=\"token\"\r\n\r\ntok"));
    assert!(upload_body.contains("name=\"file\"; filename=\"p.jpg\""));
    let submit = String::from_utf8_lossy(&requests[7].body);
    assert!(submit.contains("start_time=1775001600"));
    assert!(submit.contains("end_time=1775005200"));
    assert!(submit.contains("form_time_fmt=2026-04-01+08%3A00-09%3A00"));
    assert!(submit.contains("item_id=2"));
    assert!(submit.contains("images=%5B%22uploaded.jpg%22%5D"));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 记录查询在概览刷新凭据后使用当前代次() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-records-credential-{}",
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
    let state = Arc::new(Mutex::new(YgdkRefreshState::default()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        YgdkCredentialRefreshTransport {
            state: Arc::clone(&state),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    runtime.block_on(client.ygdk_records(1, 20)).unwrap();

    let state = state.lock().unwrap();
    assert_eq!(state.login_calls, 2);
    let records = state
        .requests
        .iter()
        .find(|request| {
            url::Url::parse(&request.url).unwrap().path() == "/api/Front/Clockin/Clockin/getList"
        })
        .expect("应发送记录请求");
    let form = url::form_urlencoded::parse(&records.body)
        .into_owned()
        .collect::<std::collections::BTreeMap<_, _>>();
    assert_eq!(form.get("uid").map(String::as_str), Some("8"));
    assert_eq!(form.get("token").map(String::as_str), Some("new-token"));
    assert_eq!(form.get("user_id").map(String::as_str), Some("8"));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 上传各类失败均只尝试一次且不会进入最终提交或认证重放() {
    for (case, reply) in [
        ("transport", FailureReply::Transport),
        ("non-200", FailureReply::Status(503)),
        ("redirect", FailureReply::Redirect),
        ("bad-json", FailureReply::Body("secret invalid json")),
        (
            "bad-file-name",
            FailureReply::Body(r#"{"code":1,"result":{"file_name":123}}"#),
        ),
    ] {
        let requests = run_write_failure_scenario(case, FailureStage::Upload, reply, |result| {
            let error = result.expect_err("上传失败不得确认提交成功");
            assert_eq!(error.message, "阳光打卡照片上传未完成", "{case}");
            assert_eq!(error.code, ErrorCode::UpstreamUnavailable, "{case}");
            assert_eq!(error.kind, ErrorKind::Upstream, "{case}");
            assert!(!error.retryable, "{case}");
            assert!(!error.message.contains("secret"), "{case}");
        });
        assert_write_request_counts(&requests, 1, 0, case);
    }
}

#[test]
fn 最终提交各类发送后失败均只发送一次并归一为结果未知() {
    for (case, reply) in [
        ("transport", FailureReply::Transport),
        ("non-200", FailureReply::Status(503)),
        ("redirect", FailureReply::Redirect),
        ("bad-body", FailureReply::Body("secret invalid json")),
    ] {
        let requests = run_write_failure_scenario(case, FailureStage::Final, reply, |result| {
            let error = result.expect_err("final 歧义不得确认提交成功");
            assert_eq!(error.code, ErrorCode::OutcomeUnknown, "{case}");
            assert_eq!(error.kind, ErrorKind::Upstream, "{case}");
            assert!(!error.retryable, "{case}");
            assert_eq!(
                error.message, "阳光打卡提交结果未知，请刷新概览和记录后核对",
                "{case}"
            );
            assert!(!error.message.contains("secret"), "{case}");
        });
        assert_write_request_counts(&requests, 1, 1, case);
    }
}

fn run_write_failure_scenario(
    case: &str,
    stage: FailureStage,
    reply: FailureReply,
    assert_result: impl FnOnce(
        Result<ubaa_core::facade::FeatureResult<ubaa_core::facade::YgdkClockinSubmitResult>>,
    ),
) -> Vec<HttpRequest> {
    let stage_name = match stage {
        FailureStage::Upload => "upload",
        FailureStage::Final => "final",
    };
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-write-failure-{stage_name}-{case}-{}",
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
        YgdkWriteFailureTransport {
            requests: Arc::clone(&requests),
            stage,
            reply,
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    assert_result(runtime.block_on(client.ygdk_submit(valid_submit_request())));
    let collected = requests.lock().unwrap().clone();
    let _ = std::fs::remove_dir_all(root);
    collected
}

fn assert_write_request_counts(
    requests: &[HttpRequest],
    expected_upload: usize,
    expected_final: usize,
    case: &str,
) {
    let count = |path: &str| {
        requests
            .iter()
            .filter(|request| url::Url::parse(&request.url).unwrap().path() == path)
            .count()
    };
    assert_eq!(
        count("/uc/api/oauth/index"),
        1,
        "{case}: OAuth 不得刷新或重放"
    );
    assert_eq!(
        count("/api/Front/Clockin/User/campusAppLogin"),
        1,
        "{case}: 业务登录不得刷新或重放"
    );
    for path in [
        "/api/Front/Clockin/Classify/getList",
        "/api/Front/Clockin/Item/getList",
        "/api/Front/Clockin/Clockin/getCount",
        "/api/Front/Clockin/Term/get",
    ] {
        assert_eq!(count(path), 1, "{case}: fresh authority 不得重放 {path}");
    }
    assert_eq!(
        count("/api/Front/Upload/File/post"),
        expected_upload,
        "{case}: upload 次数"
    );
    assert_eq!(
        count("/api/Front/Clockin/Clockin/clockin"),
        expected_final,
        "{case}: final 次数"
    );
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum FailureStage {
    Upload,
    Final,
}

#[derive(Clone, Copy)]
enum FailureReply {
    Transport,
    Status(u16),
    Redirect,
    Body(&'static str),
}

#[derive(Clone)]
struct YgdkWriteFailureTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    stage: FailureStage,
    reply: FailureReply,
}

#[derive(Clone)]
struct YgdkWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

struct YgdkOptionalTransport;

#[derive(Default)]
struct YgdkRefreshState {
    login_calls: usize,
    classify_calls: usize,
    requests: Vec<HttpRequest>,
}

#[derive(Clone)]
struct YgdkCredentialRefreshTransport {
    state: Arc<Mutex<YgdkRefreshState>>,
}

#[async_trait]
impl HttpTransport for YgdkOptionalTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = url::Url::parse(&request.url).map_err(|_| test_error("invalid test URL"))?;
        let path = url.path();
        let body = match path {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" => {
                br#"{"code":1,"result":{"uid":7,"token":"tok"}}"#.to_vec()
            }
            "/api/Front/Clockin/Classify/getList" => {
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Item/getList" => {
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","sort":1}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Clockin/getCount" | "/api/Front/Clockin/Term/get" => {
                return Err(test_error("optional ygdk request failed"));
            }
            _ => return Err(test_error("unexpected ygdk path")),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

#[async_trait]
impl HttpTransport for YgdkWriteFailureTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = url::Url::parse(&request.url).map_err(|_| test_error("invalid test URL"))?;
        let path = url.path().to_owned();
        self.requests.lock().unwrap().push(request.clone());
        let is_target = matches!(
            (self.stage, path.as_str()),
            (FailureStage::Upload, "/api/Front/Upload/File/post")
                | (FailureStage::Final, "/api/Front/Clockin/Clockin/clockin")
        );
        if is_target {
            return match self.reply {
                FailureReply::Transport => Err(UbaaError::new(
                    ErrorCode::NetworkError,
                    ErrorKind::Network,
                    true,
                    "secret raw transport detail",
                )),
                FailureReply::Status(status) => Ok(HttpResponse::new(
                    status,
                    request.url,
                    b"secret status body".to_vec(),
                )),
                FailureReply::Redirect => Ok(HttpResponse::new(
                    200,
                    "https://ygdk.buaa.edu.cn/unexpected",
                    b"secret redirect body".to_vec(),
                )),
                FailureReply::Body(body) => Ok(HttpResponse::new(
                    200,
                    request.url,
                    body.as_bytes().to_vec(),
                )),
            };
        }
        let body = match path.as_str() {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" => {
                br#"{"code":1,"result":{"uid":7,"token":"tok"}}"#.to_vec()
            }
            "/api/Front/Clockin/Classify/getList" => {
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Item/getList" => {
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Clockin/getCount" | "/api/Front/Clockin/Term/get" => {
                br#"{"code":1,"result":{}}"#.to_vec()
            }
            "/api/Front/Upload/File/post" => {
                br#"{"code":1,"result":{"file_name":"uploaded.jpg"}}"#.to_vec()
            }
            "/api/Front/Clockin/Clockin/clockin" => {
                br#"{"code":1,"result":{"record_id":8}}"#.to_vec()
            }
            _ => return Err(test_error("unexpected ygdk path")),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

#[async_trait]
impl HttpTransport for YgdkCredentialRefreshTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = url::Url::parse(&request.url).map_err(|_| test_error("invalid test URL"))?;
        let path = url.path();
        let mut state = self.state.lock().unwrap();
        state.requests.push(request.clone());
        let body = match path {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" => {
                state.login_calls += 1;
                if state.login_calls == 1 {
                    br#"{"code":1,"result":{"uid":7,"token":"old-token"}}"#.to_vec()
                } else {
                    br#"{"code":1,"result":{"uid":8,"token":"new-token"}}"#.to_vec()
                }
            }
            "/api/Front/Clockin/Classify/getList" => {
                state.classify_calls += 1;
                if state.classify_calls == 1 {
                    br#"{"code":-98,"msg":"expired"}"#.to_vec()
                } else {
                    r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#
                        .as_bytes()
                        .to_vec()
                }
            }
            "/api/Front/Clockin/Item/getList" => {
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Clockin/getCount" | "/api/Front/Clockin/Term/get" => {
                br#"{"code":1,"result":{}}"#.to_vec()
            }
            "/api/Front/Clockin/Clockin/getList" => {
                br#"{"code":1,"result":{"total":0,"list":[]}}"#.to_vec()
            }
            _ => return Err(test_error("unexpected ygdk path")),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

#[async_trait]
impl HttpTransport for YgdkWriteTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = url::Url::parse(&request.url).map_err(|_| test_error("invalid test URL"))?;
        let path = url.path();
        self.requests.lock().unwrap().push(request.clone());
        let body = match path {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" =>
                br#"{"code":1,"result":{"uid":7,"token":"tok"}}"#.to_vec(),
            "/api/Front/Clockin/Classify/getList" =>
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"} ]}}"#.as_bytes().to_vec(),
            "/api/Front/Clockin/Item/getList" =>
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#.as_bytes().to_vec(),
            "/api/Front/Clockin/Clockin/getCount" =>
                br#"{"code":1,"result":{"term_good_count_show":1,"week_count":1,"month_count":1,"day_count":1}}"#.to_vec(),
            "/api/Front/Clockin/Term/get" =>
                r#"{"code":1,"result":{"term_id":9,"name":"2025秋"}}"#.as_bytes().to_vec(),
            "/api/Front/Upload/File/post" =>
                br#"{"code":1,"result":{"file_name":"uploaded.jpg"}}"#.to_vec(),
            "/api/Front/Clockin/Clockin/clockin" =>
                br#"{"code":1,"result":{"record_id":8}}"#.to_vec(),
            _ => return Err(test_error("unexpected ygdk path")),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
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
