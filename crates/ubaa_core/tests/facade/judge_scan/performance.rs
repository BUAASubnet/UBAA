//! 渐进读取的请求数量与完整结果回归。
use super::*;
use ubaa_core::facade::{JudgeOnlineOptions, JudgeRefreshOptions};

#[test]
fn 自动刷新复用有效索引和详情() {
    let (root, mut client, cache, transport) = setup("judge-refresh-cache-budget");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for round in 0..2 {
                transport.requests.lock().unwrap().clear();
                let mut plan = client
                    .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                    .await
                    .unwrap();
                loop {
                    let result = client.next_judge_refresh(&mut plan).await.unwrap();
                    if result.batch.finished {
                        assert!(result.batch.complete);
                        assert_eq!(result.summaries.len(), 3);
                        break;
                    }
                }
                if round == 1 {
                    assert_eq!(
                        judge_requests(&transport),
                        0,
                        "有效缓存下自动刷新不重复请求学校目录、索引或详情"
                    );
                }
            }
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 无持久缓存的重复读取仍复用内存() {
    let (root, mut client, cache, transport) = setup("judge-online-cache-budget");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for round in 0..2 {
                transport.requests.lock().unwrap().clear();
                let mut plan = client
                    .begin_judge_online(JudgeOnlineOptions::default())
                    .await
                    .unwrap();
                loop {
                    let result = client.next_judge_online(&mut plan).await.unwrap();
                    if result.batch.finished {
                        assert!(result.batch.complete);
                        assert_eq!(result.summaries.len(), 3);
                        break;
                    }
                }
                if round == 1 {
                    assert_eq!(
                        judge_requests(&transport),
                        0,
                        "存储不可用不应使内存缓存失效"
                    );
                }
            }
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

fn judge_requests(transport: &ScanTransport) -> usize {
    transport
        .requests
        .lock()
        .unwrap()
        .iter()
        .filter(|request| {
            request.url.contains("judge.buaa.edu.cn")
                || request.url.contains("judge.buaa.edu.cn%2F")
        })
        .count()
}

#[test]
fn 短课程复用父会话并发读取且先展示课程索引() {
    let (root, mut client, cache, transport) = setup("judge-direct-detail-wave");
    transport.detail_delay_ms.store(40, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            let first = client.next_judge_refresh(&mut plan).await.unwrap();
            assert_eq!(first.batch.kind, JudgeScanKind::Assignments);
            assert_eq!(detail_request_count(&transport), 0, "首批索引不等待详情");
            loop {
                let result = client.next_judge_refresh(&mut plan).await.unwrap();
                if result.batch.finished {
                    assert!(result.batch.complete);
                    assert_eq!(result.summaries.len(), 3);
                    break;
                }
            }
            assert_eq!(transport.max_active_details.load(Ordering::SeqCst), 2);
            assert_eq!(detail_request_count(&transport), 3);
            assert_eq!(
                transport.active_details.load(Ordering::SeqCst),
                0,
                "让位时没有在途请求"
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 连续缓存详情合并发布且保留首批索引() {
    let (root, mut client, cache, transport) = setup("judge-cache-batching");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for round in 0..2 {
                let mut plan = client
                    .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                    .await
                    .unwrap();
                let mut batches = 0;
                loop {
                    let result = client.next_judge_refresh(&mut plan).await.unwrap();
                    batches += 1;
                    if batches == 1 {
                        assert_eq!(result.batch.kind, JudgeScanKind::Assignments);
                    }
                    if result.batch.finished {
                        assert!(result.batch.complete);
                        assert_eq!(result.summaries.len(), 3);
                        break;
                    }
                }
                if round == 1 {
                    assert_eq!(batches, 4, "两门课各返回索引及合并后的缓存详情");
                }
            }
            assert_eq!(detail_request_count(&transport), 3);
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 已知未完成课程优先且显式课程优先级最高() {
    use ubaa_core::facade::{
        CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeAssignmentSummary,
        JudgeSubmissionStatus, OfflineRepository,
    };
    let (root, mut client, cache, _) = setup("judge-course-priority");
    let mut repository = OfflineRepository::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let ticket = repository
        .begin_read(CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::JudgeSummaries {
                include_expired: false,
            },
        })
        .unwrap();
    repository
        .publish(
            &ticket,
            CachePayload::JudgeSummaries(vec![
                JudgeAssignmentSummary {
                    course_id: "12".into(),
                    assignment_id: "101".into(),
                    submission_status: JudgeSubmissionStatus::Submitted,
                    ..Default::default()
                },
                JudgeAssignmentSummary {
                    course_id: "13".into(),
                    assignment_id: "201".into(),
                    submission_status: JudgeSubmissionStatus::Unsubmitted,
                    due_time: Some("2027-01-01 00:00:00".into()),
                    ..Default::default()
                },
            ]),
            chrono::Utc::now().timestamp(),
            CacheCompleteness::Complete,
        )
        .unwrap();
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for preferred in [None, Some("12".to_owned())] {
                let mut plan = client
                    .begin_judge_refresh(
                        &cache,
                        JudgeRefreshOptions {
                            preferred_course: preferred.clone(),
                            ..Default::default()
                        },
                    )
                    .await
                    .unwrap();
                let first = client.next_judge_refresh(&mut plan).await.unwrap();
                assert_eq!(
                    first.batch.course_id.as_deref(),
                    Some(preferred.as_deref().unwrap_or("13"))
                );
            }
        });
    drop((client, cache, repository));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 大课程并发上限为四且取消拒绝剩余预取() {
    let (root, mut client, cache, transport) = setup("judge-wave-limit");
    transport.assignment_count.store(8, Ordering::SeqCst);
    transport.detail_delay_ms.store(10, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            client.next_judge_refresh(&mut plan).await.unwrap();
            let first = client.next_judge_refresh(&mut plan).await.unwrap();
            assert_eq!(first.batch.detail.unwrap().assignment_id, "101");
            assert_eq!(transport.max_active_details.load(Ordering::SeqCst), 4);
            assert_eq!(detail_request_count(&transport), 4);
            assert_eq!(transport.active_details.load(Ordering::SeqCst), 0);
            plan.cancellation().cancel();
            let before = transport.requests.lock().unwrap().len();
            assert!(client.next_judge_refresh(&mut plan).await.is_err());
            assert_eq!(transport.requests.lock().unwrap().len(), before);
            assert!(
                cache
                    .read_judge_detail(ConnectionMode::Direct, "12".into(), "102".into())
                    .unwrap()
                    .is_none(),
                "取消后未交付的预取不得持久发布"
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 手动索引刷新发现新增与改名并按需重读无存储详情() {
    let (root, mut client, cache, transport) = setup("judge-online-renamed");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for renamed in [false, true] {
                transport.rename_assignment.store(renamed, Ordering::SeqCst);
                let mut plan = client
                    .begin_judge_online(JudgeOnlineOptions {
                        refresh_indices: true,
                        ..Default::default()
                    })
                    .await
                    .unwrap();
                loop {
                    let result = client.next_judge_online(&mut plan).await.unwrap();
                    if result.batch.finished {
                        assert!(result.batch.complete);
                        let item = result
                            .summaries
                            .iter()
                            .find(|item| item.assignment_id == "101")
                            .unwrap();
                        assert_eq!(
                            item.title,
                            if renamed {
                                "Task A1 updated"
                            } else {
                                "Task A1"
                            }
                        );
                        break;
                    }
                }
            }
            assert_eq!(
                detail_request_count(&transport),
                4,
                "只重新获取改名作业详情"
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
#[ignore = "显式测量带合成网络延迟的渐进读取，不设置机器耗时阈值"]
fn 渐进读取首批和完整耗时基准() {
    let (root, mut client, cache, transport) = setup("judge-progressive-benchmark");
    transport.assignment_count.store(96, Ordering::SeqCst);
    transport.detail_delay_ms.store(50, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async {
        for round in 0..2 {
            transport.requests.lock().unwrap().clear();
            let started = std::time::Instant::now();
            let mut batches = 0;
            let mut first_ms = 0;
            let mut plan = client.begin_judge_refresh(&cache, JudgeRefreshOptions::default()).await.unwrap();
            loop {
                let result = client.next_judge_refresh(&mut plan).await.unwrap();
                batches += 1;
                if batches == 1 { first_ms = started.elapsed().as_millis(); }
                if result.batch.finished { assert!(result.batch.complete); assert_eq!(result.summaries.len(), 97); break; }
            }
            eprintln!("round={round} first_ms={first_ms} complete_ms={} batches={batches} requests={}", started.elapsed().as_millis(), judge_requests(&transport));
        }
    });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 较新详情覆盖预取后其余作业仍按二元键交付() {
    use ubaa_core::facade::{
        CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeAssignmentDetail,
        OfflineRepository,
    };
    let (root, mut client, cache, transport) = setup("judge-prefetch-replaced");
    transport.assignment_count.store(8, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut plan = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            client.next_judge_refresh(&mut plan).await.unwrap();
            client.next_judge_refresh(&mut plan).await.unwrap();
            assert_eq!(detail_request_count(&transport), 4);
            let mut repository = OfflineRepository::open(
                &root,
                "0123456789abcdef0123456789abcdef",
                CacheKey::new([9; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            let ticket = repository
                .begin_read(CacheScope {
                    route: ConnectionMode::Direct,
                    query: CacheQuery::JudgeDetail {
                        course_id: "12".into(),
                        assignment_id: "102".into(),
                    },
                })
                .unwrap();
            repository
                .publish(
                    &ticket,
                    CachePayload::JudgeDetail(Box::new(JudgeAssignmentDetail {
                        course_id: "12".into(),
                        course_name: "Course A".into(),
                        assignment_id: "102".into(),
                        title: "Task A2".into(),
                        my_score: Some("7".into()),
                        ..Default::default()
                    })),
                    chrono::Utc::now().timestamp(),
                    CacheCompleteness::Complete,
                )
                .unwrap();
            loop {
                let result = client.next_judge_refresh(&mut plan).await.unwrap();
                if result.batch.finished {
                    assert!(result.batch.complete);
                    assert_eq!(result.summaries.len(), 9);
                    assert_eq!(
                        result
                            .summaries
                            .iter()
                            .find(|item| item.assignment_id == "102")
                            .unwrap()
                            .my_score
                            .as_deref(),
                        Some("7")
                    );
                    assert_eq!(
                        result
                            .summaries
                            .iter()
                            .find(|item| item.assignment_id == "201")
                            .unwrap()
                            .course_id,
                        "13"
                    );
                    break;
                }
            }
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 本轮索引附带详情在强制刷新中不重复请求() {
    for online in [false, true] {
        let (root, mut client, cache, transport) = setup("judge-index-detail");
        transport.embedded_detail.store(true, Ordering::SeqCst);
        if online {
            let mut plan = client
                .begin_judge_online(JudgeOnlineOptions {
                    full_refresh: true,
                    ..Default::default()
                })
                .await
                .unwrap();
            loop {
                let result = client.next_judge_online(&mut plan).await.unwrap();
                if result.batch.finished {
                    assert!(result.batch.complete);
                    assert_eq!(result.summaries.len(), 3);
                    break;
                }
            }
        } else {
            let mut plan = client
                .begin_judge_refresh(
                    &cache,
                    JudgeRefreshOptions {
                        full_refresh: true,
                        ..Default::default()
                    },
                )
                .await
                .unwrap();
            loop {
                let result = client.next_judge_refresh(&mut plan).await.unwrap();
                if result.batch.finished {
                    assert!(result.batch.complete);
                    assert_eq!(result.summaries.len(), 3);
                    break;
                }
            }
        }
        assert_eq!(
            detail_request_count(&transport),
            1,
            "两门课程各复用一份本轮详情"
        );
        drop((client, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn direct预取复用父会话而不重复激活选课() {
    let (root, mut client, cache, transport) = setup("judge-direct-parent-wave");
    transport.assignment_count.store(8, Ordering::SeqCst);
    transport.detail_delay_ms.store(10, Ordering::SeqCst);
    let mut plan = client
        .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
        .await
        .unwrap();
    loop {
        let result = client.next_judge_refresh(&mut plan).await.unwrap();
        assert_eq!(transport.active_details.load(Ordering::SeqCst), 0);
        if result.batch.finished {
            assert!(result.batch.complete);
            assert_eq!(result.summaries.len(), 9);
            break;
        }
    }
    assert_eq!(transport.max_active_details.load(Ordering::SeqCst), 4);
    let requests = transport.requests.lock().unwrap();
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.url.ends_with("courselist.jsp?courseID=12"))
            .count(),
        1
    );
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.url.contains("/login?service=") && r.url.contains("judge.buaa.edu.cn"))
            .count(),
        1
    );
    drop(requests);
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}
