use super::*;

#[test]
fn fresh_项目响应期间凭据代次变化时不得上传或最终提交() {
    let root =
        std::env::temp_dir().join(format!("ubaa-ygdk-generation-race-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    save_session(
        &store,
        &SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        },
    )
    .unwrap();
    let state = Arc::new(Mutex::new(None));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        GenerationMutationTransport {
            state: Arc::clone(&state),
            requests: Arc::clone(&requests),
            mutated: Arc::new(AtomicBool::new(false)),
            login_calls: Arc::new(AtomicUsize::new(0)),
        },
        store,
    )
    .unwrap();
    *state.lock().unwrap() = Some(runtime.feature_state());
    runtime.begin_non_idempotent_operation();

    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(submit_clockin(&mut runtime, valid_submit_request()));

    let error = result.expect_err("旧 authority 与新 credential 不得拼接提交");
    assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
    let requests = requests.lock().unwrap();
    assert_eq!(
        requests
            .iter()
            .filter(|request| request_path(request) == "/api/Front/Upload/File/post")
            .count(),
        0
    );
    assert_eq!(
        requests
            .iter()
            .filter(|request| request_path(request) == "/api/Front/Clockin/Clockin/clockin")
            .count(),
        0
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 记录读取在项目响应期间代次变化后重新完整读取权威() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-records-generation-race-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    save_session(
        &store,
        &SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        },
    )
    .unwrap();
    let state = Arc::new(Mutex::new(None));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        GenerationMutationTransport {
            state: Arc::clone(&state),
            requests: Arc::clone(&requests),
            mutated: Arc::new(AtomicBool::new(false)),
            login_calls: Arc::new(AtomicUsize::new(0)),
        },
        store,
    )
    .unwrap();
    *state.lock().unwrap() = Some(runtime.feature_state());

    let page = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(get_records(&mut runtime, 1, 20))
        .expect("只读链可从新代次完整重取后继续");

    assert!(page.content.is_empty());
    let requests = requests.lock().unwrap();
    assert_eq!(
        requests
            .iter()
            .filter(|request| request_path(request) == "/api/Front/Clockin/Classify/getList")
            .count(),
        2
    );
    assert_eq!(
        requests
            .iter()
            .filter(|request| request_path(request) == "/api/Front/Clockin/Item/getList")
            .count(),
        2
    );
    let records = requests
        .iter()
        .filter(|request| request_path(request) == "/api/Front/Clockin/Clockin/getList")
        .collect::<Vec<_>>();
    assert_eq!(records.len(), 1);
    let form = url::form_urlencoded::parse(&records[0].body)
        .into_owned()
        .collect::<std::collections::BTreeMap<_, _>>();
    assert_eq!(form.get("uid").map(String::as_str), Some("8"));
    assert_eq!(form.get("token").map(String::as_str), Some("new-token"));
    assert_eq!(form.get("user_id").map(String::as_str), Some("8"));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn oauth_响应期间业务代次变化时不得发送业务登录请求() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-oauth-generation-guard-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    save_session(&store, &authenticated_session()).unwrap();
    let state = Arc::new(Mutex::new(None));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        OauthGuardMutationTransport {
            mutation: OauthGuardMutation::Generation(Arc::clone(&state)),
            requests: Arc::clone(&requests),
            mutated: Arc::new(AtomicBool::new(false)),
        },
        store,
    )
    .unwrap();
    *state.lock().unwrap() = Some(runtime.feature_state());

    let error = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(ensure_login(&mut runtime))
        .expect_err("OAuth 返回后已失效代次不得继续发送登录请求");

    assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
    assert!(!error.retryable);
    assert_login_guard_requests(&requests, 1, 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn oauth_响应期间会话修订变化时不得发送业务登录请求() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-oauth-session-guard-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let session = authenticated_session();
    save_session(&store, &session).unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        OauthGuardMutationTransport {
            mutation: OauthGuardMutation::Session {
                store: store.clone(),
                replacement: session,
            },
            requests: Arc::clone(&requests),
            mutated: Arc::new(AtomicBool::new(false)),
        },
        store,
    )
    .unwrap();

    let error = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(ensure_login(&mut runtime))
        .expect_err("OAuth 返回后外部会话已变化不得继续发送登录请求");

    assert_eq!(error.code, crate::error::ErrorCode::InternalError);
    assert!(error.retryable);
    assert_eq!(error.message, "阳光打卡本地会话状态检查失败");
    assert_login_guard_requests(&requests, 1, 0);
    let _ = std::fs::remove_dir_all(root);
}

fn authenticated_session() -> SessionSnapshot {
    SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: Vec::new(),
        authenticated_at: 1_000,
        last_activity: 1_001,
    }
}

fn assert_login_guard_requests(
    requests: &Arc<Mutex<Vec<HttpRequest>>>,
    oauth_count: usize,
    login_count: usize,
) {
    let requests = requests.lock().unwrap();
    assert_eq!(
        requests
            .iter()
            .filter(|request| request_path(request) == "/uc/api/oauth/index")
            .count(),
        oauth_count
    );
    assert_eq!(
        requests
            .iter()
            .filter(|request| { request_path(request) == "/api/Front/Clockin/User/campusAppLogin" })
            .count(),
        login_count
    );
}

#[test]
fn 上传元数据拒绝_multipart_头注入与非图片_mime() {
    let credential = YgdkCredential {
        uid: 7,
        token: "tok".into(),
    };
    for (file_name, mime_type) in [
        ("bad\r\nX-Evil: yes.jpg", "image/jpeg"),
        ("bad\".jpg", "image/jpeg"),
        ("../bad.jpg", "image/jpeg"),
        ("bad.jpg", "image/jpeg\r\nX-Evil: yes"),
        ("bad.jpg", "application/octet-stream"),
    ] {
        let photo = YgdkPhotoUpload {
            bytes: vec![1],
            file_name: file_name.into(),
            mime_type: mime_type.into(),
        };
        let error = build_upload_body(&credential, &photo, "b")
            .expect_err("危险 multipart 元数据必须失败关闭");
        assert_eq!(error.code, crate::error::ErrorCode::InvalidInput);
    }
}

#[test]
fn 上传回执文件名只接受实际非空_json_字符串() {
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let credential = YgdkCredential {
        uid: 7,
        token: "tok".into(),
    };
    let photo = valid_submit_request().photo;

    for (case, body, expected) in [
        (
            "string",
            r#"{"code":1,"result":{"file_name":"uploaded.jpg"}}"#,
            Some("uploaded.jpg"),
        ),
        ("number", r#"{"code":1,"result":{"file_name":123}}"#, None),
        ("boolean", r#"{"code":1,"result":{"file_name":true}}"#, None),
        ("blank", r#"{"code":1,"result":{"file_name":"   "}}"#, None),
    ] {
        let calls = Arc::new(AtomicUsize::new(0));
        let root = std::env::temp_dir().join(format!(
            "ubaa-ygdk-upload-receipt-{case}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let mut runtime = ClientRuntime::new(
            ConnectionMode::Direct,
            StaticResponseTransport {
                body,
                calls: Arc::clone(&calls),
            },
            FileSessionStore::new(&root).unwrap(),
        )
        .unwrap();
        runtime.feature_state().ygdk.set(credential.clone());
        let generation = runtime.feature_state().ygdk.generation();

        let result = executor.block_on(upload_photo(&mut runtime, &credential, generation, &photo));
        if let Some(expected) = expected {
            assert_eq!(result.as_deref(), Ok(expected), "{case}");
        } else {
            let error = result.expect_err("非字符串上传文件名必须拒绝");
            assert_eq!(error.code, crate::error::ErrorCode::UpstreamUnavailable);
            assert_eq!(error.message, "阳光打卡照片上传未完成");
            assert!(!error.retryable);
        }
        assert_eq!(calls.load(Ordering::SeqCst), 1, "{case}");
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn 最终发送后的传输失败归一为阳光打卡固定未知文案() {
    let calls = Arc::new(AtomicUsize::new(0));
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-final-outcome-unknown-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        FailingResponseTransport {
            calls: Arc::clone(&calls),
        },
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    runtime.begin_non_idempotent_operation();
    let credential = YgdkCredential {
        uid: 7,
        token: "tok".into(),
    };
    runtime.feature_state().ygdk.set(credential.clone());
    let generation = runtime.feature_state().ygdk.generation();

    let error = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(post_non_idempotent(
            &mut runtime,
            "/api/Front/Clockin/Clockin/clockin",
            &credential,
            generation,
            &[],
        ))
        .expect_err("最终传输失败必须保持未知结果");

    assert_eq!(error.code, crate::error::ErrorCode::OutcomeUnknown);
    assert_eq!(error.kind, crate::error::ErrorKind::Upstream);
    assert!(!error.retryable);
    assert_eq!(
        error.message,
        "阳光打卡提交结果未知，请刷新概览和记录后核对"
    );
    assert!(!error.message.contains("secret"));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 带业务凭据的每类请求在发送入口发现代次失效时零传输() {
    let calls = Arc::new(AtomicUsize::new(0));
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-pre-send-generation-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        FailingResponseTransport {
            calls: Arc::clone(&calls),
        },
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let credential = YgdkCredential {
        uid: 7,
        token: "tok".into(),
    };
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    for (case, path, with_query) in [
        ("classify", "/api/Front/Clockin/Classify/getList", false),
        ("item", "/api/Front/Clockin/Item/getList", true),
        ("count", "/api/Front/Clockin/Clockin/getCount", false),
        ("term", "/api/Front/Clockin/Term/get", false),
        ("records", "/api/Front/Clockin/Clockin/getList", true),
    ] {
        runtime.feature_state().ygdk.set(credential.clone());
        let generation = runtime.feature_state().ygdk.generation();
        runtime.feature_state().ygdk.clear();
        let result = if with_query {
            executor.block_on(post_with_query(
                &mut runtime,
                path,
                &credential,
                generation,
                &[],
            ))
        } else {
            executor.block_on(post(&mut runtime, path, &credential, generation, &[]))
        };
        let error = result.expect_err("失效代次不得交给 transport");
        assert_eq!(
            error.code,
            crate::error::ErrorCode::AuthenticationRequired,
            "{case}"
        );
        assert!(!error.retryable, "{case}");
        assert_eq!(calls.load(Ordering::SeqCst), 0, "{case}");
    }

    runtime.feature_state().ygdk.set(credential.clone());
    let upload_generation = runtime.feature_state().ygdk.generation();
    runtime.feature_state().ygdk.clear();
    let upload_error = executor
        .block_on(upload_photo(
            &mut runtime,
            &credential,
            upload_generation,
            &valid_submit_request().photo,
        ))
        .expect_err("上传入口必须检查业务代次");
    assert_eq!(
        upload_error.code,
        crate::error::ErrorCode::AuthenticationRequired
    );
    assert_eq!(calls.load(Ordering::SeqCst), 0);

    runtime.feature_state().ygdk.set(credential.clone());
    let final_generation = runtime.feature_state().ygdk.generation();
    runtime.feature_state().ygdk.clear();
    runtime.begin_non_idempotent_operation();
    let final_error = executor
        .block_on(post_non_idempotent(
            &mut runtime,
            "/api/Front/Clockin/Clockin/clockin",
            &credential,
            final_generation,
            &[],
        ))
        .expect_err("final 入口必须检查业务代次");
    assert_eq!(
        final_error.code,
        crate::error::ErrorCode::AuthenticationRequired
    );
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert!(!runtime.take_non_idempotent_boundary_crossed());
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 无效打卡输入在任何网络请求前被拒绝() {
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        NoNetworkTransport,
        FileSessionStore::new(
            std::env::temp_dir().join(format!("ubaa-ygdk-input-{}", std::process::id())),
        )
        .unwrap(),
    )
    .unwrap();
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(submit_clockin(
            &mut runtime,
            YgdkClockinSubmitRequest {
                start_time: "2026-04-01 09:00".into(),
                end_time: "2026-04-01 08:00".into(),
                ..valid_submit_request()
            },
        ))
        .unwrap_err();
    assert_eq!(result.code, crate::error::ErrorCode::InvalidInput);
    assert_eq!(result.message, "结束时间必须晚于开始时间");
}

struct NoNetworkTransport;

#[derive(Clone)]
struct StaticResponseTransport {
    body: &'static str,
    calls: Arc<AtomicUsize>,
}

#[async_trait]
impl HttpTransport for StaticResponseTransport {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(HttpResponse::new(
            200,
            request.url,
            self.body.as_bytes().to_vec(),
        ))
    }
}

#[derive(Clone)]
struct FailingResponseTransport {
    calls: Arc<AtomicUsize>,
}

#[derive(Clone)]
struct GenerationMutationTransport {
    state: Arc<Mutex<Option<Arc<crate::internal::route_state::RouteFeatureState>>>>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    mutated: Arc<AtomicBool>,
    login_calls: Arc<AtomicUsize>,
}

#[derive(Clone)]
enum OauthGuardMutation {
    Generation(Arc<Mutex<Option<Arc<crate::internal::route_state::RouteFeatureState>>>>),
    Session {
        store: FileSessionStore,
        replacement: SessionSnapshot,
    },
}

#[derive(Clone)]
struct OauthGuardMutationTransport {
    mutation: OauthGuardMutation,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    mutated: Arc<AtomicBool>,
}

#[async_trait]
impl HttpTransport for OauthGuardMutationTransport {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        let path = request_path(&request);
        self.requests.lock().unwrap().push(request.clone());
        if path == "/uc/api/oauth/index" && !self.mutated.swap(true, Ordering::SeqCst) {
            match &self.mutation {
                OauthGuardMutation::Generation(state) => state
                    .lock()
                    .unwrap()
                    .as_ref()
                    .expect("设置路线业务状态")
                    .ygdk
                    .clear(),
                OauthGuardMutation::Session { store, replacement } => {
                    save_session(store, replacement)?;
                }
            }
        }
        let (final_url, body) = match path.as_str() {
            "/uc/api/oauth/index" => (
                "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into(),
                Vec::new(),
            ),
            "/api/Front/Clockin/User/campusAppLogin" => (
                request.url,
                br#"{"code":1,"result":{"uid":7,"token":"safe-token"}}"#.to_vec(),
            ),
            _ => panic!("未预期的阳光打卡 OAuth guard 测试请求: {path}"),
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

#[async_trait]
impl HttpTransport for GenerationMutationTransport {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        let url = url::Url::parse(&request.url).expect("测试请求 URL");
        let path = url.path().to_owned();
        self.requests.lock().unwrap().push(request.clone());
        let body = match path.as_str() {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" => {
                let call = self.login_calls.fetch_add(1, Ordering::SeqCst);
                if call == 0 {
                    br#"{"code":1,"result":{"uid":7,"token":"old-token"}}"#.to_vec()
                } else {
                    br#"{"code":1,"result":{"uid":8,"token":"new-token"}}"#.to_vec()
                }
            }
            "/api/Front/Clockin/Classify/getList" => {
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Item/getList" => {
                if !self.mutated.swap(true, Ordering::SeqCst) {
                    self.state
                        .lock()
                        .unwrap()
                        .as_ref()
                        .expect("设置路线业务状态")
                        .ygdk
                        .clear();
                }
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
            "/api/Front/Clockin/Clockin/getList" => {
                br#"{"code":1,"result":{"total":0,"list":[]}}"#.to_vec()
            }
            _ => panic!("未预期的阳光打卡 generation 测试请求: {path}"),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

fn request_path(request: &HttpRequest) -> String {
    url::Url::parse(&request.url)
        .expect("测试请求 URL")
        .path()
        .to_owned()
}

#[async_trait]
impl HttpTransport for FailingResponseTransport {
    async fn execute(&self, _request: HttpRequest) -> crate::error::Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::NetworkError,
            crate::error::ErrorKind::Network,
            true,
            "secret upstream transport detail\nprivate",
        ))
    }
}

#[async_trait]
impl HttpTransport for NoNetworkTransport {
    async fn execute(&self, _request: HttpRequest) -> crate::error::Result<HttpResponse> {
        panic!("无效输入不应触发网络请求");
    }
}
