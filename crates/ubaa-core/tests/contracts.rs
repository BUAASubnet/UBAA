use serde_json::{Value, json};
use ubaa_core::domain::{
    ConnectionMode, LoginChallenge, SecretValue, UserInfoResponse, UserProfile,
};
use ubaa_core::error::{ErrorCode, ErrorKind, ExitCode, UbaaError};
use ubaa_core::output::JsonEnvelope;

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
fn stable_error_codes_have_expected_exit_codes() {
    let cases = [
        (ErrorCode::InvalidInput, ExitCode::InvalidInput),
        (ErrorCode::AuthenticationRequired, ExitCode::Authentication),
        (ErrorCode::InvalidCredentials, ExitCode::Authentication),
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
fn error_json_envelope_is_stable_and_carries_captcha_challenge() {
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
    assert_eq!(value["error"]["challenge"]["id"], "captcha-fixture");
    assert_eq!(value["meta"]["connectionMode"], "webvpn");
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
