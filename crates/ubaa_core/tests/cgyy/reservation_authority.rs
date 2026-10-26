use serde_json::{Value, json};
use ubaa_core::facade::{ActionEligibility, ErrorCode};

use super::reservation_support::{
    FIRST_TIME_ID, GROUP_ID, OTHER_DATE, OTHER_SPACE_ID, RESERVATION_DATE, SECOND_TIME_ID, SITE_ID,
    SPACE_ID, Scenario, Submit, THIRD_TIME_ID, allowed_slot, cleanup, client_for, day_body,
    day_body_with_time_slots, denied_slot, external_captcha_request, reservation_request, runtime,
    selection, space, standard_spaces,
};

#[test]
fn 场馆预约槽位把缺失畸形和未知状态保留为_typed_unknown() {
    let cases = [
        (
            "missing",
            json!({"tradeNo": null, "orderId": null, "takeUp": false}),
            Value::Null,
        ),
        (
            "malformed",
            json!({
                "reservationStatus": "bad",
                "tradeNo": null,
                "orderId": null,
                "takeUp": false
            }),
            Value::Null,
        ),
        (
            "missing-occupancy",
            json!({"reservationStatus": 1}),
            json!(1),
        ),
        (
            "malformed-occupancy",
            json!({
                "reservationStatus": 1,
                "tradeNo": [],
                "orderId": {},
                "takeUp": "bad"
            }),
            json!(1),
        ),
    ];

    for (case, slot, expected_status) in cases {
        let scenario = Scenario::new([day_body(RESERVATION_DATE, standard_spaces(slot))]);
        let (mut client, root) = client_for(case, scenario);
        let result = runtime()
            .block_on(client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
            .expect("typed unknown 仍应作为安全只读结果返回")
            .data;
        let slot = serde_json::to_value(&result.spaces[0].slots[0]).expect("序列化槽位");

        assert_eq!(slot["reservationStatus"], expected_status, "{case}");
        assert_eq!(
            slot["reservationEligibility"],
            json!(ActionEligibility::Unknown),
            "{case}"
        );
        assert_eq!(slot["reservationTarget"], Value::Null, "{case}");
        assert!(slot.get("isReservable").is_none(), "{case}");
        cleanup(root);
    }
}

#[test]
fn 场馆预约明确允许时产生完整且不可反向猜测的_typed_target() {
    let scenario = Scenario::new([day_body(RESERVATION_DATE, standard_spaces(allowed_slot()))]);
    let (mut client, root) = client_for("typed-target", scenario);

    let result = runtime()
        .block_on(client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
        .expect("明确允许槽位应返回 typed target")
        .data;
    let slot = serde_json::to_value(&result.spaces[0].slots[0]).expect("序列化槽位");

    assert_eq!(slot["reservationStatus"], json!(1));
    assert_eq!(
        slot["reservationEligibility"],
        json!(ActionEligibility::Allowed)
    );
    assert_eq!(
        slot["reservationTarget"],
        json!({
            "venueSiteId": SITE_ID,
            "reservationDate": RESERVATION_DATE,
            "spaceId": SPACE_ID,
            "timeId": FIRST_TIME_ID,
            "venueSpaceGroupId": GROUP_ID,
            "timeOrdinal": 0
        })
    );
    assert!(slot.get("isReservable").is_none());
    cleanup(root);
}

#[test]
fn 场馆预约拒绝无效选择和不唯一_fresh_target_且不进入写阶段() {
    let normal_spaces = || {
        vec![
            space(
                SPACE_ID,
                SITE_ID,
                Some(GROUP_ID),
                [
                    (FIRST_TIME_ID, allowed_slot()),
                    (SECOND_TIME_ID, allowed_slot()),
                    (THIRD_TIME_ID, allowed_slot()),
                ],
            ),
            space(
                OTHER_SPACE_ID,
                SITE_ID,
                Some(GROUP_ID + 1),
                [(FIRST_TIME_ID, allowed_slot())],
            ),
        ]
    };
    let cases = vec![
        (
            "duplicate-selection",
            vec![
                selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID)),
                selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID)),
            ],
            normal_spaces(),
        ),
        (
            "cross-space",
            vec![
                selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID)),
                selection(OTHER_SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID + 1)),
            ],
            normal_spaces(),
        ),
        (
            "more-than-two",
            vec![
                selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID)),
                selection(SPACE_ID, SECOND_TIME_ID, Some(GROUP_ID)),
                selection(SPACE_ID, THIRD_TIME_ID, Some(GROUP_ID)),
            ],
            normal_spaces(),
        ),
        (
            "non-adjacent",
            vec![
                selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID)),
                selection(SPACE_ID, THIRD_TIME_ID, Some(GROUP_ID)),
            ],
            normal_spaces(),
        ),
        (
            "group-mismatch",
            vec![selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID + 1))],
            normal_spaces(),
        ),
        (
            "duplicate-fresh-space",
            vec![selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID))],
            vec![
                space(
                    SPACE_ID,
                    SITE_ID,
                    Some(GROUP_ID),
                    [(FIRST_TIME_ID, allowed_slot())],
                ),
                space(
                    SPACE_ID,
                    SITE_ID,
                    Some(GROUP_ID),
                    [(FIRST_TIME_ID, allowed_slot())],
                ),
            ],
        ),
    ];
    let mut violations = Vec::new();

    for (case, selections, spaces) in cases {
        let scenario = Scenario::new([day_body(RESERVATION_DATE, spaces)]);
        let (mut client, root) = client_for(case, scenario.clone());
        let result = runtime()
            .block_on(client.cgyy_submit_reservation(external_captcha_request(selections)));
        if result.is_ok() {
            violations.push(format!("{case}: 无效选择被接受"));
        }
        if scenario.write_phase_count() != 0 {
            violations.push(format!(
                "{case}: 触发了 {} 个 context/captcha/submit 请求",
                scenario.write_phase_count()
            ));
        }
        cleanup(root);
    }

    assert!(violations.is_empty(), "{}", violations.join("; "));
}

#[test]
fn 重复时段身份和站点错配都只能产生_unknown_且不得授权预约() {
    let cases = [
        (
            "duplicate-time-identity",
            day_body_with_time_slots(
                RESERVATION_DATE,
                vec![
                    json!({"id": FIRST_TIME_ID, "beginTime": "08:00", "endTime": "09:00"}),
                    json!({"id": FIRST_TIME_ID, "beginTime": "09:30", "endTime": "10:30"}),
                ],
                standard_spaces(allowed_slot()),
            ),
        ),
        (
            "site-mismatch",
            day_body(
                RESERVATION_DATE,
                vec![space(
                    SPACE_ID,
                    SITE_ID + 1,
                    Some(GROUP_ID),
                    [(FIRST_TIME_ID, allowed_slot())],
                )],
            ),
        ),
    ];

    for (case, day) in cases {
        let read_scenario = Scenario::new([day.clone()]);
        let (mut read_client, read_root) = client_for(&format!("{case}-read"), read_scenario);
        let info = runtime()
            .block_on(read_client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
            .expect("身份冲突仍应保留安全只读投影")
            .data;
        assert!(
            info.spaces[0].slots.iter().all(|slot| {
                slot.reservation_eligibility == ActionEligibility::Unknown
                    && slot.reservation_target.is_none()
            }),
            "{case}"
        );
        cleanup(read_root);

        let write_scenario = Scenario::new([day]);
        let (mut write_client, write_root) =
            client_for(&format!("{case}-write"), write_scenario.clone());
        runtime()
            .block_on(
                write_client.cgyy_submit_reservation(external_captcha_request(vec![selection(
                    SPACE_ID,
                    FIRST_TIME_ID,
                    Some(GROUP_ID),
                )])),
            )
            .expect_err("身份冲突不得授权预约");
        assert_eq!(write_scenario.write_phase_count(), 0, "{case}");
        cleanup(write_root);
    }
}

#[test]
fn 展示字段残缺的同_id_时段也参与身份计数并阻止完整行授权() {
    let day = day_body_with_time_slots(
        RESERVATION_DATE,
        vec![
            json!({"id": FIRST_TIME_ID, "beginTime": "08:00", "endTime": "09:00"}),
            json!({"id": FIRST_TIME_ID, "beginTime": "09:30"}),
        ],
        standard_spaces(allowed_slot()),
    );
    let scenario = Scenario::new([day]);
    let (mut client, root) = client_for("duplicate-time-incomplete-row", scenario);

    let info = runtime()
        .block_on(client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
        .expect("残缺重复行不得破坏安全只读投影")
        .data;
    let matching = info.spaces[0]
        .slots
        .iter()
        .filter(|slot| slot.time_id == FIRST_TIME_ID)
        .collect::<Vec<_>>();

    assert!(!matching.is_empty());
    assert!(matching.iter().all(|slot| {
        slot.reservation_eligibility == ActionEligibility::Unknown
            && slot.reservation_target.is_none()
    }));
    cleanup(root);
}

#[test]
fn canonical_与非_canonical_同_display_id_仍视为重复身份() {
    let day = day_body_with_time_slots(
        RESERVATION_DATE,
        vec![
            json!({"id": FIRST_TIME_ID, "beginTime": "08:00", "endTime": "09:00"}),
            json!({"id": "0101", "beginTime": "09:30"}),
        ],
        standard_spaces(allowed_slot()),
    );
    let scenario = Scenario::new([day]);
    let (mut client, root) = client_for("mixed-canonical-time-identity", scenario);

    let info = runtime()
        .block_on(client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
        .expect("混合 canonical 重复身份仍应保留安全只读投影")
        .data;
    let matching = info.spaces[0]
        .slots
        .iter()
        .filter(|slot| slot.time_id == FIRST_TIME_ID)
        .collect::<Vec<_>>();

    assert_eq!(matching.len(), 1, "完整 canonical 展示槽位应保留");
    assert_eq!(
        matching[0].reservation_eligibility,
        ActionEligibility::Unknown
    );
    assert!(matching[0].reservation_target.is_none());
    cleanup(root);
}

#[test]
fn space_动态时段键的非_canonical_alias_会阻断写_authority() {
    let day = day_body_with_time_slots(
        RESERVATION_DATE,
        vec![json!({
            "id": FIRST_TIME_ID,
            "beginTime": "08:00",
            "endTime": "09:00"
        })],
        vec![json!({
            "id": SPACE_ID,
            "spaceName": "脱敏空间",
            "venueSiteId": SITE_ID,
            "venueSpaceGroupId": GROUP_ID,
            (FIRST_TIME_ID.to_string()): allowed_slot(),
            "0101": denied_slot()
        })],
    );
    let read_scenario = Scenario::new([day.clone()]);
    let (mut read_client, read_root) = client_for("space-slot-alias-read", read_scenario);

    let info = runtime()
        .block_on(read_client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
        .expect("动态时段键 alias 冲突仍应保留安全只读投影")
        .data;
    let slot = info.spaces[0]
        .slots
        .iter()
        .find(|slot| slot.time_id == FIRST_TIME_ID)
        .expect("canonical 时段状态应保留用于展示");
    assert_eq!(slot.reservation_eligibility, ActionEligibility::Unknown);
    assert!(slot.reservation_target.is_none());
    cleanup(read_root);

    let write_scenario = Scenario::new([day]);
    let (mut write_client, write_root) =
        client_for("space-slot-alias-write", write_scenario.clone());
    runtime()
        .block_on(
            write_client.cgyy_submit_reservation(external_captcha_request(vec![selection(
                SPACE_ID,
                FIRST_TIME_ID,
                Some(GROUP_ID),
            )])),
        )
        .expect_err("动态时段键 alias 冲突不得授权预约");
    assert_eq!(write_scenario.write_phase_count(), 0);
    cleanup(write_root);
}

#[test]
fn 非_canonical_字符串身份只供兼容展示且绝不产生预约_target() {
    let canonical_time_slots =
        vec![json!({"id": FIRST_TIME_ID, "beginTime": "08:00", "endTime": "09:00"})];
    let cases = [
        (
            "time-id",
            vec![json!({"id": "0101", "beginTime": "08:00", "endTime": "09:00"})],
            vec![space(
                SPACE_ID,
                SITE_ID,
                Some(GROUP_ID),
                [(FIRST_TIME_ID, allowed_slot())],
            )],
        ),
        (
            "space-id",
            canonical_time_slots.clone(),
            vec![json!({
                "id": "06",
                "spaceName": "脱敏空间",
                "venueSiteId": SITE_ID,
                "venueSpaceGroupId": GROUP_ID,
                (FIRST_TIME_ID.to_string()): allowed_slot()
            })],
        ),
        (
            "site-id",
            canonical_time_slots.clone(),
            vec![json!({
                "id": SPACE_ID,
                "spaceName": "脱敏空间",
                "venueSiteId": "04",
                "venueSpaceGroupId": GROUP_ID,
                (FIRST_TIME_ID.to_string()): allowed_slot()
            })],
        ),
        (
            "group-id",
            canonical_time_slots,
            vec![json!({
                "id": SPACE_ID,
                "spaceName": "脱敏空间",
                "venueSiteId": SITE_ID,
                "venueSpaceGroupId": "09",
                (FIRST_TIME_ID.to_string()): allowed_slot()
            })],
        ),
    ];

    for (case, time_slots, spaces) in cases {
        let scenario = Scenario::new([day_body_with_time_slots(
            RESERVATION_DATE,
            time_slots,
            spaces,
        )]);
        let (mut client, root) = client_for(&format!("noncanonical-{case}"), scenario);
        let info = runtime()
            .block_on(client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
            .expect("兼容只读解析不应丢弃可展示身份")
            .data;
        let matching = info.spaces[0]
            .slots
            .iter()
            .filter(|slot| slot.time_id == FIRST_TIME_ID)
            .collect::<Vec<_>>();

        assert!(!matching.is_empty(), "{case} 应保留兼容展示槽位");
        assert!(
            matching.iter().all(|slot| {
                slot.reservation_eligibility == ActionEligibility::Unknown
                    && slot.reservation_target.is_none()
            }),
            "{case}"
        );
        cleanup(root);
    }
}

#[test]
fn 场馆预约必填字段不完整时在任何网络请求前失败关闭() {
    let base = || reservation_request(vec![selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID))]);
    let mut cases = Vec::new();
    let mut request = base();
    request.phone = " \t".into();
    cases.push(("phone", request));
    let mut request = base();
    request.theme.clear();
    cases.push(("theme", request));
    let mut request = base();
    request.activity_content = "\n".into();
    cases.push(("activity-content", request));
    let mut request = base();
    request.joiners.clear();
    cases.push(("joiners", request));
    let mut request = base();
    request.purpose_type = 0;
    cases.push(("purpose-type", request));
    let mut request = base();
    request.joiner_num = 0;
    cases.push(("joiner-num", request));

    for (case, request) in cases {
        let scenario = Scenario::new([]);
        let (mut client, root) = client_for(case, scenario.clone());
        let error = runtime()
            .block_on(client.cgyy_submit_reservation(request))
            .expect_err("必填输入缺失必须失败关闭");
        assert_eq!(error.code, ErrorCode::InvalidInput, "{case}");
        assert!(scenario.requests().is_empty(), "{case}");
        cleanup(root);
    }
}

#[test]
fn 请求日期不存在时首键回退只供展示且绝不授权预约() {
    let scenario = Scenario::new([day_body(OTHER_DATE, standard_spaces(allowed_slot()))]);
    let (mut client, root) = client_for("date-fallback", scenario.clone());

    let error = runtime()
        .block_on(
            client.cgyy_submit_reservation(external_captcha_request(vec![selection(
                SPACE_ID,
                FIRST_TIME_ID,
                Some(GROUP_ID),
            )])),
        )
        .expect_err("请求日期没有精确键时不得预约");

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    assert_eq!(scenario.write_phase_count(), 0);
    cleanup(root);
}

#[test]
fn 场馆预约_prepare_与_commit_分别执行_fresh_authority_且不复用旧资格() {
    let scenario = Scenario::new([
        day_body(RESERVATION_DATE, standard_spaces(allowed_slot())),
        day_body(RESERVATION_DATE, standard_spaces(denied_slot())),
    ]);
    let (mut client, root) = client_for("fresh-authority", scenario.clone());
    let request = reservation_request(vec![selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID))]);
    let test_runtime = runtime();

    let preflight = test_runtime
        .block_on(client.preflight_cgyy_reservation(&request))
        .expect("prepare 阶段的 fresh target 明确允许")
        .data;
    assert_eq!(preflight.venue_site_id, SITE_ID);
    assert_eq!(preflight.reservation_date, RESERVATION_DATE);
    assert_eq!(preflight.targets.len(), 1);
    assert_eq!(preflight.targets[0].venue_site_id, SITE_ID);
    assert_eq!(preflight.targets[0].reservation_date, RESERVATION_DATE);
    assert_eq!(preflight.targets[0].space_id, SPACE_ID);
    assert_eq!(preflight.targets[0].time_id, FIRST_TIME_ID);
    assert_eq!(preflight.targets[0].venue_space_group_id, Some(GROUP_ID));
    assert_eq!(preflight.targets[0].time_ordinal, 0);
    assert_eq!(
        scenario.path_count("/venue-zhjs-server/api/reservation/day/info"),
        1
    );
    assert_eq!(scenario.write_phase_count(), 0);

    test_runtime
        .block_on(client.cgyy_submit_reservation(request))
        .expect_err("commit 必须 fresh 复核，不能复用 prepare 的旧 allowed target");
    assert_eq!(
        scenario.path_count("/venue-zhjs-server/api/reservation/day/info"),
        2
    );
    assert_eq!(scenario.write_phase_count(), 0);
    cleanup(root);
}

#[test]
fn 场馆预约发送后歧义统一为_outcome_unknown_且最终_submit_只发送一次() {
    let cases = [
        ("transport", Submit::TransportError),
        (
            "authentication-final-url",
            Submit::FinalUrl(
                "https://sso.buaa.edu.cn/login",
                r#"{"code":200,"message":"不得采信","data":{}}"#.into(),
            ),
        ),
        ("non-json", Submit::Response(200, "not-json".into())),
    ];
    let mut violations = Vec::new();

    for (case, submit) in cases {
        let scenario = Scenario::new([day_body(RESERVATION_DATE, standard_spaces(allowed_slot()))])
            .with_submit(submit);
        let (mut client, root) = client_for(case, scenario.clone());
        let result = runtime().block_on(client.cgyy_submit_reservation(external_captcha_request(
            vec![selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID))],
        )));
        match result {
            Ok(_) => violations.push(format!("{case}: 歧义响应被当作成功")),
            Err(error) if (error.code, error.retryable) != (ErrorCode::OutcomeUnknown, false) => {
                violations.push(format!(
                    "{case}: 得到 {:?}/retryable={}，预期 outcome_unknown/false",
                    error.code, error.retryable
                ));
            }
            Err(_) => {}
        }
        let submit_count = scenario.path_count("/venue-zhjs-server/api/reservation/order/submit");
        if submit_count != 1 {
            violations.push(format!("{case}: 最终 submit 发送 {submit_count} 次"));
        }
        cleanup(root);
    }

    assert!(violations.is_empty(), "{}", violations.join("; "));
}

#[test]
fn 场馆验证码最多三轮但最终_submit_不得重新进入循环() {
    let selections = vec![selection(SPACE_ID, FIRST_TIME_ID, Some(GROUP_ID))];

    let retry_scenario =
        Scenario::new([day_body(RESERVATION_DATE, standard_spaces(allowed_slot()))])
            .with_captcha_checks([false, false, true]);
    let (mut retry_client, retry_root) =
        client_for("captcha-preflight-retry", retry_scenario.clone());
    let result = runtime()
        .block_on(retry_client.cgyy_submit_reservation(reservation_request(selections.clone())))
        .expect("第三轮验证码通过后应提交成功")
        .data;
    assert!(result.success);
    assert_eq!(
        retry_scenario.path_count("/venue-zhjs-server/api/captcha/get"),
        3
    );
    assert_eq!(
        retry_scenario.path_count("/venue-zhjs-server/api/captcha/check"),
        3
    );
    assert_eq!(
        retry_scenario.path_count("/venue-zhjs-server/api/reservation/order/submit"),
        1
    );
    cleanup(retry_root);

    let submit_failure =
        Scenario::new([day_body(RESERVATION_DATE, standard_spaces(allowed_slot()))])
            .with_captcha_checks([true, true, true])
            .with_submit(Submit::TransportError);
    let (mut failure_client, failure_root) =
        client_for("submit-outside-captcha-loop", submit_failure.clone());
    let error = runtime()
        .block_on(failure_client.cgyy_submit_reservation(reservation_request(selections)))
        .expect_err("最终发送失败不得重新进入验证码循环");

    assert_eq!(
        (error.code, error.retryable),
        (ErrorCode::OutcomeUnknown, false)
    );
    assert_eq!(
        submit_failure.path_count("/venue-zhjs-server/api/captcha/get"),
        1
    );
    assert_eq!(
        submit_failure.path_count("/venue-zhjs-server/api/captcha/check"),
        1
    );
    assert_eq!(
        submit_failure.path_count("/venue-zhjs-server/api/reservation/order/submit"),
        1
    );
    cleanup(failure_root);
}

#[test]
fn 场馆预约错误和成功收据都不透传_raw_message_或个人数据() {
    let raw_messages = [
        "账号 user-one@example.test token=raw-one\u{0007}",
        "电话 010-12345678 cookie=raw-two\u{0008}",
    ];
    let mut safe_messages = Vec::new();
    for (index, raw_message) in raw_messages.into_iter().enumerate() {
        let day = json!({"code": 500, "message": raw_message, "data": null}).to_string();
        let scenario = Scenario::new([day]);
        let (mut client, root) = client_for(&format!("raw-error-{index}"), scenario.clone());
        let error = runtime()
            .block_on(
                client.cgyy_submit_reservation(external_captcha_request(vec![selection(
                    SPACE_ID,
                    FIRST_TIME_ID,
                    Some(GROUP_ID),
                )])),
            )
            .expect_err("非成功信封应返回固定安全错误");
        assert!(!error.message.contains("example.test"));
        assert!(!error.message.contains("010-12345678"));
        assert!(!error.message.contains("raw-one"));
        assert!(!error.message.contains("raw-two"));
        assert!(!error.message.chars().any(char::is_control));
        assert_eq!(scenario.write_phase_count(), 0);
        safe_messages.push(error.message);
        cleanup(root);
    }
    assert_eq!(safe_messages[0], safe_messages[1]);

    let submit_body = json!({
        "code": 200,
        "message": "预约成功 user-two@example.test token=raw-three\u{0007}",
        "data": {
            "orderInfo": {
                "id": 88,
                "venueSiteId": SITE_ID,
                "reservationDate": RESERVATION_DATE,
                "orderStatus": 1,
                "tradeNo": "trade-raw-four",
                "phone": "010-87654321",
                "joiners": "个人甲,个人乙",
                "activityContent": "不应离开 Core 的正文"
            }
        }
    })
    .to_string();
    let scenario = Scenario::new([day_body(RESERVATION_DATE, standard_spaces(allowed_slot()))])
        .with_submit(Submit::Response(200, submit_body));
    let (mut client, root) = client_for("safe-receipt", scenario);
    let result = runtime()
        .block_on(
            client.cgyy_submit_reservation(external_captcha_request(vec![selection(
                SPACE_ID,
                FIRST_TIME_ID,
                Some(GROUP_ID),
            )])),
        )
        .expect("明确 code=200 应返回固定安全成功结果")
        .data;
    let rendered = serde_json::to_value(result).expect("序列化场馆预约收据");

    assert_eq!(
        rendered,
        json!({
            "success": true,
            "message": "预约成功",
            "receipt": {
                "orderId": 88,
                "venueSiteId": SITE_ID,
                "reservationDate": RESERVATION_DATE,
                "orderStatus": 1
            }
        })
    );
    let serialized = rendered.to_string();
    for forbidden in [
        "example.test",
        "raw-three",
        "trade-raw-four",
        "010-87654321",
        "个人甲",
        "不应离开 Core 的正文",
    ] {
        assert!(!serialized.contains(forbidden), "泄漏字段: {forbidden}");
    }
    cleanup(root);
}

#[test]
fn 明确成功收据的站点错配时只丢弃可选站点字段() {
    let submit_body = json!({
        "code": 200,
        "message": "不得透传的上游成功文案",
        "data": {
            "orderInfo": {
                "id": 88,
                "venueSiteId": SITE_ID + 1,
                "reservationDate": RESERVATION_DATE,
                "orderStatus": 1
            }
        }
    })
    .to_string();
    let scenario = Scenario::new([day_body(RESERVATION_DATE, standard_spaces(allowed_slot()))])
        .with_submit(Submit::Response(200, submit_body));
    let (mut client, root) = client_for("receipt-site-mismatch", scenario);

    let result = runtime()
        .block_on(
            client.cgyy_submit_reservation(external_captcha_request(vec![selection(
                SPACE_ID,
                FIRST_TIME_ID,
                Some(GROUP_ID),
            )])),
        )
        .expect("明确 code=200 仍应保持成功")
        .data;
    let receipt = result.receipt.expect("正订单编号应形成安全收据");

    assert!(result.success);
    assert_eq!(receipt.order_id, 88);
    assert_eq!(receipt.venue_site_id, None);
    assert_eq!(receipt.reservation_date.as_deref(), Some(RESERVATION_DATE));
    cleanup(root);
}

#[test]
fn 明确不可预约槽位返回_denied_且不产生_target() {
    for (case, raw) in [
        ("known-denied", denied_slot()),
        (
            "other-canonical-status",
            json!({
                "reservationStatus": 99,
                "tradeNo": null,
                "orderId": null,
                "takeUp": false
            }),
        ),
    ] {
        let scenario = Scenario::new([day_body(RESERVATION_DATE, standard_spaces(raw))]);
        let (mut client, root) = client_for(case, scenario);
        let result = runtime()
            .block_on(client.cgyy_day_info(SITE_ID, RESERVATION_DATE))
            .expect("明确不可预约仍是有效只读结果")
            .data;
        let slot = serde_json::to_value(&result.spaces[0].slots[0]).expect("序列化槽位");
        assert_eq!(
            slot["reservationEligibility"],
            json!(ActionEligibility::Denied),
            "{case}"
        );
        assert_eq!(slot["reservationTarget"], Value::Null, "{case}");
        cleanup(root);
    }
}
