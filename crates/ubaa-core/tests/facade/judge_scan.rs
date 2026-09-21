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
}
#[async_trait]
impl HttpTransport for ScanTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let parsed = url::Url::parse(&request.url).unwrap();
        let query = parsed
            .query_pairs()
            .collect::<std::collections::HashMap<_, _>>();
        let mut response = if request.url.ends_with("/api/uc/status") {
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
                HttpResponse::new(
                    200,
                    request.url.clone(),
                    include_bytes!("../../../../fixtures/readonly/judge-detail.html").to_vec(),
                )
            } else {
                let body = if cookie.contains("selected=13") {
                    "<a href='assignment/index.jsp?assignID=201'>Task B</a>"
                } else {
                    "<a href='assignment/index.jsp?assignID=101'>Task A1</a><a href='assignment/index.jsp?assignID=102'>Task A2</a>"
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
        if parsed.host_str() == Some("judge.buaa.edu.cn") {
            let selected = if parsed.path() == "/" {
                Some("0")
            } else {
                query.get("courseID").map(std::convert::AsRef::as_ref)
            };
            if let Some(selected) = selected {
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec![format!("selected={selected}; Path=/; Secure")],
                );
            }
        }
        Ok(response)
    }
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
        assert_eq!(
            transport
                .requests
                .lock()
                .unwrap()
                .iter()
                .filter(|r| r.url.contains("assignID="))
                .count(),
            1
        );
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
