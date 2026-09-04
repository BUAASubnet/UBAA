use std::io::Cursor;

use clap::Parser;
use ubaa_cli::{
    AggregateJsonEnvelope, AggregateLogoutData, CLI_JSON_SCHEMA_VERSION, Cli, CliFeature,
    ResolvedRoutedJsonMeta, RoutedJsonEnvelope, UnresolvedRoutedJsonMeta, run_with_backend,
    run_with_routed_backend,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, LibBookCancelResult, LoginOutcome, LoginReadiness,
    NetworkState, RouteLoginResult, RouteLoginState, RoutePolicy, SafeError, SpocAssignmentDetail,
    UbaaError, UserProfile,
};

use crate::common::{FakeBackend, FakeRoutedBackend, assert_cli_schema, profile, route_resolution};

#[path = "output_helpers.rs"]
mod output_helpers;

use output_helpers::{
    assert_all_routed_features_validate, assert_schema_rejects_invalid_envelopes,
    assert_schema_rejects_invalid_routed_data,
};

fn masked_profile() -> UserProfile {
    UserProfile {
        phone: Some("PH***NE".into()),
        id_card_number: Some("ID***ER".into()),
        ..profile()
    }
}

#[tokio::test]
async fn json_login_outputs_one_parseable_redacted_envelope() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "--config-dir",
        "/tmp/ubaa-fixture",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username-stdin",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-user\nfixture-password\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["ok"], true);
    assert_eq!(value["schemaVersion"], 5);
    assert_eq!(value["meta"]["feature"], "auth");
    assert_eq!(value["meta"]["routePolicy"], "direct");
    assert_eq!(value["data"]["schoolId"], "TEST-0001");
    assert_ne!(value["data"]["phone"], "PHONE-FIXTURE-VALUE");
    assert_ne!(value["data"]["idCardNumber"], "TEST-ID-0001");
    assert!(!String::from_utf8_lossy(&stdout).contains("fixture-password"));
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn human_user_output_masks_phone_and_identity_number() {
    let cli = Cli::try_parse_from(["ubaa", "user", "show"]).unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;

    let output = String::from_utf8(stdout).unwrap();
    assert_eq!(code, 0);
    assert!(output.contains("Fixture User"));
    assert!(output.contains("TEST-0001"));
    assert!(!output.contains("PHONE-FIXTURE-VALUE"));
    assert!(!output.contains("TEST-ID-0001"));
}

#[tokio::test]
async fn hidden_judge_diagnostics_exposes_only_safe_counts_and_summaries() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "judge",
        "diagnostics",
        "--include-expired",
    ])
    .unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["data"]["courseCount"], 3);
    assert_eq!(value["data"]["rawAnchorCount"], 7);
    assert_eq!(value["data"]["filteredUniqueCount"], 2);
    assert_eq!(value["data"]["summaries"], serde_json::json!([]));
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn hidden_spoc_diagnostics_proves_global_pages_without_raw_protocol_data() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "spoc", "diagnostics"]).unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["data"]["globalPageCount"], 2);
    assert_eq!(value["data"]["result"]["termCode"], "2025-2026-2");
    assert_eq!(
        value["data"]["result"]["assignments"],
        serde_json::json!([])
    );
    assert!(value["data"].get("token").is_none());
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert!(stderr.is_empty());
}

#[test]
fn spoc_detail_cli_json_exposes_plain_text_but_never_raw_html() {
    let detail = SpocAssignmentDetail {
        assignment_id: "assignment-1".into(),
        content_plain_text: Some("Fixture content".into()),
        ..SpocAssignmentDetail::default()
    };
    let envelope = RoutedJsonEnvelope::success(
        detail,
        ResolvedRoutedJsonMeta::from_resolution(
            CliFeature::Spoc,
            route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        ),
    );
    let value = serde_json::to_value(envelope).unwrap();

    assert_eq!(value["data"]["contentPlainText"], "Fixture content");
    assert!(value["data"].get("contentHtml").is_none());
}

#[test]
fn serialized_envelopes_match_the_cli_json_schema() {
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let direct_resolution = route_resolution(
        RoutePolicy::Direct,
        NetworkState::Unknown,
        ConnectionMode::Direct,
    );
    let success = RoutedJsonEnvelope::success(
        masked_profile(),
        ResolvedRoutedJsonMeta::from_resolution(CliFeature::User, direct_resolution),
    );
    let failure = RoutedJsonEnvelope::<serde_json::Value>::resolved_failure(
        UbaaError::new(
            ErrorCode::NetworkError,
            ErrorKind::Network,
            true,
            "network unavailable",
        ),
        ResolvedRoutedJsonMeta::from_resolution(CliFeature::User, direct_resolution),
    );
    let unresolved = RoutedJsonEnvelope::<serde_json::Value>::unresolved_failure(
        UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "invalid command",
        ),
        UnresolvedRoutedJsonMeta::new(CliFeature::Cli),
    );
    let success_bytes = serde_json::to_vec(&success).unwrap();
    let failure_bytes = serde_json::to_vec(&failure).unwrap();
    let success: serde_json::Value = serde_json::from_slice(&success_bytes).unwrap();
    let failure: serde_json::Value = serde_json::from_slice(&failure_bytes).unwrap();
    let aggregate_outcome = LoginOutcome {
        readiness: LoginReadiness::Partial,
        routes: [
            RouteLoginResult {
                route: ConnectionMode::Direct,
                state: RouteLoginState::Ready,
                error: None,
            },
            RouteLoginResult {
                route: ConnectionMode::WebVpn,
                state: RouteLoginState::Failed,
                error: Some(SafeError {
                    code: "upstream_unavailable".into(),
                    kind: "upstream".into(),
                    retryable: true,
                    message: "fixture unavailable".into(),
                }),
            },
        ],
        profile: Some(masked_profile()),
    };
    let aggregate = serde_json::to_value(
        AggregateJsonEnvelope::auth_success(aggregate_outcome, RoutePolicy::Auto).unwrap(),
    )
    .unwrap();
    let logout =
        serde_json::to_value(AggregateJsonEnvelope::logout_success(RoutePolicy::Auto)).unwrap();
    let unresolved = serde_json::to_value(unresolved).unwrap();
    let mut resolved_missing_network = serde_json::to_value(&success).unwrap();
    resolved_missing_network["meta"]
        .as_object_mut()
        .unwrap()
        .remove("networkState");

    assert!(validator.is_valid(&serde_json::to_value(&success).unwrap()));
    assert!(validator.is_valid(&serde_json::to_value(&failure).unwrap()));
    assert!(validator.is_valid(&unresolved));
    assert!(validator.is_valid(&aggregate));
    assert!(validator.is_valid(&logout));
    assert!(!validator.is_valid(&resolved_missing_network));

    assert_all_routed_features_validate(&validator, direct_resolution);

    assert_schema_rejects_invalid_envelopes(
        &validator,
        &success,
        &failure,
        &unresolved,
        &aggregate,
    );
    assert_schema_rejects_invalid_routed_data(&validator, direct_resolution);

    let success = serde_json::to_value(success).unwrap();
    let failure = serde_json::to_value(failure).unwrap();
    assert_eq!(success["data"]["schoolId"], "TEST-0001");
    assert_eq!(failure["error"]["code"], "network_error");
}

#[test]
fn cli_json_schema_accepts_empty_libbook_collections() {
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let envelope = RoutedJsonEnvelope::success(
        serde_json::json!([]),
        ResolvedRoutedJsonMeta::explicit(CliFeature::LibBook, ConnectionMode::Direct),
    );
    let value = serde_json::to_value(envelope).unwrap();

    assert!(
        validator.is_valid(&value),
        "合法的图书馆空列表必须符合 CLI schema v5：{value}"
    );
}

#[test]
fn cli_json_schema_accepts_strict_libbook_cancel_result() {
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let meta = ResolvedRoutedJsonMeta::explicit(CliFeature::LibBook, ConnectionMode::Direct);
    let valid = serde_json::to_value(RoutedJsonEnvelope::success(
        LibBookCancelResult {
            success: true,
            message: "取消成功".to_owned(),
        },
        meta,
    ))
    .unwrap();
    let missing_message = serde_json::to_value(RoutedJsonEnvelope::success(
        serde_json::json!({"success": true}),
        meta,
    ))
    .unwrap();
    let unexpected_field = serde_json::to_value(RoutedJsonEnvelope::success(
        serde_json::json!({
            "success": true,
            "message": "取消成功",
            "unexpected": true
        }),
        meta,
    ))
    .unwrap();

    assert!(
        validator.is_valid(&valid),
        "实际序列化的图书馆取消结果必须符合 CLI schema v5：{valid}"
    );
    assert!(!validator.is_valid(&missing_message));
    assert!(!validator.is_valid(&unexpected_field));
}

#[test]
fn cli_json_contract_has_one_schema_version_and_closed_feature_names() {
    assert_eq!(CLI_JSON_SCHEMA_VERSION, 5);

    let features = [
        CliFeature::Cli,
        CliFeature::Auth,
        CliFeature::User,
        CliFeature::Signin,
        CliFeature::Schedule,
        CliFeature::Exam,
        CliFeature::Grades,
        CliFeature::Classroom,
        CliFeature::Spoc,
        CliFeature::Judge,
    ];
    assert_eq!(
        serde_json::to_value(features).unwrap(),
        serde_json::json!([
            "cli",
            "auth",
            "user",
            "signin",
            "schedule",
            "exam",
            "grades",
            "classroom",
            "spoc",
            "judge"
        ])
    );
}

#[test]
fn success_json_envelope_has_version_data_and_resolved_route_metadata() {
    let envelope = RoutedJsonEnvelope::success(
        serde_json::json!({"name": "Fixture User"}),
        ResolvedRoutedJsonMeta::explicit(CliFeature::User, ConnectionMode::Direct),
    );
    let success_debug = format!(
        "{:?}",
        RoutedJsonEnvelope::success(
            serde_json::json!({"secret": "ENVELOPE-DATA-SENTINEL"}),
            ResolvedRoutedJsonMeta::explicit(CliFeature::Auth, ConnectionMode::Direct),
        )
    );
    let value = serde_json::to_value(envelope).expect("envelope serializes");

    assert_eq!(value["schemaVersion"], 5);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["name"], "Fixture User");
    assert_eq!(
        value["meta"],
        serde_json::json!({
            "routePolicy": "direct",
            "networkState": "unknown",
            "initialRoute": "direct",
            "resolvedRoute": "direct",
            "usedFallback": false,
            "feature": "user"
        })
    );
    assert!(value.get("error").is_none());
    assert!(!success_debug.contains("ENVELOPE-DATA-SENTINEL"));

    let failure = RoutedJsonEnvelope::<serde_json::Value>::resolved_failure(
        UbaaError::new(
            ErrorCode::NetworkError,
            ErrorKind::Network,
            true,
            "ERROR-MESSAGE-SENTINEL",
        ),
        ResolvedRoutedJsonMeta::explicit(CliFeature::User, ConnectionMode::Direct),
    );
    assert!(!format!("{failure:?}").contains("ERROR-MESSAGE-SENTINEL"));
}

#[test]
fn unresolved_routed_failure_has_only_feature_metadata() {
    let error = UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "missing argument",
    );
    let envelope: RoutedJsonEnvelope<serde_json::Value> = RoutedJsonEnvelope::unresolved_failure(
        error,
        UnresolvedRoutedJsonMeta::new(CliFeature::Cli),
    );

    let value = serde_json::to_value(envelope).unwrap();
    assert_eq!(value["schemaVersion"], 5);
    assert_eq!(value["ok"], false);
    assert_eq!(value["meta"], serde_json::json!({"feature": "cli"}));
    assert!(value.get("data").is_none());
    assert_eq!(value["error"]["code"], "invalid_input");
}

#[test]
fn aggregate_auth_envelope_requires_direct_then_webvpn_and_has_fixed_meta_routes() {
    let direct = RouteLoginResult {
        route: ConnectionMode::Direct,
        state: RouteLoginState::Ready,
        error: None,
    };
    let webvpn = RouteLoginResult {
        route: ConnectionMode::WebVpn,
        state: RouteLoginState::Ready,
        error: None,
    };
    let valid = LoginOutcome {
        readiness: LoginReadiness::AllReady,
        routes: [direct.clone(), webvpn.clone()],
        profile: Some(masked_profile()),
    };
    let value = serde_json::to_value(
        AggregateJsonEnvelope::auth_success(valid, RoutePolicy::Auto).unwrap(),
    )
    .unwrap();

    assert_eq!(value["schemaVersion"], 5);
    assert_eq!(value["ok"], true);
    assert_eq!(
        value["data"]["routes"],
        serde_json::json!([
            {"route": "direct", "state": "ready"},
            {"route": "webvpn", "state": "ready"}
        ])
    );
    assert_eq!(
        value["meta"],
        serde_json::json!({
            "routePolicy": "auto",
            "resolvedRoutes": ["direct", "webvpn"],
            "feature": "auth"
        })
    );
    assert!(value.get("error").is_none());

    let reversed = LoginOutcome {
        readiness: LoginReadiness::AllReady,
        routes: [webvpn, direct],
        profile: None,
    };
    assert!(AggregateJsonEnvelope::auth_success(reversed, RoutePolicy::Auto).is_err());
}

#[test]
fn aggregate_failure_constructor_keeps_ok_data_error_consistent() {
    let route_error = SafeError {
        code: "authentication_required".into(),
        kind: "authentication".into(),
        retryable: false,
        message: "authentication is required".into(),
    };
    let failed_route = |route| RouteLoginResult {
        route,
        state: RouteLoginState::Failed,
        error: Some(route_error.clone()),
    };
    let outcome = LoginOutcome {
        readiness: LoginReadiness::NoneReady,
        routes: [
            failed_route(ConnectionMode::Direct),
            failed_route(ConnectionMode::WebVpn),
        ],
        profile: None,
    };
    let error = route_error;
    assert!(
        AggregateJsonEnvelope::auth_success(outcome.clone(), RoutePolicy::Direct).is_err(),
        "none_ready must not be emitted with ok=true"
    );
    let failure = serde_json::to_value(
        AggregateJsonEnvelope::auth_failure(outcome, error, RoutePolicy::Direct).unwrap(),
    )
    .unwrap();
    assert_eq!(failure["ok"], false);
    assert!(failure.get("data").is_some());
    assert_eq!(failure["error"]["code"], "authentication_required");
}

#[test]
fn aggregate_logout_constructor_names_both_routes() {
    let logout = serde_json::to_value(
        AggregateJsonEnvelope::<AggregateLogoutData>::logout_success(RoutePolicy::WebVpn),
    )
    .unwrap();
    assert_eq!(logout["ok"], true);
    assert!(logout.get("error").is_none());
    assert_eq!(
        logout["data"],
        serde_json::json!({
            "loggedOut": true,
            "routes": [
                {"route": "direct", "state": "logged_out"},
                {"route": "webvpn", "state": "logged_out"}
            ]
        })
    );
    assert_eq!(
        logout["meta"]["resolvedRoutes"],
        serde_json::json!(["direct", "webvpn"])
    );
}

#[test]
fn aggregate_auth_constructors_reject_inconsistent_route_states() {
    let ready_route = |route| RouteLoginResult {
        route,
        state: RouteLoginState::Ready,
        error: None,
    };
    let ready = LoginOutcome {
        readiness: LoginReadiness::AllReady,
        routes: [
            ready_route(ConnectionMode::Direct),
            ready_route(ConnectionMode::WebVpn),
        ],
        profile: None,
    };
    let impossible_error = SafeError {
        code: "internal_error".into(),
        kind: "internal".into(),
        retryable: false,
        message: "should not be emitted".into(),
    };
    assert!(
        AggregateJsonEnvelope::auth_failure(ready, impossible_error, RoutePolicy::Auto).is_err(),
        "all_ready must not be emitted with ok=false"
    );

    let missing_route_error = LoginOutcome {
        readiness: LoginReadiness::NoneReady,
        routes: [
            RouteLoginResult {
                route: ConnectionMode::Direct,
                state: RouteLoginState::Failed,
                error: None,
            },
            RouteLoginResult {
                route: ConnectionMode::WebVpn,
                state: RouteLoginState::Failed,
                error: None,
            },
        ],
        profile: None,
    };
    let top_error = SafeError {
        code: "internal_error".into(),
        kind: "internal".into(),
        retryable: false,
        message: "route error is missing".into(),
    };
    assert!(
        AggregateJsonEnvelope::auth_failure(missing_route_error, top_error, RoutePolicy::Auto)
            .is_err(),
        "failed routes must carry a safe error"
    );
}

#[test]
fn aggregate_auth_constructors_bind_profile_presence_to_route_readiness() {
    let ready_route = |route| RouteLoginResult {
        route,
        state: RouteLoginState::Ready,
        error: None,
    };
    let ready_without_profile = LoginOutcome {
        readiness: LoginReadiness::AllReady,
        routes: [
            ready_route(ConnectionMode::Direct),
            ready_route(ConnectionMode::WebVpn),
        ],
        profile: None,
    };
    assert!(
        AggregateJsonEnvelope::auth_success(ready_without_profile, RoutePolicy::Auto).is_err(),
        "ready routes must carry the profile returned by authentication"
    );

    let route_error = SafeError {
        code: "authentication_required".into(),
        kind: "authentication".into(),
        retryable: false,
        message: "authentication is required".into(),
    };
    let failed_route = |route| RouteLoginResult {
        route,
        state: RouteLoginState::Failed,
        error: Some(route_error.clone()),
    };
    let none_ready_with_profile = LoginOutcome {
        readiness: LoginReadiness::NoneReady,
        routes: [
            failed_route(ConnectionMode::Direct),
            failed_route(ConnectionMode::WebVpn),
        ],
        profile: Some(masked_profile()),
    };
    assert!(
        AggregateJsonEnvelope::auth_failure(
            none_ready_with_profile,
            route_error,
            RoutePolicy::Auto,
        )
        .is_err(),
        "a profile must not be emitted when no route is ready"
    );
}

#[test]
fn cli_json_schema_contains_no_v1_or_legacy_route_contract() {
    let schema = include_str!("../../../../docs/contracts/cli-json.schema.json");

    assert!(!schema.contains("\"const\": 1"));
    assert!(!schema.contains("connectionMode"));
    assert!(!schema.contains("legacyError"));
}
