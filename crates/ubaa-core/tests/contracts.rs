use serde_json::{Value, json};
use ubaa_core::domain::{
    AuthStatus, ConnectionMode, LoginChallenge, LoginInput, RouteLoginChallenge, SecretValue,
    UserInfoResponse, UserProfile,
};
use ubaa_core::error::{ErrorCode, ErrorKind, ExitCode, UbaaError};
use ubaa_core::output::JsonEnvelope;
use ubaa_core::ports::{HttpRequest, HttpResponse};
use ubaa_core::session::{SessionSnapshot, StoredCookie, VersionedSession};

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
    let failure_envelope: JsonEnvelope<Value> =
        JsonEnvelope::failure(error.clone(), Some(ConnectionMode::WebVpn));
    let success_envelope = JsonEnvelope::success(
        json!({"secret": "ENVELOPE-DATA-SENTINEL"}),
        ConnectionMode::Direct,
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

    let envelope: JsonEnvelope<Value> = JsonEnvelope::failure(error, Some(ConnectionMode::WebVpn));
    let value = serde_json::to_value(envelope).expect("envelope serializes");

    assert_eq!(value["schemaVersion"], 1);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "captcha_required");
    assert_eq!(value["error"]["kind"], "authentication");
    assert_eq!(value["error"]["retryable"], true);
    assert!(value["error"].get("challenge").is_none());
    assert_eq!(value["meta"]["connectionMode"], "webvpn");
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
fn success_json_envelope_has_version_data_and_mode() {
    let envelope = JsonEnvelope::success(json!({"name": "Fixture User"}), ConnectionMode::Direct);
    let value = serde_json::to_value(envelope).expect("envelope serializes");

    assert_eq!(value["schemaVersion"], 1);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["name"], "Fixture User");
    assert_eq!(value["meta"]["connectionMode"], "direct");
    assert!(value.get("error").is_none());
}
