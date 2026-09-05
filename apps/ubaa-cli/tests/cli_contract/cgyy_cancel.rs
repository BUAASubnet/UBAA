use std::io::Cursor;

use clap::Parser;
use serde_json::{Value, json};
use ubaa_cli::{CLI_JSON_SCHEMA_VERSION, Cli, run_with_backend, run_with_routed_backend};
use ubaa_core::facade::{ActionEligibility, CgyyCancelOrderTarget, CgyyOrder};

use crate::common::{CgyyCancelFixtureResult, FakeBackend, FakeRoutedBackend, assert_cli_schema};

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

fn canonical_order() -> Value {
    json!({
        "id": 42,
        "tradeNo": null,
        "venueSiteId": 4,
        "reservationDate": "2999-09-05",
        "reservationDateDetail": "2999-09-05",
        "venueSpaceName": "脱敏空间",
        "campusName": "脱敏校区",
        "venueName": "脱敏场馆",
        "siteName": "脱敏站点",
        "reservationStartDate": "2999-09-05 12:00:00",
        "reservationEndDate": "2999-09-05 13:00:00",
        "phone": null,
        "orderStatus": 1,
        "payStatus": null,
        "checkStatus": 1,
        "theme": "脱敏主题",
        "purposeType": 1,
        "purposeTypeName": "脱敏用途",
        "joinerNum": 1,
        "activityContent": null,
        "joiners": null,
        "checkContent": null,
        "handleReason": null,
        "remark": null,
        "cancelEligibility": "allowed",
        "cancelTarget": { "orderId": 42 },
        "cancelledTarget": null
    })
}

#[test]
fn cli_场馆取消合同升级为唯一_schema_v10() {
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
}

#[test]
fn 场馆订单取消资格仅allowed可携带正数目标() {
    let validator = definition_validator("cgyyOrder");
    let canonical = canonical_order();
    assert!(
        validator.is_valid(&canonical),
        "canonical 订单应有效：{canonical}"
    );

    let mut allowed_without_target = canonical.clone();
    allowed_without_target["cancelTarget"] = Value::Null;
    assert!(!validator.is_valid(&allowed_without_target));

    for eligibility in ["denied", "unknown"] {
        let mut forbidden_target = canonical.clone();
        forbidden_target["cancelEligibility"] = eligibility.into();
        assert!(
            !validator.is_valid(&forbidden_target),
            "{eligibility} 不得携带取消目标"
        );
        forbidden_target["cancelTarget"] = Value::Null;
        assert!(validator.is_valid(&forbidden_target));
    }

    for invalid_id in [0, -1] {
        let mut invalid_target = canonical.clone();
        invalid_target["cancelTarget"]["orderId"] = invalid_id.into();
        assert!(!validator.is_valid(&invalid_target));
    }

    let mut missing_eligibility = canonical;
    missing_eligibility
        .as_object_mut()
        .unwrap()
        .remove("cancelEligibility");
    assert!(!validator.is_valid(&missing_eligibility));
}

#[test]
fn 场馆订单只以可空typed目标暴露strict已取消证明() {
    let validator = definition_validator("cgyyOrder");
    let mut cancelled = canonical_order();
    cancelled["orderStatus"] = 2.into();
    cancelled["cancelEligibility"] = "denied".into();
    cancelled["cancelTarget"] = Value::Null;
    cancelled["cancelledTarget"] = json!({"orderId": 42});
    assert!(
        validator.is_valid(&cancelled),
        "strict 已取消证明应有效：{cancelled}"
    );

    for invalid_id in [0, -1] {
        let mut invalid = cancelled.clone();
        invalid["cancelledTarget"]["orderId"] = invalid_id.into();
        assert!(!validator.is_valid(&invalid));
    }

    let mut contradictory = cancelled.clone();
    contradictory["orderStatus"] = 1.into();
    assert!(!validator.is_valid(&contradictory));
    contradictory["orderStatus"] = 2.into();
    contradictory["cancelEligibility"] = "allowed".into();
    contradictory["cancelTarget"] = json!({"orderId": 42});
    assert!(!validator.is_valid(&contradictory));

    let mut missing_proof_field = canonical_order();
    missing_proof_field
        .as_object_mut()
        .unwrap()
        .remove("cancelledTarget");
    assert!(!validator.is_valid(&missing_proof_field));
}

#[test]
fn 场馆订单实际序列化保持strict证明与兼容id一致() {
    let value = serde_json::to_value(CgyyOrder {
        id: 42,
        order_status: Some(2),
        cancel_eligibility: ActionEligibility::Denied,
        cancel_target: None,
        cancelled_target: Some(CgyyCancelOrderTarget { order_id: 42 }),
        ..CgyyOrder::default()
    })
    .unwrap();

    assert_eq!(value["cancelledTarget"]["orderId"], value["id"]);
    assert!(definition_validator("cgyyOrder").is_valid(&value));
}

#[test]
fn 场馆取消结果只接受成功布尔与固定安全消息() {
    let validator = definition_validator("cgyyCancelOrderResult");
    let success = json!({"success": true, "message": "场馆订单已取消"});
    assert!(validator.is_valid(&success), "安全结果应有效：{success}");

    for invalid in [
        json!({"success": true}),
        json!({"message": "场馆订单已取消"}),
        json!({"success": false, "message": "场馆订单取消未完成"}),
        json!({"success": true, "message": "RAW-UPSTREAM"}),
        json!({"success": true, "message": "场馆订单已取消", "order": canonical_order()}),
        json!({"success": true, "message": "场馆订单已取消", "phone": "PRIVATE"}),
        json!({"success": true, "message": "场馆订单已取消", "tradeNo": "PRIVATE"}),
    ] {
        assert!(
            !validator.is_valid(&invalid),
            "不安全结果必须拒绝：{invalid}"
        );
    }
}

fn cancel_arguments(order_id: i32, confirm_write: bool) -> Vec<String> {
    let mut arguments = vec![
        "ubaa".to_owned(),
        "--json".to_owned(),
        "cgyy".to_owned(),
        "cancel".to_owned(),
        format!("--id={order_id}"),
    ];
    if confirm_write {
        arguments.push("--confirm-write".into());
    }
    arguments
}

#[tokio::test]
async fn 场馆取消未确认或非正目标均在路由后端前拒绝() {
    for (order_id, confirm_write) in [(42, false), (0, true), (-1, true)] {
        let cli = Cli::try_parse_from(cancel_arguments(order_id, confirm_write)).unwrap();
        let mut backend = FakeRoutedBackend::default();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();

        let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
        let value: Value = serde_json::from_slice(&stdout).unwrap();

        assert_eq!(exit, 2);
        assert_cli_schema(&value);
        assert_eq!(value["schemaVersion"], 10);
        assert_eq!(value["error"]["code"], "invalid_input");
        assert_eq!(backend.cgyy_cancel_calls, 0);
        assert!(backend.cgyy_last_cancel_request.is_none());
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn 场馆取消路由后端只调用一次并固定安全成功结果() {
    let cli = Cli::try_parse_from(cancel_arguments(42, true)).unwrap();
    let mut backend = FakeRoutedBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();
    let serialized = String::from_utf8(stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["success"], true);
    assert_eq!(value["data"]["message"], "场馆订单已取消");
    assert_eq!(value["meta"]["feature"], "cgyy");
    assert_eq!(backend.cgyy_cancel_calls, 1);
    assert_eq!(
        backend
            .cgyy_last_cancel_request
            .as_ref()
            .expect("后端必须收到 typed action")
            .order_id,
        42
    );
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "phone", "token"] {
        assert!(!serialized.contains(forbidden));
    }
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 场馆取消outcome_unknown退出5且只调用一次并隐藏原始正文() {
    let cli = Cli::try_parse_from(cancel_arguments(42, true)).unwrap();
    let mut backend = FakeRoutedBackend {
        cgyy_cancel_result: CgyyCancelFixtureResult::OutcomeUnknown,
        ..FakeRoutedBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_routed_backend(cli, &mut backend, &mut stdout, &mut stderr).await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();
    let serialized = String::from_utf8(stdout).unwrap();

    assert_eq!(exit, 5);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    assert_eq!(value["error"]["code"], "outcome_unknown");
    assert_eq!(value["error"]["retryable"], false);
    assert_eq!(
        value["error"]["message"],
        "场馆订单取消结果未知，请刷新订单列表与详情核对后再操作"
    );
    assert_eq!(backend.cgyy_cancel_calls, 1);
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "phone", "token", "Set-Cookie"] {
        assert!(!serialized.contains(forbidden));
    }
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 场馆取消发送前结构变化使用固定安全错误且只调用一次() {
    let cli = Cli::try_parse_from(cancel_arguments(42, true)).unwrap();
    let mut backend = FakeRoutedBackend {
        cgyy_cancel_result: CgyyCancelFixtureResult::PreSendChanged,
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
    assert_eq!(value["error"]["message"], "场馆订单取消资格核对响应无效");
    assert_eq!(backend.cgyy_cancel_calls, 1);
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "phone", "token"] {
        assert!(!serialized.contains(forbidden));
    }
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 固定路线场馆取消同样校验typed请求且只调用一次() {
    let invalid = Cli::try_parse_from(cancel_arguments(0, true)).unwrap();
    let mut backend = FakeBackend::default();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_backend(
        invalid,
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    assert_eq!(exit, 2);
    assert_eq!(backend.cgyy_cancel_calls, 0);
    assert!(backend.cgyy_last_cancel_request.is_none());

    let valid = Cli::try_parse_from(cancel_arguments(42, true)).unwrap();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_backend(
        valid,
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    let value: Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["data"]["message"], "场馆订单已取消");
    assert_eq!(backend.cgyy_cancel_calls, 1);
    assert_eq!(
        backend
            .cgyy_last_cancel_request
            .as_ref()
            .expect("固定后端收到请求")
            .order_id,
        42
    );
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn 固定路线场馆取消错误也固定脱敏且只调用一次() {
    for (fixture, expected_exit, expected_code, expected_message) in [
        (
            CgyyCancelFixtureResult::OutcomeUnknown,
            5,
            "outcome_unknown",
            "场馆订单取消结果未知，请刷新订单列表与详情核对后再操作",
        ),
        (
            CgyyCancelFixtureResult::PreSendChanged,
            6,
            "upstream_changed",
            "场馆订单取消资格核对响应无效",
        ),
    ] {
        let cli = Cli::try_parse_from(cancel_arguments(42, true)).unwrap();
        let mut backend = FakeBackend {
            cgyy_cancel_result: fixture,
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
        let serialized = String::from_utf8(stdout).unwrap();

        assert_eq!(exit, expected_exit);
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], expected_code);
        assert_eq!(value["error"]["message"], expected_message);
        assert_eq!(backend.cgyy_cancel_calls, 1);
        for forbidden in ["RAW-UPSTREAM", "PRIVATE", "phone", "token", "Set-Cookie"] {
            assert!(!serialized.contains(forbidden));
        }
        assert!(stderr.is_empty());
    }
}
