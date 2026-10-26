use super::*;

#[test]
fn expected_route_mismatch_is_rejected_before_http() {
    let root = test_root("route-mismatch");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    save_both_routes(&store);
    let direct_calls = Arc::new(AtomicUsize::new(0));
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        CountingTransport(Arc::clone(&direct_calls)),
        CountingTransport(Arc::clone(&webvpn_calls)),
        store,
        RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error =
        runtime
            .block_on(client.evaluation_submit_courses_if_route_matches(
                request(&["one"]),
                ConnectionMode::Direct,
            ))
            .expect_err("路线变化必须在 authority 和 final 请求前拒绝");

    assert_eq!(error.error.code, ErrorCode::InvalidInput);
    assert_eq!(error.resolution.unwrap().mode, ConnectionMode::WebVpn);
    assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn empty_or_duplicate_targets_are_rejected_before_route_or_http() {
    for (label, request) in [
        (
            "empty-targets",
            EvaluationSubmitCoursesRequest {
                targets: Vec::new(),
            },
        ),
        (
            "duplicate-targets",
            EvaluationSubmitCoursesRequest {
                targets: vec![target("one"), target("one")],
            },
        ),
    ] {
        let root = test_root(label);
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).unwrap();
        save_both_routes(&store);
        let direct_calls = Arc::new(AtomicUsize::new(0));
        let webvpn_calls = Arc::new(AtomicUsize::new(0));
        let mut client = UbaaClient::with_routing(
            CountingTransport(Arc::clone(&direct_calls)),
            CountingTransport(Arc::clone(&webvpn_calls)),
            store,
            RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap(),
            NeverProbe,
        )
        .unwrap();

        let error = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(client.evaluation_submit_courses(request))
            .unwrap_err();

        assert_eq!(error.error.code, ErrorCode::InvalidInput);
        assert!(error.resolution.is_none());
        assert_eq!(direct_calls.load(Ordering::SeqCst), 0);
        assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
        let _ = std::fs::remove_dir_all(root);
    }
}
