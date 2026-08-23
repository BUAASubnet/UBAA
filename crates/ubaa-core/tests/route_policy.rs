use std::time::Duration;

use ubaa_core::config::{FeatureRouteConfig, RouteConfig};
use ubaa_core::connection::{
    CachingDnsProbe, DnsProbe, NetworkState, RouteDiagnostic, resolve_feature_route,
};
use ubaa_core::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};

#[derive(Clone)]
struct ProbeResult(NetworkState);

impl DnsProbe for ProbeResult {
    fn resolve_gateway(&self, _timeout: Duration) -> NetworkState {
        self.0
    }
}

#[test]
fn auto_route_maps_three_dns_states_and_exposes_diagnostic() {
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
fn judge_auto_follows_the_common_dns_route_contract_after_direct_revalidation() {
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

    let explicit_direct = resolve_feature_route(
        ReadonlyFeature::Judge,
        RoutePolicy::Direct,
        &config,
        &ProbeResult(NetworkState::OffCampus),
    )
    .expect("explicit Judge direct route");
    assert_eq!(explicit_direct.mode, ConnectionMode::Direct);
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
fn dns_probe_cache_expires_and_reprobes() {
    use std::sync::{Arc, Mutex};

    #[derive(Clone)]
    struct CountingProbe {
        calls: Arc<Mutex<usize>>,
    }
    impl DnsProbe for CountingProbe {
        fn resolve_gateway(&self, _timeout: Duration) -> NetworkState {
            *self.calls.lock().expect("counter") += 1;
            NetworkState::Campus
        }
    }

    let calls = Arc::new(Mutex::new(0));
    let probe = CachingDnsProbe::new(
        CountingProbe {
            calls: calls.clone(),
        },
        Duration::from_millis(1),
    );
    assert_eq!(
        probe.resolve_gateway(Duration::from_millis(500)),
        NetworkState::Campus
    );
    assert_eq!(
        probe.resolve_gateway(Duration::from_millis(500)),
        NetworkState::Campus
    );
    std::thread::sleep(Duration::from_millis(3));
    assert_eq!(
        probe.resolve_gateway(Duration::from_millis(500)),
        NetworkState::Campus
    );
    assert_eq!(*calls.lock().expect("counter"), 2);
}
