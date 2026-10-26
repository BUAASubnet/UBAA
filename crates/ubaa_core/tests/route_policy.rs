use std::sync::atomic::{AtomicUsize, Ordering};

use ubaa_core::facade::testing::RouteConfig;
use ubaa_core::facade::{ReadonlyFeature, RoutePolicy, UbaaClient};

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
