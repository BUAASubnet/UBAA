use super::*;
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize},
};
use ubaa_core::facade::testing::HttpRequest;

struct InterruptedTransport {
    mock: MockTransport,
    armed: Arc<AtomicBool>,
    writes: Arc<AtomicUsize>,
    after_write: bool,
}

#[tokio::test]
async fn 写后博雅回读固定原路线而不使用当前默认路线() {
    let root = test_root("pinned-readback");
    let store = seed_sessions(&root, true, true);
    let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
    ]);
    install_core(
        &client,
        store,
        "[route]\ndefault=\"webvpn\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let result = client
        .bykc_chosen_courses_on_route(BridgeConnectionMode::Direct)
        .await
        .unwrap();
    assert_eq!(result.pinned_route, BridgeConnectionMode::Direct);
    direct.assert_exhausted().unwrap();
    client.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

#[async_trait::async_trait]
impl HttpTransport for InterruptedTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::facade::Result<HttpResponse> {
        let final_write = request.url.ends_with("/signCourseByUser");
        assert!(
            !self.armed.load(Ordering::SeqCst) || self.after_write,
            "合成发送前异常"
        );
        let response = self.mock.execute(request).await?;
        if final_write {
            self.writes.fetch_add(1, Ordering::SeqCst);
            // 上游合成状态已经改变，此时丢失响应而不返回普通 Result 错误。
            panic!("合成生效后异常");
        }
        Ok(response)
    }
}

#[tokio::test]
async fn 写入生效后panic保留未知结果且发送前panic不冒充已发送() {
    for (after_write, full_hints) in [(true, false), (false, false), (true, true)] {
        let root = test_root("write-panic");
        let store = seed_sessions(&root, true, false);
        let armed = Arc::new(AtomicBool::new(false));
        let writes = Arc::new(AtomicUsize::new(0));
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        install_core(
            &client,
            store,
            "[route]\ndefault=\"direct\"\n",
            InterruptedTransport {
                mock: MockTransport::new([
                    bykc_login_request(),
                    bykc_all_config_request(),
                    signable_bykc_chosen_request(),
                    bykc_all_config_request(),
                    signable_bykc_chosen_request(),
                    bykc_sign_write_request(200, r#"{"status":"0","message":"ok"}"#),
                ]),
                armed: armed.clone(),
                writes: writes.clone(),
                after_write,
            },
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
            .unwrap();
        let (cache, mut repo) = super::cached_commit::cache(&root).await;
        if full_hints {
            for _ in 0..64 {
                repo.begin_write_readback(
                    ubaa_core::facade::WriteReadbackOperation::BykcSignCourse,
                    ubaa_core::facade::ConnectionMode::Direct,
                    100,
                )
                .unwrap();
            }
        }
        armed.store(true, Ordering::SeqCst);
        let result = client
            .commit_write_cached(&cache, intent.intent_id.clone())
            .await
            .unwrap();
        assert_eq!(
            result.cache_error,
            full_hints.then_some(crate::api::offline::BridgeCacheFailure::Capacity)
        );
        let error = result.error.unwrap();
        assert_eq!(
            repo.write_readback_hints().unwrap().len(),
            if full_hints {
                64
            } else {
                usize::from(after_write)
            }
        );
        assert_eq!(writes.load(Ordering::SeqCst), usize::from(after_write));
        assert_eq!(
            error.code,
            if after_write {
                BridgeErrorCode::OutcomeUnknown
            } else {
                BridgeErrorCode::InternalError
            }
        );
        if after_write {
            assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
        }
        assert_eq!(
            client
                .commit_write(intent.intent_id)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::IntentExpired
        );
        assert_eq!(writes.load(Ordering::SeqCst), usize::from(after_write));
        client.dispose().await.unwrap();
        drop(repo);
        drop(cache);
        std::fs::remove_dir_all(root).unwrap();
    }
}
