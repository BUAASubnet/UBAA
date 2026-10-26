use super::*;
use ubaa_core::facade::{CacheKey, CacheLimits, CachePayload, CachePublication, OfflineCache};
#[derive(Clone)]
struct CacheTransport {
    mode: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
    cancel: Arc<std::sync::Mutex<Option<ubaa_core::facade::EvaluationScanCancellation>>>,
}
#[async_trait]
impl HttpTransport for CacheTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let url = url::Url::parse(&request.url).unwrap();
        let path = url.path();
        if path.ends_with("getRequiredReviewsData")
            && let Some(cancel) = self.cancel.lock().unwrap().take()
        {
            cancel.cancel();
        }
        let mode = self.mode.load(Ordering::SeqCst);
        let query: std::collections::HashMap<_, _> = url.query_pairs().collect();
        let body = match path {
            "/api/uc/status" => {
                let mut value: serde_json::Value = serde_json::from_str(include_str!(
                    "../../../../fixtures/auth/userinfo-success.json"
                ))
                .unwrap();
                if matches!(mode, 12 | 13) {
                    value["data"].as_object_mut().unwrap().remove("schoolid");
                }
                if mode == 13 {
                    value["data"].as_object_mut().unwrap().remove("username");
                }
                value.to_string()
            }
            "/pjxt/cas" => String::new(),
            "/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks" => {
                assert_eq!(
                    query.get("yhdm").unwrap(),
                    if mode == 12 {
                        "fixture-user"
                    } else {
                        "TEST-0001"
                    },
                    "恢复后必须沿本次已核实学校标识请求"
                );
                assert_eq!(query.get("pageNum").unwrap(), "1");
                assert_eq!(query.get("pageSize").unwrap(), "10");
                let list = if mode == 2 {
                    serde_json::json!([])
                } else if mode == 3 {
                    serde_json::json!([{"rwmc":"缺少身份"}])
                } else if mode == 4 {
                    serde_json::Value::Array(
                        (0..10)
                            .map(|i| serde_json::json!({"rwid":format!("rw{i}")}))
                            .collect(),
                    )
                } else {
                    serde_json::json!([{"rwid":"rw1"}])
                };
                serde_json::json!({"code":200,"result":{"list":list}}).to_string()
            }
            "/pjxt/evaluationMethodSix/getQuestionnaireListToTask" => {
                if mode == 11 {
                    r#"{"code":200,"result":[{"wjid":"wj1","msid":"1"},{"wjid":"wj1","msid":"1"}]}"#
                        .into()
                } else if matches!(mode, 9 | 10) {
                    r#"{"code":200,"result":[{"wjid":"wj1","msid":"1"},{"wjid":"wj2","msid":"1"}]}"#
                        .into()
                } else {
                    r#"{"code":200,"result":[{"wjid":"wj1","msid":"1"}]}"#.into()
                }
            }
            "/pjxt/evaluationMethodSix/getRequiredReviewsData" => {
                assert!(matches!(query.get("wjid").unwrap().as_ref(), "wj1" | "wj2"));
                if matches!(mode, 10 | 11) {
                    return Ok(HttpResponse::new(200, request.url, br#"{"code":200,"result":[{"kcdm":"kc1","kcmc":"synthetic-course","bpmc":"synthetic-teacher","ypjcs":0,"sxz":"1","pjrdm":"synthetic","pjrmc":"synthetic","rwh":"synthetic","xn":"2026","xq":"1","xnxq":"2026-20271","yxsfktjst":"0"}]}"#.to_vec()));
                }
                serde_json::json!({"code":200,"result":[{"kcdm":"kc1","kcmc":"合成评教课程","bpmc":"合成教师","ypjcs": if mode == 7 {serde_json::Value::Null} else {serde_json::json!(1)}}]}).to_string()
            }
            _ => panic!("出现非只读合成请求"),
        };
        let status = if mode == 8 && path.ends_with("getRequiredReviewsData") {
            401
        } else if (mode == 1 && path.ends_with("getRequiredReviewsData"))
            || (mode == 5 && path == "/pjxt/cas")
            || (mode == 9 && query.get("wjid").is_some_and(|value| value == "wj2"))
        {
            503
        } else {
            200
        };
        Ok(HttpResponse::new(status, request.url, body.into_bytes()))
    }
}
fn setup(root: &std::path::Path) -> (UbaaClient, OfflineCache, CacheTransport) {
    let store = FileSessionStore::new(root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = CacheTransport {
        mode: Arc::new(AtomicUsize::new(0)),
        calls: Arc::new(AtomicUsize::new(0)),
        cancel: Arc::new(std::sync::Mutex::new(None)),
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
        CacheKey::new([4; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (client, cache, transport)
}

#[test]
fn 评教持久快照剥离资格且部分失败不清空旧课程() {
    let root = test_root("evaluation-cache");
    let (mut client, cache, transport) = setup(&root);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let fresh = runtime
        .block_on(client.refresh_cached_evaluation(&cache))
        .unwrap();
    assert!(fresh.complete);
    assert_eq!(fresh.publication, Some(CachePublication::Stored));
    let old = cache
        .read_evaluation(ConnectionMode::Direct)
        .unwrap()
        .unwrap();
    let CachePayload::EvaluationCurrent(saved) = &old.payload else {
        panic!("必须为评教")
    };
    assert_eq!(saved.courses.len(), 1);
    assert_eq!(saved.progress.evaluated_courses, 1);
    let json = serde_json::to_string(saved).unwrap();
    for forbidden in [
        "submit_eligibility",
        "submit_target",
        "msid",
        "pjrdm",
        "rwid",
        "wjid",
    ] {
        assert!(!json.contains(forbidden));
    }
    assert!(
        cache
            .read_evaluation(ConnectionMode::WebVpn)
            .unwrap()
            .is_none()
    );
    for mode in [1, 3, 4, 5, 7, 9] {
        transport.mode.store(mode, Ordering::SeqCst);
        let result = runtime
            .block_on(client.refresh_cached_evaluation(&cache))
            .unwrap();
        assert!(!result.complete, "模式{mode}");
        if mode == 9 {
            assert_eq!(result.result.data.courses.len(), 1);
        }
        assert_eq!(result.publication, Some(CachePublication::Preserved));
        assert_eq!(
            cache
                .read_evaluation(ConnectionMode::Direct)
                .unwrap()
                .unwrap()
                .payload,
            old.payload
        );
    }
    transport.mode.store(2, Ordering::SeqCst);
    let empty = runtime
        .block_on(client.refresh_cached_evaluation(&cache))
        .unwrap();
    assert!(empty.complete);
    let CachePayload::EvaluationCurrent(saved) = cache
        .read_evaluation(ConnectionMode::Direct)
        .unwrap()
        .unwrap()
        .payload
    else {
        panic!("必须为评教")
    };
    assert!(saved.courses.is_empty());
    transport.mode.store(8, Ordering::SeqCst);
    assert!(
        runtime
            .block_on(client.refresh_cached_evaluation(&cache))
            .is_err()
    );
    assert_eq!(
        cache
            .read_evaluation(ConnectionMode::Direct)
            .unwrap()
            .unwrap()
            .payload,
        CachePayload::EvaluationCurrent(saved)
    );
    cache.deactivate().unwrap();
    assert!(cache.read_evaluation(ConnectionMode::Direct).is_err());
    drop(cache);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[path = "evaluation_cache/scan.rs"]
mod scan;
