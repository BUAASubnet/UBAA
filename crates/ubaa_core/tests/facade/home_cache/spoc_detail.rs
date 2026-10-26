use super::*;
#[test]
fn spoc_详情前置逐页让位且正文补充只读取一次() {
    let root = test_root("spoc-detail-scan");
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    rt().block_on(async {
        let mut plan = client
            .begin_spoc_detail_scan(Some(&cache), Some("fixture-user"), "a1")
            .await
            .unwrap();
        for _ in 0..4 {
            let batch = client.next_spoc_detail_scan(&mut plan).await.unwrap();
            assert!(!batch.finished);
            assert!(batch.data.is_none());
        }
        assert_eq!(transport.page.load(Ordering::SeqCst), 2);
        client.signin_today().await.unwrap();
        let last = client.next_spoc_detail_scan(&mut plan).await.unwrap();
        assert!(last.finished && last.complete);
        assert_eq!(last.data.unwrap().assignment_id, "a1");
        assert_eq!(
            transport.page.load(Ordering::SeqCst),
            2,
            "正文步骤不能再扫描全量列表"
        );
        assert_eq!(last.publication, Some(CachePublication::Stored));
        let saved = cache
            .read_home(
                ConnectionMode::Direct,
                &HomeQuery::SpocDetail {
                    assignment_id: "a1".into(),
                },
            )
            .unwrap()
            .unwrap();
        assert_eq!(saved.fetched_at, last.fetched_at);
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn spoc_详情部分补充保留完整旧值_缺目标不请求正文_无缓存不声明保存() {
    let root = test_root("spoc-detail-partial");
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    rt().block_on(async {
        let query = HomeQuery::SpocDetail {
            assignment_id: "a1".into(),
        };
        client
            .refresh_cached_home(&cache, query.clone())
            .await
            .unwrap();
        let old = cache
            .read_home(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        transport.base.mode.store(2, Ordering::SeqCst);
        let partial = client
            .refresh_cached_home(&cache, query.clone())
            .await
            .unwrap();
        assert!(!partial.complete);
        assert_eq!(partial.publication, Some(CachePublication::Preserved));
        let saved = cache
            .read_home(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        assert_eq!(saved.payload, old.payload);
        assert_eq!(saved.fetched_at, old.fetched_at);
        transport.base.mode.store(0, Ordering::SeqCst);
        let mut missing = client
            .begin_spoc_detail_scan(None, Some("fixture-user"), "absent")
            .await
            .unwrap();
        for _ in 0..4 {
            client.next_spoc_detail_scan(&mut missing).await.unwrap();
        }
        let before = transport.base.requests.lock().unwrap().len();
        assert!(matches!(
            client.next_spoc_detail_scan(&mut missing).await,
            Err(OfflineReadError::Read(_))
        ));
        assert_eq!(transport.base.requests.lock().unwrap().len(), before);
        let mut online = client
            .begin_spoc_detail_scan(None, Some("fixture-user"), "a1")
            .await
            .unwrap();
        loop {
            let batch = client.next_spoc_detail_scan(&mut online).await.unwrap();
            if batch.finished {
                assert!(batch.complete);
                assert!(batch.publication.is_none());
                assert!(batch.data.is_some());
                break;
            }
        }
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn spoc_详情已完成前置也不能绕过取消清理退出和同目标新请求() {
    for reason in 0..4 {
        let root = test_root(&format!("spoc-detail-lifecycle-{reason}"));
        let transport = Pages::default();
        let (mut client, cache) = setup(&root, transport.clone());
        rt().block_on(async {
            let mut plan = client
                .begin_spoc_detail_scan(Some(&cache), None, "a1")
                .await
                .unwrap();
            for _ in 0..4 {
                client.next_spoc_detail_scan(&mut plan).await.unwrap();
            }
            match reason {
                0 => plan.cancellation().cancel(),
                1 => cache.clear().unwrap(),
                2 => cache.deactivate().unwrap(),
                _ => {
                    let _newer = client
                        .begin_spoc_detail_scan(Some(&cache), None, "a1")
                        .await
                        .unwrap();
                }
            }
            let before = transport.base.requests.lock().unwrap().len();
            assert!(client.next_spoc_detail_scan(&mut plan).await.is_err());
            assert_eq!(transport.base.requests.lock().unwrap().len(), before);
        });
        drop(cache);
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}
#[test]
fn spoc_详情正文在途取消后不能入库() {
    let root = test_root("spoc-detail-late");
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    rt().block_on(async {
        let mut plan = client
            .begin_spoc_detail_scan(Some(&cache), None, "a1")
            .await
            .unwrap();
        for _ in 0..4 {
            client.next_spoc_detail_scan(&mut plan).await.unwrap();
        }
        *transport.cancel.lock().unwrap() = Some(plan.cancellation());
        assert!(matches!(
            client.next_spoc_detail_scan(&mut plan).await,
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        assert!(
            cache
                .read_home(
                    ConnectionMode::Direct,
                    &HomeQuery::SpocDetail {
                        assignment_id: "a1".into()
                    }
                )
                .unwrap()
                .is_none()
        );
    });
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
