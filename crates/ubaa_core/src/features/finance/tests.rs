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
#[test]
fn finance_部门和项目字段保留并排除银行证件() {
    let entry = parser::income(&json!({
        "lsh":"synthetic-income",
        "bmmc":" 示例学院 ",
        "bmbh":"SYNTH-DEPT-CODE",
        "xmbh":"\tSYNTH-PROJECT-01 ",
        "xmmc":" 合成项目名称\n",
        "ffxmmc":"合成发放项目",
        "bmhb":"SYNTH-DEPT-CODE/示例学院",
        "xmhb":"SYNTH-PROJECT-01/合成项目名称",
        "sfzh":"synthetic-id-card",
        "yhzh":"synthetic-masked-account",
        "yhzh_":"synthetic-account"
    }))
    .unwrap();
    assert_eq!(entry.department.as_deref(), Some("示例学院"));
    assert_eq!(entry.project_code.as_deref(), Some("SYNTH-PROJECT-01"));
    assert_eq!(entry.project_name.as_deref(), Some("合成项目名称"));
    let exported = serde_json::to_string(&entry).unwrap();
    for private in [
        "synthetic-id-card",
        "synthetic-masked-account",
        "synthetic-account",
    ] {
        assert!(!exported.contains(private));
    }
}
#[test]
fn finance_部门和项目字段可缺失() {
    for display in [
        Some(json!(123)),
        Some(json!({"example": "合成对象"})),
        Some(json!("")),
        Some(json!(" \t\n")),
        Some(json!(null)),
        None,
    ] {
        let mut row = json!({"lsh":"synthetic-income","je":12.34});
        if let Some(display) = display {
            for key in ["bmmc", "xmbh", "xmmc"] {
                row[key] = display.clone();
            }
        }
        let entry = parser::income(&row).unwrap();
        assert_eq!(entry.department, None);
        assert_eq!(entry.project_code, None);
        assert_eq!(entry.project_name, None);
        assert_eq!(entry.amount_cents, Some(1234));
    }
}
#[test]
fn finance_旧缓存缺部门和项目字段仍可读取() {
    let old: crate::domain::FinanceIncome = serde_json::from_value(json!({
        "id":"synthetic-income",
        "project":"旧发放项目",
        "description":"旧摘要",
        "amountCents":100,
        "taxCents":0,
        "paidCents":100,
        "taxRate":null,
        "recordedDate":"2026-01-01",
        "year":"2026",
        "month":"01"
    }))
    .unwrap();
    assert_eq!(old.project.as_deref(), Some("旧发放项目"));
    assert_eq!(old.department, None);
    assert_eq!(old.project_code, None);
    assert_eq!(old.project_name, None);
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
    redirect: Option<(&'static str, &'static str)>,
    response: Option<(&'static str, u16, &'static str)>,
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
        if let Some((path, status, body)) = s.response
            && u.path() == path
        {
            response.status = status;
            response.body = body.as_bytes().to_vec();
            return Ok(response);
        }
        if let Some((path, location)) = s.redirect
            && u.path() == path
        {
            response.status = 302;
            response
                .headers
                .insert("Location".into(), vec![location.into()]);
            return Ok(response);
        }
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
) -> (
    ClientRuntime,
    Arc<Mutex<Scenario>>,
    crate::test_tmp::TestTempDir,
) {
    let root = crate::test_tmp::test_temp_dir("ubaa_core_features_finance").unwrap();
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
async fn finance_webvpn_网关要求登录时返回认证失效且不跟随跳转() {
    for path in ["/jump.aspx", "/api-zhcx/login", "/api-zhcx/getStudentSRCX"] {
        let (mut runtime, state, _root) = fixture(
            ConnectionMode::WebVpn,
            Scenario {
                redirect: Some((path, "https://d.buaa.edu.cn/login")),
                ..Default::default()
            },
        );
        let error = super::incomes(&mut runtime).await.unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
        assert!(
            state
                .lock()
                .unwrap()
                .requests
                .iter()
                .all(|request| { url::Url::parse(&request.url).unwrap().path() != "/login" })
        );
    }
}

#[tokio::test]
async fn finance_非网关登录跳转和直连跳转仍是协议错误() {
    for (mode, location) in [
        (ConnectionMode::WebVpn, "https://other.example/login"),
        (ConnectionMode::WebVpn, "https://d.buaa.edu.cn:8443/login"),
        (ConnectionMode::Direct, "https://d.buaa.edu.cn/login"),
    ] {
        let (mut runtime, _, _root) = fixture(
            mode,
            Scenario {
                redirect: Some(("/api-zhcx/getStudentSRCX", location)),
                ..Default::default()
            },
        );
        let error = super::incomes(&mut runtime).await.unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
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

#[tokio::test]
async fn finance_诊断区分门户票据登录和收入响应失败() {
    for (path, status, body, step, reason) in [
        (
            "/jump.aspx",
            200,
            "private-ticket",
            "query_jump",
            "jump_status_invalid",
        ),
        (
            "/api-zhcx/login",
            503,
            "private-login",
            "query_login",
            "login_http_status_invalid",
        ),
        (
            "/api-zhcx/login",
            200,
            r#"{"code":200,"data":{"token":null,"name":"private-login"}}"#,
            "query_login",
            "token_null",
        ),
        (
            "/api-zhcx/getStudentSRCX",
            503,
            "private-http",
            "income_page",
            "http_status_invalid",
        ),
        (
            "/api-zhcx/getStudentSRCX",
            200,
            "<html>统一身份认证 private-login</html>",
            "income_page",
            "json_invalid",
        ),
        (
            "/api-zhcx/getStudentSRCX",
            200,
            r#"{"code":500,"data":"private-business"}"#,
            "income_page",
            "business_rejected",
        ),
        (
            "/api-zhcx/getStudentSRCX",
            200,
            r#"{"code":200,"data":[]}"#,
            "income_page",
            "data_type_invalid",
        ),
    ] {
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let (mut runtime, _, _root) = fixture(
                mode,
                Scenario {
                    response: Some((path, status, body)),
                    ..Default::default()
                },
            );
            let error = super::incomes(&mut runtime).await.unwrap_err();
            let diagnostic = error.diagnostic();
            assert_eq!(diagnostic.reason.as_deref(), Some(reason));
            assert_eq!(diagnostic.status, Some(status));
            assert!(
                diagnostic
                    .stage
                    .as_deref()
                    .is_some_and(|stage| stage.starts_with(step))
            );
            assert_eq!(diagnostic.response_bytes, Some(body.len() as u64));
            let exported = diagnostic.to_json().unwrap();
            assert!(!exported.contains("private-"));
            assert!(!exported.contains("fixture-token"));
            assert!(!exported.contains("SYNTHETIC"));
        }
    }
}

#[test]
fn finance_诊断区分字段和金额的具体条件() {
    for (value, reason) in [
        (
            json!({"lsh":"private-id","je":"private-money"}),
            "je_type_invalid",
        ),
        (json!({"lsh":"private-id","se":0.001}), "se_format_invalid"),
        (
            json!({"lsh":"private-id","sfje":"private-money"}),
            "sfje_type_invalid",
        ),
        (
            json!({"lsh":"private-id","ffxmmc":false}),
            "ffxmmc_type_invalid",
        ),
        (json!({"je":1}), "lsh_missing"),
        (json!({"lsh":null,"je":1}), "lsh_null"),
        (json!({"lsh":"","je":1}), "lsh_empty"),
    ] {
        let error = parser::income(&value).unwrap_err();
        let diagnostic = error.diagnostic();
        assert_eq!(diagnostic.stage.as_deref(), Some("income_fields"));
        assert_eq!(diagnostic.reason.as_deref(), Some(reason));
        let exported = diagnostic.to_json().unwrap();
        assert!(!exported.contains("private-"));
        assert!(
            diagnostic
                .source
                .starts_with("crates/ubaa_core/src/features/finance/parser.rs:")
        );
    }
}

#[tokio::test]
async fn finance_诊断区分分页缺页与重复记录() {
    for (scenario, reason) in [
        (
            Scenario {
                empty_second: true,
                ..Default::default()
            },
            "page_incomplete",
        ),
        (
            Scenario {
                duplicate: true,
                ..Default::default()
            },
            "record_duplicate",
        ),
    ] {
        let (mut runtime, _, _root) = fixture(ConnectionMode::Direct, scenario);
        let error = super::incomes(&mut runtime).await.unwrap_err();
        assert_eq!(
            error.diagnostic().stage.as_deref(),
            Some("income_pagination")
        );
        assert_eq!(error.diagnostic().reason.as_deref(), Some(reason));
        assert!(
            error
                .diagnostic()
                .source
                .starts_with("crates/ubaa_core/src/features/finance/mod.rs:")
        );
        assert!(error.diagnostic().to_json().is_some());
    }
}

#[test]
fn finance_加密快照跨路线复用且失败保留旧值() {
    use crate::cache::{
        CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
        OfflineRepository,
    };
    let root = crate::test_tmp::test_temp_dir("ubaa_core_features_finance").unwrap();
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

#[test]
fn finance_诊断区分包络字段金额和分页失败() {
    let malformed = parser::envelope(b"<html>private</html>", "income_response").unwrap_err();
    assert_eq!(
        malformed.diagnostic().reason.as_deref(),
        Some("json_invalid")
    );
    assert_eq!(
        malformed.diagnostic().response_kind.as_deref(),
        Some("html")
    );
    let code = parser::envelope(br#"{"code":503,"data":null}"#, "income_response").unwrap_err();
    assert_eq!(code.diagnostic().upstream_code, Some(503));
    assert_eq!(
        code.diagnostic().reason.as_deref(),
        Some("business_rejected")
    );
    let rows = parser::page(&json!({"mx":null,"total":0})).unwrap_err();
    let total = parser::page(&json!({"mx":[],"total":"PRIVATE"})).unwrap_err();
    assert_ne!(rows.diagnostic().reason, total.diagnostic().reason);
    assert_ne!(rows.diagnostic().source, total.diagnostic().source);
    let amount = parser::income(&json!({"lsh":"PRIVATE","je":"PRIVATE"})).unwrap_err();
    let tax = parser::income(&json!({"lsh":"PRIVATE","se":"PRIVATE"})).unwrap_err();
    assert_ne!(amount.diagnostic().reason, tax.diagnostic().reason);
    for error in [malformed, code, rows, total, amount, tax] {
        let text = error.diagnostic().to_json().unwrap();
        assert!(!text.contains("PRIVATE"));
        assert!(!text.contains("private"));
    }
}
