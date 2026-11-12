use std::collections::BTreeSet;

use serde_json::{Value, json};

use super::*;

#[test]
fn wire_enums_match_the_worker_schema() {
    fn check<T: Serialize>(variants: &[T], schema: &Value) {
        let actual: BTreeSet<_> = variants
            .iter()
            .map(|variant| {
                let Value::String(value) = serde_json::to_value(variant).unwrap() else {
                    panic!("白名单值必须序列化为字符串");
                };
                value
            })
            .collect();
        let expected: BTreeSet<String> = serde_json::from_value(schema["enum"].clone()).unwrap();
        assert_eq!(actual.len(), variants.len());
        assert_eq!(actual, expected);
    }

    let schema: Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../docs/contracts/app-service.schema.json"
    )))
    .unwrap();
    let definitions = &schema["$defs"];
    check(Platform::ALL, &definitions["platform"]);
    check(Channel::ALL, &definitions["channel"]);
    check(
        Surface::ALL,
        &definitions["day"]["properties"]["surfaces"]["items"],
    );
    check(Feature::ALL, &definitions["feature"]);
    check(Route::ALL, &definitions["route"]);
    check(
        CounterEvent::ALL,
        &definitions["counter"]["properties"]["event"],
    );
    check(CounterResult::ALL, &definitions["result"]);
    check(
        ErrorEvent::ALL,
        &definitions["error"]["properties"]["event"],
    );
    check(
        TimingMetric::ALL,
        &definitions["timing"]["properties"]["metric"],
    );
    check(
        TimingBucket::ALL,
        &definitions["timing"]["properties"]["bucket"],
    );
    for platform in Platform::ALL {
        assert_eq!(serde_json::to_value(platform).unwrap(), platform.wire());
    }
    for channel in Channel::ALL {
        let wire = serde_json::to_value(channel).unwrap();
        assert_eq!(wire, channel.wire());
        assert_eq!(Channel::parse(wire.as_str().unwrap()), Some(*channel));
    }
}

#[test]
fn counter_and_timing_reject_unknown_dimensions() {
    let counter = json!({
        "event": "feature_loaded", "feature": "schedule", "route": "direct", "result": "success"
    });
    assert!(serde_json::from_value::<CounterDimensions>(counter.clone()).is_ok());
    for (key, value) in [
        ("event", "feature_failed"),
        ("feature", "agenda"),
        ("route", "internet"),
        ("result", "partial"),
        ("message", "不能进入遥测的错误原文"),
    ] {
        let mut invalid = counter.clone();
        invalid[key] = json!(value);
        assert!(serde_json::from_value::<CounterDimensions>(invalid).is_err());
    }

    let timing = json!({
        "metric": "first_content", "feature": "app", "route": "none", "bucket": "lt_1000"
    });
    let parsed = serde_json::from_value::<TimingDimensions>(timing.clone()).unwrap();
    assert_eq!(serde_json::to_value(parsed).unwrap(), timing);
    let mut invalid = timing;
    invalid["bucket"] = json!("123ms");
    assert!(serde_json::from_value::<TimingDimensions>(invalid).is_err());
}

#[test]
fn error_dimensions_require_safe_codes_and_source_locations() {
    let error = |event, code: &str, source: Option<&str>| {
        TelemetryEvent::Error(ErrorDimensions {
            event,
            feature: Feature::Grades,
            route: Route::Webvpn,
            error_code: code.to_owned(),
            error_kind: ErrorKind::Parse,
            retryable: false,
            source: source.map(str::to_owned),
        })
        .is_valid()
    };
    assert!(error(ErrorEvent::FeatureFailed, "parse_error", None));
    assert!(error(
        ErrorEvent::FeatureFailed,
        "parse_error",
        Some("package:ubaa_app/src/bridge/read/grades.dart:120"),
    ));
    assert!(error(
        ErrorEvent::Crash,
        "panic",
        Some("crates/ubaa_core/src/facade/read.rs:15"),
    ));
    assert!(error(ErrorEvent::Crash, "StateError", None));
    assert!(!error(ErrorEvent::FeatureFailed, "StateError", None));
    assert!(!error(ErrorEvent::Crash, "StateError<int>", None));
    assert!(!error(ErrorEvent::Crash, "error\n", None));
    assert!(!error(ErrorEvent::FeatureFailed, &"a".repeat(49), None));
    assert!(!error(ErrorEvent::Crash, &"a".repeat(65), None));
    for source in [
        "https://example.invalid/grades",
        "/private-evidence/crates/ubaa_core/src/facade/read.rs:15",
        "package:ubaa_app/src/../grades.dart:120",
        "package:ubaa_app/src/grades.dart:１",
        "package:ubaa_app/src/grades.dart:120\n",
    ] {
        assert!(!error(ErrorEvent::Crash, "StateError", Some(source)));
    }
    let long_source = format!("package:ubaa_app/{}.dart:1", "a".repeat(120));
    assert!(!error(ErrorEvent::Crash, "StateError", Some(&long_source)));
}

#[test]
fn absent_error_source_is_omitted() {
    let input = json!({
        "event": "auth_failed", "feature": "auth", "route": "direct",
        "error_code": "invalid_credentials", "error_kind": "authentication", "retryable": false
    });
    let parsed: ErrorDimensions = serde_json::from_value(input.clone()).unwrap();
    let encoded: Value = serde_json::to_value(parsed).unwrap();
    assert_eq!(encoded, input);
    let mut invalid = input;
    invalid["error_kind"] = json!("raw_error");
    assert!(serde_json::from_value::<ErrorDimensions>(invalid).is_err());
}

#[test]
fn version_accepts_only_the_wire_format() {
    for version in ["2.0.0", "2.1.0-rc.1+15", "2.1.0+15"] {
        assert!(valid_app_version(version));
    }
    for version in [
        "",
        "2.0",
        "２.０.０",
        "v2.0.0",
        "2.0.0+abc",
        "2.0.0-",
        "2.0.0-rc..1",
        "2.0.0\n",
    ] {
        assert!(!valid_app_version(version));
    }
    assert!(valid_app_version(&format!("2.0.0-{}", "a".repeat(42))));
    assert!(!valid_app_version(&format!("2.0.0-{}", "a".repeat(43))));
}
