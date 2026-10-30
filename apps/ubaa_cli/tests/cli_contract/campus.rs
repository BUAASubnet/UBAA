use crate::common::{FakeBackend, FakeRoutedBackend, assert_cli_schema};
use clap::Parser;
use std::io::Cursor;
use ubaa_cli::{Cli, run_with_backend, run_with_routed_backend};

#[tokio::test]
async fn 三个校园命令分别投影正确数据并符合_json_合同() {
    for (group, operation, key) in [
        ("portal", "profile", "identity"),
        ("portal", "metrics", "cloudStorageRemaining"),
        ("network", "usage", "products"),
    ] {
        for routed in [true, false] {
            let cli = Cli::try_parse_from(["ubaa", "--json", group, operation]).unwrap();
            let mut output = Vec::new();
            let mut errors = Vec::new();
            let code = if routed {
                run_with_routed_backend(
                    cli,
                    &mut FakeRoutedBackend::default(),
                    &mut output,
                    &mut errors,
                )
                .await
            } else {
                run_with_backend(
                    cli,
                    &mut FakeBackend::default(),
                    &mut Cursor::new(Vec::<u8>::new()),
                    &mut output,
                    &mut errors,
                )
                .await
            };
            assert_eq!(code, 0);
            assert!(errors.is_empty());
            let value: serde_json::Value = serde_json::from_slice(&output).unwrap();
            assert_cli_schema(&value);
            assert_eq!(value["meta"]["feature"], group);
            assert_eq!(value["meta"]["resolvedRoute"], "direct");
            assert!(!value["data"][key].is_null());
            if operation == "metrics" {
                assert_eq!(value["data"]["unreadMail"]["status"], "failure");
                assert_eq!(value["data"]["borrowedBooks"]["value"], 0);
                assert_eq!(
                    value["data"]["cloudStorageRemaining"]["value"]["value"],
                    "80.125"
                );
            }
        }
    }
}

#[tokio::test]
async fn 校园人类输出保留中文含义和单项错误() {
    for (group, operation, labels) in [
        ("portal", "profile", vec!["身份：本科生", "学院：示例学院"]),
        (
            "portal",
            "metrics",
            vec!["云盘剩余空间：80.125G", "未读邮件：暂不可用", "待还图书：0"],
        ),
        (
            "network",
            "usage",
            vec![
                "已用流量：90.001G",
                "免费流量剩余（不含套餐）：0byte",
                "计费流量剩余（不含套餐）：40.125G",
            ],
        ),
    ] {
        let cli = Cli::try_parse_from(["ubaa", group, operation]).unwrap();
        let mut output = Vec::new();
        let mut errors = Vec::new();
        assert_eq!(
            run_with_routed_backend(
                cli,
                &mut FakeRoutedBackend::default(),
                &mut output,
                &mut errors
            )
            .await,
            0
        );
        let output = String::from_utf8(output).unwrap();
        for label in labels {
            assert!(output.contains(label), "缺少语义结果：{label}");
        }
    }
}

#[test]
fn 校园_json_拒绝缺失项错误单位和值及额外原始字段() {
    use ubaa_cli::{CliFeature, ResolvedRoutedJsonMeta, RoutedJsonEnvelope};
    use ubaa_core::facade::ConnectionMode;
    let envelope = RoutedJsonEnvelope::success(
        crate::common::campus_metrics(),
        ResolvedRoutedJsonMeta::explicit(CliFeature::Portal, ConnectionMode::Direct),
    );
    let valid = serde_json::to_value(envelope).unwrap();
    assert_cli_schema(&valid);
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let mut invalid = valid.clone();
    invalid["data"]["borrowedBooks"]["value"] = serde_json::json!(-1);
    assert!(!validator.is_valid(&invalid));
    let mut invalid = valid.clone();
    invalid["data"]["networkBalance"]["value"]["value"] = serde_json::json!(12.34);
    assert!(!validator.is_valid(&invalid));
    let mut invalid = valid.clone();
    invalid["data"]["cloudStorageRemaining"]["account"] = serde_json::json!("原始额外字段");
    assert!(!validator.is_valid(&invalid));
    let mut invalid = valid;
    invalid["data"]
        .as_object_mut()
        .unwrap()
        .remove("cardBalance");
    assert!(!validator.is_valid(&invalid));
}
