use super::*;
use crate::api::write::BridgeLibbookReserveRequest;

const AREA_ID: &str = "area-safe";
const SEAT_ID: &str = "seat-safe";
const DAY: &str = "2026-09-04";
const SEGMENT: &str = "segment-safe";
const START_TIME: &str = "08:00";
const END_TIME: &str = "10:00";

#[tokio::test]
async fn 图书馆预约准备读取新鲜权威并生成安全目标摘要() {
    let root = test_root("prepare-libbook-reserve");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cas_request(),
        libbook_login_request(),
        libbook_area_detail_request(),
        libbook_seats_request(
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"阅览\n座位\u0000","no":"0\r01","status":1,"status_name":"可预约"}]}}"#,
        ),
    ]);
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

    let intent = client
        .prepare_libbook_reserve(libbook_request())
        .await
        .expect("明确可预约的唯一座位应签发意图");

    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::LibbookReserve
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    for expected in [AREA_ID, SEAT_ID, DAY, SEGMENT, START_TIME, END_TIME] {
        assert!(
            intent.target_summary.contains(expected),
            "摘要缺少稳定目标字段 {expected}"
        );
    }
    assert!(intent.target_summary.contains("阅览座位"));
    assert!(intent.target_summary.contains("001"));
    assert!(!intent.target_summary.chars().any(char::is_control));
    direct
        .assert_exhausted()
        .expect("prepare 必须完成区域详情和座位的 fresh 复核");
    let requests = direct.requests().expect("读取 Direct 请求");
    assert_eq!(requests.len(), 4);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    let area_body = request_body(&requests, "/v4/Space/map");
    assert!(area_body.contains(r#""id":"area-safe""#));
    let seats_body = request_body(&requests, "/v4/Space/seat");
    for expected in [
        r#""id":"area-safe""#,
        r#""day":"2026-09-04""#,
        r#""start_time":"08:00""#,
        r#""end_time":"10:00""#,
    ] {
        assert!(seats_body.contains(expected), "座位查询正文缺少 {expected}");
    }
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆预约准备拒绝_denied_unknown_缺失和重复目标() {
    let cases = [
        (
            "denied-status-2",
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位","no":"001","status":2,"status_name":"已占用"}]}}"#,
            BridgeErrorCode::OperationConflict,
            true,
        ),
        (
            "denied-status-3",
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位","no":"001","status":3,"status_name":"临时离开"}]}}"#,
            BridgeErrorCode::OperationConflict,
            true,
        ),
        (
            "unknown-status",
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位","no":"001","status":9,"status_name":"新状态"}]}}"#,
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
        (
            "missing-status",
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位","no":"001","status_name":"状态缺失"}]}}"#,
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
        (
            "missing-target",
            r#"{"code":1,"data":{"list":[]}}"#,
            BridgeErrorCode::OperationConflict,
            true,
        ),
        (
            "duplicate-target",
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位一","no":"001","status":1,"status_name":"可预约"},{"id":"seat-safe","name":"座位二","no":"002","status":1,"status_name":"可预约"}]}}"#,
            BridgeErrorCode::UpstreamChanged,
            false,
        ),
    ];

    for (label, seats, expected_code, expected_retryable) in cases {
        let root = test_root(label);
        let _ = std::fs::remove_dir_all(&root);
        let store = seed_sessions(&root, true, false);
        let direct = MockTransport::new([
            libbook_cas_request(),
            libbook_login_request(),
            libbook_area_detail_request(),
            libbook_seats_request(seats),
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
            .prepare_libbook_reserve(libbook_request())
            .await
            .expect_err("非 Allowed 或不唯一目标不得签发意图");

        assert_eq!(error.code, expected_code, "case={label}");
        assert_eq!(error.retryable, expected_retryable, "case={label}");
        assert!(client.write_intents.lock().await.is_empty(), "case={label}");
        direct
            .assert_exhausted()
            .expect("拒绝必须停在 fresh 只读权威链");
        assert_eq!(
            direct.requests().expect("读取请求").len(),
            4,
            "case={label}"
        );
        client.dispose().await.expect("销毁 bridge");
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn 图书馆预约提交前资格漂移会消费意图且不发送最终写请求() {
    let root = test_root("commit-libbook-drift");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cas_request(),
        libbook_login_request(),
        libbook_area_detail_request(),
        available_libbook_seats_request(),
        libbook_area_detail_request(),
        libbook_seats_request(
            r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位","no":"001","status":2,"status_name":"已占用"}]}}"#,
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
        .prepare_libbook_reserve(libbook_request())
        .await
        .expect("准备图书馆预约");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("提交前座位资格漂移必须拒绝");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct
        .assert_exhausted()
        .expect("资格漂移后不得发送 space/confirm");
    let requests = direct.requests().expect("读取请求");
    assert_eq!(requests.len(), 6);
    assert!(
        !requests
            .iter()
            .any(|request| request.url.ends_with("/v4/space/confirm"))
    );
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆预约明确业务拒绝保留_false_且只发送一次() {
    let root = test_root("commit-libbook-business-false");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cas_request(),
        libbook_login_request(),
        libbook_area_detail_request(),
        available_libbook_seats_request(),
        libbook_area_detail_request(),
        available_libbook_seats_request(),
        libbook_confirm_request(200, r#"{"code":1,"message":"该座位不可预约","data":null}"#),
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
        .prepare_libbook_reserve(libbook_request())
        .await
        .expect("准备图书馆预约");

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("明确业务 false 应作为确定结果返回");

    assert!(!result.success);
    assert_eq!(result.message, "图书馆预约未完成");
    assert!(!result.message.contains("该座位不可预约"));
    assert!(!result.outcome_unknown);
    assert_eq!(confirm_request_count(&direct), 1);
    direct.assert_exhausted().expect("最终写请求必须恰好一次");
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("业务拒绝也必须消费一次性意图");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(confirm_request_count(&direct), 1);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 图书馆预约最终发送后登录失效归为_outcome_unknown_且绝不重放() {
    let root = test_root("commit-libbook-outcome-unknown");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        libbook_cas_request(),
        libbook_login_request(),
        libbook_area_detail_request(),
        available_libbook_seats_request(),
        libbook_area_detail_request(),
        available_libbook_seats_request(),
        libbook_confirm_request(200, r#"{"code":2,"message":"登录失效"}"#),
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
        .prepare_libbook_reserve(libbook_request())
        .await
        .expect("准备图书馆预约");

    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("最终请求发送后的认证歧义不得宣称失败可重试");

    assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!error.retryable);
    assert_eq!(confirm_request_count(&direct), 1);
    direct
        .assert_exhausted()
        .expect("登录失效响应后不得刷新 token 或重放最终写请求");
    assert_eq!(direct.requests().expect("读取请求").len(), 7);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

fn libbook_request() -> BridgeLibbookReserveRequest {
    BridgeLibbookReserveRequest {
        area_id: AREA_ID.into(),
        seat_id: SEAT_ID.into(),
        day: DAY.into(),
        segment: SEGMENT.into(),
        start_time: START_TIME.into(),
        end_time: END_TIME.into(),
    }
}

fn libbook_cas_request() -> ExpectedRequest {
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

fn libbook_login_request() -> ExpectedRequest {
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

fn libbook_area_detail_request() -> ExpectedRequest {
    let url = "https://booking.lib.buaa.edu.cn/v4/Space/map";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(
            200,
            url,
            r#"{"code":1,"data":{"area":{"id":"area-safe","name":"脱敏分区"},"date":{"list":[{"day":"2026-09-04","times":[{"id":"segment-safe","start":"08:00","end":"10:00"}]}]}}}"#
                .as_bytes()
                .to_vec(),
        ),
    )
}

fn available_libbook_seats_request() -> ExpectedRequest {
    libbook_seats_request(
        r#"{"code":1,"data":{"list":[{"id":"seat-safe","name":"座位","no":"001","status":1,"status_name":"可预约"}]}}"#,
    )
}

fn libbook_seats_request(body: &str) -> ExpectedRequest {
    let url = "https://booking.lib.buaa.edu.cn/v4/Space/seat";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(200, url, body.as_bytes().to_vec()),
    )
}

fn libbook_confirm_request(status: u16, body: &str) -> ExpectedRequest {
    let url = "https://booking.lib.buaa.edu.cn/v4/space/confirm";
    ExpectedRequest::new(
        HttpMethod::Post,
        url,
        HttpResponse::new(status, url, body.as_bytes().to_vec()),
    )
}

fn request_body(requests: &[ubaa_core::facade::testing::HttpRequest], path: &str) -> String {
    let request = requests
        .iter()
        .find(|request| request.url.ends_with(path))
        .unwrap_or_else(|| panic!("缺少请求 {path}"));
    String::from_utf8(request.body.clone()).expect("请求正文应为 UTF-8 JSON")
}

fn confirm_request_count(transport: &MockTransport) -> usize {
    transport
        .requests()
        .expect("读取请求")
        .iter()
        .filter(|request| request.url.ends_with("/v4/space/confirm"))
        .count()
}
