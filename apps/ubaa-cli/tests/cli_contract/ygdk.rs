use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use clap::Parser;
use serde_json::{Value, json};
use ubaa_cli::{CLI_JSON_SCHEMA_VERSION, Cli, run_with_backend, run_with_routed_backend};
use ubaa_core::facade::{
    ActionEligibility, ConnectionMode, YgdkOverview, YgdkRecord, YgdkRecordsPage,
};

use crate::common::{FakeBackend, FakeRoutedBackend, YgdkSubmitFixtureResult, assert_cli_schema};

static NEXT_PHOTO_ID: AtomicUsize = AtomicUsize::new(0);

struct TestPhoto {
    directory: PathBuf,
    path: PathBuf,
}

impl TestPhoto {
    fn new(file_name: &str, bytes: &[u8]) -> Self {
        let directory = std::env::temp_dir().join(format!(
            "ubaa-cli-ygdk-{}-{}",
            std::process::id(),
            NEXT_PHOTO_ID.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&directory).expect("创建隔离的照片测试目录");
        let path = directory.join(file_name);
        std::fs::write(&path, bytes).expect("写入照片测试文件");
        Self { directory, path }
    }

    fn sparse(file_name: &str, size: u64) -> Self {
        let photo = Self::new(file_name, &[1]);
        std::fs::OpenOptions::new()
            .write(true)
            .open(&photo.path)
            .expect("打开照片测试文件")
            .set_len(size)
            .expect("设置照片测试文件长度");
        photo
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TestPhoto {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

fn contract_schema() -> Value {
    serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap()
}

fn definition_validator(name: &str) -> jsonschema::Validator {
    let contract = contract_schema();
    let schema = json!({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$ref": format!("#/$defs/{name}"),
        "$defs": contract["$defs"].clone(),
    });
    jsonschema::validator_for(&schema).unwrap()
}

fn overview_fixture() -> YgdkOverview {
    serde_json::from_value(json!({
        "summary": {
            "termId": 1,
            "termName": "脱敏学期",
            "termCount": 3,
            "termTarget": 10,
            "weekCount": 1,
            "weekTarget": 3,
            "monthCount": 2,
            "monthTarget": 5,
            "dayCount": 1,
            "goodCount": 1
        },
        "classifyId": 11,
        "classifyName": "脱敏分类",
        "defaultItemId": 22,
        "defaultItemName": "脱敏项目",
        "items": [
            {
                "itemId": 22,
                "name": "规范项目",
                "kind": 1,
                "sort": 1,
                "submitEligibility": "allowed",
                "submitTarget": {"classifyId": 11, "itemId": 22}
            },
            {
                "itemId": 33,
                "name": "重复项目甲",
                "kind": null,
                "sort": 2,
                "submitEligibility": "allowed",
                "submitTarget": {"classifyId": 11, "itemId": 33}
            },
            {
                "itemId": 33,
                "name": "重复项目乙",
                "kind": null,
                "sort": 3,
                "submitEligibility": "allowed",
                "submitTarget": {"classifyId": 11, "itemId": 33}
            },
            {
                "itemId": 44,
                "name": "错配项目",
                "kind": null,
                "sort": 4,
                "submitEligibility": "allowed",
                "submitTarget": {"classifyId": 12, "itemId": 45}
            },
            {
                "itemId": 55,
                "name": "拒绝项目",
                "kind": null,
                "sort": 5,
                "submitEligibility": "denied",
                "submitTarget": {"classifyId": 11, "itemId": 55}
            }
        ]
    }))
    .unwrap()
}

fn submit_arguments(
    photo: &Path,
    classify_id: i32,
    item_id: i32,
    start_time: &str,
    end_time: &str,
) -> Vec<String> {
    [
        "ubaa".to_owned(),
        "--json".to_owned(),
        "ygdk".to_owned(),
        "submit".to_owned(),
        format!("--classify-id={classify_id}"),
        format!("--item-id={item_id}"),
        "--start-time".to_owned(),
        start_time.to_owned(),
        "--end-time".to_owned(),
        end_time.to_owned(),
        "--place".to_owned(),
        " 脱敏地点 ".to_owned(),
        "--photo".to_owned(),
        photo.to_string_lossy().into_owned(),
        "--share-to-square".to_owned(),
        "--confirm-write".to_owned(),
    ]
    .into()
}

#[test]
fn cli_阳光打卡合同升级为唯一_schema_v10并拒绝旧v9() {
    assert_eq!(CLI_JSON_SCHEMA_VERSION, 10);
    for definition in [
        "resolvedRoutedEnvelope",
        "unresolvedRoutedFailure",
        "aggregateAuthEnvelope",
        "aggregateLogoutEnvelope",
    ] {
        let schema = &contract_schema()["$defs"][definition];
        assert_eq!(schema["properties"]["schemaVersion"]["const"], 10);
    }

    let receipt = json!({
        "schemaVersion": 10,
        "ok": true,
        "data": {"success": true, "message": "阳光打卡已提交", "recordId": 77},
        "meta": {
            "routePolicy": "direct",
            "networkState": "unknown",
            "initialRoute": "direct",
            "resolvedRoute": "direct",
            "usedFallback": false,
            "feature": "ygdk"
        }
    });
    assert_cli_schema(&receipt);
    let mut old = receipt;
    old["schemaVersion"] = 9.into();
    assert!(
        !jsonschema::validator_for(&contract_schema())
            .unwrap()
            .is_valid(&old)
    );
}

#[test]
fn 阳光打卡项目合同只允许allowed携带正数typed目标() {
    let validator = definition_validator("ygdkItem");
    let canonical = json!({
        "itemId": 22,
        "name": "脱敏项目",
        "kind": 1,
        "sort": 1,
        "submitEligibility": "allowed",
        "submitTarget": {"classifyId": 11, "itemId": 22}
    });
    assert!(validator.is_valid(&canonical));

    for field in ["classifyId", "itemId"] {
        for invalid_id in [0, -1] {
            let mut invalid = canonical.clone();
            invalid["submitTarget"][field] = invalid_id.into();
            assert!(!validator.is_valid(&invalid));
        }
    }

    let mut allowed_without_target = canonical.clone();
    allowed_without_target["submitTarget"] = Value::Null;
    assert!(!validator.is_valid(&allowed_without_target));

    for eligibility in ["denied", "unknown"] {
        let mut forbidden_target = canonical.clone();
        forbidden_target["submitEligibility"] = eligibility.into();
        assert!(!validator.is_valid(&forbidden_target));
        forbidden_target["submitTarget"] = Value::Null;
        assert!(validator.is_valid(&forbidden_target));
    }
}

#[tokio::test]
async fn 阳光打卡概览投影再次关闭重复错配与非allowed目标() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "ygdk", "overview"]).unwrap();
    let mut backend = FakeRoutedBackend {
        ygdk_overview: Some(overview_fixture()),
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    assert_eq!(value["data"]["items"][0]["submitEligibility"], "allowed");
    assert_eq!(value["data"]["items"][0]["submitTarget"]["classifyId"], 11);
    assert_eq!(
        value["data"]["items"][0]["submitTarget"]["itemId"],
        value["data"]["items"][0]["itemId"]
    );
    for index in [1, 2, 3] {
        assert_eq!(
            value["data"]["items"][index]["submitEligibility"],
            "unknown"
        );
        assert!(value["data"]["items"][index]["submitTarget"].is_null());
    }
    assert_eq!(value["data"]["items"][4]["submitEligibility"], "unknown");
    assert!(value["data"]["items"][4]["submitTarget"].is_null());
    assert_eq!(backend.ygdk_overview_calls, 1);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 阳光打卡空父分类名称不能保留任何allowed目标() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "ygdk", "overview"]).unwrap();
    let mut overview = overview_fixture();
    overview.classify_name = "   ".into();
    let mut backend = FakeRoutedBackend {
        ygdk_overview: Some(overview),
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    for item in value["data"]["items"].as_array().unwrap() {
        assert_eq!(item["submitEligibility"], "unknown");
        assert!(item["submitTarget"].is_null());
    }
    assert_eq!(backend.ygdk_overview_calls, 1);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 阳光打卡概览投影关闭其余三类矛盾资格() {
    for case in [
        "unknown_with_target",
        "blank_item_name",
        "nonpositive_parent",
    ] {
        let mut overview = overview_fixture();
        overview.items.truncate(1);
        match case {
            "unknown_with_target" => {
                overview.items[0].submit_eligibility = ActionEligibility::Unknown;
            }
            "blank_item_name" => overview.items[0].name = "   ".into(),
            "nonpositive_parent" => overview.classify_id = 0,
            _ => unreachable!(),
        }
        let cli = Cli::try_parse_from(["ubaa", "--json", "ygdk", "overview"]).unwrap();
        let mut backend = FakeRoutedBackend {
            ygdk_overview: Some(overview),
            ..FakeRoutedBackend::default()
        };
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 0, "防御分支失败：{case}");
        assert_cli_schema(&value);
        assert_eq!(value["data"]["items"][0]["submitEligibility"], "unknown");
        assert!(value["data"]["items"][0]["submitTarget"].is_null());
        assert_eq!(backend.ygdk_overview_calls, 1);
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 阳光打卡记录仅公开图片数量且不泄露图片地址() {
    let cli = Cli::try_parse_from([
        "ubaa", "--json", "ygdk", "records", "--page", "1", "--size", "20",
    ])
    .unwrap();
    let sentinel = "https://ygdk.invalid/private.jpg?token=SENTINEL";
    let mut backend = FakeRoutedBackend {
        ygdk_records: Some(YgdkRecordsPage {
            content: vec![YgdkRecord {
                record_id: 77,
                item_id: Some(22),
                item_name: Some("脱敏项目".into()),
                start_time: Some("2026-04-01 08:00".into()),
                end_time: Some("2026-04-01 09:00".into()),
                place: Some("脱敏地点".into()),
                images: vec![sentinel.into(), "https://ygdk.invalid/second.jpg".into()],
                is_open: true,
                state: Some(1),
                created_at: Some("2026-04-01 09:01".into()),
                created_at_label: Some("刚刚".into()),
            }],
            total: 1,
            page: 1,
            size: 20,
            has_more: false,
        }),
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();
    let serialized = String::from_utf8(stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["data"]["content"][0]["imageCount"], 2);
    assert!(value["data"]["content"][0].get("images").is_none());
    assert!(!serialized.contains(sentinel));
    assert!(!serialized.contains("SENTINEL"));
    assert_eq!(backend.ygdk_records_calls, 1);
    assert!(stderr.is_empty());

    let validator = definition_validator("ygdkRecord");
    assert!(validator.is_valid(&value["data"]["content"][0]));
    let mut unsafe_record = value["data"]["content"][0].clone();
    unsafe_record.as_object_mut().unwrap().remove("imageCount");
    unsafe_record["images"] = json!([sentinel]);
    assert!(!validator.is_valid(&unsafe_record));
}

#[test]
fn 阳光打卡提交命令强制显式typed目标且debug不泄露本地输入() {
    let photo = TestPhoto::new("private-photo.JPG", b"safe-photo");
    let arguments = submit_arguments(photo.path(), 11, 22, "2026-04-01 08:00", "2026-04-01 09:00");
    let cli = Cli::try_parse_from(&arguments).unwrap();
    let debug = format!("{cli:?}");

    for private in [
        "2026-04-01 08:00",
        "2026-04-01 09:00",
        "脱敏地点",
        "private-photo.JPG",
        &photo.path().to_string_lossy(),
    ] {
        assert!(!debug.contains(private), "Debug 泄露了 {private}");
    }

    for missing_flag in ["--classify-id=", "--item-id="] {
        let flag = arguments
            .iter()
            .position(|value| value.starts_with(missing_flag))
            .unwrap();
        let mut missing = arguments.clone();
        missing.remove(flag);
        assert!(Cli::try_parse_from(missing).is_err());
    }
}

#[tokio::test]
async fn 阳光打卡提交构造typed请求且仅输出固定安全收据() {
    let photo = TestPhoto::new("safe-photo.JPG", b"safe-photo");
    let cli = Cli::try_parse_from(submit_arguments(
        photo.path(),
        11,
        22,
        "2026-04-01 08:00",
        "2026-04-01 09:00",
    ))
    .unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();
    let serialized = String::from_utf8(stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    assert_eq!(
        value["data"],
        json!({"success": true, "message": "阳光打卡已提交", "recordId": 77})
    );
    assert_eq!(value["meta"]["feature"], "ygdk");
    assert_eq!(value["meta"]["resolvedRoute"], "direct");
    assert_eq!(backend.ygdk_submit_calls, 1);
    assert_eq!(backend.ygdk_readback_overview_calls, 1);
    assert_eq!(
        backend.ygdk_readback_overview_routes,
        vec![ConnectionMode::Direct]
    );
    assert_eq!(backend.ygdk_readback_records_calls, 1);
    assert_eq!(
        backend.ygdk_readback_records_requests,
        vec![(ConnectionMode::Direct, 1, 20)]
    );
    let request = backend
        .ygdk_last_submit_request
        .as_ref()
        .expect("后端应收到 typed 阳光打卡请求");
    assert_eq!(request.target.classify_id, 11);
    assert_eq!(request.target.item_id, 22);
    assert_eq!(request.start_time, "2026-04-01 08:00");
    assert_eq!(request.end_time, "2026-04-01 09:00");
    assert_eq!(request.place.as_deref(), Some("脱敏地点"));
    assert!(request.share_to_square);
    assert_eq!(request.photo.bytes, b"safe-photo");
    assert_eq!(request.photo.file_name, "safe-photo.JPG");
    assert_eq!(request.photo.mime_type, "image/jpeg");
    let photo_debug = format!("{:?}", request.photo);
    assert!(!photo_debug.contains("safe-photo.JPG"));
    assert!(!photo_debug.contains("safe-photo"));
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "token", "summary", "fileName"] {
        assert!(!serialized.contains(forbidden));
    }
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 阳光打卡成功收据丢弃非正record_id而不泄露原始结果() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    let cli = Cli::try_parse_from(submit_arguments(
        photo.path(),
        11,
        22,
        "2026-04-01 08:00",
        "2026-04-01 09:00",
    ))
    .unwrap();
    let mut backend = FakeRoutedBackend {
        ygdk_submit_result: YgdkSubmitFixtureResult::SuccessWithInvalidRecordId,
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["data"]["recordId"], Value::Null);
    assert_eq!(backend.ygdk_submit_calls, 1);
    assert_eq!(backend.ygdk_readback_overview_calls, 1);
    assert_eq!(backend.ygdk_readback_records_calls, 1);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 阳光打卡不可信false与上游变化均固定安全失败且不重放() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    for fixture in [
        YgdkSubmitFixtureResult::UnsafeFalse,
        YgdkSubmitFixtureResult::PreSendChanged,
    ] {
        let cli = Cli::try_parse_from(submit_arguments(
            photo.path(),
            11,
            22,
            "2026-04-01 08:00",
            "2026-04-01 09:00",
        ))
        .unwrap();
        let mut backend = FakeRoutedBackend {
            ygdk_submit_result: fixture,
            ..FakeRoutedBackend::default()
        };
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: Value = serde_json::from_slice(&stdout).unwrap();
        let serialized = String::from_utf8(stdout).unwrap();

        assert_eq!(exit, 6);
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], "upstream_changed");
        assert_eq!(value["error"]["message"], "阳光打卡提交资格核对响应无效");
        assert_eq!(value["error"]["retryable"], false);
        assert_eq!(backend.ygdk_submit_calls, 1);
        for forbidden in ["RAW-UPSTREAM", "PRIVATE", "photo", "token"] {
            assert!(!serialized.contains(forbidden));
        }
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 阳光打卡outcome_unknown退出5且提示双刷新并只调用一次() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    let cli = Cli::try_parse_from(submit_arguments(
        photo.path(),
        11,
        22,
        "2026-04-01 08:00",
        "2026-04-01 09:00",
    ))
    .unwrap();
    let mut backend = FakeRoutedBackend {
        ygdk_submit_result: YgdkSubmitFixtureResult::OutcomeUnknown,
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();
    let serialized = String::from_utf8(stdout).unwrap();

    assert_eq!(exit, 5);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "outcome_unknown");
    assert_eq!(
        value["error"]["message"],
        "阳光打卡提交结果未知，请刷新概览与记录核对后再操作"
    );
    assert_eq!(value["error"]["retryable"], false);
    assert_eq!(backend.ygdk_submit_calls, 1);
    assert_eq!(backend.ygdk_readback_overview_calls, 1);
    assert_eq!(
        backend.ygdk_readback_overview_routes,
        vec![ConnectionMode::Direct]
    );
    assert_eq!(backend.ygdk_readback_records_calls, 1);
    assert_eq!(
        backend.ygdk_readback_records_requests,
        vec![(ConnectionMode::Direct, 1, 20)]
    );
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "Set-Cookie", "photo", "token"] {
        assert!(!serialized.contains(forbidden));
    }
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 阳光打卡双回读彼此独立且失败不覆盖原提交结论() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    for (fixture, overview_fails, records_fails, expected_exit, expected_code) in [
        (YgdkSubmitFixtureResult::Success, true, false, 0, None),
        (
            YgdkSubmitFixtureResult::OutcomeUnknown,
            false,
            true,
            5,
            Some("outcome_unknown"),
        ),
    ] {
        let cli = Cli::try_parse_from(submit_arguments(
            photo.path(),
            11,
            22,
            "2026-04-01 08:00",
            "2026-04-01 09:00",
        ))
        .unwrap();
        let mut backend = FakeRoutedBackend {
            ygdk_submit_result: fixture,
            ygdk_readback_overview_fails: overview_fails,
            ygdk_readback_records_fails: records_fails,
            ..FakeRoutedBackend::default()
        };
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, expected_exit);
        assert_cli_schema(&value);
        assert_eq!(backend.ygdk_submit_calls, 1);
        assert_eq!(backend.ygdk_readback_overview_calls, 1);
        assert_eq!(backend.ygdk_readback_records_calls, 1);
        assert_eq!(
            backend.ygdk_readback_overview_routes,
            vec![ConnectionMode::Direct]
        );
        assert_eq!(
            backend.ygdk_readback_records_requests,
            vec![(ConnectionMode::Direct, 1, 20)]
        );
        if let Some(expected_code) = expected_code {
            assert_eq!(value["error"]["code"], expected_code);
        } else {
            assert_eq!(value["data"]["message"], "阳光打卡已提交");
        }
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 固定路线成功后也只在原route执行双回读() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    let cli = Cli::try_parse_from(submit_arguments(
        photo.path(),
        11,
        22,
        "2026-04-01 08:00",
        "2026-04-01 09:00",
    ))
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
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["data"]["message"], "阳光打卡已提交");
    assert_eq!(backend.ygdk_submit_calls, 1);
    assert_eq!(backend.ygdk_readback_overview_calls, 1);
    assert_eq!(
        backend.ygdk_readback_overview_routes,
        vec![ConnectionMode::Direct]
    );
    assert_eq!(backend.ygdk_readback_records_calls, 1);
    assert_eq!(
        backend.ygdk_readback_records_requests,
        vec![(ConnectionMode::Direct, 1, 20)]
    );
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 固定路线outcome_unknown也只在原route执行双回读() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    let cli = Cli::try_parse_from(submit_arguments(
        photo.path(),
        11,
        22,
        "2026-04-01 08:00",
        "2026-04-01 09:00",
    ))
    .unwrap();
    let mut backend = FakeBackend {
        ygdk_submit_result: YgdkSubmitFixtureResult::OutcomeUnknown,
        ..FakeBackend::default()
    };
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
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 5);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "outcome_unknown");
    assert_eq!(backend.ygdk_submit_calls, 1);
    assert_eq!(backend.ygdk_readback_overview_calls, 1);
    assert_eq!(
        backend.ygdk_readback_overview_routes,
        vec![ConnectionMode::Direct]
    );
    assert_eq!(backend.ygdk_readback_records_calls, 1);
    assert_eq!(
        backend.ygdk_readback_records_requests,
        vec![(ConnectionMode::Direct, 1, 20)]
    );
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 阳光打卡非正目标与非canonical时间在路由前拒绝() {
    let photo = TestPhoto::new("safe.jpg", b"safe-photo");
    let cases = [
        (0, 22, "2026-04-01 08:00", "2026-04-01 09:00"),
        (-1, 22, "2026-04-01 08:00", "2026-04-01 09:00"),
        (11, 0, "2026-04-01 08:00", "2026-04-01 09:00"),
        (11, -1, "2026-04-01 08:00", "2026-04-01 09:00"),
        (11, 22, "2026-04-01T08:00", "2026-04-01 09:00"),
        (11, 22, "2026-04-01 08:00:00", "2026-04-01 09:00"),
        (11, 22, " 2026-04-01 08:00", "2026-04-01 09:00"),
        (11, 22, "2026-04-01 08:00", "2026-04-01 09:00 "),
        (11, 22, "2026-04-01 25:00", "2026-04-01 26:00"),
        (11, 22, "2026-04-01 09:00", "2026-04-01 09:00"),
        (11, 22, "2026-04-01 10:00", "2026-04-01 09:00"),
        (11, 22, "2026-04-01 23:00", "2026-04-02 00:00"),
    ];

    for (classify_id, item_id, start, end) in cases {
        let cli = Cli::try_parse_from(submit_arguments(
            photo.path(),
            classify_id,
            item_id,
            start,
            end,
        ))
        .unwrap();
        let mut backend = FakeRoutedBackend::default();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 2, "未拒绝 classify={classify_id}, item={item_id}");
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], "invalid_input");
        assert_eq!(backend.ygdk_submit_calls, 0);
        assert!(backend.ygdk_last_submit_request.is_none());
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 阳光打卡危险照片与扩展token在路由前失败关闭() {
    let mut photos = vec![
        TestPhoto::new("empty.jpg", b""),
        TestPhoto::sparse("oversize.jpg", 10 * 1024 * 1024 + 1),
        TestPhoto::new("parameter.jpg;size=1", b"safe-photo"),
        TestPhoto::new("whitespace.bad extension", b"safe-photo"),
        TestPhoto::new("non-ascii.照片", b"safe-photo"),
        TestPhoto::new("quote\"name.jpg", b"safe-photo"),
        TestPhoto::new("line\r\nbreak.jpg", b"safe-photo"),
        TestPhoto::new("back\\slash.jpg", b"safe-photo"),
        TestPhoto::new("control\u{0085}name.jpg", b"safe-photo"),
        TestPhoto::new("trailing.jpg ", b"safe-photo"),
    ];

    for photo in &mut photos {
        let cli = Cli::try_parse_from(submit_arguments(
            photo.path(),
            11,
            22,
            "2026-04-01 08:00",
            "2026-04-01 09:00",
        ))
        .unwrap();
        let mut backend = FakeRoutedBackend::default();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 2, "未拒绝危险照片路径：{:?}", photo.path());
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], "invalid_input");
        assert_eq!(backend.ygdk_submit_calls, 0);
        assert!(backend.ygdk_last_submit_request.is_none());
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 固定路线同样在后端前拒绝危险照片扩展token() {
    let photo = TestPhoto::new("unsafe.bad;param", b"safe-photo");
    let cli = Cli::try_parse_from(submit_arguments(
        photo.path(),
        11,
        22,
        "2026-04-01 08:00",
        "2026-04-01 09:00",
    ))
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
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 2);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(backend.ygdk_submit_calls, 0);
    assert!(backend.ygdk_last_submit_request.is_none());
    assert!(stderr.is_empty());
}

#[test]
fn 阳光打卡安全收据schema拒绝false_raw与敏感扩展字段() {
    let validator = definition_validator("ygdkSubmitReceipt");
    let canonical = json!({
        "success": true,
        "message": "阳光打卡已提交",
        "recordId": 77
    });
    assert!(validator.is_valid(&canonical));
    let mut without_record = canonical.clone();
    without_record["recordId"] = Value::Null;
    assert!(validator.is_valid(&without_record));

    for invalid in [
        json!({"success": false, "message": "阳光打卡未提交", "recordId": null}),
        json!({"success": true, "message": "RAW-UPSTREAM", "recordId": 77}),
        json!({"success": true, "message": "阳光打卡已提交", "recordId": 0}),
        json!({"success": true, "message": "阳光打卡已提交", "recordId": -1}),
        json!({"success": true, "message": "阳光打卡已提交", "recordId": 77, "summary": {}}),
        json!({"success": true, "message": "阳光打卡已提交", "recordId": 77, "fileName": "PRIVATE.jpg"}),
        json!({"success": true, "message": "阳光打卡已提交", "recordId": 77, "photo": "PRIVATE"}),
        json!({"success": true, "message": "阳光打卡已提交", "recordId": 77, "token": "PRIVATE"}),
    ] {
        assert!(
            !validator.is_valid(&invalid),
            "不安全收据必须拒绝：{invalid}"
        );
    }
}
