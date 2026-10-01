use super::*;
use ubaa_core::facade::{
    BykcCacheQuery, BykcReadData, CacheKey, CacheLimits, CachePayload, OfflineCache,
};

#[derive(Clone)]
struct BykcCacheTransport {
    fail: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
}
#[async_trait]
impl HttpTransport for BykcCacheTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        if path == "/api/uc/status" {
            return Ok(HttpResponse::new(
                200,
                request.url,
                include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
            ));
        }
        if path == "/sscv/cas/login" {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response.headers.insert(
                "Location".into(),
                vec!["https://bykc.buaa.edu.cn/cas-login?token=synthetic".into()],
            );
            return Ok(response);
        }
        // 不解密、不记录请求正文；测试只允许这五项原只读操作及配置读取。
        let data = match path.as_str() {
            "/sscv/getUserProfile" => r#"{"id":1,"realName":"合成姓名"}"#,
            "/sscv/queryStudentSemesterCourseByPage" => {
                r#"{"content":[{"id":42,"courseName":"合成课程","courseNewKind1":{"kindName":"博雅课程"},"courseNewKind2":{"kindName":"美育"},"courseCampusList":["沙河校区"],"courseContact":"合成联系人"}],"size":20,"number":0,"totalElements":21,"totalPages":2}"#
            }
            "/sscv/queryCourseById" => {
                r#"{"id":42,"courseName":"合成课程","courseNewKind1":{"kindName":"博雅课程"},"courseNewKind2":{"kindName":"美育"},"courseCampusList":["沙河校区"],"courseContact":"合成联系人"}"#
            }
            "/sscv/getAllConfig" => {
                r#"{"semester":[{"semesterStartDate":"2026-09-01 00:00:00","semesterEndDate":"2027-01-31 23:59:59"}]}"#
            }
            "/sscv/queryChosenCourse" => {
                r#"{"courseList":[{"id":1,"courseInfo":{"id":42,"courseName":"合成已选"},"signInfo":"合成位置结果"}]}"#
            }
            "/sscv/queryStatisticByUserId" => r#"{"validCount":3,"statistical":{}}"#,
            _ => panic!("出现未授权请求"),
        };
        let state = self.fail.load(Ordering::SeqCst);
        let data = if state == 2 && path == "/sscv/queryChosenCourse" {
            r#"{"courseList":[]}"#
        } else if state == 3 && path == "/sscv/queryCourseById" {
            r#"{"id":99,"courseName":"其他合成课程"}"#
        } else {
            data
        };
        let body = if state == 1 {
            r#"{"status":"1","errmsg":"合成失败"}"#.into()
        } else {
            format!(r#"{{"status":"0","data":{data}}}"#)
        };
        Ok(HttpResponse::new(200, request.url, body.into_bytes()))
    }
}
#[test]
fn 博雅五类在线结果与只读持久结果分离并保护旧数据() {
    let root = test_root("bykc-cache");
    let (mut client, cache, transport) = setup(&root);
    let fail = transport.fail;
    let calls = transport.calls;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for query in [
        BykcCacheQuery::Profile,
        BykcCacheQuery::Courses {
            page: 1,
            size: 20,
            all: false,
        },
        BykcCacheQuery::Detail { course_id: 42 },
        BykcCacheQuery::Chosen,
        BykcCacheQuery::Statistics,
    ] {
        let online = runtime
            .block_on(client.refresh_cached_bykc(&cache, query.clone()))
            .unwrap();
        assert!(online.save_error.is_none());
        let previous = cache
            .read_bykc(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        assert!(
            !serde_json::to_string(&previous.payload)
                .unwrap()
                .contains("eligibility")
        );
        if let BykcReadData::Chosen {
            semester_start,
            semester_end,
            courses,
        } = online.data
        {
            assert_eq!(semester_start, "2026-09-01 00:00:00");
            assert_eq!(semester_end, "2027-01-31 23:59:59");
            assert!(courses[0].sign_info.is_some());
            let CachePayload::BykcChosen(saved) = &previous.payload else {
                panic!("必须为已选课程")
            };
            assert_eq!(saved.semester_start, semester_start);
            assert!(!serde_json::to_string(saved).unwrap().contains("位置结果"));
        }
        assert!(
            cache
                .read_bykc(ConnectionMode::WebVpn, &query)
                .unwrap()
                .is_none()
        );
        fail.store(1, Ordering::SeqCst);
        assert!(
            runtime
                .block_on(client.refresh_cached_bykc(&cache, query.clone()))
                .is_err()
        );
        let retained = cache
            .read_bykc(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        assert_eq!(retained.payload, previous.payload);
        assert!(!retained.last_attempt_succeeded);
        fail.store(0, Ordering::SeqCst);
    }
    check_replacement(&mut client, &cache, &runtime, &fail);
    let before = calls.load(Ordering::SeqCst);
    assert!(
        runtime
            .block_on(client.refresh_cached_bykc(
                &cache,
                BykcCacheQuery::Courses {
                    page: 0,
                    size: 20,
                    all: false
                }
            ))
            .is_err()
    );
    assert_eq!(calls.load(Ordering::SeqCst), before);
    cache.deactivate().unwrap();
    assert!(
        cache
            .read_bykc(ConnectionMode::Direct, &BykcCacheQuery::Profile)
            .is_err()
    );
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

fn setup(root: &std::path::Path) -> (UbaaClient, OfflineCache, BykcCacheTransport) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let fail = Arc::new(AtomicUsize::new(0));
    let calls = Arc::new(AtomicUsize::new(0));
    let client = UbaaClient::with_routing(
        BykcCacheTransport {
            fail: fail.clone(),
            calls: calls.clone(),
        },
        CountingTransport(Arc::new(AtomicUsize::new(0))),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    let cache = OfflineCache::open(
        root,
        "0123456789abcdef0123456789abcdef",
        "fixture-user",
        CacheKey::new([4; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (client, cache, BykcCacheTransport { fail, calls })
}

fn check_replacement(
    client: &mut UbaaClient,
    cache: &OfflineCache,
    runtime: &tokio::runtime::Runtime,
    fail: &AtomicUsize,
) {
    fail.store(2, Ordering::SeqCst);
    runtime
        .block_on(client.refresh_cached_bykc(cache, BykcCacheQuery::Chosen))
        .unwrap();
    let CachePayload::BykcChosen(empty) = cache
        .read_bykc(ConnectionMode::Direct, &BykcCacheQuery::Chosen)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为已选")
    };
    assert!(empty.courses.is_empty());
    fail.store(3, Ordering::SeqCst);
    let mismatched = runtime
        .block_on(client.refresh_cached_bykc(cache, BykcCacheQuery::Detail { course_id: 42 }))
        .unwrap();
    assert_eq!(
        mismatched.save_error,
        Some(ubaa_core::facade::CacheError::InvalidInput)
    );
    let CachePayload::BykcDetail(old) = cache
        .read_bykc(
            ConnectionMode::Direct,
            &BykcCacheQuery::Detail { course_id: 42 },
        )
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为详情")
    };
    assert_eq!(old.id, 42);
}

#[test]
fn 完整博雅读取与缓存筛选一致且不落盘联系人或资格() {
    let root = test_root("bykc-catalog-cache");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for query in [
        BykcCacheQuery::Catalog {
            page: 1,
            size: 20,
            all: true,
        },
        BykcCacheQuery::FullDetail { course_id: 42 },
    ] {
        let fresh = runtime
            .block_on(client.refresh_cached_bykc(&cache, query.clone()))
            .unwrap();
        assert!(fresh.save_error.is_none());
        let calls = transport.calls.load(Ordering::SeqCst);
        let saved = cache
            .read_bykc(ConnectionMode::Direct, &query)
            .unwrap()
            .unwrap();
        assert_eq!(calls, transport.calls.load(Ordering::SeqCst));
        let serialized = serde_json::to_string(&saved.payload).unwrap();
        assert!(!serialized.contains("合成联系人"));
        assert!(!serialized.contains("eligibility"));
        let course = match saved.payload {
            CachePayload::BykcCourses(page) => page.content.into_iter().next().unwrap(),
            CachePayload::BykcDetail(course) => course,
            _ => panic!("必须保存同范围博雅只读投影"),
        };
        assert_eq!(
            course.category,
            Some(ubaa_core::facade::BykcCourseCategory::Boya)
        );
        assert_eq!(
            course.sub_category,
            Some(ubaa_core::facade::BykcCourseSubCategory::Aesthetic)
        );
        assert_eq!(course.audience_campuses, Some(vec!["沙河校区".into()]));
    }
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}
