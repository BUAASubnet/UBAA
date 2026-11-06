use super::*;

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
