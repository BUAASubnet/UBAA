use super::*;

#[tokio::test]
async fn 有效准备先复核资格且提交只命中已解析路线() {
    let root = test_root("prepare-commit-route");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let select_url = "https://bykc.buaa.edu.cn/sscv/choseCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        eligible_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            select_url,
            HttpResponse::new(
                200,
                select_url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
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
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::BykcSelectCourse
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("提交写入");
    assert!(result.success);
    assert!(!result.outcome_unknown);
    assert!(matches!(
        result.operation,
        BridgeWriteOperation::BykcSelectCourse
    ));
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    direct.assert_exhausted().expect("Direct 脚本必须全部消费");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 4);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("同一 intent 不得重复提交");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 4);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 详情标识错配时准备拒绝且不签发意图() {
    let root = test_root("mismatched-bykc-course-id");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), mismatched_bykc_detail_request()]);
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

    let error = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("错配详情不得准备选课");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许读取错配详情");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前资格变化时消费意图且不发送选课写请求() {
    let root = test_root("changed-bykc-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        denied_bykc_detail_request(),
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
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("资格变化后不得提交选课");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct.assert_exhausted().expect("不得发送选课写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前详情标识错配时消费意图且不发送选课写请求() {
    let root = test_root("mismatched-bykc-course-id-on-commit");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        mismatched_bykc_detail_request(),
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
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备写入");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("错配详情不得通过提交前复核");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    direct.assert_exhausted().expect("不得发送选课写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("详情错配后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 资格未知时准备拒绝且不签发意图() {
    let root = test_root("unknown-bykc-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), incomplete_bykc_detail_request()]);
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

    let error = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("资格未知时不得准备选课");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许资格预检请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 退选资格未知时准备拒绝且不签发意图() {
    let root = test_root("unknown-bykc-deselect-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), unknown_deselect_bykc_detail_request()]);
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

    let error = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("资格未知时不得准备退选");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许资格预检请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 退选详情标识错配时准备拒绝且不签发意图() {
    let root = test_root("mismatched-bykc-deselect-id");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([bykc_login_request(), mismatched_bykc_detail_request()]);
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

    let error = client
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect_err("错配详情不得准备退选");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许读取错配详情");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 有效退选在准备和提交时复核且只命中已解析路线() {
    let root = test_root("prepare-commit-bykc-deselect");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let deselect_url = "https://bykc.buaa.edu.cn/sscv/delChosenCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        deselectable_bykc_detail_request(),
        deselectable_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            deselect_url,
            HttpResponse::new(
                200,
                deselect_url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
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
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 2);

    let result = client
        .commit_write(intent.intent_id)
        .await
        .expect("提交退选");
    assert!(result.success);
    assert!(matches!(
        result.operation,
        BridgeWriteOperation::BykcDeselectCourse
    ));
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    direct.assert_exhausted().expect("Direct 脚本必须全部消费");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 4);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前已退选时消费意图且不发送退选写请求() {
    let root = test_root("changed-bykc-deselect-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        deselectable_bykc_detail_request(),
        eligible_bykc_detail_request(),
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
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("已退选后不得再次提交");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct.assert_exhausted().expect("不得发送退选写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 提交前退选详情标识错配时消费意图且不发送写请求() {
    let root = test_root("mismatched-bykc-deselect-id-on-commit");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        deselectable_bykc_detail_request(),
        mismatched_bykc_detail_request(),
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
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("错配详情不得通过提交前复核");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    direct.assert_exhausted().expect("不得发送退选写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("详情错配后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}
