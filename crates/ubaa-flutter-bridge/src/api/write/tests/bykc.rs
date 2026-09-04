use super::*;

#[tokio::test]
async fn 博雅签到准备先复核当前学期资格再签发意图() {
    let root = test_root("prepare-bykc-sign");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
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
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        })
        .await
        .expect("准备博雅签到");

    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::BykcSignCourse
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert!(intent.target_summary.contains("脱敏资格课程"));
    assert!(intent.target_summary.contains("签到"));
    assert!(intent.target_summary.contains("2000-01-01 00:00:00"));
    assert!(intent.target_summary.contains("2999-12-31 23:59:59"));
    assert!(
        intent
            .warnings
            .iter()
            .any(|value| value.contains("签到范围"))
    );
    direct.assert_exhausted().expect("必须完整复核签到资格");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 3);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 同一课程同一签到类型只能保留一个待确认意图() {
    let root = test_root("duplicate-bykc-sign-intent");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
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
    let request = BridgeBykcSignCourseRequest {
        course_id: 42,
        lat: None,
        lng: None,
        sign_type: 1,
    };

    client
        .prepare_bykc_sign_course(request.clone())
        .await
        .expect("首次准备签到");
    let error = client
        .prepare_bykc_sign_course(request)
        .await
        .expect_err("同目标不得生成第二个待确认意图");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    direct.assert_exhausted().expect("两次预检均应完整结束");
    assert_eq!(direct.requests().expect("读取请求").len(), 5);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 取消确认会释放同目标意图且不发送写请求() {
    let root = test_root("discard-bykc-sign-intent");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
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
    let request = BridgeBykcSignCourseRequest {
        course_id: 42,
        lat: None,
        lng: None,
        sign_type: 1,
    };

    let first = client
        .prepare_bykc_sign_course(request.clone())
        .await
        .expect("首次准备签到");
    client
        .discard_write_intent(first.intent_id.clone())
        .await
        .expect("取消待确认意图");
    let second = client
        .prepare_bykc_sign_course(request)
        .await
        .expect("取消后允许重新准备同目标");
    assert_ne!(first.intent_id, second.intent_id);

    let discarded = client
        .commit_write(first.intent_id)
        .await
        .expect_err("已取消意图不得提交");
    assert_eq!(discarded.code, BridgeErrorCode::IntentExpired);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    direct.assert_exhausted().expect("只允许两轮只读预检");
    assert_eq!(direct.requests().expect("读取请求").len(), 5);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 博雅签到提交前资格变化时消费意图且不发送写请求() {
    let root = test_root("changed-bykc-sign-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        denied_bykc_chosen_sign_request(),
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
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        })
        .await
        .expect("准备博雅签到");
    let error = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect_err("资格变化后不得提交博雅签到");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct.assert_exhausted().expect("不得发送签到写请求");
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 5);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("资格冲突后的 intent 已消费");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 博雅签到资格未知时准备拒绝且不签发意图() {
    let root = test_root("unknown-bykc-sign-eligibility");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        unknown_bykc_chosen_sign_request(),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn,
    )
    .await;

    let error = client
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        })
        .await
        .expect_err("资格未知时不得准备博雅签到");

    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().expect("只允许资格预检请求");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 博雅签到非法类型和不完整坐标在路线解析前拒绝() {
    let root = test_root("invalid-bykc-sign-input");
    let _ = std::fs::remove_dir_all(&root);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    for request in [
        BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 3,
        },
        BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: Some(39.9),
            lng: None,
            sign_type: 1,
        },
        BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: Some(f64::NAN),
            lng: Some(116.3),
            sign_type: 1,
        },
    ] {
        let error = client
            .prepare_bykc_sign_course(request)
            .await
            .expect_err("无效输入必须在访问 Core 前拒绝");
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);
    }
    assert!(client.write_intents.lock().await.is_empty());
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 博雅签退成功只提交一次并返回准确确认文案() {
    let root = test_root("commit-bykc-sign-out");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_sign_write_request(200, r#"{"status":"0","data":{"message":"ok"}}"#),
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
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 2,
        })
        .await
        .expect("准备博雅签退");
    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("提交博雅签退");

    assert!(result.success);
    assert_eq!(result.message, "博雅签退已提交");
    assert!(!result.outcome_unknown);
    direct.assert_exhausted().expect("最终写请求必须恰好一次");
    assert_eq!(direct.requests().expect("读取请求").len(), 6);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("已消费 intent 不得重放");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取请求").len(), 6);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 博雅签到最终请求非成功响应归为结果未知() {
    let root = test_root("unknown-bykc-sign-result");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_sign_write_request(503, ""),
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
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        })
        .await
        .expect("准备博雅签到");
    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("最终响应不确定时不得宣称成功");

    assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
    direct.assert_exhausted().expect("最终写请求不得重放");
    assert_eq!(direct.requests().expect("读取请求").len(), 6);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 博雅选课确认摘要包含安全课程详情时间与容量() {
    let root = test_root("bykc-select-summary");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        summarized_selectable_bykc_detail_request(),
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
        .expect("准备选课");

    let target_summary = intent.target_summary;
    direct.assert_exhausted().expect("只允许读取课程详情");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);

    assert_eq!(
        target_summary,
        "安全课程（课程 42）·选课期 2000-01-01 00:00:00 至 2998-12-31 23:59:59·容量 0/10"
    );
    assert!(!target_summary.chars().any(char::is_control));
}

#[tokio::test]
async fn 博雅退选确认摘要包含安全课程详情与退选截止() {
    let root = test_root("bykc-deselect-summary");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        summarized_deselectable_bykc_detail_request(),
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
        .prepare_bykc_deselect_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .expect("准备退选");

    let target_summary = intent.target_summary;
    direct.assert_exhausted().expect("只允许读取课程详情");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);

    assert_eq!(
        target_summary,
        "已选课程（课程 42）·退选截止 2998-11-30 23:59:59"
    );
    assert!(!target_summary.chars().any(char::is_control));
}

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
        // Bridge 提交复核后，Core 写边界仍必须独立执行最终权威复核。
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
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 5);
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());

    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("同一 intent 不得重复提交");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 5);
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
        // Bridge 提交复核后，Core 写边界仍必须独立执行最终权威复核。
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
    assert_eq!(direct.requests().expect("读取 Direct 请求").len(), 5);
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
