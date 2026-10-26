use super::*;
use ubaa_core::facade::JudgeAssignmentKey;

fn keys() -> Vec<JudgeAssignmentKey> {
    ["101", "102"]
        .into_iter()
        .map(|id| JudgeAssignmentKey {
            course_id: "12".into(),
            assignment_id: id.into(),
        })
        .collect()
}

#[test]
fn 批量详情逐项保存且只读目标课程_重开后可离线访问() {
    let (root, mut client, cache, transport) = setup("judge-batch-persistence");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let mut plan = client.begin_judge_details(&cache, keys()).await.unwrap();
        loop {
            let result = client.next_judge_details(&mut plan).await.unwrap().progress;
            if result.batch.finished {
                assert!(result.batch.complete);
                break;
            }
        }
    });
    for id in ["101", "102"] {
        assert!(
            cache
                .read_judge_detail(ConnectionMode::Direct, "12".into(), id.into())
                .unwrap()
                .is_some(),
            "完整在线详情必须独立保存"
        );
    }
    let requests = transport.requests.lock().unwrap();
    assert!(!requests.iter().any(|r| r.url.ends_with("assignID=201")));
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.url.ends_with("/assignment/index.jsp"))
            .count(),
        1
    );
    drop(requests);
    drop(cache);
    drop(client);
    let reopened = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    assert!(
        reopened
            .read_judge_detail(ConnectionMode::Direct, "12".into(), "102".into())
            .unwrap()
            .is_some()
    );
    assert!(
        reopened
            .read_judge_detail(ConnectionMode::WebVpn, "12".into(), "102".into())
            .unwrap()
            .is_none()
    );
    drop(reopened);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 批量清理退出取消与较新同目标读取阻止后续请求() {
    for action in ["clear", "logout", "cancel", "newer"] {
        let (root, mut client, cache, transport) = setup(&format!("judge-details-{action}"));
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                let mut plan = client.begin_judge_details(&cache, keys()).await.unwrap();
                client.next_judge_details(&mut plan).await.unwrap();
                match action {
                    "clear" => cache.clear().unwrap(),
                    "logout" => cache.deactivate().unwrap(),
                    "cancel" => plan.cancellation().cancel(),
                    _ => {
                        client.begin_judge_details(&cache, keys()).await.unwrap();
                    }
                }
                let before = transport.requests.lock().unwrap().len();
                assert!(client.next_judge_details(&mut plan).await.is_err());
                assert_eq!(before, transport.requests.lock().unwrap().len());
            });
        drop((client, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 批量详情在途清理拒绝迟到内容写回() {
    let (root, mut client, cache, transport) = setup("judge-details-late");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client.begin_judge_details(&cache, keys()).await.unwrap();
            client.next_judge_details(&mut plan).await.unwrap();
            *transport.clear_on_detail.lock().unwrap() = Some(cache.clone());
            assert!(matches!(
                client.next_judge_details(&mut plan).await,
                Err(ubaa_core::facade::OfflineReadError::Cache(
                    ubaa_core::facade::CacheError::Superseded
                ))
            ));
            assert!(
                cache
                    .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                    .unwrap()
                    .is_none()
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 批量学校失败保留旧完整详情且不写聚合摘要() {
    let (root, mut client, cache, transport) = setup("judge-details-preserve");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut first = client.begin_judge_details(&cache, keys()).await.unwrap();
            while !client
                .next_judge_details(&mut first)
                .await
                .unwrap()
                .progress
                .batch
                .finished
            {}
            let old = cache
                .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                .unwrap()
                .unwrap();
            transport.fail_detail.store(true, Ordering::SeqCst);
            let mut failing = client.begin_judge_details(&cache, keys()).await.unwrap();
            loop {
                let batch = client.next_judge_details(&mut failing).await.unwrap();
                if batch.progress.batch.finished {
                    assert!(!batch.progress.batch.complete);
                    assert_eq!(
                        batch.progress.batch.error.unwrap().code,
                        ubaa_core::facade::ErrorCode::NetworkError
                    );
                    assert_eq!(batch.save_error, None);
                    break;
                }
            }
            let retained = cache
                .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                .unwrap()
                .unwrap();
            assert_eq!(retained.payload, old.payload);
            assert_eq!(retained.fetched_at, old.fetched_at);
            assert!(!retained.last_attempt_succeeded);
            assert!(
                cache
                    .read_judge(ConnectionMode::Direct, false)
                    .unwrap()
                    .is_none()
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 批量缓存容量失败仍交付完整在线详情() {
    let (root, mut client, cache, _) = setup("judge-details-capacity");
    drop(cache);
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits {
            soft_bytes: 64,
            hard_bytes: 64,
        },
    )
    .unwrap();
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client.begin_judge_details(&cache, keys()).await.unwrap();
            let mut seen = 0;
            loop {
                let batch = client.next_judge_details(&mut plan).await.unwrap();
                if batch.progress.batch.detail.is_some() {
                    seen += 1;
                    assert_eq!(
                        batch.save_error,
                        Some(ubaa_core::facade::CacheError::Capacity)
                    );
                }
                if batch.progress.batch.finished {
                    assert!(batch.progress.batch.complete);
                    break;
                }
            }
            assert_eq!(seen, 2);
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}
