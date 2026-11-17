use super::*;
use ubaa_core::facade::{
    CacheCompleteness, CacheError, CacheInvalidation, CacheQuery, CacheScope,
    CachedEvaluationCourse, CachedEvaluationCourses, EvaluationProgress, OfflineReadError,
    OfflineRepository,
};

pub(super) fn shared_scope() -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::EvaluationCurrent,
    }
}

fn peer(root: &std::path::Path) -> OfflineRepository {
    OfflineRepository::open(
        root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([4; 32]),
        CacheLimits::default(),
    )
    .unwrap()
}

fn save_peer(repository: &mut OfflineRepository) {
    let ticket = repository.begin_read(shared_scope()).unwrap();
    let data = CachedEvaluationCourses {
        courses: vec![CachedEvaluationCourse {
            id: "peer-course".into(),
            kcmc: "另一端课程".into(),
            bpmc: "合成教师".into(),
            is_evaluated: true,
        }],
        progress: EvaluationProgress {
            total_courses: 1,
            evaluated_courses: 1,
            pending_courses: 0,
        },
    };
    repository
        .publish(
            &ticket,
            CachePayload::EvaluationCurrent(data),
            42,
            CacheCompleteness::Complete,
        )
        .unwrap();
}

#[test]
fn 共享资料目录评教复用完整结果且写后失效不恢复() {
    for invalidated in [false, true] {
        let root = test_root("evaluation-shared-reuse");
        let (mut client, cache, transport) = setup(&root);
        let mut other = peer(&root);
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let mut plan = client
                .begin_evaluation_scan(Some(&cache), None)
                .await
                .unwrap();
            if invalidated {
                other
                    .invalidate(ConnectionMode::Direct, &CacheInvalidation::Evaluation)
                    .unwrap();
            }
            save_peer(&mut other);
            let before = transport.calls.load(Ordering::SeqCst);
            let result = client.next_evaluation_scan(&mut plan).await;
            assert_eq!(transport.calls.load(Ordering::SeqCst), before);
            if invalidated {
                assert!(matches!(
                    result,
                    Err(OfflineReadError::Cache(CacheError::Superseded))
                ));
            } else {
                let batch = result.unwrap();
                assert!(batch.finished && batch.complete);
                assert_eq!(batch.fetched_at, 42);
                assert_eq!(batch.data.courses[0].id, "peer-course");
                assert_eq!(batch.data.progress.evaluated_courses, 1);
                assert!(batch.data.courses[0].submit_target.is_none());
                assert!(batch.save_error.is_none());
                assert!(client.next_evaluation_scan(&mut plan).await.is_err());
            }
        });
        drop((client, cache, other));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 共享资料目录评教未完成保留旧内容_完成后只重试本地发布() {
    for finished in [false, true] {
        let root = test_root("evaluation-shared-pending");
        let (mut client, cache, transport) = setup(&root);
        let mut other = peer(&root);
        save_peer(&mut other);
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let mut plan = client
                .begin_evaluation_scan(Some(&cache), None)
                .await
                .unwrap();
            if finished {
                for _ in 0..3 {
                    client.next_evaluation_scan(&mut plan).await.unwrap();
                }
                *transport.replace.lock().unwrap() = Some(other);
            } else {
                other.begin_read(shared_scope()).unwrap();
            }
            let before = transport.calls.load(Ordering::SeqCst);
            let batch = client.next_evaluation_scan(&mut plan).await.unwrap();
            assert_eq!(
                transport.calls.load(Ordering::SeqCst) - before,
                usize::from(finished)
            );
            assert!(batch.finished);
            let record = cache
                .read_evaluation(ConnectionMode::Direct)
                .unwrap()
                .unwrap();
            let CachePayload::EvaluationCurrent(saved) = record.payload else {
                panic!("必须为评教")
            };
            if finished {
                assert!(batch.complete);
                assert!(batch.save_error.is_none());
                assert_eq!(batch.publication, Some(CachePublication::Stored));
                assert_eq!(saved.courses[0].kcmc, "合成评教课程");
            } else {
                assert!(!batch.complete);
                assert_eq!(batch.save_error, Some(CacheError::Superseded));
                assert!(batch.error.is_none());
                assert_eq!(batch.data.courses[0].id, "peer-course");
                assert_eq!(saved.courses[0].id, "peer-course");
            }
        });
        drop((client, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 评教分段每批一个完整只读边界且前置阶段不清空旧集合() {
    let root = test_root("evaluation-scan");
    let (mut client, cache, transport) = setup(&root);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let mut plan = client
            .begin_evaluation_scan(Some(&cache), Some("fixture-user"))
            .await
            .unwrap();
        for _ in 0..3 {
            let before = transport.calls.load(Ordering::SeqCst);
            let batch = client.next_evaluation_scan(&mut plan).await.unwrap();
            assert_eq!(transport.calls.load(Ordering::SeqCst) - before, 1);
            assert!(!batch.finished);
            assert_eq!(batch.completed_course_lists, 0);
        }
        client
            .recover_required_session(ubaa_core::facade::ReadonlyFeature::Schedule)
            .await
            .unwrap();
        let last = client.next_evaluation_scan(&mut plan).await.unwrap();
        assert!(last.finished && last.complete);
        assert_eq!(last.data.courses.len(), 1);
        assert_eq!(last.publication, Some(CachePublication::Stored));
        assert!(
            cache
                .read_evaluation(ConnectionMode::Direct)
                .unwrap()
                .is_some()
        );
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 评教课程渐进阶段不授予资格_完整后仍去重_失败保留完整旧缓存() {
    let root = test_root("evaluation-scan-partial");
    let (mut client, cache, transport) = setup(&root);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        transport.mode.store(10, Ordering::SeqCst);
        let mut plan = client
            .begin_evaluation_scan(Some(&cache), None)
            .await
            .unwrap();
        for _ in 0..3 {
            client.next_evaluation_scan(&mut plan).await.unwrap();
        }
        let first = client.next_evaluation_scan(&mut plan).await.unwrap();
        assert!(!first.finished);
        assert_eq!(first.data.courses.len(), 1);
        assert!(
            first
                .data
                .courses
                .iter()
                .all(|row| row.submit_target.is_none())
        );
        let last = client.next_evaluation_scan(&mut plan).await.unwrap();
        assert!(last.complete);
        assert_eq!(last.data.courses.len(), 2);
        assert!(
            last.data
                .courses
                .iter()
                .all(|row| row.submit_target.is_some())
        );
        let old = cache
            .read_evaluation(ConnectionMode::Direct)
            .unwrap()
            .unwrap();
        for mode in [9, 11] {
            transport.mode.store(mode, Ordering::SeqCst);
            let partial = client.refresh_cached_evaluation(&cache).await.unwrap();
            assert!(!partial.complete);
            assert!(
                partial
                    .result
                    .data
                    .courses
                    .iter()
                    .all(|row| row.submit_target.is_none())
            );
            assert_eq!(partial.publication, Some(CachePublication::Preserved));
            let saved = cache
                .read_evaluation(ConnectionMode::Direct)
                .unwrap()
                .unwrap();
            assert_eq!(saved.payload, old.payload);
            assert_eq!(saved.fetched_at, old.fetched_at);
        }
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 评教无缓存仍核对身份且结束后不可继续_取消和迟到课程不入库() {
    let root = test_root("evaluation-scan-online");
    let (mut client, cache, transport) = setup(&root);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        assert!(matches!(
            client
                .begin_evaluation_scan(None, Some("different-user"))
                .await,
            Err(ubaa_core::facade::OfflineReadError::IdentityMismatch { .. })
        ));
        let mut online = client
            .begin_evaluation_scan(None, Some("fixture-user"))
            .await
            .unwrap();
        loop {
            let batch = client.next_evaluation_scan(&mut online).await.unwrap();
            if batch.finished {
                assert!(batch.complete);
                assert!(batch.publication.is_none());
                break;
            }
        }
        assert!(client.next_evaluation_scan(&mut online).await.is_err());
        let mut plan = client
            .begin_evaluation_scan(Some(&cache), None)
            .await
            .unwrap();
        for _ in 0..3 {
            client.next_evaluation_scan(&mut plan).await.unwrap();
        }
        *transport.cancel.lock().unwrap() = Some(plan.cancellation());
        assert!(client.next_evaluation_scan(&mut plan).await.is_err());
        assert!(
            cache
                .read_evaluation(ConnectionMode::Direct)
                .unwrap()
                .is_none()
        );
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 评教新请求退出和清理拒绝旧计划且不增加请求() {
    for reason in 0..3 {
        let root = test_root(&format!("evaluation-scan-stale-{reason}"));
        let (mut client, cache, transport) = setup(&root);
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let mut plan = client
                .begin_evaluation_scan(Some(&cache), None)
                .await
                .unwrap();
            client.next_evaluation_scan(&mut plan).await.unwrap();
            match reason {
                0 => {
                    let _newer = client
                        .begin_evaluation_scan(Some(&cache), None)
                        .await
                        .unwrap();
                }
                1 => cache.clear().unwrap(),
                _ => cache.deactivate().unwrap(),
            }
            let before = transport.calls.load(Ordering::SeqCst);
            assert!(client.next_evaluation_scan(&mut plan).await.is_err());
            assert_eq!(transport.calls.load(Ordering::SeqCst), before);
        });
        drop(cache);
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 评教恢复缺学校标识使用已核实用户名_两者均缺不发送业务请求() {
    let root = test_root("evaluation-scan-identity");
    let (mut client, cache, transport) = setup(&root);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        transport.mode.store(12, Ordering::SeqCst);
        let mut plan = client
            .begin_evaluation_scan(None, Some("fixture-user"))
            .await
            .unwrap();
        loop {
            if client
                .next_evaluation_scan(&mut plan)
                .await
                .unwrap()
                .finished
            {
                break;
            }
        }
        transport.mode.store(13, Ordering::SeqCst);
        let before = transport.calls.load(Ordering::SeqCst);
        assert!(client.begin_evaluation_scan(None, None).await.is_err());
        assert_eq!(transport.calls.load(Ordering::SeqCst) - before, 1);
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 评教子请求网络失败须保留可重试错误而非伪装完整空集合() {
    let root = test_root("evaluation-scan-network");
    let (mut client, cache, transport) = setup(&root);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        transport.mode.store(9, Ordering::SeqCst);
        let mut plan = client
            .begin_evaluation_scan(Some(&cache), None)
            .await
            .unwrap();
        loop {
            let batch = client.next_evaluation_scan(&mut plan).await.unwrap();
            if batch.finished {
                assert!(!batch.complete);
                assert_eq!(batch.data.courses.len(), 1);
                assert_eq!(
                    batch.error.unwrap().error.code,
                    ubaa_core::facade::ErrorCode::UpstreamUnavailable
                );
                break;
            }
        }
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 评教激活失败保留稳定错误且不继续任务读取() {
    let root = test_root("evaluation-scan-activation");
    let (mut client, cache, transport) = setup(&root);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        client.refresh_cached_evaluation(&cache).await.unwrap();
        let old = cache
            .read_evaluation(ConnectionMode::Direct)
            .unwrap()
            .unwrap();
        transport.mode.store(5, Ordering::SeqCst);
        let mut plan = client
            .begin_evaluation_scan(Some(&cache), None)
            .await
            .unwrap();
        let before = transport.calls.load(Ordering::SeqCst);
        let batch = client.next_evaluation_scan(&mut plan).await.unwrap();
        assert!(batch.finished && !batch.complete);
        assert_eq!(transport.calls.load(Ordering::SeqCst) - before, 1);
        assert_eq!(
            batch.error.unwrap().error.code,
            ubaa_core::facade::ErrorCode::UpstreamUnavailable
        );
        let saved = cache
            .read_evaluation(ConnectionMode::Direct)
            .unwrap()
            .unwrap();
        assert_eq!(saved.payload, old.payload);
        assert_eq!(saved.fetched_at, old.fetched_at);
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
