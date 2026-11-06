use super::*;
use ubaa_core::facade::JudgeRefreshOptions;

#[test]
fn judge_detail_pending_competitor_still_returns_requested_detail() {
    detail_competition(false);
}

#[test]
fn judge_detail_committed_competitor_still_returns_requested_detail() {
    detail_competition(true);
}

fn detail_competition(committed: bool) {
    let (root, mut client, cache, _) = setup(&format!("judge-detail-concurrent-{committed}"));
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut detail = client
                .begin_judge_refresh(
                    &cache,
                    JudgeRefreshOptions {
                        current_assignment: Some(ubaa_core::facade::JudgeAssignmentKey {
                            course_id: "12".into(),
                            assignment_id: "101".into(),
                        }),
                        ..JudgeRefreshOptions::default()
                    },
                )
                .await
                .unwrap();
            client.next_judge_refresh(&mut detail).await.unwrap();
            let mut summary = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            if committed {
                while !client
                    .next_judge_refresh(&mut summary)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {}
            }
            let result = client.next_judge_refresh(&mut detail).await.unwrap();
            assert_eq!(result.batch.kind, JudgeScanKind::Detail);
            let value = result.batch.detail.expect("详情读取必须交付目标正文");
            assert_eq!(value.course_id, "12");
            assert_eq!(value.assignment_id, "101");
        });
    drop((cache, client));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn judge_concurrent_refresh_reuses_newer_commit_or_rereads_pending_query() {
    for committed in [false, true] {
        let (root, mut client, cache, transport) = setup(&format!("judge-concurrent-{committed}"));
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                let mut home = client
                    .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                    .await
                    .unwrap();
                client.next_judge_refresh(&mut home).await.unwrap();
                let mut agenda = client
                    .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                    .await
                    .unwrap();
                if committed {
                    while !client
                        .next_judge_refresh(&mut agenda)
                        .await
                        .unwrap()
                        .batch
                        .finished
                    {}
                }
                let before = transport.requests.lock().unwrap().len();
                let result = client.next_judge_refresh(&mut home).await.unwrap();
                assert!(result.batch.finished && result.batch.complete);
                assert_eq!(result.summaries.len(), 3);
                if committed {
                    assert_eq!(
                        transport.requests.lock().unwrap().len(),
                        before,
                        "已提交的较新完整摘要直接复用"
                    );
                } else {
                    let result = client.next_judge_refresh(&mut agenda).await.unwrap();
                    assert!(result.batch.finished && result.batch.complete);
                    assert_eq!(result.summaries.len(), 3);
                }
            });
        drop((cache, client));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn judge_same_query_recovery_does_not_revive_cancelled_cleared_or_replaced_sessions() {
    for reason in 0..4 {
        let (root, mut client, cache, transport) =
            setup(&format!("judge-concurrent-fence-{reason}"));
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                let mut home = client
                    .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                    .await
                    .unwrap();
                let mut newer = client
                    .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                    .await
                    .unwrap();
                while !client
                    .next_judge_refresh(&mut newer)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {}
                match reason {
                    0 => home.cancellation().cancel(),
                    1 => cache.clear().unwrap(),
                    2 => cache.deactivate().unwrap(),
                    _ => {
                        client = UbaaClient::with_routing(
                            transport.clone(),
                            CountingTransport(Arc::new(AtomicUsize::new(0))),
                            FileSessionStore::new(&root).unwrap(),
                            RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
                            NeverProbe,
                        )
                        .unwrap();
                    }
                }
                let before = transport.requests.lock().unwrap().len();
                assert!(client.next_judge_refresh(&mut home).await.is_err());
                assert_eq!(transport.requests.lock().unwrap().len(), before);
            });
        drop((cache, client));
        std::fs::remove_dir_all(root).unwrap();
    }
}
