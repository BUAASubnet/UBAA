use std::io::Cursor;

use clap::Parser;
use ubaa_cli::{Cli, run_with_backend, run_with_routed_backend};

use crate::common::{FakeBackend, FakeRoutedBackend, SigninFixtureResult, assert_cli_schema};

#[tokio::test]
async fn 课堂签到今日与写结果都符合_schema_v4() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "signin", "today"]).unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

    assert_eq!(code, 0);
    let today: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&today);
    assert_eq!(today["schemaVersion"], 4);
    assert_eq!(today["data"][0]["signStatus"], 0);
    assert_eq!(today["data"][0]["signinEligibility"], "allowed");
    assert_eq!(today["data"][1]["signinEligibility"], "denied");
    assert!(today["data"][2]["signStatus"].is_null());
    assert_eq!(today["data"][2]["signinEligibility"], "unknown");
    assert_eq!(today["data"][3]["signStatus"], 2);
    assert_eq!(today["data"][3]["signinEligibility"], "unknown");
    assert_eq!(backend.signin_today_calls, 1);
    assert!(stderr.is_empty());

    let mut old = today.clone();
    old["schemaVersion"] = 3.into();
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    assert!(!jsonschema::validator_for(&schema).unwrap().is_valid(&old));

    for value in [2_147_483_648_i64, -2_147_483_649_i64] {
        let mut out_of_range = today.clone();
        out_of_range["data"][0]["signStatus"] = value.into();
        assert!(
            !jsonschema::validator_for(&schema)
                .unwrap()
                .is_valid(&out_of_range),
            "Signin 原始状态仍须遵守 Rust i32 边界：{value}",
        );
    }
}

#[tokio::test]
async fn 课堂签到确定成功与业务_false_保持内外层语义() {
    for (fixture, expected_success, expected_code) in [
        (SigninFixtureResult::Success, true, 200),
        (SigninFixtureResult::BusinessFalse, false, 400),
    ] {
        let cli = Cli::try_parse_from([
            "ubaa",
            "--json",
            "signin",
            "perform",
            "--course-id",
            "schedule-safe",
            "--confirm-write",
        ])
        .unwrap();
        let mut backend = FakeRoutedBackend {
            signin_result: fixture,
            ..FakeRoutedBackend::default()
        };
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 0, "确定业务 false 仍表示调用完成");
        assert_cli_schema(&value);
        assert_eq!(value["schemaVersion"], 4);
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["success"], expected_success);
        assert_eq!(value["data"]["code"], expected_code);
        assert_eq!(backend.signin_perform_calls, 1);
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 课堂签到发送前超时与发送后未知保持不同错误分类且不重放() {
    for (fixture, expected_error) in [
        (SigninFixtureResult::PreSendTimeout, "timeout"),
        (SigninFixtureResult::OutcomeUnknown, "outcome_unknown"),
    ] {
        let cli = Cli::try_parse_from([
            "ubaa",
            "--json",
            "signin",
            "perform",
            "--course-id",
            "schedule-safe",
            "--confirm-write",
        ])
        .unwrap();
        let mut backend = FakeRoutedBackend {
            signin_result: fixture,
            ..FakeRoutedBackend::default()
        };
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 5);
        assert_cli_schema(&value);
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], expected_error);
        assert_eq!(backend.signin_perform_calls, 1);
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 课堂签到未确认或空目标在后端调用前拒绝() {
    for arguments in [
        vec![
            "ubaa",
            "--json",
            "signin",
            "perform",
            "--course-id",
            "schedule-safe",
        ],
        vec![
            "ubaa",
            "--json",
            "signin",
            "perform",
            "--course-id",
            "   ",
            "--confirm-write",
        ],
    ] {
        let cli = Cli::try_parse_from(arguments).unwrap();
        let mut backend = FakeRoutedBackend::default();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 2);
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], "invalid_input");
        assert_eq!(backend.signin_perform_calls, 0);
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 固定路线课堂签到空目标同样在后端调用前拒绝() {
    let cli = Cli::try_parse_from([
        "ubaa",
        "--json",
        "signin",
        "perform",
        "--course-id",
        "   ",
        "--confirm-write",
    ])
    .unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_backend(
        cli,
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 2);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(backend.signin_perform_calls, 0);
    assert!(stderr.is_empty());
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
async fn 博雅三类写操作确认后输出均符合_schema_v4() {
    let cases = [
        (
            vec![
                "ubaa",
                "--json",
                "bykc",
                "select",
                "--course-id",
                "11",
                "--confirm-write",
            ],
            "fixture select",
        ),
        (
            vec![
                "ubaa",
                "--json",
                "bykc",
                "deselect",
                "--course-id",
                "11",
                "--confirm-write",
            ],
            "fixture deselect",
        ),
        (
            vec![
                "ubaa",
                "--json",
                "bykc",
                "sign",
                "--course-id",
                "11",
                "--sign-type",
                "1",
                "--confirm-write",
            ],
            "fixture sign",
        ),
    ];

    for (arguments, expected_message) in cases {
        let cli = Cli::try_parse_from(arguments).unwrap();
        let mut backend = FakeRoutedBackend::default();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let code = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;

        assert_eq!(code, 0);
        let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
        assert_cli_schema(&value);
        assert_eq!(value["schemaVersion"], 4);
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["message"], expected_message);
        assert_eq!(value["meta"]["feature"], "bykc");
        assert!(stderr.is_empty());
    }
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

#[tokio::test]
async fn 场馆预约默认拒绝且不读取标准输入() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "cgyy", "submit"]).unwrap();
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

#[tokio::test]
async fn 其他写命令未确认时统一拒绝() {
    let commands = [
        Cli::try_parse_from(["ubaa", "--json", "signin", "perform", "--course-id", "safe"])
            .unwrap(),
        Cli::try_parse_from([
            "ubaa",
            "--json",
            "ygdk",
            "submit",
            "--start-time",
            "08:00",
            "--end-time",
            "09:00",
            "--photo",
            "/tmp/不存在的照片.jpg",
        ])
        .unwrap(),
        Cli::try_parse_from([
            "ubaa",
            "--json",
            "libbook",
            "reserve",
            "--area-id",
            "a",
            "--seat-id",
            "s",
            "--day",
            "2026-08-28",
            "--segment",
            "1",
        ])
        .unwrap(),
        Cli::try_parse_from(["ubaa", "--json", "bykc", "select", "--course-id", "1"]).unwrap(),
    ];
    for cli in commands {
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
}

#[tokio::test]
async fn 自动评教提交未确认时拒绝且不查询课程() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "evaluation", "submit-pending"]).unwrap();
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
