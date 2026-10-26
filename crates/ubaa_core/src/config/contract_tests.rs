use super::{FeatureRouteConfig, RouteConfig};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};

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
