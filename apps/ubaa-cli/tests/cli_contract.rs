use std::io::Cursor;

use async_trait::async_trait;
use clap::{CommandFactory, Parser};
use ubaa_cli::{
    BykcCommand, Cli, CliBackend, Command, ReadonlyRouteContext, RoutedCliBackend,
    run_with_backend, run_with_backend_with_route, run_with_routed_backend,
};
use ubaa_core::connection::{NetworkState, RouteDiagnostic, RouteResolution};
use ubaa_core::domain::{
    AuthStatus, BykcChosenCourse, BykcCourse, BykcSignConfig, BykcSignPoint, BykcUserProfile,
    CgyyActionResult, ClassroomInfo, ClassroomQuery, ConnectionMode, CourseClass, Exam,
    ExamArrangement, FeatureResult, Grade, GradeData, JudgeAssignmentDetail,
    JudgeAssignmentSummary, JudgeAssignmentsDiagnostics, JudgeProblem, LoginInput, LoginOutcome,
    LoginReadiness, RouteLoginResult, RouteLoginState, RoutePolicy, SafeError,
    SpocAssignmentDetail, SpocAssignmentSummary, SpocAssignments, SpocAssignmentsDiagnostics, Term,
    TodayClass, UserProfile, Week, WeeklySchedule,
};
use ubaa_core::error::{ErrorCode, ErrorKind, Result, UbaaError};
use ubaa_core::facade::{Routed, RoutedError, RoutedResult};
use ubaa_core::output::{
    AggregateJsonEnvelope, CliFeature, ResolvedRoutedJsonMeta, RoutedJsonEnvelope,
    UnresolvedRoutedJsonMeta,
};

fn assert_cli_schema(value: &serde_json::Value) {
    let schema: serde_json::Value =
        serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json")).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    assert!(validator.is_valid(value), "invalid CLI envelope: {value}");
}

#[test]
fn 博雅课程命令可显式包含已结束课程() {
    let cli = Cli::try_parse_from(["ubaa", "bykc", "courses", "--all"]).unwrap();

    assert!(matches!(
        cli.command,
        Command::Bykc(arguments)
            if matches!(arguments.command, BykcCommand::Courses { all: true, .. })
    ));
}

#[tokio::test]
async fn 场馆取消默认拒绝且不调用后端() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "cgyy", "cancel", "--id", "42"]).unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 2);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(value["meta"]["feature"], "cgyy");
    assert!(value["meta"].get("resolvedRoute").is_none());
    assert_eq!(backend.cgyy_cancel_calls, 0);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 场馆取消显式确认后才调用后端() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "cgyy",
        "cancel",
        "--id",
        "42",
        "--confirm-write",
    ])
    .unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["message"], "fixture cancellation");
    assert_eq!(value["meta"]["feature"], "cgyy");
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert_eq!(backend.cgyy_cancel_calls, 1);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 评教提交默认拒绝且不读取后端() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "evaluation",
        "submit",
        "--payload",
        "/tmp/不存在的评教文件.json",
    ])
    .unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 2);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert!(stderr.is_empty());
}

#[derive(Default)]
struct FakeBackend {
    login_calls: usize,
    schedule_success: bool,
}

#[derive(Default)]
struct FakeRoutedBackend {
    fail_schedule: bool,
    cgyy_cancel_calls: usize,
}

#[async_trait]
impl RoutedCliBackend for FakeRoutedBackend {
    async fn cgyy_cancel_order(&mut self, _id: i32) -> RoutedResult<CgyyActionResult> {
        self.cgyy_cancel_calls += 1;
        Ok(Routed {
            data: CgyyActionResult {
                message: "fixture cancellation".into(),
                order: None,
            },
            resolution: route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        })
    }

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

    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        Ok(Routed {
            data: JudgeAssignmentsDiagnostics {
                course_count: 3,
                raw_anchor_count: 7,
                filtered_unique_count: 2,
                summaries: Vec::new(),
            },
            resolution: route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        })
    }

    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        Ok(Routed {
            data: SpocAssignmentsDiagnostics {
                global_page_count: 2,
                result: SpocAssignments {
                    term_code: "2025-2026-2".into(),
                    term_name: Some("Spring".into()),
                    assignments: Vec::new(),
                },
            },
            resolution: route_resolution(
                RoutePolicy::Direct,
                NetworkState::Unknown,
                ConnectionMode::Direct,
            ),
        })
    }
}

#[async_trait]
impl CliBackend for FakeBackend {
    fn mode(&self) -> ConnectionMode {
        ConnectionMode::Direct
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

fn masked_profile() -> UserProfile {
    UserProfile {
        phone: Some("PH***NE".into()),
        id_card_number: Some("ID***ER".into()),
        ..profile()
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
#[allow(clippy::too_many_lines)]
fn 扩展只读命令全部要求已有会话并映射正确功能() {
    let cases = [
        (vec!["ubaa", "signin", "today"], CliFeature::Signin),
        (
            vec!["ubaa", "libbook", "libraries", "--day", "2026-08-27"],
            CliFeature::LibBook,
        ),
        (
            vec![
                "ubaa",
                "libbook",
                "areas",
                "--premises-id",
                "9",
                "--storey-id",
                "10",
                "--day",
                "2026-08-27",
            ],
            CliFeature::LibBook,
        ),
        (
            vec!["ubaa", "libbook", "area-detail", "--area-id", "8"],
            CliFeature::LibBook,
        ),
        (
            vec![
                "ubaa",
                "libbook",
                "seats",
                "--area-id",
                "8",
                "--day",
                "2026-08-27",
                "--start-time",
                "08:00",
                "--end-time",
                "10:00",
            ],
            CliFeature::LibBook,
        ),
        (
            vec![
                "ubaa", "libbook", "bookings", "--page", "1", "--limit", "20",
            ],
            CliFeature::LibBook,
        ),
        (vec!["ubaa", "ygdk", "overview"], CliFeature::Ygdk),
        (
            vec!["ubaa", "ygdk", "records", "--page", "1", "--size", "20"],
            CliFeature::Ygdk,
        ),
        (vec!["ubaa", "bykc", "profile"], CliFeature::Bykc),
        (
            vec!["ubaa", "bykc", "courses", "--page", "1", "--size", "20"],
            CliFeature::Bykc,
        ),
        (
            vec!["ubaa", "bykc", "course", "--id", "1"],
            CliFeature::Bykc,
        ),
        (vec!["ubaa", "bykc", "chosen"], CliFeature::Bykc),
        (vec!["ubaa", "bykc", "statistics"], CliFeature::Bykc),
        (vec!["ubaa", "cgyy", "sites"], CliFeature::Cgyy),
        (vec!["ubaa", "cgyy", "purposes"], CliFeature::Cgyy),
        (
            vec![
                "ubaa",
                "cgyy",
                "day",
                "--site-id",
                "1",
                "--date",
                "2026-08-27",
            ],
            CliFeature::Cgyy,
        ),
        (
            vec!["ubaa", "cgyy", "orders", "--page", "0", "--size", "10"],
            CliFeature::Cgyy,
        ),
        (
            vec!["ubaa", "cgyy", "detail", "--id", "1"],
            CliFeature::Cgyy,
        ),
    ];

    for (arguments, feature) in cases {
        let cli = Cli::try_parse_from(arguments.clone())
            .unwrap_or_else(|error| panic!("命令解析失败 {arguments:?}: {error}"));
        assert!(cli.requires_session(), "命令未要求会话: {arguments:?}");
        assert_eq!(cli.feature(), feature, "功能映射错误: {arguments:?}");
    }
}

#[tokio::test]
async fn routed_feature_error_preserves_post_resolution_core_diagnostics() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "schedule", "terms"]).unwrap();
    let mut backend = FakeRoutedBackend {
        fail_schedule: true,
        cgyy_cancel_calls: 0,
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
    let mut command = Cli::command();
    let help = command.render_long_help().to_string();
    assert!(help.contains("北航统一认证命令行客户端"));
    assert!(help.contains("认证并管理持久化会话"));
    assert!(!help.contains("BUAA unified authentication client"));
    assert!(!help.contains("--mode"));
    for command in ["schedule", "exam", "grades", "classroom", "spoc", "judge"] {
        assert!(
            help.contains(command),
            "missing {command} from top-level help"
        );
    }
    for group in ["spoc", "judge"] {
        let help = command
            .find_subcommand_mut(group)
            .expect("read-only group")
            .render_long_help()
            .to_string();
        assert!(
            !help.contains("diagnostics"),
            "diagnostic command leaked into ordinary {group} help"
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

fn assert_all_routed_features_validate(
    validator: &jsonschema::Validator,
    resolution: RouteResolution,
) {
    for (feature, data) in routed_success_representatives() {
        let envelope = RoutedJsonEnvelope::success(
            data,
            ResolvedRoutedJsonMeta::from_resolution(feature, resolution),
        );
        let value = serde_json::to_value(envelope).unwrap();
        assert!(
            validator.is_valid(&value),
            "schema rejected {feature:?} representative: {value}"
        );
    }
}

fn routed_success_representatives() -> Vec<(CliFeature, serde_json::Value)> {
    let mut representatives = routed_primary_success_representatives();
    representatives.extend(routed_assignment_success_representatives());
    representatives
}

#[allow(clippy::too_many_lines)]
fn routed_primary_success_representatives() -> Vec<(CliFeature, serde_json::Value)> {
    let profile = masked_profile();

    vec![
        (CliFeature::Auth, serde_json::to_value(&profile).unwrap()),
        (
            CliFeature::Auth,
            serde_json::to_value(AuthStatus {
                user: profile.clone(),
                authenticated_at: 1,
                last_activity: 2,
            })
            .unwrap(),
        ),
        (CliFeature::Auth, serde_json::json!({"loggedOut": true})),
        (CliFeature::User, serde_json::to_value(profile).unwrap()),
        (
            CliFeature::Schedule,
            serde_json::to_value(vec![Term {
                item_code: "2025-2026-1".into(),
                item_name: "Term".into(),
                selected: true,
                item_index: 1,
            }])
            .unwrap(),
        ),
        (
            CliFeature::Schedule,
            serde_json::to_value(vec![Week {
                start_date: "2025-09-01".into(),
                end_date: "2025-09-07".into(),
                term: "2025-2026-1".into(),
                cur_week: true,
                serial_number: 1,
                name: "Week 1".into(),
            }])
            .unwrap(),
        ),
        (
            CliFeature::Schedule,
            serde_json::to_value(WeeklySchedule {
                arranged_list: vec![CourseClass::default()],
                code: "2025-2026-1".into(),
                name: "Term".into(),
            })
            .unwrap(),
        ),
        (
            CliFeature::Schedule,
            serde_json::to_value(vec![TodayClass::default()]).unwrap(),
        ),
        (
            CliFeature::Exam,
            serde_json::to_value(ExamArrangement {
                arranged: vec![Exam::default()],
                not_arranged: Vec::new(),
            })
            .unwrap(),
        ),
        (
            CliFeature::Grades,
            serde_json::to_value(GradeData {
                term_code: "2025-2026-1".into(),
                grades: vec![Grade {
                    term_code: Some("2025-2026-1".into()),
                    ..Grade::default()
                }],
            })
            .unwrap(),
        ),
        (
            CliFeature::Grades,
            serde_json::to_value(GradeData {
                term_code: "2025-2026-1".into(),
                grades: vec![Grade::default()],
            })
            .unwrap(),
        ),
        (
            CliFeature::Classroom,
            serde_json::to_value(ClassroomQuery {
                code: 0,
                message: "ok".into(),
                floors: [("1".into(), vec![ClassroomInfo::default()])]
                    .into_iter()
                    .collect(),
            })
            .unwrap(),
        ),
        (
            CliFeature::Bykc,
            serde_json::to_value(BykcUserProfile::default()).unwrap(),
        ),
        (
            CliFeature::Bykc,
            serde_json::to_value(BykcCourse::default()).unwrap(),
        ),
        (
            CliFeature::Bykc,
            serde_json::to_value(vec![BykcChosenCourse {
                sign_config: Some(BykcSignConfig {
                    sign_points: vec![BykcSignPoint {
                        lat: 39.9,
                        lng: 116.3,
                        radius: 100.0,
                    }],
                    ..BykcSignConfig::default()
                }),
                ..BykcChosenCourse::default()
            }])
            .unwrap(),
        ),
        (CliFeature::Bykc, serde_json::json!([])),
        (CliFeature::Cgyy, serde_json::json!([])),
        (
            CliFeature::Cgyy,
            serde_json::to_value(CgyyActionResult::default()).unwrap(),
        ),
    ]
}

fn routed_assignment_success_representatives() -> Vec<(CliFeature, serde_json::Value)> {
    let summary = judge_summary();
    let detail = judge_detail();
    let spoc_summary = SpocAssignmentSummary {
        assignment_id: "spoc-assignment".into(),
        course_id: String::new(),
        course_name: "Course".into(),
        teacher_name: None,
        title: "Assignment".into(),
        start_time: None,
        due_time: None,
        score: None,
        submission_status: ubaa_core::domain::SpocSubmissionStatus::default(),
        submission_status_text: "未知状态(9)".into(),
    };
    let spoc_assignments = SpocAssignments {
        term_code: "2025-2026-1".into(),
        term_name: None,
        assignments: vec![spoc_summary],
    };

    vec![
        (
            CliFeature::Spoc,
            serde_json::to_value(&spoc_assignments).unwrap(),
        ),
        (
            CliFeature::Spoc,
            serde_json::to_value(SpocAssignmentsDiagnostics {
                global_page_count: 1,
                result: spoc_assignments,
            })
            .unwrap(),
        ),
        (
            CliFeature::Spoc,
            serde_json::to_value(SpocAssignmentDetail {
                assignment_id: "spoc-assignment".into(),
                course_id: String::new(),
                course_name: "Course".into(),
                teacher_name: None,
                title: "Assignment".into(),
                start_time: None,
                due_time: None,
                score: None,
                submission_status: ubaa_core::domain::SpocSubmissionStatus::Unknown,
                submission_status_text: "未知状态".into(),
                content_plain_text: None,
                submitted_at: None,
            })
            .unwrap(),
        ),
        (
            CliFeature::Judge,
            serde_json::to_value(vec![summary.clone()]).unwrap(),
        ),
        (
            CliFeature::Judge,
            serde_json::to_value(JudgeAssignmentsDiagnostics {
                course_count: 1,
                raw_anchor_count: 1,
                filtered_unique_count: 1,
                summaries: vec![summary],
            })
            .unwrap(),
        ),
        (CliFeature::Judge, serde_json::to_value(&detail).unwrap()),
        (
            CliFeature::Judge,
            serde_json::to_value(vec![detail]).unwrap(),
        ),
    ]
}

fn judge_summary() -> JudgeAssignmentSummary {
    JudgeAssignmentSummary {
        course_id: "12".into(),
        course_name: "Course".into(),
        assignment_id: "34".into(),
        title: "Assignment".into(),
        start_time: None,
        due_time: None,
        max_score: Some("10.00".into()),
        my_score: Some("7.00".into()),
        total_problems: 1,
        submitted_count: 1,
        submission_status: ubaa_core::domain::JudgeSubmissionStatus::Submitted,
        submission_status_text: "已完成 7.00/10.00".into(),
    }
}

fn judge_detail() -> JudgeAssignmentDetail {
    JudgeAssignmentDetail {
        course_id: "12".into(),
        course_name: "Course".into(),
        assignment_id: "34".into(),
        title: "Assignment".into(),
        start_time: None,
        due_time: None,
        max_score: None,
        my_score: None,
        total_problems: 1,
        submitted_count: 1,
        submission_status: ubaa_core::domain::JudgeSubmissionStatus::Submitted,
        submission_status_text: "已完成".into(),
        problems: vec![JudgeProblem {
            name: "Problem".into(),
            score: None,
            max_score: None,
            status: ubaa_core::domain::JudgeSubmissionStatus::Submitted,
            status_text: "已提交".into(),
        }],
        content_plain_text: None,
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

    assert_schema_rejects_invalid_aggregate_states(validator, aggregate);

    let mut legacy_mode = unresolved.clone();
    legacy_mode["meta"]["connectionMode"] = serde_json::json!("direct");
    assert!(!validator.is_valid(&legacy_mode));

    let mut success_with_error = success.clone();
    success_with_error["error"] = failure["error"].clone();
    assert!(!validator.is_valid(&success_with_error));

    let mut failure_with_data = failure.clone();
    failure_with_data["data"] = serde_json::json!({});
    assert!(!validator.is_valid(&failure_with_data));
}

fn assert_schema_rejects_invalid_aggregate_states(
    validator: &jsonschema::Validator,
    aggregate: &serde_json::Value,
) {
    let mut ready_without_profile = aggregate.clone();
    ready_without_profile["data"]
        .as_object_mut()
        .unwrap()
        .remove("profile");
    assert!(!validator.is_valid(&ready_without_profile));

    let mut none_ready_with_profile = aggregate.clone();
    none_ready_with_profile["ok"] = serde_json::json!(false);
    none_ready_with_profile["error"] = serde_json::json!({
        "code": "authentication_required",
        "kind": "authentication",
        "message": "authentication is required",
        "retryable": false
    });
    none_ready_with_profile["data"]["readiness"] = serde_json::json!("none_ready");
    for route in none_ready_with_profile["data"]["routes"]
        .as_array_mut()
        .unwrap()
    {
        route["state"] = serde_json::json!("failed");
        route["error"] = serde_json::json!({
            "code": "authentication_required",
            "kind": "authentication",
            "message": "authentication is required",
            "retryable": false
        });
    }
    assert!(!validator.is_valid(&none_ready_with_profile));

    let mut mixed_route_meta = aggregate.clone();
    mixed_route_meta["meta"]["resolvedRoute"] = serde_json::json!("direct");
    assert!(!validator.is_valid(&mixed_route_meta));
}

fn routed_envelope(
    feature: CliFeature,
    data: serde_json::Value,
    resolution: RouteResolution,
) -> serde_json::Value {
    serde_json::to_value(RoutedJsonEnvelope::success(
        data,
        ResolvedRoutedJsonMeta::from_resolution(feature, resolution),
    ))
    .unwrap()
}

fn assert_schema_rejects_invalid_profile_and_sensitive_data(
    validator: &jsonschema::Validator,
    resolution: RouteResolution,
) {
    let empty_schedule = routed_envelope(CliFeature::Schedule, serde_json::json!({}), resolution);
    assert!(!validator.is_valid(&empty_schedule));

    let wrong_user_dto = routed_envelope(
        CliFeature::User,
        serde_json::to_value(vec![Term::default()]).unwrap(),
        resolution,
    );
    assert!(!validator.is_valid(&wrong_user_dto));

    let mut unmasked_phone = routed_envelope(
        CliFeature::User,
        serde_json::to_value(masked_profile()).unwrap(),
        resolution,
    );
    unmasked_phone["data"]["phone"] = serde_json::json!("UNMASKED-PHONE");
    assert!(!validator.is_valid(&unmasked_phone));

    let mut unmasked_identity = routed_envelope(
        CliFeature::User,
        serde_json::to_value(masked_profile()).unwrap(),
        resolution,
    );
    unmasked_identity["data"]["idCardNumber"] = serde_json::json!("UNMASKED-ID");
    assert!(!validator.is_valid(&unmasked_identity));

    let mut raw_html = routed_envelope(
        CliFeature::Judge,
        serde_json::to_value(JudgeAssignmentsDiagnostics {
            course_count: 0,
            raw_anchor_count: 0,
            filtered_unique_count: 0,
            summaries: Vec::new(),
        })
        .unwrap(),
        resolution,
    );
    raw_html["data"]["rawHtml"] = serde_json::json!("<html>private</html>");
    assert!(!validator.is_valid(&raw_html));

    let mut cookie = routed_envelope(
        CliFeature::Spoc,
        serde_json::to_value(SpocAssignmentsDiagnostics {
            global_page_count: 1,
            result: SpocAssignments::default(),
        })
        .unwrap(),
        resolution,
    );
    cookie["data"]["cookie"] = serde_json::json!("private");
    assert!(!validator.is_valid(&cookie));

    let zero_page_count = routed_envelope(
        CliFeature::Spoc,
        serde_json::to_value(SpocAssignmentsDiagnostics {
            global_page_count: 0,
            result: SpocAssignments::default(),
        })
        .unwrap(),
        resolution,
    );
    assert!(!validator.is_valid(&zero_page_count));
}

fn assert_schema_rejects_invalid_judge_data(
    validator: &jsonschema::Validator,
    resolution: RouteResolution,
) {
    let mut nonnumeric_judge_id = routed_envelope(
        CliFeature::Judge,
        serde_json::to_value(vec![judge_summary()]).unwrap(),
        resolution,
    );
    nonnumeric_judge_id["data"][0]["assignmentId"] = serde_json::json!("not-numeric");
    assert!(!validator.is_valid(&nonnumeric_judge_id));

    let mut malformed_judge_score = routed_envelope(
        CliFeature::Judge,
        serde_json::to_value(vec![judge_summary()]).unwrap(),
        resolution,
    );
    malformed_judge_score["data"][0]["maxScore"] = serde_json::json!("1..2");
    assert!(!validator.is_valid(&malformed_judge_score));

    let mut impossible_problem_status = routed_envelope(
        CliFeature::Judge,
        serde_json::to_value(judge_detail()).unwrap(),
        resolution,
    );
    impossible_problem_status["data"]["problems"][0]["status"] = serde_json::json!("PARTIAL");
    impossible_problem_status["data"]["problems"][0]["statusText"] = serde_json::json!("部分提交");
    assert!(!validator.is_valid(&impossible_problem_status));

    let mut malformed_problem_score = routed_envelope(
        CliFeature::Judge,
        serde_json::to_value(judge_detail()).unwrap(),
        resolution,
    );
    malformed_problem_score["data"]["problems"][0]["score"] = serde_json::json!(".");
    assert!(!validator.is_valid(&malformed_problem_score));
}

fn assert_schema_rejects_invalid_spoc_data(
    validator: &jsonschema::Validator,
    resolution: RouteResolution,
) {
    let invalid_spoc_unknown = routed_envelope(
        CliFeature::Spoc,
        serde_json::json!({
            "termCode": "2025-2026-1",
            "termName": null,
            "assignments": [{
                "assignmentId": "spoc-assignment",
                "courseId": "",
                "courseName": "Course",
                "teacherName": null,
                "title": "Assignment",
                "startTime": null,
                "dueTime": null,
                "score": null,
                "submissionStatus": "UNKNOWN",
                "submissionStatusText": "未知状态"
            }]
        }),
        resolution,
    );
    assert!(!validator.is_valid(&invalid_spoc_unknown));
}

fn assert_schema_rejects_invalid_routed_data(
    validator: &jsonschema::Validator,
    resolution: RouteResolution,
) {
    assert_schema_rejects_invalid_profile_and_sensitive_data(validator, resolution);
    assert_schema_rejects_invalid_judge_data(validator, resolution);
    assert_schema_rejects_invalid_spoc_data(validator, resolution);
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
    ])
    .unwrap();

    let formatted = format!("{cli:?}");
    let sentinel = "USERNAME-SENTINEL";
    assert!(
        !formatted.contains(sentinel),
        "leaked {sentinel} in {formatted}"
    );
}
