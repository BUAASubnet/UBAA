use super::*;

#[tokio::test]
async fn 准备后路线变化在无新增请求下消费意图() {
    let root = test_root("route-change");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let direct = MockTransport::new([bykc_login_request(), eligible_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备 Direct 写入");
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    install_core(
        &client,
        store,
        "[route]\ndefault = \"webvpn\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let conflict = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("路线变化必须拒绝旧 intent");
    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert!(conflict.retryable);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 准备后会话修订过期在无新增请求下归约为操作冲突() {
    let root = test_root("stale-session");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), eligible_bykc_detail_request()]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    store
        .save_dual(&DualSessionSnapshot::new(Some(ready_slot(2_002)), None))
        .expect("推进外部会话修订");
    let conflict = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("过期会话必须拒绝旧 intent");
    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert!(conflict.retryable);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 认证状态刷新会话后立即失效已准备意图() {
    let root = test_root("auth-status-invalidates-intent");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let status_url = "https://uc.buaa.edu.cn/api/uc/status";
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
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
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");

    client.auth_status().await.expect("刷新认证状态");

    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("认证状态刷新后不得提交旧意图");
    assert_eq!(error.code, BridgeErrorCode::IntentExpired);
    direct.assert_exhausted().expect("不得为旧意图发送额外请求");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 重新登录在提交等待_core_锁时仍能失效旧意图() {
    let root = test_root("intent-lock-order");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), eligible_bykc_detail_request()]);
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
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");

    let inner_guard = client.inner.lock().await;
    let mut commit = Box::pin(client.commit_write(intent.intent_id.clone()));
    let waker = futures_util::task::noop_waker();
    let mut context = Context::from_waker(&waker);
    assert!(matches!(commit.as_mut().poll(&mut context), Poll::Pending));

    // 模拟重新登录/路线重开在同一 Core 锁内使全部旧意图失效。
    client.write_intents.lock().await.clear();
    drop(inner_guard);

    let error = commit.await.expect_err("被并发失效的旧意图不得继续提交");
    assert_eq!(error.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn unknown_or_reused_intent_is_rejected_before_network() {
    let path = std::env::temp_dir().join(format!("ubaa-bridge-write-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    let error = client
        .commit_write("missing-intent".to_owned())
        .await
        .expect_err("missing intent");
    assert_eq!(error.code, BridgeErrorCode::IntentExpired);
    let _ = std::fs::remove_dir_all(path);
}

#[tokio::test]
async fn expired_intent_is_consumed_and_cannot_be_retried() {
    let path = std::env::temp_dir().join(format!(
        "ubaa-bridge-expired-intent-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let _ = std::fs::remove_dir_all(&path);
    let client = BridgeClient::open(path.to_string_lossy().into_owned()).expect("open client");
    client.write_intents.lock().await.insert(
        "expired".to_owned(),
        PendingEntry {
            request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
            expires_at: 0,
            resolved_route: BridgeConnectionMode::Direct,
            conflict_key: "bykc-select:1".to_owned(),
        },
    );
    let first = client
        .commit_write("expired".to_owned())
        .await
        .expect_err("expired intent");
    assert_eq!(first.code, BridgeErrorCode::IntentExpired);
    let second = client
        .commit_write("expired".to_owned())
        .await
        .expect_err("consumed intent cannot be retried");
    assert_eq!(second.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("dispose client");
    let _ = std::fs::remove_dir_all(path);
}
