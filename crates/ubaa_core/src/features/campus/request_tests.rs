use crate::domain::{CampusMetric, ConnectionMode};
use crate::error::Result;
use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession};
use serde_json::json;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

const BASE: &str = "https://it.buaa.edu.cn";
const PROFILE: &str = include_str!("../../../../../fixtures/readonly/campus/profile.json");
const ITEMS: &str = include_str!("../../../../../fixtures/readonly/campus/items.json");
const FLOW: &str = include_str!("../../../../../fixtures/readonly/campus/network.html");

#[derive(Clone)]
struct Store(Arc<Mutex<VersionedSession>>);
impl SessionStore for Store {
    fn load_versioned(&self) -> Result<VersionedSession> {
        Ok(self.0.lock().unwrap().clone())
    }
    fn compare_exchange(
        &self,
        revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let mut state = self.0.lock().unwrap();
        if state.revision != revision {
            return Ok(SessionMutation::Conflict);
        }
        state.revision += 1;
        state.snapshot = replacement.cloned();
        Ok(SessionMutation::Applied {
            revision: state.revision,
        })
    }
}

struct Step {
    url: String,
    status: u16,
    body: String,
    location: Option<String>,
    cookie: Option<String>,
}
impl Step {
    fn json(path: &str, body: impl Into<String>) -> Self {
        Self {
            url: format!("{BASE}{path}"),
            status: 200,
            body: body.into(),
            location: None,
            cookie: None,
        }
    }
    fn html(url: &str, body: &str) -> Self {
        Self {
            url: url.into(),
            status: 200,
            body: body.into(),
            location: None,
            cookie: None,
        }
    }
    fn redirect(url: &str, location: &str) -> Self {
        Self {
            url: url.into(),
            status: 302,
            body: String::new(),
            location: Some(location.into()),
            cookie: None,
        }
    }
}
struct Scenario {
    steps: VecDeque<Step>,
    requests: Vec<HttpRequest>,
    invalidate_after: Option<(usize, Store)>,
}
struct Transport(Arc<Mutex<Scenario>>);
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        assert_eq!(request.method, HttpMethod::Get);
        assert!(request.body.is_empty());
        let direct = crate::connection::from_webvpn_url(&request.url)?;
        let mut scenario = self.0.lock().unwrap();
        let step = scenario.steps.pop_front().expect("不应增加额外请求");
        assert_eq!(direct, step.url);
        let mut response = HttpResponse::new(step.status, &request.url, step.body.into_bytes());
        if let Some(location) = step.location {
            response.headers.insert("Location".into(), vec![location]);
        }
        if let Some(cookie) = step.cookie {
            response.headers.insert(
                "Set-Cookie".into(),
                vec![scoped_cookie(&request.url, &cookie)],
            );
        }
        scenario.requests.push(request);
        if scenario
            .invalidate_after
            .as_ref()
            .is_some_and(|(count, _)| *count == scenario.requests.len())
        {
            let (_, store) = scenario.invalidate_after.take().unwrap();
            let revision = store.load_versioned()?.revision;
            store.compare_exchange(revision, None)?;
        }
        Ok(response)
    }
}

fn runtime(mode: ConnectionMode, steps: Vec<Step>) -> (ClientRuntime, Arc<Mutex<Scenario>>, Store) {
    let scenario = Arc::new(Mutex::new(Scenario {
        steps: steps.into(),
        requests: Vec::new(),
        invalidate_after: None,
    }));
    let mut jar = CookieJar::default();
    for (url, cookie) in [
        (
            "https://sso.buaa.edu.cn/login",
            "CASTGC=fixture-sso; Path=/; Secure; HttpOnly",
        ),
        (
            super::super::PORTAL_HOME,
            "CK_LC=fixture-portal; Path=/; Secure; HttpOnly",
        ),
    ] {
        let request_url = match mode {
            ConnectionMode::Direct => url.into(),
            ConnectionMode::WebVpn => crate::connection::to_webvpn_url(url).unwrap(),
        };
        let mut response = HttpResponse::new(200, &request_url, vec![]);
        response.headers.insert(
            "Set-Cookie".into(),
            vec![scoped_cookie(&request_url, cookie)],
        );
        jar.store_response(&response, &request_url, SystemTime::now())
            .unwrap();
    }
    let store = Store(Arc::new(Mutex::new(VersionedSession {
        revision: 1,
        snapshot: Some(SessionSnapshot {
            mode,
            cookies: jar.cookies().to_vec(),
            authenticated_at: 1,
            last_activity: 1,
        }),
    })));
    let runtime = ClientRuntime::new(mode, Transport(scenario.clone()), store.clone()).unwrap();
    (runtime, scenario, store)
}

fn details(id: &str, value: serde_json::Value, unit: &str) -> Step {
    let mut data = json!({"unit": unit, "account": "不得公开的合成账号"});
    data["value"] = value;
    Step::json(
        &format!("/personal/frontend/data/detail?id={id}"),
        json!({"e":0,"d":{"data":data}}).to_string(),
    )
}

#[test]
fn 五项读取动态id支持单项失败及校园卡回退() {
    block_on_test(async {
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let mut card = Step::json("/buaa/frontend/card/balance", "");
            card.status = 503;
            let steps = vec![
                Step::json("/personal/frontend/data/info", PROFILE),
                Step::json(
                    "/personal/frontend/data/items?type=personal_data",
                    ITEMS.replace("fixture-net-id", "changed-net-id"),
                ),
                details("changed-net-id", json!(12.34), ""),
                card,
                details("fixture-card-id", json!("20.50"), "元"),
                Step::json(
                    "/personal/frontend/data/detail?id=fixture-mail-id",
                    r#"{"e":9,"m":"不得公开的合成原文"}"#,
                ),
                details("fixture-book-id", json!(0), ""),
                details("fixture-cloud-id", json!("80.125"), "G"),
            ];
            let (mut client, scenario, _) = runtime(mode, steps);
            let result = super::super::get_metrics(&mut client).await.unwrap();
            assert!(matches!(result.unread_mail, CampusMetric::Failure { .. }));
            assert!(matches!(
                result.borrowed_books,
                CampusMetric::Success { value: 0, .. }
            ));
            assert!(
                matches!(&result.cloud_storage_remaining, CampusMetric::Success { value, .. } if value.value == "80.125")
            );
            let wire = serde_json::to_string(&result).unwrap();
            assert!(!wire.contains("不得公开"));
            assert!(!wire.contains("changed-net-id"));
            assert!(scenario.lock().unwrap().steps.is_empty());
            for request in &scenario.lock().unwrap().requests {
                assert_eq!(
                    request.headers.get("X-Requested-With").map(String::as_str),
                    Some("XMLHttpRequest")
                );
            }
        }
    });
}

#[test]
fn 业务登录只复用统一认证且凭据按作用域发送() {
    block_on_test(async {
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let sso = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fzfw.buaa.edu.cn%2Fsso%2Fcas%2Findex";
            let mut callback = Step::redirect(
                "https://zfw.buaa.edu.cn/sso/cas/index?ticket=fixture-ticket",
                "/pay/card",
            );
            callback.cookie =
                Some("PHPSESSID_8800=fixture-network; Path=/; Secure; HttpOnly".into());
            let steps = vec![
                Step::redirect(super::super::NETWORK_HOME, "/sso/cas/index"),
                Step::redirect(super::super::NETWORK_LOGIN, sso),
                Step::redirect(
                    sso,
                    "https://zfw.buaa.edu.cn/sso/cas/index?ticket=fixture-ticket",
                ),
                callback,
                Step::html("https://zfw.buaa.edu.cn/pay/card", "<html>充值入口</html>"),
                Step::html(super::super::NETWORK_HOME, FLOW),
            ];
            let (mut client, scenario, store) = runtime(mode, steps);
            let result = super::super::get_usage(&mut client).await.unwrap();
            assert_eq!(result.products.len(), 2);
            let scenario = scenario.lock().unwrap();
            assert!(scenario.steps.is_empty());
            for request in &scenario.requests {
                let url = crate::connection::from_webvpn_url(&request.url).unwrap();
                let cookie = request.headers.get("Cookie").cloned().unwrap_or_default();
                assert!(!cookie.contains("fixture-portal"));
                if url.contains("sso.buaa.edu.cn/login") {
                    assert!(cookie.contains("fixture-sso"));
                } else {
                    assert!(!cookie.contains("fixture-sso"));
                }
            }
            assert!(
                store
                    .load_versioned()
                    .unwrap()
                    .snapshot
                    .unwrap()
                    .cookies
                    .iter()
                    .any(|cookie| cookie.name == "PHPSESSID_8800")
            );
        }
    });
}

#[test]
fn 门户引导成功后才能发布资料() {
    block_on_test(async {
        let home = super::super::PORTAL_HOME;
        let bootstrap = format!(
            "{BASE}/manage/common/login/index?redirect=https%3A%2F%2Fit.buaa.edu.cn%2Fhome%2F"
        );
        let entry = format!(
            "{BASE}/manage/common/cas_login/30001?to_bind=0&redirect=https%3A%2F%2Fit.buaa.edu.cn%2Fhome%2F"
        );
        let service = format!(
            "{BASE}/manage/common/cas_login/30001?redirect=https%3A%2F%2Fit.buaa.edu.cn%2Fhome%2F"
        );
        let sso = format!(
            "https://sso.buaa.edu.cn/login?{}",
            url::form_urlencoded::Serializer::new(String::new())
                .append_pair("service", &service)
                .finish()
        );
        let callback = format!("{service}&ticket=fixture-ticket");
        let steps = vec![
            Step::json("/personal/frontend/data/info", r#"{"e":10013}"#),
            Step::redirect(&bootstrap, &entry),
            Step::redirect(&entry, &sso),
            Step::redirect(&sso, &callback),
            Step::redirect(&callback, home),
            Step::html(home, "<html></html>"),
            Step::json("/personal/frontend/data/info", PROFILE),
        ];
        let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
        let profile = super::super::get_profile(&mut client).await.unwrap();
        assert_eq!(profile.department, "示例学院");
        assert!(scenario.lock().unwrap().steps.is_empty());
    });
}

#[test]
fn 会话修订变化在请求前拒绝且不发布部分数据() {
    block_on_test(async {
        let (mut client, scenario, store) = runtime(ConnectionMode::Direct, vec![]);
        store.compare_exchange(1, None).unwrap();
        assert!(
            super::super::get_metrics(&mut client)
                .await
                .unwrap_err()
                .is_session_conflict()
        );
        assert!(scenario.lock().unwrap().requests.is_empty());
    });
}

fn block_on_test(task: impl std::future::Future<Output = ()>) {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(task);
}

// 模拟网关按上游路径作用域重写 Set-Cookie；Direct 保持原始属性。
fn scoped_cookie(request_url: &str, cookie: &str) -> String {
    let url = url::Url::parse(request_url).unwrap();
    if url.host_str() == Some("d.buaa.edu.cn") {
        let prefix = url.path().split('/').take(3).collect::<Vec<_>>().join("/");
        cookie.replace("Path=/;", &format!("Path={prefix}/;"))
    } else {
        cookie.into()
    }
}

#[test]
fn 读取期间账号会话变化不会发布旧账号结果() {
    block_on_test(async {
        let (mut client, scenario, store) = runtime(
            ConnectionMode::Direct,
            vec![Step::json("/personal/frontend/data/info", PROFILE)],
        );
        scenario.lock().unwrap().invalidate_after = Some((1, store));
        assert!(
            super::super::get_profile(&mut client)
                .await
                .unwrap_err()
                .is_session_conflict()
        );
        assert_eq!(scenario.lock().unwrap().requests.len(), 1);
    });
}

#[test]
fn 外域跳转和统一认证登录页都停止业务引导() {
    block_on_test(async {
        let sso = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fzfw.buaa.edu.cn%2Fsso%2Fcas%2Findex";
        for tail in [
            vec![Step::redirect(
                super::super::NETWORK_LOGIN,
                "https://example.invalid/steal",
            )],
            vec![
                Step::redirect(super::super::NETWORK_LOGIN, sso),
                Step::html(
                    sso,
                    "<form><input name='execution'><input type='password'></form>",
                ),
            ],
        ] {
            let mut steps = vec![Step::redirect(super::super::NETWORK_HOME, "/sso/cas/index")];
            steps.extend(tail);
            let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
            assert!(super::super::get_usage(&mut client).await.is_err());
            assert!(scenario.lock().unwrap().steps.is_empty());
            assert!(client.has_local_session());
        }
    });
}

#[test]
fn 缺失及重复指标不会阻止其他指标读取() {
    block_on_test(async {
        let mut items: serde_json::Value = serde_json::from_str(ITEMS).unwrap();
        let list = items["d"]["data"].as_array_mut().unwrap();
        list.retain(|item| item["key"] != "net.netFee");
        let mail = list
            .iter()
            .find(|item| item["key"] == "mail.unread")
            .unwrap()
            .clone();
        list.push(mail);
        let steps = vec![
            Step::json("/personal/frontend/data/info", PROFILE),
            Step::json(
                "/personal/frontend/data/items?type=personal_data",
                items.to_string(),
            ),
            Step::json(
                "/buaa/frontend/card/balance",
                r#"{"e":0,"d":{"value":"0.00","unit":"元"}}"#,
            ),
            details("fixture-book-id", json!(3), ""),
            details("fixture-cloud-id", json!("100"), "G"),
        ];
        let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
        let metrics = super::super::get_metrics(&mut client).await.unwrap();
        assert!(matches!(
            metrics.network_balance,
            CampusMetric::Failure { .. }
        ));
        assert!(matches!(metrics.unread_mail, CampusMetric::Failure { .. }));
        assert!(matches!(
            metrics.borrowed_books,
            CampusMetric::Success { value: 3, .. }
        ));
        assert!(scenario.lock().unwrap().steps.is_empty());
    });
}
