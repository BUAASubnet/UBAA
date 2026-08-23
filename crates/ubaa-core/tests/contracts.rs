use serde_json::{Value, json};
use ubaa_core::domain::{
    AuthStatus, ConnectionMode, DualLoginPreparation, LoginChallenge, LoginInput, LoginOutcome,
    LoginReadiness, RouteLoginChallenge, RouteLoginResult, RouteLoginState, RoutePolicy, SafeError,
    SecretValue, UserInfoResponse, UserProfile,
};
use ubaa_core::error::{ErrorCode, ErrorKind, ExitCode, UbaaError};
use ubaa_core::output::{
    AggregateJsonEnvelope, AggregateLogoutData, CliFeature, CliJsonError, ResolvedRoutedJsonMeta,
    RoutedJsonEnvelope, UnresolvedRoutedJsonMeta,
};
use ubaa_core::ports::{HttpRequest, HttpResponse};
use ubaa_core::session::{SessionSnapshot, StoredCookie, VersionedSession};

#[test]
fn cli_json_contract_has_one_schema_version_and_closed_feature_names() {
    assert_eq!(ubaa_core::output::CLI_JSON_SCHEMA_VERSION, 2);

    let features = [
        ubaa_core::output::CliFeature::Cli,
        ubaa_core::output::CliFeature::Auth,
        ubaa_core::output::CliFeature::User,
        ubaa_core::output::CliFeature::Schedule,
        ubaa_core::output::CliFeature::Exam,
        ubaa_core::output::CliFeature::Grades,
        ubaa_core::output::CliFeature::Classroom,
        ubaa_core::output::CliFeature::Spoc,
        ubaa_core::output::CliFeature::Judge,
    ];
    assert_eq!(
        serde_json::to_value(features).unwrap(),
        json!([
            "cli",
            "auth",
            "user",
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
fn user_info_response_maps_legacy_camel_case_fields() {
    let payload = json!({
        "code": 0,
        "data": {
            "idCardType": "TEST_TYPE",
            "idCardTypeName": "Synthetic document",
            "phone": "PHONE-REDACTED",
            "schoolid": "TEST-0001",
            "name": "Fixture User",
            "idCardNumber": "TEST-ID-0001",
            "email": "fixture@example.invalid",
            "username": "fixture-user"
        }
    });

    let parsed: UserInfoResponse = serde_json::from_value(payload).expect("fixture parses");
    let profile = parsed.data.expect("profile is present");

    assert_eq!(profile.school_id.as_deref(), Some("TEST-0001"));
    assert_eq!(profile.id_card_type.as_deref(), Some("TEST_TYPE"));
    assert_eq!(profile.id_card_number.as_deref(), Some("TEST-ID-0001"));
    assert_eq!(profile.username.as_deref(), Some("fixture-user"));
}

#[test]
fn user_profile_serializes_cli_fields_as_camel_case() {
    let profile = UserProfile {
        school_id: Some("TEST-0001".into()),
        id_card_number: Some("TEST-ID-0001".into()),
        ..UserProfile::default()
    };

    let value = serde_json::to_value(profile).expect("profile serializes");

    assert_eq!(value["schoolId"], "TEST-0001");
    assert_eq!(value["idCardNumber"], "TEST-ID-0001");
    assert!(value.get("school_id").is_none());
}

#[test]
fn aggregate_login_contract_has_exactly_two_ordered_routes() {
    let routes: [RouteLoginResult; 2] = [
        RouteLoginResult {
            route: ConnectionMode::Direct,
            state: RouteLoginState::Ready,
            error: None,
        },
        RouteLoginResult {
            route: ConnectionMode::WebVpn,
            state: RouteLoginState::Failed,
            error: None,
        },
    ];
    let outcome = LoginOutcome {
        readiness: LoginReadiness::Partial,
        routes: routes.clone(),
        profile: None,
        challenges: Vec::new(),
    };
    let preparation = DualLoginPreparation {
        routes,
        challenges: Vec::new(),
    };

    assert_eq!(
        serde_json::to_value(outcome).unwrap()["routes"],
        json!([
            {"route": "direct", "state": "ready"},
            {"route": "webvpn", "state": "failed"}
        ])
    );
    assert_eq!(
        serde_json::to_value(preparation).unwrap()["routes"],
        json!([
            {"route": "direct", "state": "ready"},
            {"route": "webvpn", "state": "failed"}
        ])
    );

    let incomplete = json!({
        "readiness": "partial",
        "routes": [{"route": "direct", "state": "ready"}],
        "challenges": []
    });
    assert!(serde_json::from_value::<LoginOutcome>(incomplete).is_err());
}

#[test]
fn secret_value_never_serializes_or_formats_plaintext() {
    let secret = SecretValue::new("do-not-leak");

    assert_eq!(format!("{secret}"), "[REDACTED]");
    assert_eq!(format!("{secret:?}"), "SecretValue([REDACTED])");
    assert_eq!(serde_json::to_string(&secret).unwrap(), "\"[REDACTED]\"");
    assert_eq!(secret.expose_secret(), "do-not-leak");
}

#[test]
fn debug_formatting_redacts_sensitive_request_response_and_domain_values() {
    let request = HttpRequest::post(
        "https://example.invalid/login?token=REQUEST-SENTINEL",
        b"body-REQUEST-SENTINEL".to_vec(),
    )
    .with_header("Cookie", "SESSION=REQUEST-SENTINEL");
    let response = HttpResponse {
        status: 200,
        final_url: "https://example.invalid/response?token=RESPONSE-SENTINEL".into(),
        headers: std::collections::BTreeMap::from([(
            "Set-Cookie".into(),
            vec!["SESSION=RESPONSE-SENTINEL".into()],
        )]),
        body: b"body-RESPONSE-SENTINEL".to_vec(),
    };
    let login_input = LoginInput {
        username: "USERNAME-SENTINEL".into(),
        password: SecretValue::new("PASSWORD-SENTINEL"),
        captcha: Some("CAPTCHA-SENTINEL".into()),
    };
    let challenge = LoginChallenge {
        id: "CHALLENGE-SENTINEL".into(),
        execution: "EXECUTION-SENTINEL".into(),
        image_data_url: Some("data:image/jpeg;base64,CHALLENGE-SENTINEL".into()),
    };
    let profile = sensitive_profile();
    let cookie = sensitive_cookie();
    let snapshot = SessionSnapshot {
        mode: ConnectionMode::Direct,
        cookies: vec![cookie.clone()],
        authenticated_at: 111,
        last_activity: 222,
    };
    let versioned = VersionedSession {
        snapshot: Some(snapshot.clone()),
        revision: 7,
    };
    let error = UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "ERROR-MESSAGE-SENTINEL",
    )
    .with_challenge(challenge.clone());
    let response_wrapper = UserInfoResponse {
        code: 0,
        data: Some(profile.clone()),
    };
    let status = AuthStatus {
        user: profile.clone(),
        authenticated_at: 333,
        last_activity: 444,
    };
    let meta = ResolvedRoutedJsonMeta::explicit(CliFeature::Auth, ConnectionMode::WebVpn);
    let failure_envelope: RoutedJsonEnvelope<Value> =
        RoutedJsonEnvelope::resolved_failure(error.clone(), meta);
    let success_envelope = RoutedJsonEnvelope::success(
        json!({"secret": "ENVELOPE-DATA-SENTINEL"}),
        ResolvedRoutedJsonMeta::explicit(CliFeature::Auth, ConnectionMode::Direct),
    );

    let formatted = format!(
        "{request:?} {response:?} {login_input:?} {challenge:?} {profile:?} {response_wrapper:?} \
         {status:?} {cookie:?} {snapshot:?} {versioned:?} {error:?} {failure_envelope:?} \
         {success_envelope:?}"
    );

    assert_debug_redacts(
        &formatted,
        &[
            "REQUEST-SENTINEL",
            "RESPONSE-SENTINEL",
            "USERNAME-SENTINEL",
            "PASSWORD-SENTINEL",
            "CAPTCHA-SENTINEL",
            "CHALLENGE-SENTINEL",
            "EXECUTION-SENTINEL",
            "ID-TYPE-SENTINEL",
            "ID-TYPE-NAME-SENTINEL",
            "NAME-SENTINEL",
            "SCHOOL-SENTINEL",
            "PHONE-SENTINEL",
            "ID-SENTINEL",
            "EMAIL-SENTINEL",
            "COOKIE-SENTINEL",
            "COOKIE-VALUE-SENTINEL",
            "DOMAIN-SENTINEL",
            "PATH-SENTINEL",
            "ERROR-MESSAGE-SENTINEL",
            "ENVELOPE-DATA-SENTINEL",
        ],
    );
}

fn sensitive_profile() -> UserProfile {
    UserProfile {
        id_card_type: Some("ID-TYPE-SENTINEL".into()),
        id_card_type_name: Some("ID-TYPE-NAME-SENTINEL".into()),
        phone: Some("PHONE-SENTINEL".into()),
        school_id: Some("SCHOOL-SENTINEL".into()),
        name: Some("NAME-SENTINEL".into()),
        id_card_number: Some("ID-SENTINEL".into()),
        email: Some("EMAIL-SENTINEL".into()),
        username: Some("USERNAME-SENTINEL".into()),
    }
}

fn sensitive_cookie() -> StoredCookie {
    StoredCookie {
        name: "COOKIE-SENTINEL".into(),
        value: "COOKIE-VALUE-SENTINEL".into(),
        domain: "DOMAIN-SENTINEL.invalid".into(),
        host_only: true,
        path: "/PATH-SENTINEL".into(),
        secure: true,
        expires_at: Some(123),
        created_at: 456,
        max_age: Some(789),
    }
}

fn assert_debug_redacts(formatted: &str, sentinels: &[&str]) {
    for sentinel in sentinels {
        assert!(
            !formatted.contains(sentinel),
            "leaked {sentinel} in {formatted}"
        );
    }
}

#[test]
fn stable_error_codes_have_expected_exit_codes() {
    let cases = [
        (ErrorCode::InvalidInput, ExitCode::InvalidInput),
        (ErrorCode::AuthenticationRequired, ExitCode::Authentication),
        (ErrorCode::InvalidCredentials, ExitCode::Authentication),
        (
            ErrorCode::PasswordRiskConfirmationFailed,
            ExitCode::Authentication,
        ),
        (ErrorCode::CaptchaRequired, ExitCode::CaptchaRequired),
        (ErrorCode::NetworkError, ExitCode::Network),
        (ErrorCode::Timeout, ExitCode::Network),
        (ErrorCode::UpstreamChanged, ExitCode::Upstream),
        (ErrorCode::ParseError, ExitCode::Upstream),
        (ErrorCode::InternalError, ExitCode::Internal),
    ];

    for (code, expected) in cases {
        assert_eq!(code.exit_code(), expected);
    }
}

#[test]
fn error_json_envelope_never_serializes_private_captcha_state() {
    let challenge = LoginChallenge {
        id: "captcha-fixture".into(),
        execution: "e1s1-fixture".into(),
        image_data_url: None,
    };
    let error = UbaaError::new(
        ErrorCode::CaptchaRequired,
        ErrorKind::Authentication,
        true,
        "captcha input is required",
    )
    .with_challenge(challenge);

    let envelope: RoutedJsonEnvelope<Value> = RoutedJsonEnvelope::resolved_failure(
        error,
        ResolvedRoutedJsonMeta::explicit(CliFeature::Auth, ConnectionMode::WebVpn),
    );
    let value = serde_json::to_value(envelope).expect("envelope serializes");

    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "captcha_required");
    assert_eq!(value["error"]["kind"], "authentication");
    assert_eq!(value["error"]["retryable"], true);
    assert!(value["error"].get("challenge").is_none());
    assert_eq!(value["meta"]["routePolicy"], "webvpn");
    assert_eq!(value["meta"]["networkState"], "unknown");
    assert_eq!(value["meta"]["initialRoute"], "webvpn");
    assert_eq!(value["meta"]["resolvedRoute"], "webvpn");
    assert_eq!(value["meta"]["usedFallback"], false);
    assert_eq!(value["meta"]["feature"], "auth");
    assert!(value["meta"].get("connectionMode").is_none());
}

#[test]
fn aggregate_challenge_serialization_uses_the_safe_public_projection() {
    let challenge = RouteLoginChallenge {
        route: ConnectionMode::Direct,
        challenge_id: "opaque-fixture".into(),
        image_available: true,
        image_data_url: Some("data:image/jpeg;base64,PRIVATE-IMAGE".into()),
    };

    let value = serde_json::to_value(challenge).unwrap();

    assert_eq!(value["route"], "direct");
    assert_eq!(value["challengeId"], "opaque-fixture");
    assert_eq!(value["imageAvailable"], true);
    assert!(value.get("imageDataUrl").is_none());
    assert!(!value.to_string().contains("PRIVATE-IMAGE"));
}

#[test]
fn success_json_envelope_has_version_data_and_resolved_route_metadata() {
    let envelope = RoutedJsonEnvelope::success(
        json!({"name": "Fixture User"}),
        ResolvedRoutedJsonMeta::explicit(CliFeature::User, ConnectionMode::Direct),
    );
    let value = serde_json::to_value(envelope).expect("envelope serializes");

    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["name"], "Fixture User");
    assert_eq!(
        value["meta"],
        json!({
            "routePolicy": "direct",
            "networkState": "unknown",
            "initialRoute": "direct",
            "resolvedRoute": "direct",
            "usedFallback": false,
            "feature": "user"
        })
    );
    assert!(value.get("error").is_none());
}

#[test]
fn unresolved_routed_failure_has_only_feature_metadata() {
    let error = UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "missing argument",
    );
    let envelope: RoutedJsonEnvelope<Value> = RoutedJsonEnvelope::unresolved_failure(
        error,
        UnresolvedRoutedJsonMeta::new(CliFeature::Cli),
    );

    let value = serde_json::to_value(envelope).unwrap();
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], false);
    assert_eq!(value["meta"], json!({"feature": "cli"}));
    assert!(value.get("data").is_none());
    assert_eq!(value["error"]["code"], "invalid_input");
}

#[test]
fn cli_error_exposes_only_route_scoped_public_captcha_state() {
    let raw = LoginChallenge {
        id: "RAW-ID-SENTINEL".into(),
        execution: "RAW-EXECUTION-SENTINEL".into(),
        image_data_url: Some("data:image/jpeg;base64,RAW-IMAGE-SENTINEL".into()),
    };
    let public = RouteLoginChallenge {
        route: ConnectionMode::WebVpn,
        challenge_id: "opaque-public-id".into(),
        image_available: true,
        image_data_url: Some("data:image/jpeg;base64,PUBLIC-IMAGE-SENTINEL".into()),
    };
    let error = UbaaError::new(
        ErrorCode::CaptchaRequired,
        ErrorKind::Authentication,
        true,
        "captcha input is required",
    )
    .with_challenge(raw);

    let value =
        serde_json::to_value(CliJsonError::from_core(error).with_route_challenge(&public)).unwrap();
    assert_eq!(
        value["challenge"],
        json!({
            "route": "webvpn",
            "challengeId": "opaque-public-id",
            "imageAvailable": true
        })
    );
    let serialized = value.to_string();
    assert!(!serialized.contains("RAW-ID-SENTINEL"));
    assert!(!serialized.contains("RAW-EXECUTION-SENTINEL"));
    assert!(!serialized.contains("RAW-IMAGE-SENTINEL"));
    assert!(!serialized.contains("PUBLIC-IMAGE-SENTINEL"));
    assert!(!serialized.contains("execution"));
    assert!(!serialized.contains("imageDataUrl"));
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
        profile: None,
        challenges: Vec::new(),
    };
    let value = serde_json::to_value(
        AggregateJsonEnvelope::auth_success(valid, RoutePolicy::Auto).unwrap(),
    )
    .unwrap();

    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], true);
    assert_eq!(
        value["data"]["routes"],
        json!([
            {"route": "direct", "state": "ready"},
            {"route": "webvpn", "state": "ready"}
        ])
    );
    assert_eq!(
        value["meta"],
        json!({
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
        challenges: Vec::new(),
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
        challenges: Vec::new(),
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
        json!({
            "loggedOut": true,
            "routes": [
                {"route": "direct", "state": "logged_out"},
                {"route": "webvpn", "state": "logged_out"}
            ]
        })
    );
    assert_eq!(
        logout["meta"]["resolvedRoutes"],
        json!(["direct", "webvpn"])
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
        challenges: Vec::new(),
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
        challenges: Vec::new(),
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
fn cli_json_schema_contains_no_v1_or_legacy_route_contract() {
    let schema = include_str!("../../../docs/contracts/cli-json.schema.json");

    assert!(!schema.contains("\"const\": 1"));
    assert!(!schema.contains("connectionMode"));
    assert!(!schema.contains("legacyError"));
}
