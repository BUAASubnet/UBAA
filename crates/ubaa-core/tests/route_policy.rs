use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use ubaa_core::config::{FeatureRouteConfig, RouteConfig};
use ubaa_core::connection::{
    CachingGatewayProbe, GatewayProbe, NetworkState, RouteDiagnostic, resolve_feature_route,
};
use ubaa_core::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use ubaa_core::facade::UbaaClient;

#[derive(Clone)]
struct ProbeResult(NetworkState);

impl GatewayProbe for ProbeResult {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.0
    }
}

#[test]
fn auto_route_maps_three_gateway_states_and_exposes_diagnostic() {
    let config = RouteConfig::default();
    let campus = resolve_feature_route(
        ReadonlyFeature::Schedule,
        RoutePolicy::Auto,
        &config,
        &ProbeResult(NetworkState::Campus),
    )
    .expect("campus route");
    assert_eq!(campus.mode, ConnectionMode::Direct);
    assert_eq!(
        campus.diagnostic,
        RouteDiagnostic::new(NetworkState::Campus, ConnectionMode::Direct)
    );

    let off_campus = resolve_feature_route(
        ReadonlyFeature::Schedule,
        RoutePolicy::Auto,
        &config,
        &ProbeResult(NetworkState::OffCampus),
    )
    .expect("off-campus route");
    assert_eq!(off_campus.mode, ConnectionMode::WebVpn);

    let unknown = resolve_feature_route(
        ReadonlyFeature::Schedule,
        RoutePolicy::Auto,
        &config,
        &ProbeResult(NetworkState::Unknown),
    )
    .expect("unknown route");
    assert_eq!(unknown.mode, ConnectionMode::Direct);
    assert_eq!(unknown.diagnostic.network, NetworkState::Unknown);
}

#[test]
fn requested_策略覆盖功能配置且_auto_只采用功能策略() {
    struct CountingStateProbe {
        calls: Arc<AtomicUsize>,
        state: NetworkState,
    }

    impl GatewayProbe for CountingStateProbe {
        fn probe(&self, _budget: Duration) -> NetworkState {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.state
        }
    }

    for configured in [RoutePolicy::Direct, RoutePolicy::WebVpn, RoutePolicy::Auto] {
        for requested in [RoutePolicy::Direct, RoutePolicy::WebVpn, RoutePolicy::Auto] {
            let configured_value = match configured {
                RoutePolicy::Direct => "direct",
                RoutePolicy::WebVpn => "webvpn",
                RoutePolicy::Auto => "auto",
            };
            let config = RouteConfig::parse(&format!(
                "[route]\ndefault = \"webvpn\"\n[route.features]\nschedule = \"{configured_value}\"\n"
            ))
            .expect("解析冲突路线配置");
            let calls = Arc::new(AtomicUsize::new(0));
            let resolved = resolve_feature_route(
                ReadonlyFeature::Schedule,
                requested,
                &config,
                &CountingStateProbe {
                    calls: calls.clone(),
                    state: NetworkState::OffCampus,
                },
            )
            .expect("解析 requested 与功能策略");

            let effective = if requested == RoutePolicy::Auto {
                configured
            } else {
                requested
            };
            let (mode, network, expected_calls) = match effective {
                RoutePolicy::Direct => (ConnectionMode::Direct, NetworkState::Unknown, 0),
                RoutePolicy::WebVpn => (ConnectionMode::WebVpn, NetworkState::Unknown, 0),
                RoutePolicy::Auto => (ConnectionMode::WebVpn, NetworkState::OffCampus, 1),
            };
            assert_eq!(resolved.policy, effective);
            assert_eq!(resolved.mode, mode);
            assert_eq!(resolved.diagnostic, RouteDiagnostic::new(network, mode));
            assert_eq!(calls.load(Ordering::SeqCst), expected_calls);
        }
    }
}

#[test]
fn auto_route_gives_the_gateway_probe_one_500ms_total_budget() {
    struct BudgetProbe(Arc<std::sync::Mutex<Option<Duration>>>);

    impl GatewayProbe for BudgetProbe {
        fn probe(&self, budget: Duration) -> NetworkState {
            *self.0.lock().expect("budget observation") = Some(budget);
            NetworkState::OffCampus
        }
    }

    let observed = Arc::new(std::sync::Mutex::new(None));
    resolve_feature_route(
        ReadonlyFeature::Schedule,
        RoutePolicy::Auto,
        &RouteConfig::default(),
        &BudgetProbe(observed.clone()),
    )
    .expect("auto route");

    assert_eq!(
        *observed.lock().expect("budget observation"),
        Some(Duration::from_millis(500))
    );
}

#[test]
fn judge_auto_follows_the_common_gateway_route_contract_after_direct_revalidation() {
    struct CountingProbe(Arc<AtomicUsize>);

    impl GatewayProbe for CountingProbe {
        fn probe(&self, _budget: Duration) -> NetworkState {
            self.0.fetch_add(1, Ordering::SeqCst);
            NetworkState::OffCampus
        }
    }

    let config = RouteConfig::default();
    let cases = [
        (NetworkState::Campus, ConnectionMode::Direct),
        (NetworkState::OffCampus, ConnectionMode::WebVpn),
        (NetworkState::Unknown, ConnectionMode::Direct),
    ];
    for (network, expected_mode) in cases {
        let resolved = resolve_feature_route(
            ReadonlyFeature::Judge,
            RoutePolicy::Auto,
            &config,
            &ProbeResult(network),
        )
        .expect("Judge auto route");

        assert_eq!(resolved.policy, RoutePolicy::Auto);
        assert_eq!(resolved.mode, expected_mode);
        assert_eq!(resolved.diagnostic.network, network);
    }

    let calls = Arc::new(AtomicUsize::new(0));
    let explicit_direct = resolve_feature_route(
        ReadonlyFeature::Judge,
        RoutePolicy::Direct,
        &config,
        &CountingProbe(calls.clone()),
    )
    .expect("explicit Judge direct route");
    assert_eq!(explicit_direct.mode, ConnectionMode::Direct);
    assert_eq!(calls.load(Ordering::SeqCst), 0);
}

#[test]
fn config_defaults_to_auto_and_rejects_unknown_features_or_values() {
    let config = RouteConfig::parse("").expect("missing config uses defaults");
    assert_eq!(config.default, RoutePolicy::Auto);
    assert_eq!(config.feature(ReadonlyFeature::Judge), RoutePolicy::Auto);

    let explicit = RouteConfig::parse(
        r#"
schema_version = 1
[route]
default = "webvpn"
[route.features]
schedule = "direct"
"#,
    )
    .expect("known values parse");
    assert_eq!(explicit.default, RoutePolicy::WebVpn);
    assert_eq!(
        explicit.feature(ReadonlyFeature::Schedule),
        RoutePolicy::Direct
    );
    assert_eq!(explicit.feature(ReadonlyFeature::Exam), RoutePolicy::WebVpn);

    assert!(RouteConfig::parse("[route.features]\nnot_a_feature = \"direct\"\n").is_err());
    assert!(RouteConfig::parse("[route]\ndefault = \"relay\"\n").is_err());
}

#[test]
fn feature_route_config_has_explicit_unknown_default_and_fallback_flags() {
    let row = FeatureRouteConfig::for_feature(ReadonlyFeature::Classroom);
    assert_eq!(row.auto_route_override, None);
    assert_eq!(row.unknown_default, ConnectionMode::Direct);
    assert!(!row.allow_ready_route_fallback);
    assert!(!row.allow_network_fallback);

    let judge = FeatureRouteConfig::for_feature(ReadonlyFeature::Judge);
    assert_eq!(judge.auto_route_override, None);
}

#[test]
fn gateway_probe_cache_expires_and_reprobes() {
    #[derive(Clone)]
    struct CountingProbe {
        calls: Arc<AtomicUsize>,
    }
    impl GatewayProbe for CountingProbe {
        fn probe(&self, _budget: Duration) -> NetworkState {
            self.calls.fetch_add(1, Ordering::SeqCst);
            NetworkState::Campus
        }
    }

    let calls = Arc::new(AtomicUsize::new(0));
    let probe = CachingGatewayProbe::new(
        CountingProbe {
            calls: calls.clone(),
        },
        Duration::from_millis(20),
    );
    assert_eq!(
        probe.probe(Duration::from_millis(500)),
        NetworkState::Campus
    );
    assert_eq!(
        probe.probe(Duration::from_millis(500)),
        NetworkState::Campus
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);

    std::thread::sleep(Duration::from_millis(50));
    assert_eq!(
        probe.probe(Duration::from_millis(500)),
        NetworkState::Campus
    );
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}

#[test]
fn concurrent_gateway_cache_misses_share_one_probe() {
    #[derive(Clone)]
    struct SlowCountingProbe(Arc<AtomicUsize>);

    impl GatewayProbe for SlowCountingProbe {
        fn probe(&self, _budget: Duration) -> NetworkState {
            self.0.fetch_add(1, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(20));
            NetworkState::OffCampus
        }
    }

    let calls = Arc::new(AtomicUsize::new(0));
    let probe = Arc::new(CachingGatewayProbe::new(
        SlowCountingProbe(calls.clone()),
        Duration::from_secs(1),
    ));
    let start = Arc::new(std::sync::Barrier::new(3));
    let workers = (0..2)
        .map(|_| {
            let probe = probe.clone();
            let start = start.clone();
            std::thread::spawn(move || {
                start.wait();
                probe.probe(Duration::from_millis(500))
            })
        })
        .collect::<Vec<_>>();
    start.wait();

    for worker in workers {
        assert_eq!(
            worker.join().expect("probe worker"),
            NetworkState::OffCampus
        );
    }
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[test]
fn facade_route_policy_save_clears_feature_overrides_and_updates_the_client() {
    static NEXT_DIRECTORY: AtomicUsize = AtomicUsize::new(0);

    let config_dir = std::env::temp_dir().join(format!(
        "ubaa-route-policy-save-{}-{}",
        std::process::id(),
        NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&config_dir);
    let original = RouteConfig::parse(
        r#"
schema_version = 1
[route]
default = "webvpn"
[route.features]
schedule = "webvpn"
cgyy = "direct"
"#,
    )
    .expect("parse route config");
    original.save(&config_dir).expect("save route config");

    let mut client = UbaaClient::open(&config_dir).expect("open aggregate client");
    client
        .set_default_route_policy(RoutePolicy::Direct)
        .expect("replace default route policy");
    assert_eq!(client.default_route_policy(), RoutePolicy::Direct);

    let saved = RouteConfig::load(&config_dir).expect("reload route config");
    assert_eq!(saved.default, RoutePolicy::Direct);
    assert_eq!(
        saved.feature(ReadonlyFeature::Schedule),
        RoutePolicy::Direct
    );
    assert_eq!(saved.feature(ReadonlyFeature::Cgyy), RoutePolicy::Direct);
    let stored =
        std::fs::read_to_string(config_dir.join("config.toml")).expect("read saved route config");
    assert!(!stored.contains("schedule ="));
    assert!(!stored.contains("cgyy ="));

    drop(client);
    let _ = std::fs::remove_dir_all(config_dir);
}
