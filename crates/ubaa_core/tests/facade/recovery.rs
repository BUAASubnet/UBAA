use super::*;

#[path = "recovery/identity.rs"]
mod identity;

#[test]
fn required_session_recovers_only_the_requested_feature_route() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = test_root("required-session");
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let other = Arc::new(AtomicUsize::new(0));
        let response = ubaa_core::facade::testing::sso_fixture_response(
            200,
            "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON",
            include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
        );
        let policy = if route == ConnectionMode::Direct {
            "direct"
        } else {
            "webvpn"
        };
        let config = RouteConfig::parse(&format!("[route]\ndefault = \"{policy}\"\n")).unwrap();
        let transport = RecoveryTransport {
            calls: calls.clone(),
            response,
        };
        let mut client = if route == ConnectionMode::Direct {
            UbaaClient::with_routing(
                transport,
                CountingTransport(other.clone()),
                store,
                config,
                NeverProbe,
            )
        } else {
            UbaaClient::with_routing(
                CountingTransport(other.clone()),
                transport,
                store,
                config,
                NeverProbe,
            )
        }
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let recovered = runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Signin))
            .unwrap();
        assert_eq!(recovered.resolution.mode, route);
        assert_eq!(
            recovered.data.user.username.as_deref(),
            Some("fixture-user")
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(other.load(Ordering::SeqCst), 0);
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn 首页批次同路线只校验一次且结束后重新校验() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = test_root("required-session");
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let other = Arc::new(AtomicUsize::new(0));
        let response = ubaa_core::facade::testing::sso_fixture_response(
            200,
            "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON",
            include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
        );
        let policy = if route == ConnectionMode::Direct {
            "direct"
        } else {
            "webvpn"
        };
        let config = RouteConfig::parse(&format!("[route]\ndefault = \"{policy}\"\n")).unwrap();
        let transport = RecoveryTransport {
            calls: calls.clone(),
            response,
        };
        let mut client = if route == ConnectionMode::Direct {
            UbaaClient::with_routing(
                transport,
                CountingTransport(other.clone()),
                store,
                config,
                NeverProbe,
            )
        } else {
            UbaaClient::with_routing(
                CountingTransport(other.clone()),
                transport,
                store,
                config,
                NeverProbe,
            )
        }
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let batch = client.begin_read_recovery_batch();
        let recovered = runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Signin))
            .unwrap();
        assert_eq!(recovered.resolution.mode, route);
        assert_eq!(
            recovered.data.user.username.as_deref(),
            Some("fixture-user")
        );
        runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Spoc))
            .unwrap();
        runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Judge))
            .unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        client.end_read_recovery_batch(batch);
        runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Signin))
            .unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        let previous = client.begin_read_recovery_batch();
        let current = client.begin_read_recovery_batch();
        runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Signin))
            .unwrap();
        client.end_read_recovery_batch(previous);
        runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Spoc))
            .unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 3);
        client.invalidate_read_recovery_batch();
        runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Judge))
            .unwrap();
        assert_eq!(calls.load(Ordering::SeqCst), 4);
        client.end_read_recovery_batch(current);
        assert_eq!(other.load(Ordering::SeqCst), 0);
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn required_session_without_saved_material_never_contacts_upstream() {
    let root = test_root("required-session-missing");
    let calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(calls.clone()),
        CountingTransport(calls.clone()),
        FileSessionStore::new(&root).unwrap(),
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let error = runtime
        .block_on(client.recover_required_session(ReadonlyFeature::Signin))
        .unwrap_err();
    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(error.resolution.unwrap().mode, ConnectionMode::Direct);
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct RecoveryTransport {
    calls: Arc<AtomicUsize>,
    response: HttpResponse,
}

#[async_trait]
impl HttpTransport for RecoveryTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if let Some(response) = ubaa_core::facade::testing::sso_fixture_ticket(&request) {
            return Ok(response);
        }
        assert!(request.url.contains("/serviceValidate?"));
        self.calls.fetch_add(1, Ordering::SeqCst);
        let mut response = self.response.clone();
        response.final_url = request.url;
        Ok(response)
    }
}

#[test]
fn required_session_distinguishes_expiration_from_temporary_failure() {
    for (status, code, retained) in [
        (503, ErrorCode::UpstreamUnavailable, true),
        (401, ErrorCode::AuthenticationRequired, false),
    ] {
        let root = test_root("required-session-failure");
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let mut client = UbaaClient::with_routing(
            TaggedTransport {
                calls: Arc::new(AtomicUsize::new(0)),
                status,
            },
            CountingTransport(Arc::new(AtomicUsize::new(0))),
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
            NeverProbe,
        )
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let error = runtime
            .block_on(client.recover_required_session(ReadonlyFeature::Signin))
            .unwrap_err();
        assert_eq!(error.error.code, code);
        assert_eq!(error.error.retryable, retained);
        assert_eq!(error.resolution.unwrap().mode, ConnectionMode::Direct);
        assert_eq!(
            client.active_routes().contains(&ConnectionMode::Direct),
            retained
        );
        assert!(client.active_routes().contains(&ConnectionMode::WebVpn));
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn required_session_auto_preserves_core_feature_route_without_guessing() {
    let root = test_root("required-session-auto");
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let probe_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        RecoveryTransport { calls: Arc::default(), response: ubaa_core::facade::testing::sso_fixture_response(
            200,
            "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON",
            include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
        ) },
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::default(),
        CountingProbe(probe_calls.clone()),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let recovered = runtime
        .block_on(client.recover_required_session(ReadonlyFeature::Signin))
        .unwrap();
    assert_eq!(recovered.resolution.policy, RoutePolicy::Auto);
    assert_eq!(recovered.resolution.mode, ConnectionMode::Direct);
    assert!(!recovered.resolution.diagnostic.used_fallback);
    assert_eq!(probe_calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn required_route_login_failure_never_contacts_the_sibling_route() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = test_root("required-route-login");
        let requested = Arc::new(AtomicUsize::new(0));
        let sibling = Arc::new(AtomicUsize::new(0));
        let failing = TaggedTransport {
            calls: requested.clone(),
            status: 503,
        };
        let untouched = CountingTransport(sibling.clone());
        let store = FileSessionStore::new(&root).unwrap();
        let mut client = if route == ConnectionMode::Direct {
            UbaaClient::with_routing(
                failing,
                untouched,
                store,
                RouteConfig::default(),
                NeverProbe,
            )
        } else {
            UbaaClient::with_routing(
                untouched,
                failing,
                store,
                RouteConfig::default(),
                NeverProbe,
            )
        }
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let error = runtime
            .block_on(client.login_required_route(
                route,
                ubaa_core::facade::LoginInput {
                    username: "fixture-user".into(),
                    password: ubaa_core::facade::SecretValue::new("synthetic"),
                },
            ))
            .unwrap_err();
        assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
        assert!(requested.load(Ordering::SeqCst) > 0);
        assert_eq!(sibling.load(Ordering::SeqCst), 0);
        let _ = std::fs::remove_dir_all(root);
    }
}

#[derive(Clone)]
struct ExistingSsoTransport(Arc<std::sync::Mutex<Vec<HttpRequest>>>);
#[async_trait]
impl HttpTransport for ExistingSsoTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if let Some(response) = ubaa_core::facade::testing::sso_fixture_ticket(&request) {
            return Ok(response);
        }
        self.0.lock().unwrap().push(request.clone());
        assert_eq!(request.method, ubaa_core::facade::testing::HttpMethod::Get);
        let response = match request.url.as_str() {
            "https://sso.buaa.edu.cn/login" => {
                ubaa_core::facade::testing::sso_fixture_response(302, request.url, Vec::new())
            }
            "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin" => {
                ubaa_core::facade::testing::sso_fixture_response(
                    200,
                    request.url,
                    b"ready".to_vec(),
                )
            }
            "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON"
            | "https://uc.buaa.edu.cn/api/uc/userinfo" => {
                ubaa_core::facade::testing::sso_fixture_response(
                    200,
                    request.url,
                    include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
                )
            }
            _ => panic!("不应增加认证请求"),
        };
        Ok(response)
    }
}
#[test]
fn required_route_login_reuses_valid_sso_and_returns_the_pinned_profile() {
    let root = test_root("required-route-existing-sso");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let sibling = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        ExistingSsoTransport(requests.clone()),
        CountingTransport(sibling.clone()),
        FileSessionStore::new(&root).unwrap(),
        RouteConfig::default(),
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.login_required_route(
            ConnectionMode::Direct,
            ubaa_core::facade::LoginInput {
                username: "fixture-user".into(),
                password: ubaa_core::facade::SecretValue::new("synthetic"),
            },
        ))
        .unwrap();
    assert_eq!(result.pinned_route, ConnectionMode::Direct);
    assert_eq!(result.data.username.as_deref(), Some("fixture-user"));
    assert_eq!(sibling.load(Ordering::SeqCst), 0);
    assert_eq!(requests.lock().unwrap().len(), 2);
    assert_eq!(client.active_routes(), vec![ConnectionMode::Direct]);
    let _ = std::fs::remove_dir_all(root);
}
