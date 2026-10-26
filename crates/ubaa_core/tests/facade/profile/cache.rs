use super::*;
use ubaa_core::facade::{
    CacheError, CacheKey, CacheLimits, CachePayload, CachedMaskedProfile, OfflineCache,
    OfflineReadError, UserProfile,
};
#[derive(Clone)]
struct ProfileTransport {
    mode: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
    close: Arc<std::sync::Mutex<Option<OfflineCache>>>,
}
#[async_trait]
impl HttpTransport for ProfileTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let url = url::Url::parse(&request.url).unwrap();
        assert_eq!(request.method, ubaa_core::facade::testing::HttpMethod::Get);
        assert!(request.body.is_empty());
        assert!(url.query().is_none());
        let mode = self.mode.load(Ordering::SeqCst);
        let info = url.path() == "/api/uc/userinfo";
        assert!(info || url.path() == "/api/uc/status");
        if info && let Some(cache) = self.close.lock().unwrap().take() {
            cache.deactivate().unwrap();
        }
        let body = if (info && mode == 7) || (!info && mode == 8) {
            r#"{"code":0,"data":{}}"#
        } else if (info && mode == 2) || (!info && mode == 3) {
            r#"{"code":0,"data":{"username":"another-user"}}"#
        } else if info && mode == 4 {
            r#"{"code":0,"data":{"username":"fixture-user"}}"#
        } else {
            include_str!("../../../../../fixtures/auth/userinfo-success.json")
        };
        Ok(HttpResponse::new(
            if info && mode == 1 {
                503
            } else if info && mode == 6 {
                401
            } else {
                200
            },
            request.url,
            body.as_bytes().to_vec(),
        ))
    }
}
fn setup(root: &std::path::Path) -> (UbaaClient, OfflineCache, ProfileTransport) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = ProfileTransport {
        mode: Arc::new(AtomicUsize::new(0)),
        calls: Arc::new(AtomicUsize::new(0)),
        close: Arc::default(),
    };
    let client = UbaaClient::with_routing(
        transport.clone(),
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
        CacheKey::new([6; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (client, cache, transport)
}
#[test]
fn 资料缓存仅保存遮罩字段且失败保留成功范围() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let root = test_root("profile-cache");
        let (mut client, cache, transport) = setup(&root);
        let fresh = client.refresh_cached_profile(&cache).await.unwrap();
        assert_eq!(fresh.data.username.as_deref(), Some("fixture-user"));
        assert_eq!(fresh.data.phone.as_deref(), Some("PHONE-REDACTED"));
        assert_eq!(transport.calls.load(Ordering::SeqCst), 2);
        let old = cache.read_profile(ConnectionMode::Direct).unwrap().unwrap();
        let CachePayload::MaskedProfile(value) = &old.payload else {
            panic!("资料类型错误")
        };
        assert_eq!(value.masked_username(), Some("f***r"));
        assert_eq!(value.masked_name(), Some("F***r"));
        assert_eq!(value.masked_school_id(), Some("T***1"));
        let json = serde_json::to_string(value).unwrap();
        for forbidden in [
            "phone",
            "email",
            "idCard",
            "fixture-user",
            "Fixture User",
            "TEST-0001",
        ] {
            assert!(!json.contains(forbidden));
        }
        assert!(
            cache
                .read_profile(ConnectionMode::WebVpn)
                .unwrap()
                .is_none()
        );
        transport.mode.store(1, Ordering::SeqCst);
        assert!(client.refresh_cached_profile(&cache).await.is_err());
        let after = cache.read_profile(ConnectionMode::Direct).unwrap().unwrap();
        assert_eq!(old.payload, after.payload);
        assert_eq!(old.fetched_at, after.fetched_at);
        transport.mode.store(4, Ordering::SeqCst);
        client.refresh_cached_profile(&cache).await.unwrap();
        let CachePayload::MaskedProfile(value) = cache
            .read_profile(ConnectionMode::Direct)
            .unwrap()
            .unwrap()
            .payload
        else {
            panic!("资料类型错误")
        };
        assert_eq!(value.masked_name(), None);
        assert_eq!(value.masked_school_id(), None);
        transport.mode.store(6, Ordering::SeqCst);
        let failure = client.refresh_cached_profile(&cache).await;
        assert!(matches!(failure, Err(OfflineReadError::Read(error)) if error.error.code == ErrorCode::AuthenticationRequired));
        assert!(cache.read_profile(ConnectionMode::Direct).unwrap().is_some());
        let _ = std::fs::remove_dir_all(root);
    });
}
#[test]
fn 资料状态和响应均需身份核对且退出阻止迟到回写() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        for mode in [2, 3, 0] {
            let root = test_root(&format!("profile-fence-{mode}"));
            let (mut client, cache, transport) = setup(&root);
            transport.mode.store(mode, Ordering::SeqCst);
            if mode == 0 {
                *transport.close.lock().unwrap() = Some(cache.clone());
            }
            let result = client.refresh_cached_profile(&cache).await;
            if mode == 0 {
                assert!(matches!(
                    result,
                    Err(OfflineReadError::Cache(CacheError::Inactive))
                ));
            } else {
                assert!(matches!(
                    result,
                    Err(OfflineReadError::IdentityMismatch { .. })
                ));
            }
            assert!(matches!(
                cache.read_profile(ConnectionMode::Direct),
                Err(CacheError::Inactive)
            ));
            assert_eq!(
                transport.calls.load(Ordering::SeqCst),
                if mode == 3 { 1 } else { 2 }
            );
            let _ = std::fs::remove_dir_all(root);
        }
    });
}
#[test]
fn 资料遮罩按字符处理短值并拒绝额外持久字段() {
    let value = CachedMaskedProfile::from_profile(&UserProfile {
        username: Some(" 小明 ".into()),
        name: Some("张三丰".into()),
        school_id: Some("  ".into()),
        ..Default::default()
    });
    assert_eq!(value.masked_username(), Some("***"));
    assert_eq!(value.masked_name(), Some("张***丰"));
    assert_eq!(value.masked_school_id(), None);
    assert!(serde_json::from_str::<CachedMaskedProfile>(r#"{"maskedUsername":"f***r","maskedName":null,"maskedSchoolId":null,"phone":"不应接受"}"#).is_err());
}

#[test]
fn 资料持久入口拒绝未遮罩载荷且重开保留原范围() {
    use ubaa_core::facade::{CacheCompleteness, CacheQuery, CacheScope, OfflineRepository};
    let root = test_root("profile-payload");
    std::fs::create_dir_all(&root).unwrap();
    let account = "0123456789abcdef0123456789abcdef";
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::MaskedProfile,
    };
    let mut repo = OfflineRepository::open(
        &root,
        account,
        CacheKey::new([6; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let ticket = repo.begin_read(scope.clone()).unwrap();
    let malformed = serde_json::from_str::<CachedMaskedProfile>(
        r#"{"maskedUsername":"完整账号","maskedName":null,"maskedSchoolId":null}"#,
    )
    .unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            CachePayload::MaskedProfile(malformed),
            100,
            CacheCompleteness::Complete
        ),
        Err(CacheError::InvalidInput)
    );
    let good = CachedMaskedProfile::from_profile(&UserProfile {
        username: Some("fixture-user".into()),
        ..Default::default()
    });
    repo.publish(
        &ticket,
        CachePayload::MaskedProfile(good.clone()),
        101,
        CacheCompleteness::Complete,
    )
    .unwrap();
    let _new = repo.begin_read(scope.clone()).unwrap();
    assert_eq!(
        repo.publish(
            &ticket,
            CachePayload::MaskedProfile(good.clone()),
            102,
            CacheCompleteness::Complete
        ),
        Err(CacheError::Superseded)
    );
    drop(repo);
    let cache = OfflineCache::open(
        &root,
        account,
        "fixture-user",
        CacheKey::new([6; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let record = cache.read_profile(ConnectionMode::Direct).unwrap().unwrap();
    assert_eq!(record.fetched_at, 101);
    assert_eq!(record.payload, CachePayload::MaskedProfile(good));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 资料缺少身份不能冒认另一账号或清除既有缓存() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        for mode in [7,8] {
            let root = test_root(&format!("profile-missing-{mode}"));
            let (mut client, cache, transport) = setup(&root);
            client.refresh_cached_profile(&cache).await.unwrap();
            let old = cache.read_profile(ConnectionMode::Direct).unwrap().unwrap();
            transport.mode.store(mode, Ordering::SeqCst);
            let result = client.refresh_cached_profile(&cache).await;
            assert!(matches!(result, Err(OfflineReadError::Read(error)) if error.error.code == ErrorCode::UpstreamChanged));
            let kept = cache.read_profile(ConnectionMode::Direct).unwrap().unwrap();
            assert_eq!(kept.payload, old.payload); assert_eq!(kept.fetched_at, old.fetched_at);
            assert_eq!(transport.calls.load(Ordering::SeqCst), if mode == 8 {3} else {4});
            let _ = std::fs::remove_dir_all(root);
        }
    });
}
