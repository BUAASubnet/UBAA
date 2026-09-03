use serde_json::json;
use ubaa_core::facade::testing::{
    HttpRequest, HttpResponse, SessionSnapshot, StoredCookie, VersionedSession,
};
use ubaa_core::facade::{
    AuthStatus, CgyyReservationSubmitRequest, ConnectionMode, DualLoginPreparation, ErrorCode,
    ErrorKind, LoginInput, LoginOutcome, LoginReadiness, RouteLoginResult, RouteLoginState,
    SecretValue, UbaaError, UserInfoResponse, UserProfile,
};

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
    };
    let preparation = DualLoginPreparation { routes };

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
        "routes": [{"route": "direct", "state": "ready"}]
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
    );
    let response_wrapper = UserInfoResponse {
        code: 0,
        data: Some(profile.clone()),
    };
    let status = AuthStatus {
        user: profile.clone(),
        authenticated_at: 333,
        last_activity: 444,
    };
    let formatted = format!(
        "{request:?} {response:?} {login_input:?} {profile:?} {response_wrapper:?} \
         {status:?} {cookie:?} {snapshot:?} {versioned:?} {error:?}"
    );

    assert_debug_redacts(
        &formatted,
        &[
            "REQUEST-SENTINEL",
            "RESPONSE-SENTINEL",
            "USERNAME-SENTINEL",
            "PASSWORD-SENTINEL",
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
        ],
    );
}

#[test]
fn 场馆预约请求调试输出隐藏验证码材料() {
    let request = CgyyReservationSubmitRequest::default().with_captcha_material(
        "VERIFICATION-SENTINEL",
        "POINT-SENTINEL",
        "TOKEN-SENTINEL",
    );
    let debug = format!("{request:?}");
    assert!(!debug.contains("SENTINEL"));
    assert!(debug.contains("<redacted>"));
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
