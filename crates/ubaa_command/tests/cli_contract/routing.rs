use std::io::Cursor;

use clap::Parser;
use ubaa_command::{
    Cli, CliFeature, ReadonlyRouteContext, run_with_backend_with_route, run_with_routed_backend,
};
use ubaa_core::facade::{ConnectionMode, NetworkState, RoutePolicy};

use crate::common::{FakeBackend, FakeRoutedBackend};

#[tokio::test]
async fn readonly_route_errors_use_schema_v10_diagnostics() {
    let cli = Cli::try_parse_from(["ubaa-cli", "--json", "schedule", "terms"]).unwrap();
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
    assert_eq!(value["schemaVersion"], 16);
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
    let cli = Cli::try_parse_from(["ubaa-cli", "--json", "schedule", "terms"]).unwrap();
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
    assert_eq!(value["schemaVersion"], 16);
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
    let cli = Cli::try_parse_from(["ubaa-cli", "--json", "user", "show"]).unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 0);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["schemaVersion"], 16);
    assert_eq!(value["ok"], true);
    assert_eq!(value["meta"]["feature"], "user");
    assert_eq!(value["meta"]["routePolicy"], "webvpn");
    assert_eq!(value["meta"]["initialRoute"], "webvpn");
    assert_eq!(value["meta"]["resolvedRoute"], "webvpn");
    assert_ne!(value["data"]["phone"], "PHONE-FIXTURE-VALUE");
    assert!(stderr.is_empty());
}

#[test]
#[allow(clippy::too_many_lines)]
fn 扩展只读命令全部要求已有会话并映射正确功能() {
    let cases = [
        (vec!["ubaa-cli", "signin", "today"], CliFeature::Signin),
        (
            vec!["ubaa-cli", "libbook", "libraries", "--day", "2026-08-27"],
            CliFeature::LibBook,
        ),
        (
            vec![
                "ubaa-cli",
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
            vec!["ubaa-cli", "libbook", "area-detail", "--area-id", "8"],
            CliFeature::LibBook,
        ),
        (
            vec![
                "ubaa-cli",
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
                "ubaa-cli", "libbook", "bookings", "--page", "1", "--limit", "20",
            ],
            CliFeature::LibBook,
        ),
        (vec!["ubaa-cli", "ygdk", "overview"], CliFeature::Ygdk),
        (
            vec!["ubaa-cli", "ygdk", "records", "--page", "1", "--size", "20"],
            CliFeature::Ygdk,
        ),
        (vec!["ubaa-cli", "bykc", "profile"], CliFeature::Bykc),
        (
            vec!["ubaa-cli", "bykc", "courses", "--page", "1", "--size", "20"],
            CliFeature::Bykc,
        ),
        (
            vec!["ubaa-cli", "bykc", "course", "--id", "1"],
            CliFeature::Bykc,
        ),
        (vec!["ubaa-cli", "bykc", "chosen"], CliFeature::Bykc),
        (vec!["ubaa-cli", "bykc", "statistics"], CliFeature::Bykc),
        (vec!["ubaa-cli", "cgyy", "sites"], CliFeature::Cgyy),
        (vec!["ubaa-cli", "cgyy", "purposes"], CliFeature::Cgyy),
        (
            vec![
                "ubaa-cli",
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
            vec!["ubaa-cli", "cgyy", "orders", "--page", "0", "--size", "10"],
            CliFeature::Cgyy,
        ),
        (
            vec!["ubaa-cli", "cgyy", "detail", "--id", "1"],
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
    let cli = Cli::try_parse_from(["ubaa-cli", "--json", "schedule", "terms"]).unwrap();
    let mut backend = FakeRoutedBackend {
        fail_schedule: true,
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 3);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["schemaVersion"], 16);
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
fn login_without_diagnostic_mode_uses_aggregate_path() {
    let cli = Cli::try_parse_from([
        "ubaa-cli",
        "auth",
        "login",
        "--username",
        "fixture-user",
        "--password-stdin",
    ])
    .unwrap();
    assert_eq!(cli.login_mode(), None);
}
