use super::*;

#[test]
fn cgyy_webvpn_uses_webvpn_business_transport_after_route_resolution() {
    let root = test_root("cgyy-direct-business");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 401,
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 401,
        },
        store,
        config,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime.block_on(client.cgyy_sites()).unwrap_err();

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_webvpn_writes_use_webvpn_business_transport() {
    let root = test_root("cgyy-direct-write-business");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let config = RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap();
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 401,
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 401,
        },
        store,
        config,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime
        .block_on(
            client.cgyy_cancel_order(ubaa_core::facade::CgyyCancelOrderRequest { order_id: 77 }),
        )
        .unwrap_err();

    assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 1);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_cancel_expected_route_mismatch_is_rejected_before_http() {
    let root = test_root("cgyy-cancel-expected-route-mismatch");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(direct_calls.clone()),
        CountingTransport(webvpn_calls.clone()),
        store,
        RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime
        .block_on(client.cgyy_cancel_order_if_route_matches(
            ubaa_core::facade::CgyyCancelOrderRequest { order_id: 77 },
            ConnectionMode::Direct,
        ))
        .expect_err("实际 WebVPN 与 intent Direct 不一致时必须在发送前拒绝");

    assert_eq!(error.error.code, ErrorCode::InvalidInput);
    assert_eq!(
        error
            .resolution
            .expect("不匹配错误必须携带实际解析结果")
            .mode,
        ConnectionMode::WebVpn
    );
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_cancel_invalid_id_is_rejected_before_auto_probe_or_http() {
    let root = test_root("cgyy-cancel-invalid-id-before-route");
    let _ = std::fs::remove_dir_all(&root);
    let probe_calls = Arc::new(AtomicUsize::new(0));
    let http_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(http_calls.clone()),
        CountingTransport(http_calls.clone()),
        FileSessionStore::new(&root).unwrap(),
        RouteConfig::default(),
        CountingProbe(probe_calls.clone()),
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let invalid = ubaa_core::facade::CgyyCancelOrderRequest { order_id: 0 };

    let preflight = runtime
        .block_on(client.preflight_cgyy_cancel(&invalid))
        .expect_err("非法订单编号必须在预检路线解析前拒绝");
    let regular = runtime
        .block_on(client.cgyy_cancel_order(invalid))
        .expect_err("非法订单编号必须在普通写路线解析前拒绝");
    let atomic = runtime
        .block_on(client.cgyy_cancel_order_if_route_matches(invalid, ConnectionMode::Direct))
        .expect_err("非法订单编号必须在原子写路线解析前拒绝");

    for error in [preflight, regular, atomic] {
        assert_eq!(error.error.code, ErrorCode::InvalidInput);
        assert!(error.resolution.is_none());
    }
    assert_eq!(probe_calls.load(Ordering::SeqCst), 0);
    assert_eq!(http_calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn cgyy_caller_pinned_readback_ignores_current_auto_route_without_fallback() {
    let root = test_root("cgyy-caller-pinned-readback");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let probe_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        TaggedTransport {
            calls: direct_calls.clone(),
            status: 500,
        },
        TaggedTransport {
            calls: webvpn_calls.clone(),
            status: 500,
        },
        store,
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").unwrap(),
        CountingProbe(probe_calls.clone()),
    )
    .unwrap();
    let current = client
        .resolve_route_for_feature(ReadonlyFeature::Cgyy)
        .expect("Auto 路线应可解析");
    assert_eq!(current.mode, ConnectionMode::WebVpn);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let orders = runtime
        .block_on(client.cgyy_orders_on_route(ConnectionMode::Direct, 0, 20))
        .expect_err("脱敏 Direct transport 返回 500");
    let detail = runtime
        .block_on(client.cgyy_order_detail_on_route(ConnectionMode::Direct, 77))
        .expect_err("脱敏 Direct transport 返回 500");

    assert_eq!(orders.code, ErrorCode::UpstreamUnavailable);
    assert_eq!(detail.code, ErrorCode::UpstreamUnavailable);
    assert_eq!(probe_calls.load(Ordering::SeqCst), 1);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 2);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct LockDisplayTransport {
    requests: Arc<std::sync::Mutex<Vec<HttpRequest>>>,
    cancel: Arc<std::sync::Mutex<Option<ubaa_core::facade::CgyyLockDisplayLease>>>,
}
#[async_trait]
impl HttpTransport for LockDisplayTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if request.url.contains("/api/orders/lock/code") {
            self.requests.lock().unwrap().push(request.clone());
            assert_eq!(request.method, ubaa_core::facade::testing::HttpMethod::Get);
            let url = url::Url::parse(&request.url).unwrap();
            assert_eq!(
                url.query_pairs()
                    .map(|(k, _)| k.to_string())
                    .collect::<Vec<_>>(),
                vec!["nocache"]
            );
            assert!(request.body.is_empty());
            assert!(request.headers.contains_key("cgAuthorization"));
            if let Some(lease) = self.cancel.lock().unwrap().take() {
                lease.cancel();
            }
            return Ok(HttpResponse::new(200,request.url,br#"{"code":200,"data":{"qrCode":"001234","orderView":{"tradeNo":"synthetic-reference"}}}"#.to_vec()));
        }
        CgyyWebVpnTransport {
            requests: self.requests.clone(),
        }
        .execute(request)
        .await
    }
}
#[test]
fn 门锁页面固定webvpn并拒绝取消路线变更异实例和迟到结果() {
    let root = test_root("lock-display");
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save_dual(&DualSessionSnapshot::new(
            None,
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
    let direct = Arc::new(AtomicUsize::new(0));
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let cancel = Arc::new(std::sync::Mutex::new(None));
    RouteConfig::parse("[route]\ndefault = \"webvpn\"\n")
        .unwrap()
        .save(&root)
        .unwrap();
    let mut client = ubaa_core::facade::testing::with_routing_in_config_directory(
        CountingTransport(direct.clone()),
        LockDisplayTransport {
            requests: requests.clone(),
            cancel: cancel.clone(),
        },
        &root,
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let lease = client.open_cgyy_lock_display().unwrap();
    let value = runtime
        .block_on(client.read_cgyy_lock_display(&lease))
        .unwrap();
    assert_eq!(value.code.as_deref(), Some("001234"));
    assert_eq!(
        value.reservation_reference.as_deref(),
        Some("synthetic-reference")
    );
    assert_eq!(direct.load(Ordering::SeqCst), 0);
    assert!(
        requests
            .lock()
            .unwrap()
            .iter()
            .all(|r| url::Url::parse(&r.url).unwrap().host_str() == Some("d.buaa.edu.cn"))
    );
    lease.cancel();
    let count = requests.lock().unwrap().len();
    assert!(
        runtime
            .block_on(client.read_cgyy_lock_display(&lease))
            .is_err()
    );
    assert_eq!(requests.lock().unwrap().len(), count);
    let changed = client.open_cgyy_lock_display().unwrap();
    client
        .set_default_route_policy(RoutePolicy::Direct)
        .unwrap();
    assert!(
        runtime
            .block_on(client.read_cgyy_lock_display(&changed))
            .is_err()
    );
    assert_eq!(requests.lock().unwrap().len(), count);
    client
        .set_default_route_policy(RoutePolicy::WebVpn)
        .unwrap();
    let late = client.open_cgyy_lock_display().unwrap();
    *cancel.lock().unwrap() = Some(late.clone());
    assert!(
        runtime
            .block_on(client.read_cgyy_lock_display(&late))
            .is_err()
    );
    assert!(!late.is_active());
    let other_root = test_root("lock-display-other");
    let mut other = UbaaClient::open(&other_root).unwrap();
    assert!(
        runtime
            .block_on(other.read_cgyy_lock_display(&changed))
            .is_err()
    );
    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(other_root);
}
