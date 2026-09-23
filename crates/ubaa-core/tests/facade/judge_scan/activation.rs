//! 去除重复激活不能省略课程选择、索引、详情或认证失效后的有界恢复。
use super::*;
use ubaa_core::facade::{JudgeOnlineOptions, OfflineReadError};

fn activation_count(transport: &ScanTransport) -> usize {
    transport
        .requests
        .lock()
        .unwrap()
        .iter()
        .filter(|request| {
            url::Url::parse(&request.url).unwrap().host_str() == Some("sso.buaa.edu.cn")
        })
        .count()
}

#[test]
fn cached_course_list_does_not_grant_a_new_plan_an_activation_it_never_performed() {
    let (root, mut client, cache, transport) = setup("judge-cached-course-activation");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let old = client.begin_judge_scan(&cache, false, None).await.unwrap();
            old.cancellation().cancel();
            transport.requests.lock().unwrap().clear();
            let mut plan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            assert_eq!(
                activation_count(&transport),
                0,
                "课程来自内存不等于本轮已激活"
            );
            loop {
                let batch = client.next_judge_scan(&mut plan).await.unwrap().data;
                if batch.finished {
                    assert!(batch.complete);
                    break;
                }
            }
            assert_eq!(activation_count(&transport), 1);
            assert_eq!(detail_request_count(&transport), 3);
            assert!(
                !transport
                    .requests
                    .lock()
                    .unwrap()
                    .iter()
                    .any(|request| request.url.ends_with("courseID=0"))
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn segmented_cached_scan_reuses_activation_without_skipping_selection_or_data() {
    let (root, mut client, cache, transport) = setup("judge-scan-activation");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            let mut batches = 0;
            loop {
                let batch = client.next_judge_scan(&mut plan).await.unwrap().data;
                batches += 1;
                if batch.finished {
                    assert!(batch.complete);
                    break;
                }
            }
            assert_eq!(batches, 5, "两份索引与三份详情均须取得");
            assert_full_coverage(&transport);
            assert_eq!(
                activation_count(&transport),
                1,
                "同计划沿用课程读取已完成的业务激活"
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn segmented_online_scan_reuses_activation_only_within_its_own_plan() {
    let (root, mut client, cache, transport) = setup("judge-online-activation");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for expected in 1..=2 {
                let mut plan = client
                    .begin_judge_online(JudgeOnlineOptions::default())
                    .await
                    .unwrap();
                loop {
                    let progress = client.next_judge_online(&mut plan).await.unwrap();
                    if progress.batch.finished {
                        assert!(progress.batch.complete);
                        break;
                    }
                }
                assert_eq!(
                    activation_count(&transport),
                    expected,
                    "新计划重新激活，批次复用本计划激活"
                );
            }
            assert_eq!(
                detail_request_count(&transport),
                6,
                "两轮强制在线都必须取完详情"
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn reused_activation_still_reactivates_three_times_and_stops_expired_plan() {
    let (root, mut client, cache, transport) = setup("judge-scan-reactivation");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            client.next_judge_scan(&mut plan).await.unwrap();
            let before = activation_count(&transport);
            transport.reject_detail.store(true, Ordering::SeqCst);
            let Err(OfflineReadError::Read(error)) = client.next_judge_scan(&mut plan).await else {
                panic!("业务失效必须保留原错误并停止计划");
            };
            assert_eq!(
                error.error.code,
                ubaa_core::facade::ErrorCode::UpstreamUnavailable
            );
            assert_eq!(
                activation_count(&transport) - before,
                3,
                "复用激活后仍沿原三次重新激活上限"
            );
            assert_eq!(detail_request_count(&transport), 4);
            let requests = transport.requests.lock().unwrap().len();
            assert!(client.next_judge_scan(&mut plan).await.is_err());
            assert_eq!(transport.requests.lock().unwrap().len(), requests);
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

fn assert_full_coverage(transport: &ScanTransport) {
    let requests = transport.requests.lock().unwrap();
    let count = |suffix: &str| {
        requests
            .iter()
            .filter(|request| request.url.ends_with(suffix))
            .count()
    };
    assert_eq!(count("courselist.jsp?courseID=0"), 1);
    assert_eq!(count("courselist.jsp?courseID=12"), 3);
    assert_eq!(count("courselist.jsp?courseID=13"), 2);
    assert_eq!(count("assignment/index.jsp"), 2);
    for id in ["101", "102", "201"] {
        assert_eq!(count(&format!("assignID={id}")), 1);
    }
}
