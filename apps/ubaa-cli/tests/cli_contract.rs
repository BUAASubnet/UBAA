use std::io::Cursor;

use async_trait::async_trait;
use clap::{CommandFactory, Parser};
use ubaa_cli::{
    Cli, CliBackend, ReadonlyRouteContext, RoutedCliBackend, run_dual_login, run_with_backend,
    run_with_backend_with_route, run_with_routed_backend,
};
use ubaa_core::config::RouteConfig;
use ubaa_core::connection::{
    GatewayProbe, NetworkState, RouteDiagnostic, RouteResolution, to_webvpn_url,
};
use ubaa_core::domain::{
    AuthStatus, ConnectionMode, FeatureResult, LoginChallenge, LoginInput, LoginOutcome,
    LoginReadiness, RouteLoginResult, RouteLoginState, RoutePolicy, SafeError,
    SpocAssignmentDetail, Term, UserProfile,
};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::facade::{Routed, RoutedError, RoutedResult, UbaaClient};
use ubaa_core::output::{
    AggregateJsonEnvelope, CliFeature, ResolvedRoutedJsonMeta, RoutedJsonEnvelope,
    UnresolvedRoutedJsonMeta,
};
use ubaa_core::ports::{HttpMethod, HttpResponse};
use ubaa_core::session::FileSessionStore;
use ubaa_test_support::{ExpectedRequest, MockTransport};

struct OffCampusProbe;

impl GatewayProbe for OffCampusProbe {
    fn probe(&self, _budget: std::time::Duration) -> NetworkState {
        NetworkState::OffCampus
    }
}

fn assert_cli_schema(value: &serde_json::Value) {
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json")).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    assert!(validator.is_valid(value), "invalid CLI envelope: {value}");
}

fn assert_safe_aggregate_challenges(value: &serde_json::Value) {
    let challenges = value["data"]["challenges"].as_array().unwrap();
    assert_eq!(challenges.len(), 2);
    assert_eq!(value["error"]["challenge"], challenges[0]);
    assert_ne!(challenges[0]["challengeId"], challenges[1]["challengeId"]);
    assert!(challenges.iter().all(|challenge| {
        challenge["imageAvailable"] == true
            && challenge.get("imageDataUrl").is_none()
            && challenge.get("execution").is_none()
    }));
}

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
    assert_cli_schema(&value);
    assert_eq!(value["ok"], true);
    assert_eq!(value["schemaVersion"], 2);
    assert_eq!(value["meta"]["feature"], "auth");
    assert_eq!(value["meta"]["routePolicy"], "direct");
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
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "captcha_required");
    assert_eq!(value["error"]["challenge"]["route"], "direct");
    assert_eq!(value["error"]["challenge"]["imageAvailable"], true);
    assert!(
        value["error"]["challenge"]["challengeId"]
            .as_str()
            .unwrap()
            .starts_with("cli-")
    );
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
    let config =
        RouteConfig::parse("schema_version = 1\n\n[route]\ndefault = \"direct\"\n").unwrap();
    let mut backend = UbaaClient::with_routing(
        direct,
        webvpn,
        FileSessionStore::new(&root).unwrap(),
        config,
        OffCampusProbe,
    )
    .unwrap();
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
    assert_cli_schema(&value);
    assert_eq!(value["meta"]["routePolicy"], "direct");
    assert_eq!(
        value["meta"]["resolvedRoutes"],
        serde_json::json!(["direct", "webvpn"])
    );
    assert_safe_aggregate_challenges(&value);
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
fn login_without_diagnostic_mode_uses_aggregate_path() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "auth",
        "login",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    assert_eq!(cli.login_mode(), None);
}

#[test]
fn serialized_envelopes_match_the_cli_json_schema() {
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json")).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let direct_resolution = route_resolution(
        RoutePolicy::Direct,
        NetworkState::Unknown,
        ConnectionMode::Direct,
    );
    let success = RoutedJsonEnvelope::success(
        profile(),
        ResolvedRoutedJsonMeta::from_resolution(CliFeature::User, direct_resolution),
    );
    let failure = RoutedJsonEnvelope::<serde_json::Value>::resolved_failure(
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
        ResolvedRoutedJsonMeta::from_resolution(CliFeature::Auth, direct_resolution),
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
        profile: None,
        challenges: Vec::new(),
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

    let success = serde_json::to_value(success).unwrap();
    let failure = serde_json::to_value(failure).unwrap();
    assert_eq!(success["data"]["schoolId"], "TEST-0001");
    assert_eq!(failure["error"]["code"], "captcha_required");
    assert!(failure["error"].get("challenge").is_none());
}

fn assert_all_routed_features_validate(
    validator: &jsonschema::Validator,
    resolution: RouteResolution,
) {
    for feature in [
        CliFeature::Auth,
        CliFeature::User,
        CliFeature::Schedule,
        CliFeature::Exam,
        CliFeature::Grades,
        CliFeature::Classroom,
        CliFeature::Spoc,
        CliFeature::Judge,
    ] {
        let envelope = RoutedJsonEnvelope::success(
            serde_json::json!({}),
            ResolvedRoutedJsonMeta::from_resolution(feature, resolution),
        );
        assert!(validator.is_valid(&serde_json::to_value(envelope).unwrap()));
    }
}

fn assert_schema_rejects_invalid_envelopes(
    validator: &jsonschema::Validator,
    success: &serde_json::Value,
    failure: &serde_json::Value,
    unresolved: &serde_json::Value,
    aggregate: &serde_json::Value,
) {
    let mut schema_v1 = unresolved.clone();
    schema_v1["schemaVersion"] = serde_json::json!(1);
    assert!(!validator.is_valid(&schema_v1));

    let mut invented_route = unresolved.clone();
    invented_route["meta"]["resolvedRoute"] = serde_json::json!("direct");
    assert!(!validator.is_valid(&invented_route));

    let mut one_route = aggregate.clone();
    one_route["data"]["routes"].as_array_mut().unwrap().pop();
    assert!(!validator.is_valid(&one_route));

    let mut three_routes = aggregate.clone();
    let extra_route = three_routes["data"]["routes"][1].clone();
    three_routes["data"]["routes"]
        .as_array_mut()
        .unwrap()
        .push(extra_route);
    assert!(!validator.is_valid(&three_routes));

    let mut reversed_routes = aggregate.clone();
    reversed_routes["data"]["routes"]
        .as_array_mut()
        .unwrap()
        .swap(0, 1);
    assert!(!validator.is_valid(&reversed_routes));

    let mut duplicate_routes = aggregate.clone();
    duplicate_routes["data"]["routes"][1]["route"] = serde_json::json!("direct");
    assert!(!validator.is_valid(&duplicate_routes));

    let mut mixed_route_meta = aggregate.clone();
    mixed_route_meta["meta"]["resolvedRoute"] = serde_json::json!("direct");
    assert!(!validator.is_valid(&mixed_route_meta));

    let mut legacy_mode = unresolved.clone();
    legacy_mode["meta"]["connectionMode"] = serde_json::json!("direct");
    assert!(!validator.is_valid(&legacy_mode));

    let mut leaked_challenge = failure.clone();
    leaked_challenge["error"]["challenge"] = serde_json::json!({
        "route": "direct",
        "challengeId": "opaque",
        "imageAvailable": true,
        "execution": "forbidden"
    });
    assert!(!validator.is_valid(&leaked_challenge));
    leaked_challenge["error"]["challenge"] = serde_json::json!({
        "route": "direct",
        "challengeId": "opaque",
        "imageAvailable": true,
        "imageDataUrl": "forbidden"
    });
    assert!(!validator.is_valid(&leaked_challenge));

    let mut success_with_error = success.clone();
    success_with_error["error"] = failure["error"].clone();
    assert!(!validator.is_valid(&success_with_error));

    let mut failure_with_data = failure.clone();
    failure_with_data["data"] = serde_json::json!({});
    assert!(!validator.is_valid(&failure_with_data));
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
