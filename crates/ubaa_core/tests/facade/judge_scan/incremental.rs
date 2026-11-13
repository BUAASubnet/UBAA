use super::*;
use ubaa_core::facade::{
    CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeRefreshOptions, OfflineRepository,
};

async fn refresh(client: &mut UbaaClient, cache: &OfflineCache) -> i64 {
    let mut plan = client
        .begin_judge_refresh(
            cache,
            JudgeRefreshOptions {
                refresh_indices: true,
                ..Default::default()
            },
        )
        .await
        .unwrap();
    loop {
        let batch = client.next_judge_refresh(&mut plan).await.unwrap();
        assert_eq!(batch.save_error, None);
        if batch.batch.finished {
            assert!(batch.batch.complete, "合法缓存详情复用后仍是完整集合");
            return batch.summary_fetched_at;
        }
    }
}

// 直接回填取得时间，模拟正常刷新间隔，不等待墙钟或延长请求期限。
fn age_details(root: &std::path::Path, cache: &OfflineCache, age: i64, due: Option<&str>) -> i64 {
    let at = chrono::Utc::now().timestamp() - age;
    let mut repository = OfflineRepository::open(
        root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    for (course, assignment) in [("12", "101"), ("12", "102"), ("13", "201")] {
        let record = cache
            .read_judge_detail(ConnectionMode::Direct, course.into(), assignment.into())
            .unwrap()
            .unwrap();
        let CachePayload::JudgeDetail(mut detail) = record.payload else {
            panic!("必须存在完整详情");
        };
        detail.due_time = due.map(str::to_owned);
        let ticket = repository.begin_read(record.scope).unwrap();
        repository
            .publish(
                &ticket,
                CachePayload::JudgeDetail(detail),
                at,
                CacheCompleteness::Complete,
            )
            .unwrap();
    }
    at
}

fn deadline_after(seconds: i64) -> String {
    (chrono::Utc::now() + chrono::Duration::seconds(seconds) + chrono::Duration::hours(8))
        .format("%Y-%m-%d %H:%M:%S")
        .to_string()
}

#[test]
fn 列表未变在正常刷新间隔后不读详情且保留详情核验时间() {
    let (root, mut client, cache, transport) = setup("judge-incremental-unchanged");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            refresh(&mut client, &cache).await;
            let old_at = age_details(&root, &cache, 300, Some(&deadline_after(7 * 86400)));
            let before = detail_request_count(&transport);
            let summary_at = refresh(&mut client, &cache).await;
            assert_eq!(
                detail_request_count(&transport) - before,
                0,
                "未变列表不能重复下载详情"
            );
            assert_eq!(summary_at, old_at);
            let detail = cache
                .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                .unwrap()
                .unwrap();
            assert_eq!(detail.fetched_at, old_at);
            assert_eq!(detail.last_verified_at, old_at);
            let index = cache
                .read(
                    &CacheScope {
                        route: ConnectionMode::Direct,
                        query: CacheQuery::JudgeAssignments {
                            course_id: "12".into(),
                        },
                    },
                    chrono::Utc::now().timestamp(),
                )
                .unwrap()
                .unwrap();
            assert!(
                index.last_verified_at > old_at,
                "列表与详情的核验时间分别保留"
            );
            let summary = cache
                .read_judge(ConnectionMode::Direct, false)
                .unwrap()
                .unwrap();
            assert_eq!(summary.completeness, CacheCompleteness::Complete);
            assert!(summary.last_attempt_succeeded);
            assert_eq!(summary.fetched_at, old_at);
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 新增项只读该项详情_同编号标题变化只重读变化项() {
    for changed_title in [false, true] {
        let (root, mut client, cache, transport) =
            setup(&format!("judge-incremental-change-{changed_title}"));
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                refresh(&mut client, &cache).await;
                age_details(&root, &cache, 300, Some(&deadline_after(7 * 86400)));
                if changed_title {
                    transport.rename_assignment.store(true, Ordering::SeqCst);
                } else {
                    transport.add_assignment.store(true, Ordering::SeqCst);
                }
                let before = transport.requests.lock().unwrap().len();
                refresh(&mut client, &cache).await;
                let requested: Vec<_> = transport.requests.lock().unwrap()[before..]
                    .iter()
                    .filter(|request| request.url.contains("assignID="))
                    .map(|request| request.url.clone())
                    .collect();
                assert_eq!(requested.len(), 1, "仅新增或列表变化的项目需要详情");
                assert!(requested[0].ends_with(if changed_title {
                    "assignID=101"
                } else {
                    "assignID=103"
                }));
                if changed_title {
                    let record = cache
                        .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                        .unwrap()
                        .unwrap();
                    let CachePayload::JudgeDetail(detail) = record.payload else {
                        panic!("需要完整详情");
                    };
                    assert_eq!(detail.title, "Task A1 updated");
                }
            });
        drop((client, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 列表不可见变化按期限兜底_临近截止与未知截止缩短期限() {
    for (label, age, deadline, expected) in [
        ("normal-valid", 6 * 3600 - 60, Some(Ok(7 * 86400)), 0),
        ("normal-expired", 6 * 3600 + 1, Some(Ok(7 * 86400)), 3),
        ("near-valid", 14 * 60, Some(Ok(3600)), 0),
        ("near-expired", 15 * 60 + 1, Some(Ok(3600)), 3),
        ("recently-due", 15 * 60 + 1, Some(Ok(-3600)), 3),
        ("unknown", 15 * 60 + 1, None, 3),
        (
            "invalid-deadline",
            15 * 60 + 1,
            Some(Err("2026-02-30 00:00:00")),
            3,
        ),
        ("outside-near-window", 30 * 60, Some(Ok(86400 + 60)), 0),
        ("inside-near-window", 30 * 60, Some(Ok(86400 - 60)), 3),
    ] {
        let (root, mut client, cache, transport) = setup(&format!("judge-incremental-{label}"));
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                refresh(&mut client, &cache).await;
                // 每项准备完成后再确定截止时间，前面用例的耗时不占用本项边界余量。
                let due = deadline.map(|value| match value {
                    Ok(seconds) => deadline_after(seconds),
                    Err(text) => text.to_owned(),
                });
                age_details(&root, &cache, age, due.as_deref());
                let before = detail_request_count(&transport);
                refresh(&mut client, &cache).await;
                assert_eq!(
                    detail_request_count(&transport) - before,
                    expected,
                    "{label}"
                );
            });
        drop((client, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 详情上次核对失败时即使列表未变也重新读取该项() {
    let (root, mut client, cache, transport) = setup("judge-incremental-failed-attempt");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            refresh(&mut client, &cache).await;
            age_details(&root, &cache, 300, Some(&deadline_after(7 * 86400)));
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
                        assignment_id: "101".into(),
                    },
                })
                .unwrap();
            repository
                .record_failure(&ticket, chrono::Utc::now().timestamp())
                .unwrap();
            let before = transport.requests.lock().unwrap().len();
            refresh(&mut client, &cache).await;
            let requests = transport.requests.lock().unwrap();
            let details: Vec<_> = requests[before..]
                .iter()
                .filter(|request| request.url.contains("assignID="))
                .collect();
            assert_eq!(details.len(), 1);
            assert!(details[0].url.ends_with("assignID=101"));
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}
