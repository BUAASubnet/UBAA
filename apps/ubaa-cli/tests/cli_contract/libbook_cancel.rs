use std::io::Cursor;

use clap::Parser;
use ubaa_cli::{Cli, run_with_backend, run_with_routed_backend};
use ubaa_core::facade::{ErrorCode, ErrorKind, UbaaError};

use crate::common::{FakeBackend, FakeRoutedBackend, assert_cli_schema};

fn cancel_arguments(
    booking_id: &str,
    page: Option<&str>,
    limit: Option<&str>,
    confirm_write: bool,
) -> Vec<String> {
    let mut arguments = vec![
        "ubaa".to_owned(),
        "--json".to_owned(),
        "libbook".to_owned(),
        "cancel".to_owned(),
        "--booking-id".to_owned(),
        booking_id.to_owned(),
    ];
    if let Some(page) = page {
        arguments.push(format!("--page={page}"));
    }
    if let Some(limit) = limit {
        arguments.push(format!("--limit={limit}"));
    }
    if confirm_write {
        arguments.push("--confirm-write".to_owned());
    }
    arguments
}

#[tokio::test]
async fn 图书馆预约记录取消资格与稳定目标符合_schema_v7() {
    let cli = Cli::try_parse_from([
        "ubaa", "--json", "libbook", "bookings", "--page", "1", "--limit", "20",
    ])
    .unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 7);
    assert_eq!(value["data"]["bookings"][0]["status"], 1);
    assert_eq!(value["data"]["bookings"][0]["cancelEligibility"], "allowed");
    assert_eq!(
        value["data"]["bookings"][0]["cancelTarget"],
        "booking-allowed"
    );
    assert_eq!(value["data"]["bookings"][1]["status"], 6);
    assert_eq!(value["data"]["bookings"][1]["cancelEligibility"], "denied");
    assert_eq!(
        value["data"]["bookings"][1]["cancelTarget"],
        "booking-cancelled"
    );
    assert_eq!(value["data"]["bookings"][2]["status"], 8);
    assert_eq!(value["data"]["bookings"][2]["cancelEligibility"], "denied");
    assert_eq!(
        value["data"]["bookings"][2]["cancelTarget"],
        "booking-ended"
    );
    assert!(value["data"]["bookings"][3]["status"].is_null());
    assert_eq!(value["data"]["bookings"][3]["cancelEligibility"], "unknown");
    assert!(value["data"]["bookings"][3]["cancelTarget"].is_null());
    assert_eq!(backend.libbook_bookings_calls, 1);
    assert!(stderr.is_empty());

    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let mut old = value;
    old["schemaVersion"] = 6.into();
    assert!(!jsonschema::validator_for(&schema).unwrap().is_valid(&old));
}

#[tokio::test]
async fn 图书馆取消未确认空白目标或非法分页均在路由后端调用前拒绝() {
    let cases = [
        cancel_arguments("booking-safe", None, None, false),
        cancel_arguments("   ", None, None, true),
        cancel_arguments("booking-safe", Some("0"), None, true),
        cancel_arguments("booking-safe", Some("-1"), None, true),
        cancel_arguments("booking-safe", None, Some("0"), true),
        cancel_arguments("booking-safe", None, Some("-1"), true),
    ];

    for arguments in cases {
        let cli = Cli::try_parse_from(arguments).unwrap();
        let mut backend = FakeRoutedBackend::default();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 2);
        assert_cli_schema(&value);
        assert_eq!(value["schemaVersion"], 7);
        assert_eq!(value["error"]["code"], "invalid_input");
        assert_eq!(backend.libbook_cancel_calls, 0);
        assert!(backend.libbook_last_cancel_request.is_none());
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 图书馆取消确认后向路由后端精确传递一次标准化请求() {
    let cli = Cli::try_parse_from(cancel_arguments(
        " booking-safe ",
        Some("3"),
        Some("7"),
        true,
    ))
    .unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 7);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["success"], true);
    assert_eq!(value["data"]["message"], "取消成功");
    assert_eq!(value["meta"]["feature"], "libbook");
    assert_eq!(backend.libbook_cancel_calls, 1);
    let request = backend
        .libbook_last_cancel_request
        .as_ref()
        .expect("后端应收到标准化取消请求");
    assert_eq!(request.booking_id, "booking-safe");
    assert_eq!(request.page, 3);
    assert_eq!(request.limit, 7);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 固定路线图书馆取消同样校验并传递默认分页() {
    for arguments in [
        cancel_arguments("booking-safe", None, None, false),
        cancel_arguments("   ", None, None, true),
        cancel_arguments("booking-safe", Some("0"), None, true),
        cancel_arguments("booking-safe", None, Some("0"), true),
    ] {
        let cli = Cli::try_parse_from(arguments).unwrap();
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

        assert_eq!(exit, 2);
        assert_eq!(backend.libbook_cancel_calls, 0);
        assert!(backend.libbook_last_cancel_request.is_none());
        let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], "invalid_input");
        assert!(stderr.is_empty());
    }

    let cli = Cli::try_parse_from(cancel_arguments(" fixed-safe ", None, None, true)).unwrap();
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

    assert_eq!(exit, 0);
    assert_eq!(backend.libbook_cancel_calls, 1);
    let request = backend
        .libbook_last_cancel_request
        .as_ref()
        .expect("固定路线后端应收到取消请求");
    assert_eq!(request.booking_id, "fixed-safe");
    assert_eq!(request.page, 1);
    assert_eq!(request.limit, 20);
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 7);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 图书馆取消的固定与路由输出均不暴露后端原始上游文案() {
    let raw_error = || {
        UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "失败\n学号=private token=secret\0",
        )
    };

    let cli = Cli::try_parse_from(cancel_arguments("booking-safe", None, None, true)).unwrap();
    let mut routed = FakeRoutedBackend {
        libbook_cancel_error: Some(raw_error()),
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_routed_backend(cli, &mut routed, &mut stdout, &mut stderr).await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(exit, 6);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "upstream_changed");
    assert_eq!(value["error"]["message"], "图书馆预约取消资格核对响应无效");
    let serialized = String::from_utf8(stdout).unwrap();
    for unsafe_fragment in ["private", "secret", "学号", "token", "\\u0000"] {
        assert!(!serialized.contains(unsafe_fragment));
    }
    assert!(stderr.is_empty());

    let cli = Cli::try_parse_from(cancel_arguments("booking-safe", None, None, true)).unwrap();
    let mut fixed = FakeBackend {
        libbook_cancel_error: Some(raw_error()),
        ..FakeBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_backend(
        cli,
        &mut fixed,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(exit, 6);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["message"], "图书馆预约取消资格核对响应无效");
    let serialized = String::from_utf8(stdout).unwrap();
    for unsafe_fragment in ["private", "secret", "学号", "token", "\\u0000"] {
        assert!(!serialized.contains(unsafe_fragment));
    }
    assert!(stderr.is_empty());

    let mut arguments = cancel_arguments("booking-safe", None, None, true);
    arguments.retain(|argument| argument != "--json");
    let cli = Cli::try_parse_from(arguments).unwrap();
    let mut routed = FakeRoutedBackend {
        libbook_cancel_error: Some(raw_error()),
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_routed_backend(cli, &mut routed, &mut stdout, &mut stderr).await;
    assert_eq!(exit, 6);
    assert!(stdout.is_empty());
    let rendered = String::from_utf8(stderr).unwrap();
    assert_eq!(rendered, "错误：图书馆预约取消资格核对响应无效\n");
    for unsafe_fragment in ["private", "secret", "学号", "token", "\0"] {
        assert!(!rendered.contains(unsafe_fragment));
    }
}
