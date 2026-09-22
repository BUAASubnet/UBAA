use super::*;
use std::sync::Mutex;
use ubaa_core::facade::{CacheKey, CacheLimits, JudgeScanKind, OfflineCache};

#[derive(Clone, Default)]
struct ScanTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    fail_detail: Arc<std::sync::atomic::AtomicBool>,
    cancel_on_detail: Arc<Mutex<Option<ubaa_core::facade::JudgeScanCancellation>>>,
    reject_detail: Arc<std::sync::atomic::AtomicBool>,
    expire_primary: Arc<std::sync::atomic::AtomicBool>,
    historical_details: Arc<std::sync::atomic::AtomicBool>,
    add_assignment: Arc<std::sync::atomic::AtomicBool>,
    rename_assignment: Arc<std::sync::atomic::AtomicBool>,
}
#[async_trait]
impl HttpTransport for ScanTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let parsed = url::Url::parse(&request.url).unwrap();
        let query = parsed
            .query_pairs()
            .collect::<std::collections::HashMap<_, _>>();
        let response = if request.url.ends_with("/api/uc/status") {
            if self.expire_primary.load(Ordering::SeqCst)
                && self.reject_detail.load(Ordering::SeqCst)
            {
                return Ok(HttpResponse::new(401, request.url.clone(), Vec::new()));
            }
            HttpResponse::new(
                200,
                request.url.clone(),
                include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
            )
        } else if parsed.host_str() == Some("sso.buaa.edu.cn") {
            let mut value = HttpResponse::new(302, request.url.clone(), Vec::new());
            value
                .headers
                .insert("Location".into(), vec!["https://judge.buaa.edu.cn/".into()]);
            value
        } else if parsed.path() == "/" {
            HttpResponse::new(200, request.url.clone(), b"<html>ready</html>".to_vec())
        } else if parsed.path() == "/courselist.jsp" {
            HttpResponse::new(200, request.url.clone(), br"<a href='courselist.jsp?courseID=12'>Course A</a><a href='courselist.jsp?courseID=13'>Course B</a>".to_vec())
        } else if parsed.path() == "/assignment/index.jsp" {
            let cookie = request
                .headers
                .iter()
                .find(|(key, _)| key.eq_ignore_ascii_case("cookie"))
                .map_or("", |(_, value)| value.as_str());
            if let Some(id) = query.get("assignID") {
                if let Some(cancel) = self.cancel_on_detail.lock().unwrap().take() {
                    cancel.cancel();
                }
                if self.reject_detail.load(Ordering::SeqCst) {
                    return Err(ubaa_core::facade::UbaaError::new(
                        ubaa_core::facade::ErrorCode::AuthenticationRequired,
                        ubaa_core::facade::ErrorKind::Authentication,
                        false,
                        "合成业务认证失效",
                    ));
                }
                if self.fail_detail.load(Ordering::SeqCst) && id.as_ref() == "101" {
                    return Err(ubaa_core::facade::UbaaError::new(
                        ubaa_core::facade::ErrorCode::NetworkError,
                        ubaa_core::facade::ErrorKind::Network,
                        true,
                        "合成网络故障",
                    ));
                }
                let expected = if id.starts_with('1') {
                    "selected=12"
                } else {
                    "selected=13"
                };
                assert!(cookie.contains(expected), "详情前必须显式选择本课程");
                if self.historical_details.load(Ordering::SeqCst) && id.as_ref() != "103" {
                    return Ok(HttpResponse::new(200, request.url.clone(), "<html><body>作业满分：1，共 1 道题，得分：1。作业时间：2000-01-01 00:00 至 2000-02-01 00:00</body></html>".as_bytes().to_vec()));
                }
                HttpResponse::new(
                    200,
                    request.url.clone(),
                    include_bytes!("../../../../fixtures/readonly/judge-detail.html").to_vec(),
                )
            } else {
                let body = if self.add_assignment.load(Ordering::SeqCst)
                    && cookie.contains("selected=12")
                {
                    "<a href='assignment/index.jsp?assignID=101'>Task A1</a><a href='assignment/index.jsp?assignID=102'>Task A2</a><a href='assignment/index.jsp?assignID=103'>New task</a>"
                } else if cookie.contains("selected=13") {
                    "<a href='assignment/index.jsp?assignID=201'>Task B</a>"
                } else {
                    "<a href='assignment/index.jsp?assignID=101'>Task A1</a><a href='assignment/index.jsp?assignID=102'>Task A2</a>"
                };
                let body = if self.rename_assignment.load(Ordering::SeqCst) {
                    body.replace("Task A1", "Task A1 updated")
                } else {
                    body.to_owned()
                };
                HttpResponse::new(200, request.url.clone(), body.as_bytes().to_vec())
            }
        } else if request.url.contains("currentUser.do") {
            HttpResponse::new(200, request.url.clone(), b"{}".to_vec())
        } else if request.url.contains("teachingSchedule/detail.do") {
            HttpResponse::new(
                200,
                request.url.clone(),
                include_bytes!("../../../../fixtures/readonly/schedule-today.json").to_vec(),
            )
        } else {
            panic!("未预期的合成操作");
        };
        Ok(with_selection(response, &parsed))
    }
}
fn with_selection(mut response: HttpResponse, parsed: &url::Url) -> HttpResponse {
    if parsed.host_str() == Some("judge.buaa.edu.cn") {
        let selected = if parsed.path() == "/" {
            Some("0".to_owned())
        } else {
            parsed
                .query_pairs()
                .find(|(key, _)| key == "courseID")
                .map(|(_, value)| value.into_owned())
        };
        if let Some(selected) = selected {
            response.headers.insert(
                "Set-Cookie".into(),
                vec![format!("selected={selected}; Path=/; Secure")],
            );
        }
    }
    response
}

fn setup(label: &str) -> (std::path::PathBuf, UbaaClient, OfflineCache, ScanTransport) {
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
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (root, client, cache, transport)
}
#[test]
fn scan_returns_between_index_and_each_detail_and_reselects_after_other_work() {
    let (root, mut client, cache, transport) = setup("judge-scan-boundaries");
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let mut scan = client.begin_judge_scan(&cache, false, None).await.unwrap();
        assert_eq!(scan.courses().len(), 2);
        let first = client.next_judge_scan(&mut scan).await.unwrap();
        assert_eq!(first.data.kind, JudgeScanKind::Assignments);
        assert_eq!(first.data.assignments.len(), 2);
        assert!(
            !transport
                .requests
                .lock()
                .unwrap()
                .iter()
                .any(|r| r.url.contains("assignID="))
        );
        assert_eq!(client.schedule_today().await.unwrap().data.len(), 1);
        let mut other = client
            .begin_judge_scan(&cache, true, Some("13"))
            .await
            .unwrap();
        assert_eq!(
            client
                .next_judge_scan(&mut other)
                .await
                .unwrap()
                .data
                .course_id
                .as_deref(),
            Some("13")
        );
        let detail = client.next_judge_scan(&mut scan).await.unwrap();
        assert_eq!(detail.data.kind, JudgeScanKind::Detail);
        assert_eq!(detail.data.detail.unwrap().assignment_id, "101");
        assert!(!detail.data.finished);
        assert_eq!(detail_request_count(&transport), 1);
        let cancel = scan.cancellation();
        cancel.cancel();
        let before = transport.requests.lock().unwrap().len();
        assert!(client.next_judge_scan(&mut scan).await.is_err());
        assert_eq!(transport.requests.lock().unwrap().len(), before);
    });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn superseded_and_closed_cache_plans_never_send_another_request() {
    let (root, mut client, cache, transport) = setup("judge-scan-invalidated");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut old = client.begin_judge_scan(&cache, false, None).await.unwrap();
            let mut latest = client.begin_judge_scan(&cache, false, None).await.unwrap();
            let before = transport.requests.lock().unwrap().len();
            assert!(matches!(
                client.next_judge_scan(&mut old).await,
                Err(ubaa_core::facade::OfflineReadError::Cache(
                    ubaa_core::facade::CacheError::Superseded
                ))
            ));
            assert_eq!(transport.requests.lock().unwrap().len(), before);
            cache.deactivate().unwrap();
            assert!(matches!(
                client.next_judge_scan(&mut latest).await,
                Err(ubaa_core::facade::OfflineReadError::Cache(
                    ubaa_core::facade::CacheError::Inactive
                ))
            ));
            assert_eq!(transport.requests.lock().unwrap().len(), before);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn a_course_failure_preserves_progress_and_continues_other_courses() {
    let (root, mut client, cache, transport) = setup("judge-scan-partial");
    transport.fail_detail.store(true, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut scan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            client.next_judge_scan(&mut scan).await.unwrap();
            let failure = client.next_judge_scan(&mut scan).await.unwrap().data;
            assert_eq!(failure.kind, JudgeScanKind::CourseFailure);
            assert!(!failure.complete);
            assert_eq!(failure.failed_courses, 1);
            assert_eq!(
                client
                    .next_judge_scan(&mut scan)
                    .await
                    .unwrap()
                    .data
                    .course_id
                    .as_deref(),
                Some("13")
            );
            let final_batch = client.next_judge_scan(&mut scan).await.unwrap().data;
            assert_eq!(final_batch.detail.unwrap().assignment_id, "201");
            assert!(final_batch.finished);
            assert!(!final_batch.complete);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn a_scan_cannot_be_used_by_another_client() {
    let (root, mut client, cache, transport) = setup("judge-scan-owner-a");
    let (other_root, mut other, other_cache, other_transport) = setup("judge-scan-owner-b");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut scan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            let before = transport.requests.lock().unwrap().len();
            assert!(client.next_judge_scan(&mut scan).await.is_ok());
            assert!(other.next_judge_scan(&mut scan).await.is_err());
            assert!(other_transport.requests.lock().unwrap().is_empty());
            assert!(transport.requests.lock().unwrap().len() > before);
        });
    drop((cache, other_cache));
    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(other_root);
}

#[test]
fn cancellation_during_a_request_discards_the_response_and_stops_following_batches() {
    let (root, mut client, cache, transport) = setup("judge-scan-late-cancel");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut scan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            client.next_judge_scan(&mut scan).await.unwrap();
            *transport.cancel_on_detail.lock().unwrap() = Some(scan.cancellation());
            assert!(matches!(
                client.next_judge_scan(&mut scan).await,
                Err(ubaa_core::facade::OfflineReadError::Cache(
                    ubaa_core::facade::CacheError::Superseded
                ))
            ));
            let before = transport.requests.lock().unwrap().len();
            assert!(client.next_judge_scan(&mut scan).await.is_err());
            assert_eq!(transport.requests.lock().unwrap().len(), before);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn exhausted_business_authentication_stops_the_whole_scan_after_primary_arbitration() {
    let (root, mut client, cache, transport) = setup("judge-scan-auth-stop");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut scan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            client.next_judge_scan(&mut scan).await.unwrap();
            transport.reject_detail.store(true, Ordering::SeqCst);
            let error = client.next_judge_scan(&mut scan).await.err().unwrap();
            let ubaa_core::facade::OfflineReadError::Read(error) = error else {
                panic!("必须保留认证仲裁的错误分类");
            };
            assert_eq!(
                error.error.code,
                ubaa_core::facade::ErrorCode::UpstreamUnavailable
            );
            let before = transport.requests.lock().unwrap().len();
            assert!(client.next_judge_scan(&mut scan).await.is_err());
            assert_eq!(transport.requests.lock().unwrap().len(), before);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn primary_authentication_failure_keeps_its_original_error_classification() {
    let (root, mut client, cache, transport) = setup("judge-scan-primary-expired");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut scan = client.begin_judge_scan(&cache, false, None).await.unwrap();
            client.next_judge_scan(&mut scan).await.unwrap();
            transport.expire_primary.store(true, Ordering::SeqCst);
            transport.reject_detail.store(true, Ordering::SeqCst);
            let error = client.next_judge_scan(&mut scan).await.err().unwrap();
            let ubaa_core::facade::OfflineReadError::Read(error) = error else {
                panic!("主认证错误不能被内部代次失效覆盖");
            };
            assert_eq!(
                error.error.code,
                ubaa_core::facade::ErrorCode::AuthenticationRequired
            );
            assert_eq!(error.resolution.unwrap().mode, ConnectionMode::Direct);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn persistent_refresh_reuses_details_after_restart_and_full_refresh_bypasses_memory_ttl() {
    use ubaa_core::facade::{CachePayload, CacheQuery, CacheScope, JudgeRefreshOptions};
    let (root, mut client, cache, transport) = setup("judge-persistent-refresh");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            loop {
                let batch = client.next_judge_refresh(&mut refresh).await.unwrap();
                if batch.batch.finished {
                    assert!(batch.batch.complete);
                    assert_eq!(batch.summaries.len(), 3);
                    break;
                }
            }
            assert_eq!(detail_request_count(&transport), 3);
            assert!(matches!(
                cache
                    .read(
                        &CacheScope {
                            route: ConnectionMode::Direct,
                            query: CacheQuery::JudgeCourses
                        },
                        chrono::Utc::now().timestamp()
                    )
                    .unwrap()
                    .unwrap()
                    .payload,
                CachePayload::JudgeCourses(_)
            ));
            // 新客户端没有原运行时内存缓存，仍应使用同一个账号库的合法详情。
            drop(client);
            let reopened = OfflineCache::open(
                &root,
                "0123456789abcdef0123456789abcdef",
                "fixture-user",
                CacheKey::new([9; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            let mut client = UbaaClient::with_routing(
                transport.clone(),
                CountingTransport(Arc::new(AtomicUsize::new(0))),
                FileSessionStore::new(&root).unwrap(),
                RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
                NeverProbe,
            )
            .unwrap();
            let mut refresh = client
                .begin_judge_refresh(&reopened, JudgeRefreshOptions::default())
                .await
                .unwrap();
            let mut reused = 0;
            loop {
                let batch = client.next_judge_refresh(&mut refresh).await.unwrap();
                if batch.reused && batch.batch.kind == JudgeScanKind::Detail {
                    reused += 1;
                }
                if batch.batch.finished {
                    break;
                }
            }
            assert_eq!(reused, 3);
            assert_eq!(detail_request_count(&transport), 3);
            let mut refresh = client
                .begin_judge_refresh(
                    &reopened,
                    JudgeRefreshOptions {
                        full_refresh: true,
                        ..Default::default()
                    },
                )
                .await
                .unwrap();
            loop {
                if client
                    .next_judge_refresh(&mut refresh)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {
                    break;
                }
            }
            assert_eq!(detail_request_count(&transport), 6);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn historical_course_is_rechecked_after_deadline_and_new_work_after_old_items_is_not_skipped() {
    use ubaa_core::facade::{
        CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeRefreshOptions,
        OfflineRepository,
    };
    let (root, mut client, cache, transport) = setup("judge-history-review");
    transport.historical_details.store(true, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            loop {
                if client
                    .next_judge_refresh(&mut refresh)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {
                    break;
                }
            }
            let before = transport.requests.lock().unwrap().len();
            transport.add_assignment.store(true, Ordering::SeqCst);
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            let mut reused_indexes = 0;
            loop {
                let batch = client.next_judge_refresh(&mut refresh).await.unwrap();
                if batch.reused && batch.batch.kind == JudgeScanKind::Assignments {
                    reused_indexes += 1;
                }
                if batch.batch.finished {
                    break;
                }
            }
            assert_eq!(reused_indexes, 2, "有效历史索引在一天期限内可复用");
            assert!(
                !transport.requests.lock().unwrap()[before..]
                    .iter()
                    .any(|r| r.url.contains("assignment/index.jsp"))
            );
            let now = chrono::Utc::now().timestamp();
            let review_scope = CacheScope {
                route: ConnectionMode::Direct,
                query: CacheQuery::JudgeCourseReview {
                    course_id: "12".into(),
                },
            };
            let mut review = cache.read(&review_scope, now).unwrap().unwrap();
            let CachePayload::JudgeCourseReview(metadata) = &mut review.payload else {
                panic!("必须保存历史复查依据");
            };
            metadata.next_index_check_at = now - 1;
            let mut repo = OfflineRepository::open(
                &root,
                "0123456789abcdef0123456789abcdef",
                CacheKey::new([9; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            let ticket = repo.begin_read(review_scope).unwrap();
            repo.publish(&ticket, review.payload, now, CacheCompleteness::Complete)
                .unwrap();
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            let mut found = false;
            loop {
                let batch = client.next_judge_refresh(&mut refresh).await.unwrap();
                if batch
                    .batch
                    .detail
                    .as_ref()
                    .is_some_and(|item| item.assignment_id == "103")
                {
                    found = true;
                    assert!(!batch.reused);
                }
                if batch.batch.finished {
                    assert!(batch.batch.complete);
                    break;
                }
            }
            assert!(found, "旧项目之后的新作业必须被发现，不能永久排除课程");
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn current_detail_is_first_and_changed_title_is_not_hidden_by_a_fresh_detail_cache() {
    use ubaa_core::facade::{JudgeAssignmentKey, JudgeRefreshOptions};
    let (root, mut client, cache, transport) = setup("judge-current-and-changed");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut warm = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            loop {
                if client
                    .next_judge_refresh(&mut warm)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {
                    break;
                }
            }
            let mut focus = client
                .begin_judge_refresh(
                    &cache,
                    JudgeRefreshOptions {
                        current_assignment: Some(JudgeAssignmentKey {
                            course_id: "12".into(),
                            assignment_id: "102".into(),
                        }),
                        ..Default::default()
                    },
                )
                .await
                .unwrap();
            client.next_judge_refresh(&mut focus).await.unwrap();
            let detail = client.next_judge_refresh(&mut focus).await.unwrap();
            assert_eq!(detail.batch.detail.unwrap().assignment_id, "102");
            assert!(!detail.reused, "当前详情必须提升并做真实校验");
            transport.rename_assignment.store(true, Ordering::SeqCst);
            let mut changed = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            client.next_judge_refresh(&mut changed).await.unwrap();
            let detail = client.next_judge_refresh(&mut changed).await.unwrap();
            assert_eq!(detail.batch.detail.unwrap().title, "Task A1 updated");
            assert!(!detail.reused, "同 ID 索引变化不能被旧详情 TTL 遮蔽");
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn historical_detail_is_checked_after_seven_days_even_when_course_index_is_reused() {
    use ubaa_core::facade::{
        CacheCompleteness, CacheQuery, CacheScope, JudgeRefreshOptions, OfflineRepository,
    };
    let (root, mut client, cache, transport) = setup("judge-history-detail-deadline");
    transport.historical_details.store(true, Ordering::SeqCst);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            loop {
                if client
                    .next_judge_refresh(&mut refresh)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {
                    break;
                }
            }
            let now = chrono::Utc::now().timestamp();
            let detail_scope = CacheScope {
                route: ConnectionMode::Direct,
                query: CacheQuery::JudgeDetail {
                    course_id: "12".into(),
                    assignment_id: "101".into(),
                },
            };
            let old_detail = cache.read(&detail_scope, now).unwrap().unwrap();
            let mut repo = OfflineRepository::open(
                &root,
                "0123456789abcdef0123456789abcdef",
                CacheKey::new([9; 32]),
                CacheLimits::default(),
            )
            .unwrap();
            let ticket = repo.begin_read(detail_scope).unwrap();
            repo.publish(
                &ticket,
                old_detail.payload,
                now - 8 * 86400,
                CacheCompleteness::Complete,
            )
            .unwrap();
            let before = transport.requests.lock().unwrap().len();
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            let mut expired_rechecked = false;
            loop {
                let batch = client.next_judge_refresh(&mut refresh).await.unwrap();
                if batch
                    .batch
                    .detail
                    .as_ref()
                    .is_some_and(|detail| detail.assignment_id == "101")
                {
                    expired_rechecked = true;
                    assert!(!batch.reused);
                }
                if batch.batch.finished {
                    break;
                }
            }
            assert!(expired_rechecked);
            let requests = transport.requests.lock().unwrap();
            assert_eq!(
                requests[before..]
                    .iter()
                    .filter(|request| request.url.contains("assignID="))
                    .count(),
                1
            );
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn persistent_partial_refresh_keeps_the_previous_complete_summary() {
    use ubaa_core::facade::JudgeRefreshOptions;
    let (root, mut client, cache, transport) = setup("judge-partial-persistence");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut warm = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            loop {
                if client
                    .next_judge_refresh(&mut warm)
                    .await
                    .unwrap()
                    .batch
                    .finished
                {
                    break;
                }
            }
            let prior = cache
                .read_judge(ConnectionMode::Direct, false)
                .unwrap()
                .unwrap();
            transport.fail_detail.store(true, Ordering::SeqCst);
            let mut refresh = client
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
                let batch = client.next_judge_refresh(&mut refresh).await.unwrap();
                if batch.batch.finished {
                    assert!(!batch.batch.complete);
                    break;
                }
            }
            let after = cache
                .read_judge(ConnectionMode::Direct, false)
                .unwrap()
                .unwrap();
            assert_eq!(after.payload, prior.payload);
            assert_eq!(after.fetched_at, prior.fetched_at);
            assert!(!after.last_attempt_succeeded);
        });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

fn detail_request_count(transport: &ScanTransport) -> usize {
    transport
        .requests
        .lock()
        .unwrap()
        .iter()
        .filter(|request| request.url.contains("assignID="))
        .count()
}

#[test]
fn persistent_refresh_authentication_failure_marks_attempt_without_erasing_saved_content() {
    use ubaa_core::facade::{JudgeRefreshOptions, OfflineReadError};
    let (root, mut client, cache, transport) = setup("judge-persistent-auth-failure");
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async {
        let mut warm = client.begin_judge_refresh(&cache, JudgeRefreshOptions::default()).await.unwrap();
        loop { if client.next_judge_refresh(&mut warm).await.unwrap().batch.finished { break; } }
        let prior = cache.read_judge(ConnectionMode::Direct, false).unwrap().unwrap();
        let mut refresh = client.begin_judge_refresh(&cache, JudgeRefreshOptions { full_refresh: true, ..Default::default() }).await.unwrap();
        client.next_judge_refresh(&mut refresh).await.unwrap();
        transport.expire_primary.store(true, Ordering::SeqCst);
        transport.reject_detail.store(true, Ordering::SeqCst);
        let error = client.next_judge_refresh(&mut refresh).await.err().unwrap();
        assert!(matches!(error, OfflineReadError::Read(error) if error.error.code == ErrorCode::AuthenticationRequired));
        let saved = cache.read_judge(ConnectionMode::Direct, false).unwrap().unwrap();
        assert_eq!(saved.payload, prior.payload);
        assert!(!saved.last_attempt_succeeded);
    });
    drop(cache);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn progressive_summary_time_tracks_remaining_old_items_instead_of_latest_batch_time() {
    use ubaa_core::facade::{
        CacheCompleteness, CachePayload, CacheQuery, CacheScope, JudgeAssignmentSummary,
        JudgeRefreshOptions, OfflineRepository,
    };
    let (root, mut client, cache, _) = setup("judge-summary-source-time");
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
                    course_name: "Course A".into(),
                    assignment_id: "101".into(),
                    title: "Task A1".into(),
                    ..Default::default()
                },
                JudgeAssignmentSummary {
                    course_id: "12".into(),
                    course_name: "Course A".into(),
                    assignment_id: "102".into(),
                    title: "Task A2".into(),
                    ..Default::default()
                },
            ]),
            100,
            CacheCompleteness::Complete,
        )
        .unwrap();
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut refresh = client
                .begin_judge_refresh(&cache, JudgeRefreshOptions::default())
                .await
                .unwrap();
            let index = client.next_judge_refresh(&mut refresh).await.unwrap();
            assert_eq!(index.summary_fetched_at, 100);
            assert!(index.summary_has_cached);
            let first = client.next_judge_refresh(&mut refresh).await.unwrap();
            assert_eq!(
                first.summary_fetched_at, 100,
                "仍有旧项目，不能使用新详情的时间"
            );
            assert!(first.summary_has_cached);
            let second = client.next_judge_refresh(&mut refresh).await.unwrap();
            assert!(second.summary_fetched_at > 100);
            assert!(!second.summary_has_cached);
        });
    drop((repository, cache));
    let _ = std::fs::remove_dir_all(root);
}

#[path = "judge_scan/online.rs"]
mod online;
