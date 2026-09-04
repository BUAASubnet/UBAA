use super::*;

#[test]
fn ygdk_submit_expected_route_mismatch_is_rejected_before_http() {
    let root = test_root("ygdk-submit-expected-route-mismatch");
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
        .block_on(
            client
                .ygdk_submit_if_route_matches(valid_ygdk_submit_request(), ConnectionMode::Direct),
        )
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
fn ygdk_invalid_input_is_rejected_before_auto_probe_or_http() {
    let root = test_root("ygdk-invalid-input-before-route");
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
    let mut invalid = valid_ygdk_submit_request();
    invalid.photo.file_name = "../private.jpg".into();

    let preflight = runtime
        .block_on(client.preflight_ygdk_submit(&invalid))
        .expect_err("危险照片名称必须在预检路线解析前拒绝");
    let regular = runtime
        .block_on(client.ygdk_submit(invalid.clone()))
        .expect_err("危险照片名称必须在普通写路线解析前拒绝");
    let atomic = runtime
        .block_on(client.ygdk_submit_if_route_matches(invalid, ConnectionMode::Direct))
        .expect_err("危险照片名称必须在原子写路线解析前拒绝");

    for error in [preflight, regular, atomic] {
        assert_eq!(error.error.code, ErrorCode::InvalidInput);
        assert!(error.resolution.is_none());
    }
    assert_eq!(probe_calls.load(Ordering::SeqCst), 0);
    assert_eq!(http_calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ygdk_caller_pinned_readback_ignores_current_auto_route_without_fallback() {
    let root = test_root("ygdk-caller-pinned-readback");
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
        .resolve_route_for_feature(ReadonlyFeature::Ygdk)
        .expect("Auto 路线应可解析");
    assert_eq!(current.mode, ConnectionMode::WebVpn);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let overview = runtime
        .block_on(client.ygdk_overview_on_route(ConnectionMode::Direct))
        .expect_err("脱敏 Direct transport 返回无效 OAuth 响应");
    let records = runtime
        .block_on(client.ygdk_records_on_route(ConnectionMode::Direct, 1, 20))
        .expect_err("脱敏 Direct transport 返回无效 OAuth 响应");

    assert_eq!(overview.code, ErrorCode::UpstreamChanged);
    assert_eq!(records.code, ErrorCode::UpstreamChanged);
    assert_eq!(probe_calls.load(Ordering::SeqCst), 1);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 2);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}
