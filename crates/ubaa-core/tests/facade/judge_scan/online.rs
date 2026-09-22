use super::*;
use ubaa_core::facade::{JudgeAssignmentKey, JudgeOnlineOptions, OfflineReadError};
fn online_client(label: &str) -> (std::path::PathBuf, UbaaClient, ScanTransport) {
    let root = test_root(label);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = ScanTransport::default();
    let client = UbaaClient::with_routing(
        transport.clone(),
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    (root, client, transport)
}
#[test]
fn 无缓存扫描按批让位_旧项后新增仍读取_下一轮不永久排除旧课程() {
    let (root, mut client, transport) = online_client("judge-online-history");
    transport.historical_details.store(true, Ordering::SeqCst);
    transport.add_assignment.store(true, Ordering::SeqCst);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        for _ in 0..2 {
            let mut plan = client
                .begin_judge_online(JudgeOnlineOptions::default())
                .await
                .unwrap();
            let index = client.next_judge_online(&mut plan).await.unwrap();
            assert_eq!(index.batch.kind, JudgeScanKind::Assignments);
            assert!(index.summaries.is_empty());
            let before = transport.requests.lock().unwrap().len();
            client.schedule_today().await.unwrap();
            assert!(transport.requests.lock().unwrap().len() > before);
            loop {
                let result = client.next_judge_online(&mut plan).await.unwrap();
                if result.batch.finished {
                    assert!(result.batch.complete);
                    assert!(result.summaries.iter().any(|v| v.assignment_id == "103"));
                    assert!(!result.summaries.iter().any(|v| v.assignment_id == "101"));
                    break;
                }
            }
        }
        let requests = transport.requests.lock().unwrap();
        for id in ["101", "102", "103", "201"] {
            assert_eq!(
                requests
                    .iter()
                    .filter(|r| r.url.ends_with(&format!("assignID={id}")))
                    .count(),
                2
            );
        }
    });
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 无缓存显式目标只读选中课程和作业_缺目标拒绝_取消丢弃迟到返回() {
    let (root, mut client, transport) = online_client("judge-online-keys");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let options = JudgeOnlineOptions {
            keys: Some(vec![JudgeAssignmentKey {
                course_id: "12".into(),
                assignment_id: "102".into(),
            }]),
            ..JudgeOnlineOptions::default()
        };
        let mut plan = client.begin_judge_online(options).await.unwrap();
        let index = client.next_judge_online(&mut plan).await.unwrap();
        assert_eq!(index.batch.assignments.len(), 1);
        assert_eq!(index.batch.assignments[0].assignment_id, "102");
        *transport.cancel_on_detail.lock().unwrap() = Some(plan.cancellation());
        assert!(matches!(
            client.next_judge_online(&mut plan).await,
            Err(OfflineReadError::Cache(
                ubaa_core::facade::CacheError::Superseded
            ))
        ));
        assert!(
            !transport
                .requests
                .lock()
                .unwrap()
                .iter()
                .any(|r| r.url.ends_with("assignID=101") || r.url.ends_with("courseID=13"))
        );
        let missing = JudgeOnlineOptions {
            keys: Some(vec![JudgeAssignmentKey {
                course_id: "missing".into(),
                assignment_id: "102".into(),
            }]),
            ..JudgeOnlineOptions::default()
        };
        assert!(matches!(
            client.begin_judge_online(missing).await,
            Err(OfflineReadError::Read(_))
        ));
    });
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 无缓存计划业务认证失效仍停止原计划() {
    let (root, mut client, transport) = online_client("judge-online-guards");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let mut plan = client
            .begin_judge_online(JudgeOnlineOptions::default())
            .await
            .unwrap();
        client.next_judge_online(&mut plan).await.unwrap();
        transport.reject_detail.store(true, Ordering::SeqCst);
        transport.expire_primary.store(true, Ordering::SeqCst);
        let Err(OfflineReadError::Read(error)) = client.next_judge_online(&mut plan).await else {
            panic!("必须保留认证失效")
        };
        assert_eq!(
            error.error.code,
            ubaa_core::facade::ErrorCode::AuthenticationRequired
        );
    });
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 无缓存批量目标去重且课内保留输入顺序_空目标与索引缺失拒绝() {
    let (root, mut client, transport) = online_client("judge-online-order");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let empty = JudgeOnlineOptions {
            keys: Some(Vec::new()),
            ..JudgeOnlineOptions::default()
        };
        assert!(matches!(
            client.begin_judge_online(empty).await,
            Err(OfflineReadError::Read(_))
        ));
        assert!(transport.requests.lock().unwrap().is_empty());
        let keys = [("12", "102"), ("12", "101"), ("12", "102"), ("13", "201")]
            .map(|(course, assignment)| JudgeAssignmentKey {
                course_id: course.into(),
                assignment_id: assignment.into(),
            })
            .to_vec();
        let mut plan = client
            .begin_judge_online(JudgeOnlineOptions {
                keys: Some(keys),
                ..JudgeOnlineOptions::default()
            })
            .await
            .unwrap();
        let mut ids = Vec::new();
        loop {
            let result = client.next_judge_online(&mut plan).await.unwrap();
            assert!(result.fetched_at > 0);
            if let Some(detail) = result.batch.detail {
                ids.push(detail.assignment_id);
            }
            if result.batch.finished {
                assert!(result.batch.complete);
                break;
            }
        }
        assert_eq!(ids, ["102", "101", "201"]);
        let mut plan = client
            .begin_judge_online(JudgeOnlineOptions {
                keys: Some(vec![JudgeAssignmentKey {
                    course_id: "12".into(),
                    assignment_id: "absent".into(),
                }]),
                ..JudgeOnlineOptions::default()
            })
            .await
            .unwrap();
        assert!(matches!(
            client.next_judge_online(&mut plan).await,
            Err(OfflineReadError::Read(_))
        ));
        let count = transport.requests.lock().unwrap().len();
        assert!(client.next_judge_online(&mut plan).await.is_err());
        assert_eq!(transport.requests.lock().unwrap().len(), count);
    });
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 无缓存单课程故障保留其他课程渐进内容且不冒充完整或真空集合() {
    let (root, mut client, transport) = online_client("judge-online-partial");
    transport.fail_detail.store(true, Ordering::SeqCst);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let mut plan = client
            .begin_judge_online(JudgeOnlineOptions {
                include_expired: true,
                ..JudgeOnlineOptions::default()
            })
            .await
            .unwrap();
        let mut errors = 0;
        loop {
            let result = client.next_judge_online(&mut plan).await.unwrap();
            if result.batch.kind == JudgeScanKind::CourseFailure {
                errors += 1;
                assert!(result.batch.error.is_some());
            }
            if result.batch.finished {
                assert!(!result.batch.complete);
                assert_eq!(result.batch.failed_courses, 1);
                assert_eq!(result.summaries.len(), 1);
                assert_eq!(result.summaries[0].course_id, "13");
                break;
            }
        }
        assert_eq!(errors, 1);
    });
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 无缓存不绕过已有本机账号身份核对() {
    let (root, mut client, transport) = online_client("judge-online-identity");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let options = JudgeOnlineOptions {
            expected_identity: Some("another-synthetic".into()),
            ..JudgeOnlineOptions::default()
        };
        assert!(matches!(
            client.begin_judge_online(options).await,
            Err(OfflineReadError::IdentityMismatch { .. })
        ));
        assert_eq!(transport.requests.lock().unwrap().len(), 1);
        let options = JudgeOnlineOptions {
            expected_identity: Some("fixture-user".into()),
            ..JudgeOnlineOptions::default()
        };
        assert!(client.begin_judge_online(options).await.is_ok());
    });
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
