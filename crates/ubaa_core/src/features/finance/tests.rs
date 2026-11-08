use super::parser;
use serde_json::json;
#[test]
fn finance_金额零值小数与缺失分别保留() {
    assert_eq!(parser::cents(&json!(0)).unwrap(), Some(0));
    assert_eq!(parser::cents(&json!(12.34)).unwrap(), Some(1234));
    assert_eq!(parser::cents(&json!(-0.05)).unwrap(), Some(-5));
    assert_eq!(parser::cents(&json!(null)).unwrap(), None);
    assert!(parser::cents(&json!(0.001)).is_err());
}
#[test]
fn finance_分页结构与空结果可区分() {
    assert_eq!(parser::page(&json!({"mx":[],"total":0})).unwrap().1, 0);
    assert!(parser::page(&json!({})).is_err());
    assert!(parser::page(&json!({"mx":[],"total":"0"})).is_err());
    assert!(parser::page(&json!({"mx":null,"total":0})).is_err());
    assert_eq!(parser::page(&json!({"data":[],"count":0})).unwrap().1, 0);
}

use crate::domain::ConnectionMode;
use crate::error::Result;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
use std::sync::{Arc, Mutex};
#[derive(Default)]
struct Scenario {
    requests: Vec<HttpRequest>,
    empty_second: bool,
    duplicate: bool,
    unauthorized: usize,
    logins: usize,
}
struct Transport(Arc<Mutex<Scenario>>);
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, r: HttpRequest) -> Result<HttpResponse> {
        let direct = crate::connection::from_webvpn_url(&r.url)?;
        let u = url::Url::parse(&direct).unwrap();
        let mut s = self.0.lock().unwrap();
        s.requests.push(r.clone());
        let mut response = HttpResponse {
            status: 200,
            headers: std::collections::BTreeMap::default(),
            body: vec![],
            final_url: r.url.clone(),
        };
        let location = match u.path() {
            "/login" => {
                assert_eq!(
                    u.query_pairs().find(|(k, _)| k == "service").unwrap().1,
                    "http://icw.buaa.edu.cn/checkbuaa.aspx"
                );
                Some("http://icw.buaa.edu.cn/checkbuaa.aspx?ticket=synthetic")
            }
            "/checkbuaa.aspx" => Some("/Newindex.aspx"),
            "/Newindex.aspx" => None,
            "/jump.aspx" => Some(
                "https://chaxun.icw.buaa.edu.cn/gxzhcxzhb/login?Userid=SYNTHETIC&Cypt=fixture&Stamp=1",
            ),
            "/api-zhcx/login" => {
                s.logins += 1;
                assert_eq!(
                    String::from_utf8(r.body.clone()).unwrap(),
                    "username=SYNTHETIC&password=fixture&yzm=yzm&stamp=1"
                );
                response.body = json!({"code":200,"data":{"token":"fixture-token"}})
                    .to_string()
                    .into_bytes();
                None
            }
            "/api-zhcx/getStudentSRCX" => {
                assert_eq!(
                    r.headers.get("Authorization").unwrap(),
                    "Bearer fixture-token"
                );
                let query: serde_json::Value = serde_json::from_slice(&r.body).unwrap();
                assert_eq!(query["userId"], "SYNTHETIC");
                assert_eq!(query["limit"], 100);
                if s.unauthorized > 0 {
                    s.unauthorized -= 1;
                    response.status = 401;
                    return Ok(response);
                }
                let page = query["currentPage"].as_u64().unwrap();
                let rows = if page == 2 && s.empty_second {
                    json!([])
                } else {
                    json!([{"lsh":if s.duplicate {"1".into()}else{page.to_string()},"je":100,"sfje":0,"yhzh":"不得投影"}])
                };
                response.body = json!({"code":200,"data":{"mx":rows,"total":2}})
                    .to_string()
                    .into_bytes();
                None
            }
            _ => panic!("未知请求路径"),
        };
        if let Some(l) = location {
            response.status = 302;
            response.headers.insert(
                "Location".into(),
                vec![
                    if r.url.starts_with("https://d.buaa.edu.cn/") && l == "/Newindex.aspx" {
                        crate::connection::to_webvpn_url("https://icw.buaa.edu.cn/Newindex.aspx")
                            .unwrap()
                            .trim_start_matches("https://d.buaa.edu.cn")
                            .to_owned()
                    } else {
                        l.into()
                    },
                ],
            );
        }
        Ok(response)
    }
}
fn fixture(
    mode: ConnectionMode,
    scenario: Scenario,
) -> (ClientRuntime, Arc<Mutex<Scenario>>, std::path::PathBuf) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/finance_integration/tests")
        .join(uuid::Uuid::new_v4().to_string());
    let store = FileSessionStore::new(&root).unwrap();
    let version = store.load_versioned().unwrap();
    store
        .compare_exchange(
            version.revision,
            Some(&SessionSnapshot {
                mode,
                cookies: vec![],
                authenticated_at: 1000,
                last_activity: 1001,
            }),
        )
        .unwrap();
    let state = Arc::new(Mutex::new(scenario));
    (
        ClientRuntime::new(mode, Transport(state.clone()), store).unwrap(),
        state,
        root,
    )
}
#[tokio::test]
async fn finance_双路线分页与失效重建保持请求合同() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let (mut runtime, state, _root) = fixture(
            mode,
            Scenario {
                unauthorized: 1,
                ..Default::default()
            },
        );
        let result = super::incomes(&mut runtime).await.unwrap();
        assert_eq!(result.total, 2);
        assert_eq!(result.entries[0].paid_cents, Some(0));
        assert!(!serde_json::to_string(&result).unwrap().contains("不得投影"));
        let s = state.lock().unwrap();
        assert_eq!(s.logins, 2);
        if mode == ConnectionMode::WebVpn {
            assert!(
                s.requests
                    .iter()
                    .all(|r| r.url.starts_with("https://d.buaa.edu.cn/"))
            );
        }
        assert!(s.requests.iter().all(|r| r.url.starts_with("https://")));
    }
}
#[tokio::test]
async fn finance_缺页重复及连续认证失败均不返回完整结果() {
    for scenario in [
        Scenario {
            empty_second: true,
            ..Default::default()
        },
        Scenario {
            duplicate: true,
            ..Default::default()
        },
        Scenario {
            unauthorized: 2,
            ..Default::default()
        },
    ] {
        let (mut runtime, _, _root) = fixture(ConnectionMode::Direct, scenario);
        assert!(super::incomes(&mut runtime).await.is_err());
    }
}
#[test]
fn finance_登录跳转拒绝外站且失效后不可回写() {
    assert!(
        super::auth::target("https://example.org/checkbuaa.aspx", ConnectionMode::Direct).is_err()
    );
    let state = crate::internal::route_state::CredentialState::default();
    let generation = state.generation();
    state.clear();
    assert!(!state.store_credential(
        generation,
        crate::internal::route_state::FinanceCredential {
            user: "synthetic".into(),
            token: crate::domain::SecretValue::new("secret")
        }
    ));
}

#[test]
fn finance_加密快照跨路线复用且失败保留旧值() {
    use crate::cache::{
        CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
        OfflineRepository,
    };
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/finance_integration/tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let mut repo = OfflineRepository::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        CacheKey::new([3; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::FinanceIncomes,
    };
    let ticket = repo.begin_read(scope.clone()).unwrap();
    let data = crate::domain::FinanceIncomes {
        entries: vec![
            parser::income(&json!({"lsh":"synthetic-finance-id","je":12.34,"sfje":0})).unwrap(),
        ],
        total: 1,
    };
    let payload = CachePayload::FinanceIncomes(data);
    repo.publish(&ticket, payload.clone(), 100, CacheCompleteness::Complete)
        .unwrap();
    let cross = CacheScope {
        route: ConnectionMode::WebVpn,
        ..scope.clone()
    };
    assert_eq!(repo.read(&cross, 101).unwrap().unwrap().payload, payload);
    let stale = repo.begin_read(scope.clone()).unwrap();
    let latest = repo.begin_read(scope).unwrap();
    assert!(matches!(
        repo.publish(&stale, payload.clone(), 102, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    ));
    repo.record_failure(&latest, 103).unwrap();
    assert_eq!(repo.read(&cross, 104).unwrap().unwrap().payload, payload);
    for entry in std::fs::read_dir(&root).unwrap() {
        let path = entry.unwrap().path();
        if path.is_file() {
            assert!(
                !String::from_utf8_lossy(&std::fs::read(path).unwrap())
                    .contains("synthetic-finance-id")
            );
        }
    }
}
