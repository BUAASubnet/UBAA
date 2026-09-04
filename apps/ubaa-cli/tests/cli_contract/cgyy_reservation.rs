use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};
use ubaa_cli::{
    AggregateJsonEnvelope, AggregateLogoutData, CLI_JSON_SCHEMA_VERSION, CliFeature,
    ResolvedRoutedJsonMeta, RoutedJsonEnvelope, UnresolvedRoutedJsonMeta,
};
use ubaa_core::facade::{
    ActionEligibility, CgyyDayInfo, CgyyReservationReceipt, CgyyReservationResult,
    CgyyReservationTarget, CgyySlotStatus, CgyySpaceAvailability, CgyyTimeSlot, ConnectionMode,
    ErrorCode, ErrorKind, LoginOutcome, LoginReadiness, RouteLoginResult, RouteLoginState,
    RoutePolicy, SafeError, UbaaError,
};

fn contract_schema() -> Value {
    serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap()
}

fn contract_validator() -> jsonschema::Validator {
    jsonschema::validator_for(&contract_schema()).unwrap()
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

fn cgyy_day_data() -> Value {
    serde_json::to_value(CgyyDayInfo {
        venue_site_id: 4,
        reservation_date: "2026-09-05".into(),
        available_dates: vec!["2026-09-05".into()],
        time_slots: vec![
            CgyyTimeSlot {
                id: 242,
                begin_time: "08:00".into(),
                end_time: "09:00".into(),
                label: "08:00-09:00".into(),
            },
            CgyyTimeSlot {
                id: 243,
                begin_time: "09:00".into(),
                end_time: "10:00".into(),
                label: "09:00-10:00".into(),
            },
        ],
        spaces: vec![CgyySpaceAvailability {
            space_id: 6,
            space_name: "脱敏场地".into(),
            venue_site_id: 4,
            venue_space_group_id: Some(9),
            slots: vec![
                CgyySlotStatus {
                    time_id: 242,
                    reservation_status: Some(1),
                    reservation_eligibility: ActionEligibility::Allowed,
                    reservation_target: Some(CgyyReservationTarget {
                        venue_site_id: 4,
                        reservation_date: "2026-09-05".into(),
                        space_id: 6,
                        time_id: 242,
                        venue_space_group_id: Some(9),
                        time_ordinal: 0,
                    }),
                    start_date: None,
                    end_date: None,
                    trade_no: None,
                    order_id: None,
                    use_num: Some(1),
                    already_num: Some(0),
                    take_up: Some(false),
                    take_up_explain: None,
                },
                CgyySlotStatus {
                    time_id: 243,
                    reservation_status: None,
                    reservation_eligibility: ActionEligibility::Unknown,
                    reservation_target: None,
                    start_date: None,
                    end_date: None,
                    trade_no: None,
                    order_id: None,
                    use_num: None,
                    already_num: None,
                    take_up: None,
                    take_up_explain: None,
                },
            ],
        }],
        reservation_total_num: Some(2),
    })
    .unwrap()
}

fn safe_error(message: &str) -> SafeError {
    SafeError {
        code: "authentication_required".into(),
        kind: "authentication".into(),
        retryable: false,
        message: message.into(),
    }
}

fn aggregate_auth_failure() -> Value {
    let outcome = LoginOutcome {
        readiness: LoginReadiness::NoneReady,
        routes: [
            RouteLoginResult {
                route: ConnectionMode::Direct,
                state: RouteLoginState::Failed,
                error: Some(safe_error("Direct 未认证")),
            },
            RouteLoginResult {
                route: ConnectionMode::WebVpn,
                state: RouteLoginState::Failed,
                error: Some(safe_error("WebVPN 未认证")),
            },
        ],
        profile: None,
    };
    serde_json::to_value(
        AggregateJsonEnvelope::auth_failure(
            outcome,
            safe_error("两条路线均未认证"),
            RoutePolicy::Auto,
        )
        .unwrap(),
    )
    .unwrap()
}

fn with_schema_version(mut value: Value, version: u32) -> Value {
    value["schemaVersion"] = version.into();
    value
}

#[test]
fn cli_唯一_json_schema_版本为_9() {
    assert_eq!(CLI_JSON_SCHEMA_VERSION, 9);
}

#[test]
fn 四类_cli_信封只接受_schema_v9_并拒绝旧_v8() {
    let meta = ResolvedRoutedJsonMeta::explicit(CliFeature::Cgyy, ConnectionMode::Direct);
    let envelopes = [
        (
            "resolved success",
            serde_json::to_value(RoutedJsonEnvelope::success(cgyy_day_data(), meta)).unwrap(),
        ),
        (
            "resolved failure",
            serde_json::to_value(RoutedJsonEnvelope::<Value>::resolved_failure(
                UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, "请求无效"),
                meta,
            ))
            .unwrap(),
        ),
        (
            "unresolved failure",
            serde_json::to_value(RoutedJsonEnvelope::<Value>::unresolved_failure(
                UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, "请求无效"),
                UnresolvedRoutedJsonMeta::new(CliFeature::Cgyy),
            ))
            .unwrap(),
        ),
        ("aggregate auth", aggregate_auth_failure()),
        (
            "aggregate logout",
            serde_json::to_value(
                AggregateJsonEnvelope::<AggregateLogoutData>::logout_success(RoutePolicy::Auto),
            )
            .unwrap(),
        ),
    ];
    let validator = contract_validator();

    for (kind, envelope) in envelopes {
        let current = with_schema_version(envelope, 9);
        assert!(
            validator.is_valid(&current),
            "schema v9 应接受 {kind} 信封：{current}"
        );

        let old = with_schema_version(current, 8);
        assert!(
            !validator.is_valid(&old),
            "schema v9 必须拒绝旧 v8 {kind} 信封：{old}"
        );
    }
}

#[test]
fn 场馆日期槽位使用可空原始状态_typed_资格与完整稳定目标() {
    let validator = definition_validator("cgyyDayInfo");
    let canonical = cgyy_day_data();

    assert!(
        validator.is_valid(&canonical),
        "typed 场馆日期合同应有效：{canonical}"
    );

    let mut legacy_bool = canonical.clone();
    legacy_bool["spaces"][0]["slots"][0]["isReservable"] = true.into();
    assert!(!validator.is_valid(&legacy_bool));

    let mut missing_eligibility = canonical.clone();
    missing_eligibility["spaces"][0]["slots"][0]
        .as_object_mut()
        .unwrap()
        .remove("reservationEligibility");
    assert!(!validator.is_valid(&missing_eligibility));

    let mut invalid_eligibility = canonical.clone();
    invalid_eligibility["spaces"][0]["slots"][0]["reservationEligibility"] = "reservable".into();
    assert!(!validator.is_valid(&invalid_eligibility));

    let mut incomplete_target = canonical.clone();
    incomplete_target["spaces"][0]["slots"][0]["reservationTarget"]
        .as_object_mut()
        .unwrap()
        .remove("timeOrdinal");
    assert!(!validator.is_valid(&incomplete_target));

    let mut allowed_without_target = canonical.clone();
    allowed_without_target["spaces"][0]["slots"][0]["reservationTarget"] = Value::Null;
    assert!(!validator.is_valid(&allowed_without_target));

    for eligibility in ["unknown", "denied"] {
        let mut non_allowed_with_target = canonical.clone();
        non_allowed_with_target["spaces"][0]["slots"][0]["reservationEligibility"] =
            eligibility.into();
        assert!(
            !validator.is_valid(&non_allowed_with_target),
            "{eligibility} 槽位不得携带预约目标：{non_allowed_with_target}"
        );
    }

    for field in ["venueSiteId", "spaceId", "timeId", "venueSpaceGroupId"] {
        for invalid_id in [0, -1] {
            let mut invalid_target = canonical.clone();
            invalid_target["spaces"][0]["slots"][0]["reservationTarget"][field] = invalid_id.into();
            assert!(
                !validator.is_valid(&invalid_target),
                "预约目标 {field} 必须为正数：{invalid_target}"
            );
        }
    }

    let mut nullable_group = canonical.clone();
    nullable_group["spaces"][0]["venueSpaceGroupId"] = Value::Null;
    nullable_group["spaces"][0]["slots"][0]["reservationTarget"]["venueSpaceGroupId"] = Value::Null;
    assert!(validator.is_valid(&nullable_group));

    let mut negative_ordinal = canonical.clone();
    negative_ordinal["spaces"][0]["slots"][0]["reservationTarget"]["timeOrdinal"] = (-1).into();
    assert!(!validator.is_valid(&negative_ordinal));

    let mut empty_target_date = canonical.clone();
    empty_target_date["spaces"][0]["slots"][0]["reservationTarget"]["reservationDate"] = "".into();
    assert!(
        !validator.is_valid(&empty_target_date),
        "预约目标日期不得为空：{empty_target_date}"
    );

    let mut out_of_range_status = canonical;
    out_of_range_status["spaces"][0]["slots"][0]["reservationStatus"] = 2_147_483_648_i64.into();
    assert!(!validator.is_valid(&out_of_range_status));
}

#[test]
fn 场馆提交结果只允许安全收据且不接受完整订单与敏感字段() {
    let validator = definition_validator("cgyyRoutedData");
    let success = serde_json::to_value(CgyyReservationResult {
        success: true,
        message: "预约提交成功".into(),
        receipt: Some(CgyyReservationReceipt {
            order_id: 42,
            venue_site_id: Some(4),
            reservation_date: Some("2026-09-05".into()),
            order_status: Some(1),
        }),
    })
    .unwrap();
    let business_false = serde_json::to_value(CgyyReservationResult {
        success: false,
        message: "预约未完成".into(),
        receipt: None,
    })
    .unwrap();

    assert!(
        validator.is_valid(&success),
        "安全成功收据应符合合同：{success}"
    );
    assert!(
        validator.is_valid(&business_false),
        "确定的业务 false 也必须有显式结果分支：{business_false}"
    );

    let mut false_with_receipt = business_false.clone();
    false_with_receipt["receipt"] = success["receipt"].clone();
    assert!(
        !validator.is_valid(&false_with_receipt),
        "确定业务 false 不得携带订单收据：{false_with_receipt}"
    );

    let mut full_order = success.clone();
    full_order["order"] = json!({
        "id": 42,
        "phone": "010-00000000",
        "joiners": "脱敏参与人",
        "activityContent": "脱敏活动内容",
        "tradeNo": "SAFE-TRADE"
    });
    assert!(!validator.is_valid(&full_order));

    for field in ["phone", "joiners", "activityContent", "tradeNo"] {
        let mut leaking_receipt = success.clone();
        leaking_receipt["receipt"][field] = "禁止出现在安全收据中".into();
        assert!(
            !validator.is_valid(&leaking_receipt),
            "安全收据不得接受 {field}：{leaking_receipt}"
        );
    }

    for field in ["orderId", "venueSiteId"] {
        for invalid_id in [0, -1] {
            let mut invalid_receipt = success.clone();
            invalid_receipt["receipt"][field] = invalid_id.into();
            assert!(
                !validator.is_valid(&invalid_receipt),
                "安全收据 {field} 必须为正数：{invalid_receipt}"
            );
        }
    }

    let mut nullable_site = success;
    nullable_site["receipt"]["venueSiteId"] = Value::Null;
    assert!(validator.is_valid(&nullable_site));
}

#[test]
fn 场馆预约标准输入拒绝_core_内部验证码字段() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let config = std::env::temp_dir().join(format!(
        "ubaa-cli-cgyy-private-input-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&config).unwrap();
    std::fs::write(
        config.join("config.toml"),
        "schema_version = 1\n\n[route]\ndefault = \"direct\"\n",
    )
    .unwrap();

    let mut child = Command::new(env!("CARGO_BIN_EXE_ubaa"))
        .arg("--json")
        .arg("--config-dir")
        .arg(&config)
        .arg("cgyy")
        .arg("submit")
        .arg("--request-stdin")
        .arg("--confirm-write")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(
            r#"{
                "venueSiteId": 4,
                "reservationDate": "2026-09-05",
                "selections": [{"spaceId": 6, "timeId": 242, "venueSpaceGroupId": 9}],
                "phone": "010-00000000",
                "theme": "脱敏主题",
                "purposeType": 1,
                "joinerNum": 1,
                "activityContent": "脱敏活动内容",
                "joiners": "脱敏参与人",
                "isPhilosophySocialSciences": false,
                "isOffSchoolJoiner": false,
                "captchaVerification": "private-verification",
                "captchaPointJson": "private-point-json",
                "captchaToken": "private-captcha-token",
                "captchaSecretKey": "private-secret-key",
                "captchaOriginalImageBase64": "private-original-image",
                "captchaJigsawImageBase64": "private-jigsaw-image"
            }"#
            .as_bytes(),
        )
        .unwrap();
    let output = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&config);
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();

    assert_eq!(output.status.code(), Some(2));
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(value["meta"]["feature"], "cgyy");
    assert!(output.stderr.is_empty());
    for forbidden in [
        "private-verification",
        "private-point-json",
        "private-captcha-token",
        "private-secret-key",
        "private-original-image",
        "private-jigsaw-image",
    ] {
        assert!(!String::from_utf8_lossy(&output.stdout).contains(forbidden));
    }
}
