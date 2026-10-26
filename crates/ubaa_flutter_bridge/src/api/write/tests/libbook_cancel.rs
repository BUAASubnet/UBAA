use super::*;
use crate::api::read::BridgeActionEligibility;
use crate::api::write::BridgeLibbookCancelBookingRequest;
use crate::api::write::support::map_libbook_cancel_preflight_error;

const BOOKING_ID: &str = "booking-safe";
const PAGE: i32 = 3;
const LIMIT: i32 = 7;

#[tokio::test]
async fn 图书馆取消读取投影只从canonical状态产生typed资格() {
    let root = test_root("read-libbook-cancel-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        libbook_bookings_request(bookings_matrix_body()),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let page = client
        .libbook_bookings(PAGE, LIMIT)
        .await
        .expect("读取 typed 图书馆预约")
        .data;

    assert_eq!(page.bookings.len(), 6);
    assert_eq!(page.bookings[0].status, Some(1));
    assert!(matches!(
        page.bookings[0].cancel_eligibility,
        BridgeActionEligibility::Allowed
    ));
    assert_eq!(page.bookings[0].cancel_target.as_deref(), Some("allowed"));
    assert_eq!(page.bookings[0].status_name, "已结束");
    for booking in &page.bookings[1..3] {
        assert!(matches!(
            booking.cancel_eligibility,
            BridgeActionEligibility::Denied
        ));
        assert_eq!(booking.cancel_target.as_deref(), Some(booking.id.as_str()));
    }
    for booking in &page.bookings[3..] {
        assert!(matches!(
            booking.cancel_eligibility,
            BridgeActionEligibility::Unknown
        ));
        assert!(booking.cancel_target.is_none());
    }
    let requests = direct.requests().expect("读取请求");
    assert_bookings_page_body(&requests, PAGE, LIMIT);
    direct.assert_exhausted().expect("只读取指定预约页");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消准备读取fresh同页权威并完整保存安全请求() {
    let root = test_root("prepare-libbook-cancel");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let intent = client
        .prepare_libbook_cancel_booking(BridgeLibbookCancelBookingRequest {
            id: format!("  {BOOKING_ID}  "),
            page: PAGE,
            limit: LIMIT,
        })
        .await
        .expect("fresh 页中唯一 allowed 预约应签发 intent");

    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::LibbookCancelBooking
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    for expected in [
        BOOKING_ID,
        "脱敏预约",
        "脱敏分区",
        "001",
        "2026-09-04",
        "08:00",
        "10:00",
    ] {
        assert!(
            intent.target_summary.contains(expected),
            "安全摘要缺少 {expected}"
        );
    }
    assert!(!intent.target_summary.chars().any(char::is_control));
    let intents = client.write_intents.lock().await;
    let stored = intents.get(&intent.intent_id).expect("保存一次性 intent");
    let PendingWrite::LibbookCancel(request) = &stored.request else {
        panic!("intent 必须保存图书馆取消请求");
    };
    assert_eq!(request.id, BOOKING_ID);
    assert_eq!(request.page, PAGE);
    assert_eq!(request.limit, LIMIT);
    assert_eq!(stored.conflict_key, format!("libbook-cancel:{BOOKING_ID}"));
    drop(intents);
    let requests = direct.requests().expect("读取请求");
    assert_bookings_page_body(&requests, PAGE, LIMIT);
    assert_eq!(cancel_request_count(&direct), 0);
    direct
        .assert_exhausted()
        .expect("prepare 只完成 fresh 读取");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消本地非法输入在任何网络前拒绝且不保存意图() {
    let root = test_root("invalid-libbook-cancel");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    for request in [
        BridgeLibbookCancelBookingRequest {
            id: " \n\t ".to_owned(),
            page: PAGE,
            limit: LIMIT,
        },
        BridgeLibbookCancelBookingRequest {
            id: BOOKING_ID.to_owned(),
            page: 0,
            limit: LIMIT,
        },
        BridgeLibbookCancelBookingRequest {
            id: BOOKING_ID.to_owned(),
            page: PAGE,
            limit: 0,
        },
    ] {
        let error = client
            .prepare_libbook_cancel_booking(request)
            .await
            .expect_err("非法目标或分页不得进入 Core");
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);
    }
    assert!(client.write_intents.lock().await.is_empty());
    assert!(direct.requests().expect("读取 Direct 请求").is_empty());
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消准备只为明确allowed且唯一目标保存意图() {
    let cases = [
        (
            "prepare-libbook-cancel-denied",
            bookings_body(BOOKING_ID, "6", "已预约", "脱敏预约"),
            BridgeErrorCode::OperationConflict,
            true,
        ),
        (
            "prepare-libbook-cancel-unknown",
            bookings_body(BOOKING_ID, "9", "可取消", "脱敏预约"),
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
        (
            "prepare-libbook-cancel-missing-status",
            bookings_body(BOOKING_ID, "null", "可取消", "脱敏预约"),
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
        (
            "prepare-libbook-cancel-duplicate",
            duplicate_bookings_body(),
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
    ];

    for (label, body, expected_code, expected_retryable) in cases {
        let root = test_root(label);
        let _ = std::fs::remove_dir_all(&root);
        let store = seed_sessions(&root, true, false);
        let direct = MockTransport::new([
            libbook_cancel_cas_request(),
            libbook_cancel_login_request(),
            libbook_bookings_request(body),
        ]);
        let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
        install_core(
            &client,
            store,
            "[route]\ndefault = \"direct\"\n",
            direct.clone(),
            MockTransport::new([]),
        )
        .await;

        let error = client
            .prepare_libbook_cancel_booking(cancel_request())
            .await
            .expect_err("Denied、Unknown 或重复目标不得签发 intent");

        assert_eq!(error.code, expected_code, "case={label}");
        assert_eq!(error.retryable, expected_retryable, "case={label}");
        assert!(client.write_intents.lock().await.is_empty(), "case={label}");
        assert_eq!(cancel_request_count(&direct), 0, "case={label}");
        direct.assert_exhausted().expect("只完成 fresh 同页查询");
        client.dispose().await.expect("销毁 bridge");
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn 图书馆取消准备与提交的预约列表错误不跨越_bridge_边界() {
    let unsafe_body = r#"{"code":2,"message":"失败\n学号=private token=secret\u0000"}"#.to_owned();

    let root = test_root("prepare-libbook-cancel-unsafe-member-message");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        libbook_bookings_request(unsafe_body.clone()),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let error = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect_err("prepare 原始上游文案必须安全归约");
    assert_safe_cancel_authority_error(&error);
    assert!(client.write_intents.lock().await.is_empty());
    assert_eq!(cancel_request_count(&direct), 0);
    direct
        .assert_exhausted()
        .expect("prepare 只发送预约列表请求");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);

    let root = test_root("commit-libbook-cancel-unsafe-member-message");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
        libbook_bookings_request(unsafe_body),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect("先准备图书馆取消");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("commit 原始上游文案必须安全归约");
    assert_safe_cancel_authority_error(&error);
    assert_eq!(cancel_request_count(&direct), 0);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("失败后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    direct.assert_exhausted().expect("commit 不得发送 cancel");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消提交前资格漂移会消费意图且不发送_cancel() {
    let root = test_root("commit-libbook-cancel-drift");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
        libbook_bookings_request(bookings_body(BOOKING_ID, "6", "已取消", "脱敏预约")),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect("准备图书馆取消");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("提交前取消资格漂移必须拒绝");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert_eq!(cancel_request_count(&direct), 0);
    direct
        .assert_exhausted()
        .expect("资格漂移后不得发送 cancel");
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消成功使用固定文案且重复commit不会重发() {
    let root = test_root("commit-libbook-cancel-once");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
        allowed_bookings_request(),
        libbook_cancel_write_request(200, r#"{"code":1,"message":"取消成功"}"#),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect("准备图书馆取消");

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("取消成功应返回确定结果");

    assert!(result.success);
    assert_eq!(result.message, "图书馆预约已取消");
    assert!(!result.outcome_unknown);
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(cancel_request_count(&direct), 1);
    assert_cancel_wire_body(&direct, BOOKING_ID);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("一次性 intent 不得重复提交");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(cancel_request_count(&direct), 1);
    direct.assert_exhausted().expect("最终 cancel 恰好发送一次");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消确定业务false保持失败并隐藏上游文案() {
    let root = test_root("commit-libbook-cancel-business-false");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
        allowed_bookings_request(),
        libbook_cancel_write_request(200, r#"{"code":1,"message":"取消失败 token=secret"}"#),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect("准备图书馆取消");

    let result = client
        .commit_write(intent.intent_id)
        .await
        .expect("确定业务 false 应作为确定结果返回");

    assert!(!result.success);
    assert_eq!(result.message, "图书馆预约取消未完成");
    assert!(!result.message.contains("secret"));
    assert!(!result.outcome_unknown);
    assert_eq!(cancel_request_count(&direct), 1);
    direct.assert_exhausted().expect("确定业务 false 不得重放");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消发送后歧义透传core分类且绝不重放() {
    let root = test_root("commit-libbook-cancel-unknown");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
        allowed_bookings_request(),
        libbook_cancel_write_request(200, r#"{"code":2,"message":"登录失效"}"#),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect("准备图书馆取消");

    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("最终请求发送后的认证歧义必须保持未知结果");

    assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(cancel_request_count(&direct), 1);
    direct
        .assert_exhausted()
        .expect("认证歧义后不得刷新 bearer 或重放 cancel");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆取消意图跨越认证状态刷新后失效() {
    let root = test_root("libbook-cancel-auth-lifecycle");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let status_url = "https://uc.buaa.edu.cn/api/uc/status";
    let direct = MockTransport::new([
        libbook_cancel_cas_request(),
        libbook_cancel_login_request(),
        allowed_bookings_request(),
        ExpectedRequest::new(
            HttpMethod::Get,
            status_url,
            HttpResponse::new(
                200,
                status_url,
                br#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#
                    .to_vec(),
            ),
        ),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_libbook_cancel_booking(cancel_request())
        .await
        .expect("准备图书馆取消");

    client.auth_status().await.expect("刷新认证状态");
    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("认证状态刷新后不得提交旧取消 intent");

    assert_eq!(error.code, BridgeErrorCode::IntentExpired);
    assert_eq!(cancel_request_count(&direct), 0);
    direct
        .assert_exhausted()
        .expect("旧 intent 不得触发额外请求");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 图书馆取消错误只信任core显式发送边界() {
    let preflight = map_libbook_cancel_preflight_error(RoutedError {
        error: UbaaError::new(
            ErrorCode::NetworkError,
            ErrorKind::Network,
            true,
            "fixture preflight network error",
        ),
        resolution: None,
    });
    assert_eq!(preflight.code, BridgeErrorCode::NetworkError);
    assert!(preflight.retryable);

    let changed = map_libbook_cancel_preflight_error(RoutedError {
        error: UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "失败\n学号=private token=secret\0",
        ),
        resolution: None,
    });
    assert_safe_cancel_authority_error(&changed);

    let pre_send = map_commit_error(
        BridgeWriteOperation::LibbookCancelBooking,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::Timeout,
                ErrorKind::Network,
                true,
                "fixture commit preflight timeout",
            ),
            resolution: None,
        },
    );
    assert_eq!(pre_send.code, BridgeErrorCode::Timeout);
    assert!(pre_send.retryable);

    let changed = map_commit_error(
        BridgeWriteOperation::LibbookCancelBooking,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::UpstreamChanged,
                ErrorKind::Upstream,
                false,
                "失败\n学号=private token=secret\0",
            ),
            resolution: None,
        },
    );
    assert_safe_cancel_authority_error(&changed);

    let post_send = map_commit_error(
        BridgeWriteOperation::LibbookCancelBooking,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Upstream,
                true,
                "fixture libbook cancel outcome unknown",
            ),
            resolution: None,
        },
    );
    assert_eq!(post_send.code, BridgeErrorCode::OutcomeUnknown);
    assert_eq!(post_send.kind, BridgeErrorKind::Upstream);
    assert!(!post_send.retryable);
    assert_eq!(post_send.message, "fixture libbook cancel outcome unknown");
}

fn cancel_request() -> BridgeLibbookCancelBookingRequest {
    BridgeLibbookCancelBookingRequest {
        id: BOOKING_ID.to_owned(),
        page: PAGE,
        limit: LIMIT,
    }
}

fn assert_safe_cancel_authority_error(error: &crate::api::client::BridgeError) {
    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert_eq!(error.kind, BridgeErrorKind::Upstream);
    assert!(!error.retryable);
    assert_eq!(error.message, "图书馆预约取消资格核对响应无效");
    for unsafe_fragment in ["private", "secret", "学号", "token", "\n", "\0"] {
        assert!(!error.message.contains(unsafe_fragment));
    }
}

fn libbook_cancel_cas_request() -> ExpectedRequest {
    let url = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbooking.lib.buaa.edu.cn%2Fv4%2Flogin%2Fcas";
    ExpectedRequest::new(
        HttpMethod::Get,
        url,
        HttpResponse::new(
            200,
            "https://booking.lib.buaa.edu.cn/h5/index.html#/cas/?cas=cas-safe",
            Vec::new(),
        ),
    )
}

fn libbook_cancel_login_request() -> ExpectedRequest {
    let url = "https://booking.lib.buaa.edu.cn/v4/login/user";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            br#"{"code":0,"data":{"member":{"token":"token-safe"}}}"#.to_vec(),
        ),
    )
}

fn allowed_bookings_request() -> ExpectedRequest {
    libbook_bookings_request(bookings_body(
        BOOKING_ID,
        "1",
        "已结束",
        "脱敏\\n预约\\u0000",
    ))
}

fn libbook_bookings_request(body: String) -> ExpectedRequest {
    let url = "https://booking.lib.buaa.edu.cn/v4/member/seat";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(200, url, body.into_bytes()),
    )
}

fn libbook_cancel_write_request(status: u16, body: &'static str) -> ExpectedRequest {
    let url = "https://booking.lib.buaa.edu.cn/v4/space/cancel";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(status, url, body.as_bytes().to_vec()),
    )
}

fn bookings_body(id: &str, status: &str, status_name: &str, name: &str) -> String {
    format!(
        r#"{{"code":1,"data":{{"list":[{{"id":"{id}","nameMerge":"{name}","name":"脱敏分区","no":"001","day":"2026-09-04","beginTime":"08:00","endTime":"10:00","status":{status},"statusName":"{status_name}"}}],"page":{PAGE},"limit":{LIMIT},"total":1}}}}"#,
    )
}

fn bookings_matrix_body() -> String {
    format!(
        r#"{{"code":1,"data":{{"list":[
            {{"id":"allowed","status":1,"statusName":"已结束"}},
            {{"id":"denied-6","status":6,"statusName":"已预约"}},
            {{"id":"denied-8","status":8,"statusName":"已预约"}},
            {{"id":"missing","statusName":"已预约"}},
            {{"id":"noncanonical","status":"01","statusName":"已预约"}},
            {{"id":"other","status":9,"statusName":"已预约"}}
        ],"page":{PAGE},"limit":{LIMIT},"total":6}}}}"#,
    )
}

fn duplicate_bookings_body() -> String {
    format!(
        r#"{{"code":1,"data":{{"list":[
            {{"id":"{BOOKING_ID}","status":1,"statusName":"已预约"}},
            {{"id":"{BOOKING_ID}","status":1,"statusName":"已预约"}}
        ],"page":{PAGE},"limit":{LIMIT},"total":2}}}}"#,
    )
}

fn assert_bookings_page_body(
    requests: &[ubaa_core::facade::testing::HttpRequest],
    page: i32,
    limit: i32,
) {
    let body = request_body_for(requests, "/v4/member/seat");
    assert!(body.contains(r#""type":"1""#));
    assert!(body.contains(&format!(r#""page":{page}"#)));
    assert!(body.contains(&format!(r#""limit":{limit}"#)));
}

fn assert_cancel_wire_body(transport: &MockTransport, booking_id: &str) {
    let requests = transport.requests().expect("读取请求");
    let body = request_body_for(&requests, "/v4/space/cancel");
    assert_eq!(body, format!(r#"{{"id":"{booking_id}"}}"#));
    assert!(!body.contains("page"));
    assert!(!body.contains("limit"));
    assert!(!body.contains("status"));
}

fn request_body_for(requests: &[ubaa_core::facade::testing::HttpRequest], path: &str) -> String {
    let request = requests
        .iter()
        .find(|request| request.url.ends_with(path))
        .unwrap_or_else(|| panic!("缺少请求 {path}"));
    String::from_utf8(request.body.clone()).expect("请求正文应为 UTF-8 JSON")
}

fn cancel_request_count(transport: &MockTransport) -> usize {
    transport
        .requests()
        .expect("读取请求")
        .iter()
        .filter(|request| request.url.ends_with("/v4/space/cancel"))
        .count()
}
