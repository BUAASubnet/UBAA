use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use super::{
    AuthHostPolicy, CachingGatewayProbe, GatewayProbe, NetworkState, RouteDiagnostic,
    from_webvpn_url, is_allowed_auth_host, resolve_redirect, resolve_route,
};
use crate::config::FeatureRouteConfig;
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::ErrorCode;

#[derive(Clone)]
struct ProbeResult(NetworkState);

impl GatewayProbe for ProbeResult {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.0
    }
}

#[test]
fn auth_host_policy_accepts_only_verified_sso_uc_and_gateway_hosts() {
    let policy = AuthHostPolicy::default();
    assert!(policy.allows("sso.buaa.edu.cn"));
    assert!(policy.allows("uc.buaa.edu.cn"));
    assert!(policy.allows("d.buaa.edu.cn"));
    assert!(!policy.allows("evil.example.invalid"));
    assert!(is_allowed_auth_host("https://sso.buaa.edu.cn/login"));
    assert!(is_allowed_auth_host("http://sso.buaa.edu.cn/login"));
    assert!(!is_allowed_auth_host("ftp://sso.buaa.edu.cn/login"));
    assert!(!is_allowed_auth_host("https://evil.example.invalid/login"));
}

#[test]
fn redirects_resolve_absolute_protocol_relative_root_and_path_relative_locations() {
    let current = "https://sso.buaa.edu.cn/cas/login/step";
    let cases = [
        (
            "https://uc.buaa.edu.cn/landing",
            "https://uc.buaa.edu.cn/landing",
        ),
        ("//uc.buaa.edu.cn/landing", "https://uc.buaa.edu.cn/landing"),
        ("/landing", "https://sso.buaa.edu.cn/landing"),
        ("next", "https://sso.buaa.edu.cn/cas/login/next"),
    ];

    for (location, expected) in cases {
        assert_eq!(
            resolve_redirect(current, location, ConnectionMode::Direct).unwrap(),
            expected
        );
    }
}

#[test]
fn webvpn_absolute_redirects_are_converted_but_gateway_relative_redirects_stay_gateway() {
    let direct = resolve_redirect(
        "https://d.buaa.edu.cn/https/fixture/sso/login",
        "https://uc.buaa.edu.cn/landing",
        ConnectionMode::WebVpn,
    )
    .unwrap();
    assert!(direct.starts_with("https://d.buaa.edu.cn/https/"));
    assert_eq!(
        from_webvpn_url(&direct).unwrap(),
        "https://uc.buaa.edu.cn/landing"
    );

    let relative = resolve_redirect(
        "https://d.buaa.edu.cn/https/fixture/sso/login",
        "/landing",
        ConnectionMode::WebVpn,
    )
    .unwrap();
    assert_eq!(relative, "https://d.buaa.edu.cn/landing");
}

#[test]
fn redirects_to_unverified_hosts_are_rejected_in_both_modes() {
    assert!(
        resolve_redirect(
            "https://sso.buaa.edu.cn/login",
            "https://evil.example.invalid/login",
            ConnectionMode::Direct,
        )
        .is_err()
    );
    assert!(
        resolve_redirect(
            "https://d.buaa.edu.cn/https/fixture/login",
            "https://evil.example.invalid/login",
            ConnectionMode::WebVpn,
        )
        .is_err()
    );
}

#[test]
fn redirects_reject_non_http_schemes_even_on_verified_hosts() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let error = resolve_redirect(
            "https://sso.buaa.edu.cn/login",
            "ftp://sso.buaa.edu.cn/session",
            mode,
        )
        .expect_err("authentication redirects must remain HTTP or HTTPS");

        assert_eq!(error.code, ErrorCode::PermissionDenied);
        assert_eq!(error.message, "redirect scheme is not allowed");
    }
}

#[test]
fn auto_route_maps_three_gateway_states_and_exposes_diagnostic() {
    let row = FeatureRouteConfig::for_feature(ReadonlyFeature::Schedule);
    let campus = resolve_route(RoutePolicy::Auto, row, &ProbeResult(NetworkState::Campus));
    assert_eq!(campus.mode, ConnectionMode::Direct);
    assert_eq!(
        campus.diagnostic,
        RouteDiagnostic::new(NetworkState::Campus, ConnectionMode::Direct)
    );

    let off_campus = resolve_route(
        RoutePolicy::Auto,
        row,
        &ProbeResult(NetworkState::OffCampus),
    );
    assert_eq!(off_campus.mode, ConnectionMode::WebVpn);

    let unknown = resolve_route(RoutePolicy::Auto, row, &ProbeResult(NetworkState::Unknown));
    assert_eq!(unknown.mode, ConnectionMode::Direct);
    assert_eq!(unknown.diagnostic.network, NetworkState::Unknown);
}

#[test]
fn effective_策略只在_auto_时调用网关探针() {
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

    for effective in [RoutePolicy::Direct, RoutePolicy::WebVpn, RoutePolicy::Auto] {
        let calls = Arc::new(AtomicUsize::new(0));
        let resolved = resolve_route(
            effective,
            FeatureRouteConfig::for_feature(ReadonlyFeature::Schedule),
            &CountingStateProbe {
                calls: calls.clone(),
                state: NetworkState::OffCampus,
            },
        );
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
    let _ = resolve_route(
        RoutePolicy::Auto,
        FeatureRouteConfig::for_feature(ReadonlyFeature::Schedule),
        &BudgetProbe(observed.clone()),
    );

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

    let row = FeatureRouteConfig::for_feature(ReadonlyFeature::Judge);
    let cases = [
        (NetworkState::Campus, ConnectionMode::Direct),
        (NetworkState::OffCampus, ConnectionMode::WebVpn),
        (NetworkState::Unknown, ConnectionMode::Direct),
    ];
    for (network, expected_mode) in cases {
        let resolved = resolve_route(RoutePolicy::Auto, row, &ProbeResult(network));

        assert_eq!(resolved.policy, RoutePolicy::Auto);
        assert_eq!(resolved.mode, expected_mode);
        assert_eq!(resolved.diagnostic.network, network);
    }

    let calls = Arc::new(AtomicUsize::new(0));
    let explicit_direct = resolve_route(RoutePolicy::Direct, row, &CountingProbe(calls.clone()));
    assert_eq!(explicit_direct.mode, ConnectionMode::Direct);
    assert_eq!(calls.load(Ordering::SeqCst), 0);
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
