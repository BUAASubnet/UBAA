use std::io::Cursor;

use async_trait::async_trait;
use clap::{CommandFactory, Parser};
use ubaa_cli::{
    Cli, CliBackend, ReadonlyRouteContext, RoutedCliBackend, run_dual_login, run_with_backend,
    run_with_backend_with_route, run_with_routed_backend,
};
use ubaa_core::connection::{NetworkState, RouteDiagnostic, RouteResolution, to_webvpn_url};
use ubaa_core::domain::{
    AuthStatus, ConnectionMode, FeatureResult, LoginChallenge, LoginInput, RoutePolicy, Term,
    UserProfile,
};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::facade::{Routed, RoutedError, RoutedResult, UbaaClient};
use ubaa_core::output::{
    AggregateJsonEnvelope, AggregateJsonMeta, JsonEnvelope, ReadonlyJsonEnvelope, ReadonlyJsonMeta,
};
use ubaa_core::ports::{HttpMethod, HttpResponse};
use ubaa_core::session::FileSessionStore;
use ubaa_test_support::{ExpectedRequest, MockTransport};

#[derive(Default)]
struct FakeBackend {
    challenge: Option<LoginChallenge>,
    login_calls: usize,
    schedule_success: bool,
}

#[derive(Default)]
struct FakeRoutedBackend {
    fail_schedule: bool,
}

#[async_trait]
impl RoutedCliBackend for FakeRoutedBackend {
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        Ok(Routed {
            data: profile(),
            resolution: route_resolution(
                RoutePolicy::WebVpn,
                NetworkState::Unknown,
                ConnectionMode::WebVpn,
            ),
        })
    }

    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        let resolution = route_resolution(
            RoutePolicy::Direct,
            NetworkState::Unknown,
            ConnectionMode::Direct,
        );
        if self.fail_schedule {
            Err(RoutedError {
                error: UbaaError::new(
                    ErrorCode::AuthenticationRequired,
                    ErrorKind::Authentication,
                    false,
                    "fixture schedule authentication required",
                ),
                resolution: Some(resolution),
            })
        } else {
            Ok(Routed {
                data: Vec::new(),
                resolution,
            })
        }
    }
}

#[async_trait]
impl CliBackend for FakeBackend {
    fn mode(&self) -> ConnectionMode {
        ConnectionMode::Direct
    }

    async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>> {
        Ok(self.challenge.clone())
    }

    async fn login(&mut self, _input: LoginInput) -> Result<UserProfile> {
        self.login_calls += 1;
        Ok(profile())
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        Ok(AuthStatus {
            user: profile(),
            authenticated_at: 100,
            last_activity: 101,
        })
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        Ok(profile())
    }

    async fn logout(&mut self) -> Result<()> {
        Ok(())
    }

    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        if self.schedule_success {
            return Ok(FeatureResult {
                data: Vec::new(),
                resolved_route: ConnectionMode::Direct,
            });
        }
        Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "fixture schedule authentication required",
        ))
    }
}

fn profile() -> UserProfile {
    UserProfile {
        name: Some("Fixture User".into()),
        school_id: Some("TEST-0001".into()),
        username: Some("fixture-user".into()),
        phone: Some("PHONE-FIXTURE-VALUE".into()),
        id_card_number: Some("TEST-ID-0001".into()),
        ..UserProfile::default()
    }
}

fn route_resolution(
    policy: RoutePolicy,
    network: NetworkState,
    route: ConnectionMode,
) -> RouteResolution {
    RouteResolution {
        mode: route,
        policy,
        diagnostic: RouteDiagnostic::new(network, route),
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
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["schoolId"], "TEST-0001");
    assert_ne!(value["data"]["phone"], "PHONE-FIXTURE-VALUE");
    assert_ne!(value["data"]["idCardNumber"], "TEST-ID-0001");
    assert!(!String::from_utf8_lossy(&stdout).contains("fixture-password"));
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn json_captcha_returns_exit_four_without_image_or_login_submission() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend {
        challenge: Some(LoginChallenge {
            id: "captcha-fixture".into(),
            execution: "e-cap".into(),
            image_data_url: Some("data:image/jpeg;base64,DO-NOT-PRINT".into()),
        }),
        login_calls: 0,
        schedule_success: false,
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 4);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["error"]["code"], "captcha_required");
    assert!(value["error"].get("challenge").is_none());
    let serialized = String::from_utf8_lossy(&stdout);
    assert!(!serialized.contains("captcha-fixture"));
    assert!(!serialized.contains("e-cap"));
    assert!(!serialized.contains("DO-NOT-PRINT"));
    assert_eq!(backend.login_calls, 0);
}

#[tokio::test]
async fn aggregate_json_captcha_exposes_only_actionable_safe_challenges() {
    let direct_login = "https://sso.buaa.edu.cn/login";
    let direct_captcha = "https://sso.buaa.edu.cn/captcha?captchaId=shared-upstream-id";
    let webvpn_login = to_webvpn_url(direct_login).unwrap();
    let webvpn_captcha = to_webvpn_url(direct_captcha).unwrap();
    let page = |execution: &str| {
        format!(
            r#"<form id="fm1"><input name="execution" value="{execution}"></form><script>config.captcha = {{ type: 'image', id: 'shared-upstream-id' }}</script>"#
        )
    };
    let direct = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_login,
            HttpResponse::new(200, direct_login, page("direct-execution").into_bytes()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            direct_captcha,
            HttpResponse::new(200, direct_captcha, b"DIRECT-PRIVATE-IMAGE".to_vec()),
        ),
    ]);
    let webvpn = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_login,
            HttpResponse::new(200, &webvpn_login, page("webvpn-execution").into_bytes()),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            &webvpn_captcha,
            HttpResponse::new(200, &webvpn_captcha, b"WEBVPN-PRIVATE-IMAGE".to_vec()),
        ),
    ]);
    let direct_observer = direct.clone();
    let webvpn_observer = webvpn.clone();
    let root =
        std::env::temp_dir().join(format!("ubaa-cli-aggregate-captcha-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let mut backend =
        UbaaClient::with_transports(direct, webvpn, FileSessionStore::new(&root).unwrap()).unwrap();
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "--config-dir",
        root.to_str().unwrap(),
        "auth",
        "login",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_dual_login(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 4);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    let challenges = value["data"]["challenges"].as_array().unwrap();
    assert_eq!(challenges.len(), 2);
    assert_ne!(challenges[0]["challengeId"], challenges[1]["challengeId"]);
    assert!(challenges.iter().all(|challenge| {
        challenge["imageAvailable"] == true
            && challenge.get("imageDataUrl").is_none()
            && challenge.get("execution").is_none()
    }));
    let serialized = String::from_utf8(stdout).unwrap();
    for private in [
        "shared-upstream-id",
        "direct-execution",
        "webvpn-execution",
        "PRIVATE-IMAGE",
        "fixture-password",
    ] {
        assert!(!serialized.contains(private));
    }
    assert_eq!(direct_observer.requests().unwrap().len(), 2);
    assert_eq!(webvpn_observer.requests().unwrap().len(), 2);
    direct_observer.assert_exhausted().unwrap();
    webvpn_observer.assert_exhausted().unwrap();
    assert!(stderr.is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn human_captcha_stays_in_process_until_non_empty_input() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    let mut backend = FakeBackend {
        challenge: Some(LoginChallenge {
            id: "captcha-fixture".into(),
            execution: "e-cap".into(),
            image_data_url: Some("data:image/jpeg;base64,RklYVFVSRS1JTUFHRQ==".into()),
        }),
        login_calls: 0,
        schedule_success: false,
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(b"fixture-password\n\ncaptcha-fixture-answer\n"),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 0);
    assert_eq!(backend.login_calls, 1);
    assert!(String::from_utf8(stderr).unwrap().contains("Captcha: "));
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
async fn readonly_route_errors_use_schema_v2_diagnostics() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "schedule", "terms"]).unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend_with_route(
        cli,
        &mut backend,
        explicit_direct_route_context(),
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 3);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], false);
    assert_eq!(value["meta"]["feature"], "schedule");
    assert_eq!(value["meta"]["routePolicy"], "direct");
    assert_eq!(value["meta"]["networkState"], "unknown");
    assert_eq!(value["meta"]["initialRoute"], "direct");
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert_eq!(value["meta"]["usedFallback"], false);
    assert_eq!(value["error"]["code"], "authentication_required");
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn readonly_route_success_uses_explicit_policy_and_diagnostics() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "schedule", "terms"]).unwrap();
    let mut backend = FakeBackend {
        schedule_success: true,
        ..FakeBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_backend_with_route(
        cli,
        &mut backend,
        explicit_direct_route_context(),
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], true);
    assert_eq!(value["meta"]["feature"], "schedule");
    assert_eq!(value["meta"]["routePolicy"], "direct");
    assert_eq!(value["meta"]["networkState"], "unknown");
    assert_eq!(value["meta"]["initialRoute"], "direct");
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert_eq!(value["meta"]["usedFallback"], false);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn routed_user_success_preserves_core_default_route_diagnostics() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "user", "show"]).unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], true);
    assert_eq!(value["meta"]["feature"], "user");
    assert_eq!(value["meta"]["routePolicy"], "webvpn");
    assert_eq!(value["meta"]["initialRoute"], "webvpn");
    assert_eq!(value["meta"]["resolvedRoute"], "webvpn");
    assert_ne!(value["data"]["phone"], "PHONE-FIXTURE-VALUE");
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn routed_feature_error_preserves_post_resolution_core_diagnostics() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "schedule", "terms"]).unwrap();
    let mut backend = FakeRoutedBackend {
        fail_schedule: true,
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 3);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["ok"], false);
    assert_eq!(value["meta"]["feature"], "schedule");
    assert_eq!(value["meta"]["routePolicy"], "direct");
    assert_eq!(value["meta"]["networkState"], "unknown");
    assert_eq!(value["meta"]["initialRoute"], "direct");
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert_eq!(value["meta"]["usedFallback"], false);
    assert_eq!(value["error"]["code"], "authentication_required");
    assert!(stderr.is_empty());
}

fn explicit_direct_route_context() -> ReadonlyRouteContext {
    ReadonlyRouteContext {
        policy: RoutePolicy::Direct,
        network: NetworkState::Unknown,
        initial_route: ConnectionMode::Direct,
        resolved_route: ConnectionMode::Direct,
        used_fallback: false,
    }
}

#[test]
fn clap_has_no_plaintext_password_option() {
    let error = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--password",
        "forbidden",
    ])
    .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("unexpected argument '--password'")
    );
}

#[test]
fn ordinary_help_hides_route_override_and_lists_readonly_groups() {
    let help = Cli::command().render_long_help().to_string();
    assert!(!help.contains("--mode"));
    for command in ["schedule", "exam", "grades", "classroom", "spoc", "judge"] {
        assert!(
            help.contains(command),
            "missing {command} from top-level help"
        );
    }
}

#[test]
fn login_can_reuse_a_saved_connection_mode() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    assert_eq!(
        cli.resolve_mode(Some(ConnectionMode::WebVpn)).unwrap(),
        ConnectionMode::WebVpn
    );

    let error = cli.resolve_mode(None).unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidInput);
}

#[test]
fn serialized_envelopes_match_the_cli_json_schema() {
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json")).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let success = JsonEnvelope::success(profile(), ConnectionMode::Direct);
    let failure: JsonEnvelope<serde_json::Value> = JsonEnvelope::failure(
        UbaaError::new(
            ErrorCode::CaptchaRequired,
            ErrorKind::Authentication,
            true,
            "captcha required",
        )
        .with_challenge(LoginChallenge {
            id: "fixture".into(),
            execution: "e-cap".into(),
            image_data_url: None,
        }),
        Some(ConnectionMode::WebVpn),
    );
    let success_bytes = serde_json::to_vec(&success).unwrap();
    let failure_bytes = serde_json::to_vec(&failure).unwrap();
    let success: serde_json::Value = serde_json::from_slice(&success_bytes).unwrap();
    let failure: serde_json::Value = serde_json::from_slice(&failure_bytes).unwrap();
    let aggregate = serde_json::to_value(AggregateJsonEnvelope {
        schema_version: 2,
        ok: true,
        data: serde_json::json!({
            "readiness": "partial",
            "routes": [
                { "route": "direct", "state": "ready" },
                { "route": "webvpn", "state": "failed" }
            ],
            "profile": null,
            "challenges": []
        }),
        error: None,
        meta: AggregateJsonMeta {
            route_policy: RoutePolicy::Auto,
            resolved_routes: vec![ConnectionMode::Direct],
            feature: "auth".into(),
        },
    })
    .unwrap();
    let readonly = serde_json::to_value(ReadonlyJsonEnvelope::success(
        serde_json::json!([]),
        ReadonlyJsonMeta {
            route_policy: RoutePolicy::Direct,
            network_state: NetworkState::Unknown,
            initial_route: ConnectionMode::Direct,
            resolved_route: ConnectionMode::Direct,
            used_fallback: false,
            feature: "schedule".into(),
        },
    ))
    .unwrap();
    let mut readonly_missing_network = readonly.clone();
    readonly_missing_network["meta"]
        .as_object_mut()
        .unwrap()
        .remove("networkState");

    assert!(validator.is_valid(&success));
    assert!(validator.is_valid(&failure));
    assert!(validator.is_valid(&aggregate));
    assert!(validator.is_valid(&readonly));
    assert!(!validator.is_valid(&readonly_missing_network));
    assert_eq!(success["data"]["schoolId"], "TEST-0001");
    assert_eq!(failure["error"]["code"], "captcha_required");
}

#[test]
fn error_fixture_uses_stable_code_and_exit_mapping() {
    let error = UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "fixture",
    );
    assert_eq!(error.code.exit_code() as i32, 3);
}

#[test]
fn cli_debug_formatting_redacts_sensitive_login_arguments() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "USERNAME-SENTINEL",
        "--password-stdin",
        "--captcha",
        "CAPTCHA-SENTINEL",
    ])
    .unwrap();

    let formatted = format!("{cli:?}");
    for sentinel in ["USERNAME-SENTINEL", "CAPTCHA-SENTINEL"] {
        assert!(
            !formatted.contains(sentinel),
            "leaked {sentinel} in {formatted}"
        );
    }
}
