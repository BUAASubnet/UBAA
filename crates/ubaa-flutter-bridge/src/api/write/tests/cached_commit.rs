use super::*;
use crate::api::offline::{BridgeCacheFailure, BridgeOfflineCache};
use ubaa_core::facade::{
    CacheCompleteness, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
    CachedBykcCourse, ConnectionMode, OfflineRepository,
};
const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
fn scope(route: ConnectionMode, id: i64) -> CacheScope {
    CacheScope {
        route,
        query: CacheQuery::BykcDetail { course_id: id },
    }
}
async fn cache(root: &Path) -> (BridgeOfflineCache, OfflineRepository) {
    let mut repo = OfflineRepository::open(
        root,
        ACCOUNT,
        CacheKey::new([8; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    for (route, id) in [
        (ConnectionMode::Direct, 42),
        (ConnectionMode::Direct, 43),
        (ConnectionMode::WebVpn, 42),
    ] {
        let ticket = repo.begin_read(scope(route, id)).unwrap();
        repo.publish(
            &ticket,
            CachePayload::BykcDetail(CachedBykcCourse {
                id,
                ..Default::default()
            }),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
    }
    let cache = BridgeOfflineCache::open(
        root.to_string_lossy().into(),
        ACCOUNT.into(),
        "synthetic".into(),
        vec![8; 32],
    )
    .await
    .unwrap();
    (cache, repo)
}
#[tokio::test]
async fn 单次提交成功或未知时失效原路线关联内容_不自动重发() {
    for unknown in [false, true] {
        let root = test_root("cache-commit");
        let store = seed_sessions(&root, true, false);
        let direct = MockTransport::new([
            bykc_login_request(),
            bykc_all_config_request(),
            signable_bykc_chosen_request(),
            bykc_all_config_request(),
            signable_bykc_chosen_request(),
            bykc_sign_write_request(
                if unknown { 500 } else { 200 },
                if unknown {
                    ""
                } else {
                    r#"{"status":"0","message":"ok"}"#
                },
            ),
        ]);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        install_core(
            &client,
            store,
            "[route]\ndefault=\"direct\"\n",
            direct.clone(),
            MockTransport::new([]),
        )
        .await;
        let (cache, mut repo) = cache(&root).await;
        let stale = repo.begin_read(scope(ConnectionMode::Direct, 42)).unwrap();
        let intent = client
            .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
                course_id: 42,
                lat: None,
                lng: None,
                sign_type: 1,
            })
            .await
            .unwrap();
        let result = client
            .commit_write_cached(&cache, intent.intent_id.clone())
            .await
            .unwrap();
        assert!(result.cache_error.is_none());
        if unknown {
            assert!(result.result.is_none());
            assert_eq!(result.error.unwrap().code, BridgeErrorCode::OutcomeUnknown);
        } else {
            assert!(result.error.is_none());
            assert!(result.result.unwrap().success);
        }
        assert!(
            repo.read(&scope(ConnectionMode::Direct, 42), 200)
                .unwrap()
                .is_none()
        );
        assert!(
            repo.read(&scope(ConnectionMode::Direct, 43), 200)
                .unwrap()
                .is_some()
        );
        assert!(
            repo.read(&scope(ConnectionMode::WebVpn, 42), 200)
                .unwrap()
                .is_some()
        );
        assert!(repo.validate_read(&stale).is_err());
        assert_eq!(
            client
                .commit_write_cached(&cache, intent.intent_id)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::IntentExpired
        );
        direct.assert_exhausted().unwrap();
        assert_eq!(direct.requests().unwrap().len(), 6);
        client.dispose().await.unwrap();
        drop((client, cache, repo));
        std::fs::remove_dir_all(root).unwrap();
    }
}
#[tokio::test]
async fn 本地缓存失效失败不改变学校提交成功且仍只消费一次() {
    let root = test_root("cache-commit-local-error");
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_sign_write_request(200, r#"{"status":"0","message":"ok"}"#),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
    install_core(
        &client,
        store,
        "[route]\ndefault=\"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let (cache, repo) = cache(&root).await;
    let intent = client
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        })
        .await
        .unwrap();
    cache.deactivate().await.unwrap();
    let result = client
        .commit_write_cached(&cache, intent.intent_id)
        .await
        .unwrap();
    assert!(result.result.unwrap().success);
    assert!(result.error.is_none());
    assert_eq!(result.cache_error, Some(BridgeCacheFailure::Inactive));
    direct.assert_exhausted().unwrap();
    assert!(client.write_intents.lock().await.is_empty());
    client.dispose().await.unwrap();
    drop((client, cache, repo));
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 缓存失效采用提交结果实际路线_不以意图路线改写来源() {
    let root = test_root("cache-actual-route");
    let _store = seed_sessions(&root, true, false);
    let (cache, mut repo) = cache(&root).await;
    let result = super::super::cache::finish_cached_commit(
        Some(&cache),
        ubaa_core::facade::CacheInvalidation::Bykc { course_id: 42 },
        BridgeConnectionMode::Direct,
        Ok(super::super::BridgeWriteCommitResult {
            operation: BridgeWriteOperation::BykcSignCourse,
            success: true,
            message: "合成成功".into(),
            outcome_unknown: false,
            resolved_route: Some(BridgeConnectionMode::WebVpn),
            cgyy_receipt: None,
            ygdk_receipt: None,
            evaluation_result: None,
        }),
    )
    .await;
    assert!(result.cache_error.is_none());
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 42), 200)
            .unwrap()
            .is_some()
    );
    assert!(
        repo.read(&scope(ConnectionMode::WebVpn, 42), 200)
            .unwrap()
            .is_none()
    );
    drop((cache, repo));
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 新入口仍实时拒绝变化资格_不清缓存或发送学校写入() {
    let root = test_root("cache-preflight-failure");
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        bykc_login_request(),
        bykc_all_config_request(),
        signable_bykc_chosen_request(),
        bykc_all_config_request(),
        denied_bykc_chosen_sign_request(),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
    install_core(
        &client,
        store,
        "[route]\ndefault=\"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let (cache, mut repo) = cache(&root).await;
    let intent = client
        .prepare_bykc_sign_course(BridgeBykcSignCourseRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        })
        .await
        .unwrap();
    let result = client
        .commit_write_cached(&cache, intent.intent_id)
        .await
        .unwrap();
    assert!(result.result.is_none());
    assert_ne!(result.error.unwrap().code, BridgeErrorCode::OutcomeUnknown);
    assert!(result.cache_error.is_none());
    assert!(
        repo.read(&scope(ConnectionMode::Direct, 42), 200)
            .unwrap()
            .is_some()
    );
    direct.assert_exhausted().unwrap();
    assert_eq!(direct.requests().unwrap().len(), 5);
    client.dispose().await.unwrap();
    drop((client, cache, repo));
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 评教部分成功或未知撤销旧集合_全部明确失败保留() {
    use super::super::{
        BridgeEvaluationBatchResult, BridgeEvaluationCourseOutcome as O,
        BridgeEvaluationCourseResult, BridgeWriteCommitResult,
    };
    use crate::api::read::BridgeEvaluationSubmitTarget;
    for (outcomes, changed) in [
        ([O::Success, O::Failure], true),
        ([O::Failure, O::Failure], false),
        ([O::OutcomeUnknown, O::Unattempted], true),
    ] {
        let root = test_root("cache-evaluation-partial");
        let _store = seed_sessions(&root, true, false);
        let (cache, mut repo) = cache(&root).await;
        let query = CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::EvaluationCurrent,
        };
        let ticket = repo.begin_read(query.clone()).unwrap();
        repo.publish(
            &ticket,
            CachePayload::EvaluationCurrent(ubaa_core::facade::CachedEvaluationCourses::default()),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
        let unknown = outcomes.contains(&O::OutcomeUnknown);
        let batch = BridgeEvaluationBatchResult {
            success: false,
            outcome_unknown: unknown,
            items: outcomes
                .into_iter()
                .enumerate()
                .map(|(i, outcome)| BridgeEvaluationCourseResult {
                    target: BridgeEvaluationSubmitTarget {
                        rwid: "synthetic-task".into(),
                        wjid: "synthetic-question".into(),
                        kcdm: format!("course-{i}"),
                        bpdm: None,
                    },
                    course_name: "合成课程".into(),
                    outcome,
                    message: "合成结果".into(),
                })
                .collect(),
        };
        let result = super::super::cache::finish_cached_commit(
            Some(&cache),
            ubaa_core::facade::CacheInvalidation::Evaluation,
            BridgeConnectionMode::Direct,
            Ok(BridgeWriteCommitResult {
                operation: BridgeWriteOperation::EvaluationSubmitCourses,
                success: false,
                message: "合成结果".into(),
                outcome_unknown: unknown,
                resolved_route: Some(BridgeConnectionMode::Direct),
                cgyy_receipt: None,
                ygdk_receipt: None,
                evaluation_result: Some(batch),
            }),
        )
        .await;
        assert!(result.cache_error.is_none());
        assert_eq!(repo.read(&query, 200).unwrap().is_none(), changed);
        assert!(!result.result.unwrap().success);
        drop((cache, repo));
        std::fs::remove_dir_all(root).unwrap();
    }
}
