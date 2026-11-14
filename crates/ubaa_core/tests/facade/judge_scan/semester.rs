use super::*;
use ubaa_core::facade::{
    CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeDetailRefresh,
    JudgeRefreshOptions, OfflineRepository, Term, Week,
};

fn seed_calendar(repository: &mut OfflineRepository, expired: bool) {
    let now = chrono::Utc::now() - chrono::Duration::days(if expired { 60 } else { 0 });
    for (query, payload) in [
        (
            CacheQuery::ScheduleTerms,
            CachePayload::Terms(vec![Term {
                item_code: "test-term".into(),
                selected: true,
                ..Default::default()
            }]),
        ),
        (
            CacheQuery::ScheduleWeeks {
                term: "test-term".into(),
            },
            CachePayload::Weeks(
                (0..5)
                    .map(|i| Week {
                        term: "test-term".into(),
                        serial_number: i + 1,
                        start_date: (now + chrono::Duration::days(i64::from(i) * 7 - 14))
                            .format("%Y-%m-%d 00:00:00")
                            .to_string(),
                        end_date: (now + chrono::Duration::days(i64::from(i) * 7 - 8))
                            .format("%Y-%m-%d 00:00:00")
                            .to_string(),
                        ..Default::default()
                    })
                    .collect(),
            ),
        ),
    ] {
        let ticket = repository
            .begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query,
            })
            .unwrap();
        repository
            .publish(
                &ticket,
                payload,
                now.timestamp(),
                CacheCompleteness::Complete,
            )
            .unwrap();
    }
}

async fn run(
    client: &mut UbaaClient,
    cache: &OfflineCache,
    include_expired: bool,
) -> Vec<ubaa_core::facade::JudgeAssignmentSummary> {
    let mut plan = client
        .begin_judge_refresh(
            cache,
            JudgeRefreshOptions {
                include_expired,
                refresh_indices: true,
                detail_refresh: JudgeDetailRefresh::RefreshActive,
                ..Default::default()
            },
        )
        .await
        .unwrap();
    loop {
        let result = client.next_judge_refresh(&mut plan).await.unwrap();
        assert_eq!(result.save_error, None);
        if result.batch.finished {
            assert!(result.batch.complete);
            return result.summaries;
        }
    }
}

#[test]
fn 本学期刷新跳过往期未提交课程且保留历史核验时间() {
    verify_scope(false, false);
}

#[test]
fn 混合课程先筛除往期作业且连续刷新不丢课程归属() {
    verify_scope(true, false);
}

fn verify_scope(mixed: bool, expired: bool) {
    let (root, mut client, cache, transport) = setup(&format!("judge-semester-{mixed}-{expired}"));
    transport.semester_details.store(true, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            run(&mut client, &cache, true).await;
            let mut repository = OfflineRepository::open(
                &root,
                "0123456789abcdef0123456789abcdef",
                CacheKey::new([9; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            seed_calendar(&mut repository, expired);
            let scope = CacheScope {
                route: ConnectionMode::Direct,
                query: CacheQuery::JudgeCourseReview {
                    course_id: "12".into(),
                },
            };
            let mut review = cache
                .read(&scope, chrono::Utc::now().timestamp())
                .unwrap()
                .unwrap();
            let CachePayload::JudgeCourseReview(metadata) = &mut review.payload else {
                panic!()
            };
            for item in &mut metadata.summaries {
                if !mixed || item.assignment_id == "101" {
                    item.start_time = Some("2000-01-01 00:00:00".into());
                    item.due_time = Some("2000-02-01 00:00:00".into());
                    item.submission_status = ubaa_core::facade::JudgeSubmissionStatus::Unsubmitted;
                }
            }
            let ticket = repository.begin_read(scope.clone()).unwrap();
            repository
                .publish(&ticket, review.payload, 100, CacheCompleteness::Complete)
                .unwrap();
            let historical = cache
                .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                .unwrap()
                .unwrap();
            for attempt in 0..3 {
                if !mixed && attempt == 2 {
                    let failed = repository.begin_read(scope.clone()).unwrap();
                    repository
                        .record_failure(&failed, chrono::Utc::now().timestamp())
                        .unwrap();
                }
                let before = transport.requests.lock().unwrap().len();
                let summaries = run(&mut client, &cache, false).await;
                let requests = transport.requests.lock().unwrap();
                assert!(
                    !requests[before..]
                        .iter()
                        .any(|r| r.url.ends_with("assignID=101")),
                    "往期详情不进入请求队列"
                );
                if !mixed {
                    assert!(
                        !requests[before..]
                            .iter()
                            .any(|r| r.url.ends_with("courseID=12")),
                        "往期课程不重新选课或读取索引"
                    );
                }
                assert_eq!(summaries.len(), if mixed { 2 } else { 1 });
                assert!(!summaries.iter().any(|s| s.assignment_id == "101"));
            }
            let unchanged = cache
                .read_judge_detail(ConnectionMode::Direct, "12".into(), "101".into())
                .unwrap()
                .unwrap();
            assert_eq!(unchanged.last_verified_at, historical.last_verified_at);
            let kept = cache
                .read(&scope, chrono::Utc::now().timestamp())
                .unwrap()
                .unwrap();
            let CachePayload::JudgeCourseReview(metadata) = kept.payload else {
                panic!()
            };
            assert_eq!(metadata.summaries.len(), 2, "缩小扫描后仍保留完整归属摘要");
            verify_explicit(&mut client, &cache, &mut repository, metadata.summaries).await;
            assert_eq!(
                run(&mut client, &cache, true).await.len(),
                3,
                "显式历史读取仍覆盖全部项目"
            );
        });
    drop((client, cache));
    std::fs::remove_dir_all(root).unwrap();
}

impl ScanTransport {
    pub(super) fn semester_detail_body(&self) -> Vec<u8> {
        let body = include_str!("../../../../../fixtures/readonly/judge-detail.html");
        if !self.semester_details.load(Ordering::SeqCst) {
            return body.as_bytes().to_vec();
        }
        let now = chrono::Utc::now();
        body.replace(
            "2026-08-01",
            &(now - chrono::Duration::days(7))
                .format("%Y-%m-%d")
                .to_string(),
        )
        .replace(
            "2026-08-31",
            &(now + chrono::Duration::days(7))
                .format("%Y-%m-%d")
                .to_string(),
        )
        .into_bytes()
    }
}

#[test]
fn 校历跨期尚未更新时已确认往期课程仍不重新读取() {
    verify_scope(false, true);
}

async fn verify_explicit(
    client: &mut UbaaClient,
    cache: &OfflineCache,
    repository: &mut OfflineRepository,
    summaries: Vec<ubaa_core::facade::JudgeAssignmentSummary>,
) {
    // 模拟旧版默认摘要仍包含往期未提交作业，显式详情必须仍可打开。
    let legacy = repository
        .begin_read(CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::JudgeSummaries {
                include_expired: false,
            },
        })
        .unwrap();
    repository
        .publish(
            &legacy,
            CachePayload::JudgeSummaries(summaries),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
    let mut explicit = client
        .begin_judge_refresh(
            cache,
            JudgeRefreshOptions {
                current_assignment: Some(ubaa_core::facade::JudgeAssignmentKey {
                    course_id: "12".into(),
                    assignment_id: "101".into(),
                }),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    let index = client.next_judge_refresh(&mut explicit).await.unwrap();
    assert!(
        index
            .batch
            .assignments
            .iter()
            .any(|item| item.assignment_id == "101"),
        "显式历史详情必须保留索引目标"
    );
    let detail = client.next_judge_refresh(&mut explicit).await.unwrap();
    assert_eq!(detail.batch.detail.unwrap().assignment_id, "101");
    explicit.cancellation().cancel();
}
