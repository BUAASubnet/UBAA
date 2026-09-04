use super::*;
use crate::api::write::commit::finish_commit_success;
use crate::api::write::support::map_ygdk_receipt;
use crate::api::write::{
    BridgePhotoUpload, BridgeWriteOperation, BridgeYgdkSubmitRequest, BridgeYgdkSubmitTarget,
};

const CLASSIFY_ID: i32 = 3;
const ITEM_ID: i32 = 2;
const OAUTH_URL: &str = "https://app.buaa.edu.cn/uc/api/oauth/index?redirect=https%3A%2F%2Fygdk.buaa.edu.cn%2F%23%2Fhome&appid=200230221144501510&state=STATE&qrcode=1";

fn response_request(method: HttpMethod, url: &str, body: &'static str) -> ExpectedRequest {
    ExpectedRequest::new(
        method,
        url,
        HttpResponse::new(200, url, body.as_bytes().to_vec()),
    )
}

fn oauth_request() -> ExpectedRequest {
    ExpectedRequest::new(
        HttpMethod::Get,
        OAUTH_URL,
        HttpResponse::new(
            302,
            "https://ygdk.buaa.edu.cn/#/home?code=oauth-code",
            Vec::new(),
        ),
    )
}

fn login_request() -> ExpectedRequest {
    response_request(
        HttpMethod::Get,
        "https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin?code=oauth-code",
        r#"{"code":1,"result":{"uid":7,"token":"token-safe"}}"#,
    )
}

fn authority_requests(items: &'static str) -> Vec<ExpectedRequest> {
    vec![
        response_request(
            HttpMethod::Post,
            "https://ygdk.buaa.edu.cn/api/Front/Clockin/Classify/getList",
            r#"{"code":1,"result":{"list":[{"classify_id":3,"name":"阳光体育"}]}}"#,
        ),
        response_request(
            HttpMethod::Post,
            "https://ygdk.buaa.edu.cn/api/Front/Clockin/Item/getList?page=1&limit=1000&classify_id=3",
            items,
        ),
        response_request(
            HttpMethod::Post,
            "https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/getCount",
            r#"{"code":1,"result":{"term_good_count_show":4}}"#,
        ),
        response_request(
            HttpMethod::Post,
            "https://ygdk.buaa.edu.cn/api/Front/Clockin/Term/get",
            r#"{"code":1,"result":{"term_id":9,"name":"2026春"}}"#,
        ),
    ]
}

fn allowed_authority_requests() -> Vec<ExpectedRequest> {
    authority_requests(r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","sort":1}]}}"#)
}

fn request() -> BridgeYgdkSubmitRequest {
    BridgeYgdkSubmitRequest {
        target: BridgeYgdkSubmitTarget {
            classify_id: CLASSIFY_ID,
            item_id: ITEM_ID,
        },
        start_time: "2026-04-01 08:00".to_owned(),
        end_time: "2026-04-01 09:00".to_owned(),
        place: Some("脱敏操场".to_owned()),
        share_to_square: false,
        photo: BridgePhotoUpload {
            bytes: vec![0xff, 0xd8, 0xff],
            file_name: "proof.jpg".to_owned(),
            mime_type: "image/jpeg".to_owned(),
        },
    }
}

#[tokio::test]
async fn 阳光打卡prepare读取fresh唯一目标并只保存core规范化请求() {
    let root = test_root("prepare-ygdk");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(allowed_authority_requests()),
    );
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
        .prepare_ygdk_submit(request())
        .await
        .expect("唯一完整项目应签发意图");

    assert!(matches!(intent.operation, BridgeWriteOperation::YgdkSubmit));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert!(intent.target_summary.contains(&CLASSIFY_ID.to_string()));
    assert!(intent.target_summary.contains(&ITEM_ID.to_string()));
    assert!(!intent.target_summary.contains("脱敏操场"));
    assert!(!intent.target_summary.contains("proof.jpg"));
    let intents = client.write_intents.lock().await;
    let stored = intents.get(&intent.intent_id).expect("保存一次性意图");
    let PendingWrite::Ygdk(stored_request) = &stored.request else {
        panic!("必须保存 Core 规范化的阳光打卡请求");
    };
    assert_eq!(stored_request.target.classify_id, CLASSIFY_ID);
    assert_eq!(stored_request.target.item_id, ITEM_ID);
    assert_eq!(stored_request.start_time, "2026-04-01 08:00");
    assert_eq!(stored_request.end_time, "2026-04-01 09:00");
    assert_eq!(
        stored.conflict_key,
        "ygdk:3:2:2026-04-01 08:00:2026-04-01 09:00"
    );
    drop(intents);
    direct
        .assert_exhausted()
        .expect("prepare 必须只完成 fresh authority");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡重复项目按unknown失败关闭且不保存意图() {
    let root = test_root("prepare-ygdk-duplicate");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let duplicate =
        r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"},{"item_id":2,"name":"健走"}]}}"#;
    let direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(authority_requests(duplicate)),
    );
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
        .prepare_ygdk_submit(request())
        .await
        .expect_err("重复项目不得签发写意图");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    assert!(client.write_intents.lock().await.is_empty());
    direct
        .assert_exhausted()
        .expect("拒绝应停在 fresh authority");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡手工构造的错配typed目标不得签发意图() {
    let root = test_root("prepare-ygdk-mismatch");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(allowed_authority_requests()),
    );
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let mut forged = request();
    forged.target.classify_id = CLASSIFY_ID + 1;

    let error = client
        .prepare_ygdk_submit(forged)
        .await
        .expect_err("调用方手工构造错配 target 不得越过 Core fresh authority");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    assert!(client.write_intents.lock().await.is_empty());
    direct
        .assert_exhausted()
        .expect("拒绝应停在 fresh authority");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡commit重新复核并按冻结wire恰好提交一次() {
    let root = test_root("commit-ygdk-once");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let upload_url = "https://ygdk.buaa.edu.cn/api/Front/Upload/File/post";
    let submit_url = "https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/clockin";
    let expectations = [oauth_request(), login_request()]
        .into_iter()
        .chain(allowed_authority_requests())
        .chain(allowed_authority_requests())
        .chain([
            response_request(
                HttpMethod::Post,
                upload_url,
                r#"{"code":1,"result":{"file_name":"uploaded.jpg"}}"#,
            ),
            response_request(
                HttpMethod::Post,
                submit_url,
                r#"{"code":1,"result":{"record_id":77}}"#,
            ),
        ]);
    let direct = MockTransport::new(expectations);
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
        .prepare_ygdk_submit(request())
        .await
        .expect("准备写意图");

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("严格成功响应应确认提交");

    assert!(result.success);
    assert!(!result.outcome_unknown);
    assert_eq!(result.message, "阳光打卡已提交");
    let receipt = result.ygdk_receipt.expect("正记录编号应生成安全收据");
    assert_eq!(receipt.record_id, 77);
    let requests = direct.requests().expect("读取请求");
    let final_requests = requests
        .iter()
        .filter(|item| item.url == submit_url)
        .collect::<Vec<_>>();
    assert_eq!(final_requests.len(), 1);
    let body = String::from_utf8_lossy(&final_requests[0].body);
    for expected in [
        "start_time=1775001600",
        "end_time=1775005200",
        "form_time_fmt=2026-04-01+08%3A00-09%3A00",
        "classify_id=3",
        "item_id=2",
        "item_name=%E8%B7%91%E6%AD%A5",
    ] {
        assert!(body.contains(expected), "最终正文缺少 {expected}");
    }
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("一次性意图不得重用");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    direct.assert_exhausted().expect("所有请求必须恰好一次");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡照片上传失败透传为不可自动重试且不发送最终提交() {
    let root = test_root("commit-ygdk-upload-failure");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let upload_url = "https://ygdk.buaa.edu.cn/api/Front/Upload/File/post";
    let direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(allowed_authority_requests())
            .chain(allowed_authority_requests())
            .chain([response_request(
                HttpMethod::Post,
                upload_url,
                r#"{"code":1,"result":{"file_name":123}}"#,
            )]),
    );
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
        .prepare_ygdk_submit(request())
        .await
        .expect("准备写意图");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("无效上传回执不得进入最终提交");

    assert_eq!(error.code, BridgeErrorCode::UpstreamUnavailable);
    assert!(!error.retryable);
    assert_eq!(error.message, "阳光打卡照片上传未完成");
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
    let requests = direct.requests().expect("读取请求");
    assert_eq!(
        requests
            .iter()
            .filter(|item| {
                item.url == "https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/clockin"
            })
            .count(),
        0
    );
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("上传失败后意图必须已经消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    direct.assert_exhausted().expect("请求必须恰好消费");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡commit路线变化由core在任何http前拒绝并消费意图() {
    let root = test_root("commit-ygdk-route-mismatch");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let prepare_direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(allowed_authority_requests()),
    );
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        prepare_direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_ygdk_submit(request())
        .await
        .expect("准备 Direct 意图");
    prepare_direct.assert_exhausted().expect("prepare 请求完整");

    let commit_direct = MockTransport::new([]);
    let commit_webvpn = MockTransport::new([]);
    install_core(
        &client,
        store,
        "[route]\ndefault = \"webvpn\"\n",
        commit_direct.clone(),
        commit_webvpn.clone(),
    )
    .await;

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("实际路线变化必须由 Core 原子入口拒绝");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::WebVpn));
    assert!(
        commit_direct
            .requests()
            .expect("读取 Direct 请求")
            .is_empty()
    );
    assert!(
        commit_webvpn
            .requests()
            .expect("读取 WebVPN 请求")
            .is_empty()
    );
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("路线冲突后的意图必须已经消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡caller_pinned双读取不执行auto探测或跨路线回退() {
    let root = test_root("ygdk-pinned-readback");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let records_url = "https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/getList?page=1&limit=20&classify_id=3&user_id=7";
    let direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(allowed_authority_requests())
            .chain(allowed_authority_requests())
            .chain([response_request(
                HttpMethod::Post,
                records_url,
                r#"{"code":1,"result":{"list":[],"total":0}}"#,
            )]),
    );
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    let core = UbaaClient::with_routing_and_probe_ttl(
        direct.clone(),
        webvpn.clone(),
        store,
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").expect("解析 Auto 路线"),
        NeverProbe,
        Duration::ZERO,
    )
    .expect("创建 caller-pinned 测试 Core client");
    *client.inner.lock().await = Some(core);

    let overview = client
        .ygdk_overview_on_route(BridgeConnectionMode::Direct)
        .await
        .expect("概览必须固定 Direct");
    let records = client
        .ygdk_records_on_route(BridgeConnectionMode::Direct, 1, 20)
        .await
        .expect("记录必须固定 Direct");

    assert_eq!(overview.pinned_route, BridgeConnectionMode::Direct);
    assert_eq!(records.pinned_route, BridgeConnectionMode::Direct);
    assert!(records.data.content.is_empty());
    direct.assert_exhausted().expect("固定路线请求必须完整");
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 阳光打卡最终响应歧义保持outcome_unknown且意图不可复用() {
    let root = test_root("commit-ygdk-unknown");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let upload_url = "https://ygdk.buaa.edu.cn/api/Front/Upload/File/post";
    let submit_url = "https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/clockin";
    let direct = MockTransport::new(
        [oauth_request(), login_request()]
            .into_iter()
            .chain(allowed_authority_requests())
            .chain(allowed_authority_requests())
            .chain([
                response_request(
                    HttpMethod::Post,
                    upload_url,
                    r#"{"code":1,"result":{"file_name":"uploaded.jpg"}}"#,
                ),
                response_request(
                    HttpMethod::Post,
                    submit_url,
                    r#"{"code":500,"msg":"RAW token=PRIVATE"}"#,
                ),
            ]),
    );
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
        .prepare_ygdk_submit(request())
        .await
        .expect("准备写意图");

    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("final 非 strict success 必须是结果未知");

    assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(error.message, "阳光打卡结果未知，请刷新概览与记录后再操作");
    for forbidden in ["RAW", "token", "PRIVATE", "uploaded.jpg"] {
        assert!(!error.message.contains(forbidden));
    }
    let final_count = direct
        .requests()
        .expect("读取请求")
        .iter()
        .filter(|request| request.url == submit_url)
        .count();
    assert_eq!(final_count, 1);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("结果未知后的意图不得重用");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    direct.assert_exhausted().expect("最终请求不得重放");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 阳光打卡照片与请求debug不泄露字节文件名地点和时间() {
    let rendered = format!("{:?}", request());
    for secret in ["255", "proof.jpg", "脱敏操场", "2026-04-01"] {
        assert!(!rendered.contains(secret), "Debug 泄露 {secret}");
    }
}

#[test]
fn 阳光打卡bridge只接受正记录编号收据并固定未知结果文案() {
    assert!(map_ygdk_receipt(None).is_none());
    assert!(map_ygdk_receipt(Some(0)).is_none());
    assert!(map_ygdk_receipt(Some(-1)).is_none());
    let receipt = map_ygdk_receipt(Some(41)).expect("正记录编号应生成收据");
    assert_eq!(receipt.record_id, 41);
    let rendered = format!("{receipt:?}");
    assert!(!rendered.contains("classify_id"));
    assert!(!rendered.contains("item_id"));

    let unknown = map_commit_error(
        BridgeWriteOperation::YgdkSubmit,
        RoutedError {
            error: UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Network,
                false,
                "RAW token=secret file=proof.jpg",
            ),
            resolution: None,
        },
    );
    assert_eq!(unknown.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!unknown.retryable);
    assert_eq!(
        unknown.message,
        "阳光打卡结果未知，请刷新概览与记录后再操作"
    );

    let false_result = finish_commit_success(
        BridgeWriteOperation::YgdkSubmit,
        BridgeConnectionMode::Direct,
        false,
        "RAW upstream message".to_owned(),
        None,
        None,
    )
    .expect_err("Core false 不得被投影为普通成功结果");
    assert_eq!(false_result.code, BridgeErrorCode::UpstreamChanged);
    assert_eq!(false_result.message, "阳光打卡响应未确认成功");
}

#[test]
fn 阳光打卡bridge在网络前拒绝危险目标和multipart元数据() {
    let mut invalid_target = request();
    invalid_target.target.item_id = 0;
    assert_eq!(
        validate_ygdk_request(&invalid_target)
            .expect_err("非正目标必须拒绝")
            .code,
        BridgeErrorCode::InvalidInput
    );

    for file_name in [
        "../photo.jpg",
        "photo\\name.jpg",
        "photo\".jpg",
        "photo\0.jpg",
        "photo\u{7f}.jpg",
    ] {
        let mut invalid = request();
        invalid.photo.file_name = file_name.to_owned();
        assert_eq!(
            validate_ygdk_request(&invalid)
                .expect_err("危险 filename 必须拒绝")
                .code,
            BridgeErrorCode::InvalidInput
        );
    }

    for mime_type in [
        "image/",
        "image/jpeg; charset=utf-8",
        "image/jpeg png",
        "image/a/b",
        "application/octet-stream",
        "image/jpég",
    ] {
        let mut invalid = request();
        invalid.photo.mime_type = mime_type.to_owned();
        assert_eq!(
            validate_ygdk_request(&invalid)
                .expect_err("危险 MIME 必须拒绝")
                .code,
            BridgeErrorCode::InvalidInput
        );
    }

    let mut oversized = request();
    oversized.photo.bytes = vec![0; 10 * 1024 * 1024 + 1];
    assert_eq!(
        validate_ygdk_request(&oversized)
            .expect_err("超限照片必须拒绝")
            .code,
        BridgeErrorCode::InvalidInput
    );
}
