use super::*;
use ubaa_core::facade::{
    CacheCompleteness, CacheKey, CacheLimits, CachePayload, CacheQuery, HomeQuery, HomeReadData,
    OfflineCache,
};

#[derive(Clone)]
struct HomeTransport {
    mode: Arc<AtomicUsize>,
    requests: Arc<std::sync::Mutex<Vec<HttpRequest>>>,
}
#[async_trait]
impl HttpTransport for HomeTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let mode = self.mode.load(Ordering::SeqCst);
        let failed = (mode & 1 != 0 && path.ends_with("queryKclb"))
            || (mode & 2 != 0 && path.ends_with("queryXsSubmitKczyInfo"))
            || (mode & 4 != 0 && path.ends_with("getCount"))
            || (mode & 8 != 0 && path.ends_with("Term/get"))
            || (mode & 16 != 0 && path.ends_with("queryListByPage"));
        if mode & 32 != 0 && path.ends_with("queryListByPage") {
            return Ok(HttpResponse::new(200, request.url, br#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":2,"hasNextPage":true,"list":[]}}"#.to_vec()));
        }
        if mode & 64 != 0 && path.ends_with("getCount") {
            return Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":1,"result":{}}"#.to_vec(),
            ));
        }
        if failed {
            return Ok(HttpResponse::new(503, request.url, b"synthetic".to_vec()));
        }
        if path.ends_with("/spocnewht/cas") {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response.headers.insert(
                "Location".into(),
                vec!["https://spoc.buaa.edu.cn/spocnew/cas?token=synthetic".into()],
            );
            return Ok(response);
        }
        let body = match path.as_str() {
            "/api/uc/status" => include_str!("../../../../fixtures/auth/userinfo-success.json"),
            "/" => {
                return Ok(HttpResponse::new(
                    200,
                    "https://iclass.buaa.edu.cn:8346/?loginName=synthetic",
                    Vec::new(),
                ));
            }
            "/app/user/login.action" => {
                r#"{"STATUS":"0","result":{"id":"synthetic-user","sessionId":"synthetic-session"}}"#
            }
            "/app/course/get_stu_course_sched.action" => {
                r#"{"STATUS":"0","result":[{"id":"synthetic-course","courseName":"合成课堂","classBeginTime":"08:00","classEndTime":"09:40","signStatus":0}]}"#
            }
            "/spocnewht/sys/casLogin" => r#"{"code":200,"content":{"jsdm":"01"}}"#,
            "/spocnewht/inco/ht/queryOne" => {
                r#"{"code":200,"content":{"mrxq":"2025-20262","dqxq":"合成学期"}}"#
            }
            "/spocnewht/jxkj/queryKclb" => {
                r#"{"code":200,"content":[{"kcid":"course-1","kcmc":"合成课程","skjs":"合成教师"}]}"#
            }
            "/spocnewht/inco/ht/queryListByPage" => {
                r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","zymc":"合成作业","sskcid":"course-1","tjzt":"未做"}]}}"#
            }
            "/spocnewht/kczy/queryKczyInfoByid" => {
                include_str!("../../../../fixtures/readonly/spoc-detail.json")
            }
            "/spocnewht/kczy/queryXsSubmitKczyInfo" => {
                r#"{"code":200,"content":{"tjzt":"已提交","tjsj":"2026-09-01 08:00:00"}}"#
            }
            "/uc/api/oauth/index" => {
                return Ok(HttpResponse::new(
                    200,
                    "https://ygdk.buaa.edu.cn/#/home?code=synthetic",
                    Vec::new(),
                ));
            }
            "/api/Front/Clockin/User/campusAppLogin" => {
                r#"{"code":1,"result":{"uid":1,"token":"synthetic"}}"#
            }
            "/api/Front/Clockin/Classify/getList" => {
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"体育"}]}}"#
            }
            "/api/Front/Clockin/Item/getList" => {
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#
            }
            "/api/Front/Clockin/Clockin/getCount" => r#"{"code":1,"result":{"term_count":3}}"#,
            "/api/Front/Clockin/Term/get" => {
                r#"{"code":1,"result":{"term_id":7,"name":"合成学期"}}"#
            }
            _ => panic!("出现未授权的合成请求"),
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
    }
}
fn setup(root: &std::path::Path, transport: HomeTransport) -> (UbaaClient, OfflineCache) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let client = UbaaClient::with_routing(
        transport,
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
    (client, cache)
}
#[test]
fn 首页缓存保留实时资格但持久内容不可恢复资格且日期等于请求日期() {
    let root = test_root("home-cache-complete");
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let (mut client, cache) = setup(
        &root,
        HomeTransport {
            mode: Arc::new(AtomicUsize::new(0)),
            requests: requests.clone(),
        },
    );
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.refresh_cached_home(&cache, HomeQuery::SigninToday))
        .unwrap();
    let HomeReadData::Signin(classes) = &result.result.data else {
        panic!("必须为签到数据");
    };
    assert!(classes[0].signin_target.is_some());
    let stored = cache
        .read(&result.result.scope, result.result.fetched_at)
        .unwrap()
        .unwrap();
    assert!(matches!(stored.payload, CachePayload::SigninToday(_)));
    let CacheQuery::SigninToday { date } = &stored.scope.query else {
        panic!("必须有日期");
    };
    let sent = requests.lock().unwrap();
    let request = sent
        .iter()
        .find(|r| r.url.contains("get_stu_course_sched"))
        .unwrap();
    assert_eq!(
        url::Url::parse(&request.url)
            .unwrap()
            .query_pairs()
            .find(|(k, _)| k == "dateStr")
            .unwrap()
            .1,
        date.as_str()
    );
    drop(sent);
    drop(cache);
    drop(client);
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn 首页可选步骤失败不能覆盖原完整缓存() {
    let root = test_root("home-cache-partial");
    let mode = Arc::new(AtomicUsize::new(0));
    let (mut client, cache) = setup(
        &root,
        HomeTransport {
            mode: mode.clone(),
            requests: Arc::new(std::sync::Mutex::new(Vec::new())),
        },
    );
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for (query, failure) in [
        (HomeQuery::SpocAssignments, 1),
        (HomeQuery::SpocAssignments, 32),
        (
            HomeQuery::SpocDetail {
                assignment_id: "a1".into(),
            },
            2,
        ),
        (HomeQuery::YgdkOverview, 4),
        (HomeQuery::YgdkOverview, 8),
        (HomeQuery::YgdkOverview, 64),
    ] {
        mode.store(0, Ordering::SeqCst);
        let full = runtime
            .block_on(client.refresh_cached_home(&cache, query.clone()))
            .unwrap();
        assert!(full.complete);
        let old = cache
            .read(&full.result.scope, full.result.fetched_at)
            .unwrap()
            .unwrap();
        mode.store(failure, Ordering::SeqCst);
        let partial = runtime
            .block_on(client.refresh_cached_home(&cache, query))
            .unwrap();
        assert!(!partial.complete);
        assert_eq!(
            partial.publication,
            Some(if failure == 8 {
                // 学期读取失败只保存未知学期部分，不能覆盖或标记旧已知学期。
                ubaa_core::facade::CachePublication::Stored
            } else {
                ubaa_core::facade::CachePublication::Preserved
            })
        );
        let preserved = cache
            .read(&full.result.scope, full.result.fetched_at)
            .unwrap()
            .unwrap();
        assert_eq!(preserved.payload, old.payload);
        assert_eq!(preserved.fetched_at, old.fetched_at);
        assert_eq!(preserved.completeness, CacheCompleteness::Complete);
        assert_eq!(preserved.last_attempt_succeeded, failure == 8);
        if failure == 8 {
            assert_ne!(partial.result.scope, full.result.scope);
            let home = cache
                .read_home(ConnectionMode::Direct, &HomeQuery::YgdkOverview)
                .unwrap()
                .unwrap();
            assert_eq!(home.scope, full.result.scope);
            assert_eq!(home.payload, old.payload);
        }
    }
    mode.store(16, Ordering::SeqCst);
    assert!(
        runtime
            .block_on(client.refresh_cached_home(&cache, HomeQuery::SpocAssignments))
            .is_err()
    );
    cache.clear().unwrap();
    mode.store(4, Ordering::SeqCst);
    let partial = runtime
        .block_on(client.refresh_cached_home(&cache, HomeQuery::YgdkOverview))
        .unwrap();
    assert!(!partial.complete);
    assert_eq!(
        partial.publication,
        Some(ubaa_core::facade::CachePublication::Stored)
    );
    let saved = cache
        .read(&partial.result.scope, partial.result.fetched_at)
        .unwrap()
        .unwrap();
    assert_eq!(saved.completeness, CacheCompleteness::Partial);
    assert!(
        cache
            .read_home(ConnectionMode::WebVpn, &HomeQuery::YgdkOverview)
            .unwrap()
            .is_none()
    );
    drop(cache);
    drop(client);
    let _ = std::fs::remove_dir_all(root);
}
