use super::*;
use crate::api::command::backend::CommandBackend;
use ubaa_command::RoutedCliBackend;

fn command_root(label: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/bridge_tests")
        .join(format!("{label}-{}", uuid::Uuid::new_v4()))
}

#[tokio::test]
async fn 命令尊重同客户端已有的待确认写意图() {
    let root = command_root("intent-conflict");
    let store = seed_sessions(&root, true, false);
    let url = "https://bykc.buaa.edu.cn/sscv/choseCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        eligible_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            url,
            HttpResponse::new(
                200,
                url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
        ),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).unwrap();
    install_core(
        &client,
        store,
        r#"[route]
default = "direct"
"#,
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_bykc_select_course(BridgeBykcCourseRequest { course_id: 42 })
        .await
        .unwrap();
    let mut backend = CommandBackend {
        client: &client,
        cache: None,
        command: None,
        hints: Vec::new(),
    };
    assert!(
        backend.bykc_select_course(42).await.is_err(),
        "已有意图时不得另行提交学校写入"
    );
    assert_eq!(
        direct.requests().unwrap().len(),
        3,
        "只允许两次只读准备，不得发送写请求"
    );
    assert_eq!(client.write_intents.lock().await.len(), 1);
    client.discard_write_intent(intent.intent_id).await.unwrap();
    client.dispose().await.unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 命令写入消耗共用意图并保留原始回执() {
    let root = command_root("typed-receipt");
    let store = seed_sessions(&root, true, false);
    let url = "https://bykc.buaa.edu.cn/sscv/choseCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        eligible_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            url,
            HttpResponse::new(
                200,
                url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
        ),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).unwrap();
    install_core(
        &client,
        store,
        r#"[route]
default = "direct"
"#,
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let mut backend = CommandBackend {
        client: &client,
        cache: None,
        command: None,
        hints: Vec::new(),
    };
    let receipt = backend.bykc_select_course(42).await.unwrap();
    assert_eq!(
        receipt.resolution.mode,
        ubaa_core::facade::ConnectionMode::Direct
    );
    assert!(client.write_intents.lock().await.is_empty());
    direct.assert_exhausted().unwrap();
    client.dispose().await.unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct PausedCommandWrite {
    transport: MockTransport,
    sent: std::sync::Arc<tokio::sync::Notify>,
}
#[async_trait::async_trait]
impl HttpTransport for PausedCommandWrite {
    async fn execute(
        &self,
        request: ubaa_core::facade::testing::HttpRequest,
    ) -> ubaa_core::facade::Result<HttpResponse> {
        let writing = request.url.ends_with("/choseCourse");
        let response = self.transport.execute(request).await?;
        if writing {
            self.sent.notify_one();
            std::future::pending::<()>().await;
        }
        Ok(response)
    }
}
#[tokio::test]
async fn 命令发送后换网与取消保留结果未知与原路线核对提示() {
    let root = command_root("cancel-after-send");
    let store = seed_sessions(&root, true, false);
    let url = "https://bykc.buaa.edu.cn/sscv/choseCourse";
    let direct = MockTransport::new([
        bykc_login_request(),
        eligible_bykc_detail_request(),
        eligible_bykc_detail_request(),
        ExpectedRequest::new(
            HttpMethod::Post,
            url,
            HttpResponse::new(
                200,
                url,
                br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            ),
        ),
    ]);
    let sent = std::sync::Arc::new(tokio::sync::Notify::new());
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).unwrap();
    install_core(
        &client,
        store,
        r#"[route]
default="direct"
"#,
        PausedCommandWrite {
            transport: direct.clone(),
            sent: sent.clone(),
        },
        MockTransport::new([]),
    )
    .await;
    let (cache, mut repo) = super::cached_commit::cache(&root).await;
    let argv = [
        "ubaa-cli",
        "--json",
        "bykc",
        "select",
        "--course-id",
        "42",
        "--confirm-write",
    ];
    let command = crate::api::command::BridgeCommand::parse(
        argv.iter().map(|v| (*v).into()).collect(),
        120_000,
    );
    let prepared = ubaa_command::prepare_input(
        ubaa_command::parse(argv).unwrap(),
        &mut std::io::empty(),
        &command.control,
    )
    .unwrap();
    let mut backend = CommandBackend {
        client: &client,
        cache: Some(&cache),
        command: Some(&command),
        hints: Vec::new(),
    };
    let network = client
        .inner
        .lock()
        .await
        .as_ref()
        .unwrap()
        .network_control();
    tokio::join!(
        ubaa_command::execute_attempt(&prepared, &mut backend, &command.control),
        async {
            sent.notified().await;
            let change = network
                .begin_change(false, std::time::Duration::from_secs(30))
                .unwrap();
            command.cancel();
            change.finish();
        }
    );
    let failure = command.failure(crate::api::command::BridgeCommandFailure::Cancelled);
    {
        let body = failure.body.lock().unwrap();
        assert!(
            matches!(body.as_ref(),Some(crate::api::command::Body::Error{error,..}) if error.code==ErrorCode::OutcomeUnknown),
            "发送后的取消必须保留结果未知，不能降为普通取消"
        );
        assert_eq!(repo.write_readback_hints().unwrap().len(), 1);
        direct.assert_exhausted().unwrap();
    }
    cache.close().await.unwrap();
    drop(repo);
    client.dispose().await.unwrap();
    let _ = std::fs::remove_dir_all(root);
}
