use clap::Parser;
use ubaa_cli::{Cli, run_with_routed_backend};

use crate::common::{FakeRoutedBackend, assert_cli_schema};

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
