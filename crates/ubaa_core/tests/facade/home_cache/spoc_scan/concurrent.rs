use super::*;

#[test]
fn shared_profile_spoc_pending_scan_keeps_saved_assignments_without_network() {
    let root =
        crate::test_tmp::test_temp_dir("ubaa_core_facade_home_cache_spoc_scan_concurrent").unwrap();
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    let mut other = ubaa_core::facade::OfflineRepository::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([4; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    rt().block_on(async {
        let mut warm = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
        while !client.next_spoc_scan(&mut warm).await.unwrap().finished {}
        let mut plan = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
        let newer = other
            .begin_read(CacheScope {
                query: CacheQuery::SpocSelection,
                route: ConnectionMode::Direct,
            })
            .unwrap();
        let before = transport.base.requests.lock().unwrap().len();
        let result = client.next_spoc_scan(&mut plan).await.unwrap();
        assert!(result.finished);
        assert_eq!(result.save_error, Some(CacheError::Superseded));
        assert_eq!(result.data.assignments.len(), 2);
        assert_eq!(transport.base.requests.lock().unwrap().len(), before);
        other.validate_read(&newer).unwrap();
    });
    drop((cache, client, other));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn shared_profile_spoc_detail_reuses_only_the_requested_assignment() {
    let root =
        crate::test_tmp::test_temp_dir("ubaa_core_facade_home_cache_spoc_scan_concurrent").unwrap();
    let transport = Pages::default();
    let (mut client, cache) = setup(&root, transport.clone());
    let mut other = ubaa_core::facade::OfflineRepository::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([4; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    rt().block_on(async {
        let mut warm = client
            .begin_spoc_detail_scan(Some(&cache), None, "a1")
            .await
            .unwrap();
        while !client
            .next_spoc_detail_scan(&mut warm)
            .await
            .unwrap()
            .finished
        {}
        let mut plan = client
            .begin_spoc_detail_scan(Some(&cache), None, "a1")
            .await
            .unwrap();
        let newer = other
            .begin_read(CacheScope {
                query: CacheQuery::SpocDetail {
                    assignment_id: "a1".into(),
                },
                route: ConnectionMode::Direct,
            })
            .unwrap();
        let before = transport.base.requests.lock().unwrap().len();
        let result = client.next_spoc_detail_scan(&mut plan).await.unwrap();
        assert!(result.finished);
        assert_eq!(result.save_error, Some(CacheError::Superseded));
        assert_eq!(result.data.unwrap().assignment_id, "a1");
        assert_eq!(transport.base.requests.lock().unwrap().len(), before);
        other.validate_read(&newer).unwrap();
    });
    drop((cache, client, other));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn spoc_concurrent_scan_reuses_newer_commit_or_rereads_pending_query() {
    for committed in [false, true] {
        let root = test_root(&format!("spoc-concurrent-{committed}"));
        let transport = Pages::default();
        let (mut client, cache) = setup(&root, transport.clone());
        rt().block_on(async {
            let mut home = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
            client.next_spoc_scan(&mut home).await.unwrap();
            let mut agenda = client.begin_spoc_scan(Some(&cache), None).await.unwrap();
            if committed {
                while !client.next_spoc_scan(&mut agenda).await.unwrap().finished {}
            }
            let before = transport.base.requests.lock().unwrap().len();
            let result = client.next_spoc_scan(&mut home).await.unwrap();
            assert!(result.finished && result.complete);
            assert_eq!(result.data.assignments.len(), 2);
            if committed {
                assert_eq!(
                    transport.base.requests.lock().unwrap().len(),
                    before,
                    "已提交的较新完整结果直接复用"
                );
            } else {
                let result = client.next_spoc_scan(&mut agenda).await.unwrap();
                assert!(result.finished && result.complete);
                assert_eq!(result.data.assignments.len(), 2);
            }
        });
        drop((cache, client));
        std::fs::remove_dir_all(root).unwrap();
    }
}
