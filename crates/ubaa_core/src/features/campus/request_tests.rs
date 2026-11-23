use crate::domain::{CampusMetric, ConnectionMode};
use crate::error::{Result, UbaaError};
use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession};
use serde_json::json;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

#[path = "library_route_tests.rs"]
mod library_routes;

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

#[derive(Clone)]
struct Step {
    url: String,
    status: u16,
    body: String,
    location: Option<String>,
    cookie: Option<String>,
    method: HttpMethod,
    request_body: Option<Vec<u8>>,
}
impl Step {
    fn json(path: &str, body: impl Into<String>) -> Self {
        Self {
            url: if path.starts_with("https://") {
                path.into()
            } else {
                format!("{BASE}{path}")
            },
            status: 200,
            body: body.into(),
            location: None,
            cookie: None,
            method: HttpMethod::Get,
            request_body: None,
        }
    }
    fn post(url: &str, body: &str, response: &str) -> Self {
        Self {
            url: url.into(),
            status: 200,
            body: response.into(),
            location: None,
            cookie: None,
            method: HttpMethod::Post,
            request_body: Some(body.as_bytes().to_vec()),
        }
    }
    fn html(url: &str, body: &str) -> Self {
        Self {
            url: url.into(),
            status: 200,
            body: body.into(),
            location: None,
            cookie: None,
            method: HttpMethod::Get,
            request_body: None,
        }
    }
    fn redirect(url: &str, location: &str) -> Self {
        Self {
            url: url.into(),
            status: 302,
            body: String::new(),
            location: Some(location.into()),
            cookie: None,
            method: HttpMethod::Get,
            request_body: None,
        }
    }
}
struct Scenario {
    steps: VecDeque<Step>,
    requests: Vec<HttpRequest>,
    invalidate_after: Option<(usize, Store)>,
    fail_at: Option<(usize, UbaaError)>,
}
struct Transport(Arc<Mutex<Scenario>>);
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let direct = crate::connection::from_webvpn_url(&request.url)?;
        let mut scenario = self.0.lock().unwrap();
        let step = scenario.steps.pop_front().expect("不应增加额外请求");
        assert_eq!(direct, step.url);
        assert_eq!(request.method, step.method);
        match &step.request_body {
            Some(body) => assert_eq!(&request.body, body),
            None => assert_eq!(request.body.len(), 0),
        }
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
        if scenario
            .fail_at
            .as_ref()
            .is_some_and(|(count, _)| *count == scenario.requests.len())
        {
            let (_, error) = scenario.fail_at.take().unwrap();
            return Err(error);
        }
        Ok(response)
    }
}

fn runtime(mode: ConnectionMode, steps: Vec<Step>) -> (ClientRuntime, Arc<Mutex<Scenario>>, Store) {
    let scenario = Arc::new(Mutex::new(Scenario {
        steps: steps.into(),
        requests: Vec::new(),
        invalidate_after: None,
        fail_at: None,
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
            assert_eq!(scenario.lock().unwrap().steps.len(), 0);
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
            assert_eq!(scenario.steps.len(), 0);
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
        assert_eq!(scenario.lock().unwrap().steps.len(), 0);
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
        assert_eq!(scenario.lock().unwrap().requests.len(), 0);
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
            assert_eq!(scenario.lock().unwrap().steps.len(), 0);
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
        assert_eq!(scenario.lock().unwrap().steps.len(), 0);
    });
}

const LIB_ENTRY: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/cas/rosetta";
const LIB_SSO: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fspace.lib.buaa.edu.cn%3A443%2Fmeta-local%2Fopac%2Fcas%2Frosetta";
const LIB_LIST: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/loans";
const LIB_MAX: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/loan_max_renew_times";
const LIB_RENEW: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/batch_renew";

fn loan_row(id: &str, bar: &str, renew: i64, status: &str) -> serde_json::Value {
    json!({
        "loanId": id,
        "title": format!("合成书目{id}"),
        "author": "合成作者",
        "item": {"barCode": bar},
        "location": "合成馆藏地",
        "loanDate": "2026-11-01 09:30:00",
        "dueDate": "2026-12-01 23:59:00",
        "renewTimes": renew,
        "loanStatus": status,
        "loanType": "normal"
    })
}

fn loan_page(page: u64, total: u64, total_page: u64, rows: &[serde_json::Value]) -> String {
    json!({
        "code": 0,
        "msg": null,
        "data": {
            "currentPage": page,
            "pageSize": 20,
            "total": total,
            "totalPage": total_page,
            "items": rows
        }
    })
    .to_string()
}

fn max_page(rows: &[(&str, u64)]) -> String {
    json!({
        "code": 0,
        "msg": null,
        "data": {
            "items": rows.iter().map(|(bar, max)| json!({
                "barCode": bar,
                "maxRenewTimes": max
            })).collect::<Vec<_>>()
        }
    })
    .to_string()
}

#[test]
fn 借阅列表先复用已有统一认证会话并在失效时建立图书馆会话() {
    block_on_test(async {
        let mut expired = Step::json(&format!("{LIB_LIST}?page=1&pageSize=20"), "");
        expired.status = 401;
        let steps = vec![
            expired,
            Step::redirect(LIB_ENTRY, LIB_SSO),
            Step::redirect(LIB_SSO, &format!("{LIB_ENTRY}?ticket=ST-fixture")),
            Step {
                cookie: Some(
                    "meta-opac.session=fixture-loan; Path=/meta-local; Secure; HttpOnly".into(),
                ),
                ..Step::redirect(&format!("{LIB_ENTRY}?ticket=ST-fixture"), LIB_ENTRY)
            },
            Step::html(LIB_ENTRY, "<html>图书馆</html>"),
            Step::json(
                &format!("{LIB_LIST}?page=1&pageSize=20"),
                loan_page(
                    1,
                    2,
                    1,
                    &[
                        loan_row("loan-1", "bar-1", 1, "soon"),
                        loan_row("loan-2", "bar-2", 0, "overdue"),
                    ],
                ),
            ),
            Step::json(
                &format!("{LIB_MAX}?page=1&pageSize=20"),
                max_page(&[("bar-1", 3), ("bar-2", 1)]),
            ),
        ];
        let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
        let loans = super::super::current_loans(&mut client).await.unwrap();
        assert_eq!(loans.total, 2);
        assert_eq!(loans.entries.len(), 2);
        assert_eq!(loans.entries[0].id, "loan-1");
        assert_eq!(loans.entries[0].title, "合成书目loan-1");
        assert_eq!(loans.entries[0].author.as_deref(), Some("合成作者"));
        assert_eq!(
            loans.entries[0].due_date.as_deref(),
            Some("2026-12-01 23:59:00")
        );
        assert_eq!(loans.entries[0].renew_times, Some(1));
        assert_eq!(loans.entries[0].can_renew_times, Some(2));
        assert_eq!(
            loans.entries[0].status,
            crate::domain::LibraryLoanStatus::Soon
        );
        assert_eq!(loans.entries[1].can_renew_times, Some(1));
        assert_eq!(
            loans.entries[1].status,
            crate::domain::LibraryLoanStatus::Overdue
        );
        let scenario = scenario.lock().unwrap();
        assert!(scenario.steps.is_empty());
        assert_eq!(scenario.requests.len(), 7);
        let first_list = &scenario.requests[0];
        assert!(
            !first_list
                .headers
                .get("Cookie")
                .is_some_and(|cookie| cookie.contains("CASTGC"))
        );
        assert!(
            !scenario.requests[1]
                .headers
                .get("Cookie")
                .is_some_and(|cookie| cookie.contains("CASTGC"))
        );
        let sso = &scenario.requests[2];
        assert!(sso.headers["Cookie"].contains("CASTGC=fixture-sso"));
        let second_list = &scenario.requests[5];
        assert!(!second_list.headers["Cookie"].contains("CASTGC"));
        assert!(second_list.headers["Cookie"].contains("meta-opac.session=fixture-loan"));
        for request in [second_list, &scenario.requests[6]] {
            assert_eq!(
                request.headers.get("X-Hw-Lang").map(String::as_str),
                Some("chi")
            );
            assert_eq!("m", request.headers["X-Hw-explorer"]);
            assert_eq!("", request.headers["X-CSRF-TOKEN"]);
        }
    });
}

#[test]
fn 借阅列表分页且续借上限读取失败只保留未知() {
    block_on_test(async {
        let mut first = (1..=20)
            .map(|index| {
                loan_row(
                    &format!("loan-{index}"),
                    &format!("bar-{index}"),
                    0,
                    "normal",
                )
            })
            .collect::<Vec<_>>();
        first.truncate(20);
        let second = loan_row("loan-21", "bar-21", 2, "normal");
        let mut failed = Step::json(
            &format!("{LIB_MAX}?page=1&pageSize=20"),
            max_page(&[("bar-1", 3)]),
        );
        failed.status = 500;
        let steps = vec![
            Step::json(
                &format!("{LIB_LIST}?page=1&pageSize=20"),
                loan_page(1, 21, 2, &first),
            ),
            failed,
            Step::json(
                &format!("{LIB_LIST}?page=2&pageSize=20"),
                loan_page(2, 21, 2, &[second]),
            ),
            Step::json(
                &format!("{LIB_MAX}?page=2&pageSize=20"),
                max_page(&[("bar-21", 3)]),
            ),
        ];
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let (mut client, scenario, _) = runtime(mode, steps.clone());
            let loans = super::super::current_loans(&mut client).await.unwrap();
            assert_eq!(loans.total, 21);
            assert_eq!(loans.entries.len(), 21);
            assert_eq!(loans.entries[0].can_renew_times, None);
            assert_eq!(loans.entries[20].can_renew_times, Some(1));
            assert_eq!(scenario.lock().unwrap().requests.len(), 4);
        }
    });
}

#[test]
fn 续借上限超时保留已读借阅但会话失效仍返回失败() {
    use crate::error::{ErrorCode, ErrorKind};

    block_on_test(async {
        let steps = vec![
            Step::json(
                &format!("{LIB_LIST}?page=1&pageSize=20"),
                loan_page(1, 1, 1, &[loan_row("loan-1", "bar-1", 1, "normal")]),
            ),
            Step::json(&format!("{LIB_MAX}?page=1&pageSize=20"), ""),
        ];
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            for session_invalidated in [false, true] {
                let (mut client, scenario, store) = runtime(mode, steps.clone());
                {
                    let mut scenario = scenario.lock().unwrap();
                    scenario.fail_at = Some((
                        2,
                        UbaaError::new(ErrorCode::Timeout, ErrorKind::Network, true, "请求超时"),
                    ));
                    scenario.invalidate_after = session_invalidated.then_some((2, store));
                }
                let loans = super::super::current_loans(&mut client).await;
                assert_eq!(scenario.lock().unwrap().requests.len(), 2);
                if session_invalidated {
                    assert!(loans.unwrap_err().is_session_conflict());
                } else {
                    let loans = loans.unwrap();
                    assert_eq!(loans.total, 1);
                    assert_eq!(loans.entries[0].id, "loan-1");
                    assert!(loans.entries[0].due_date.is_some());
                    assert_eq!(loans.entries[0].renew_times, Some(1));
                    assert_eq!(loans.entries[0].can_renew_times, None);
                }
            }
        }
    });
}

#[test]
fn 借阅列表拒绝错误分页重复标识和异常字段() {
    block_on_test(async {
        let cases = vec![
            json!({"code":0,"data":{"currentPage":2,"pageSize":20,"total":1,"totalPage":1,"items":[loan_row("loan-1","bar-1",0,"normal")]}}).to_string(),
            json!({"code":0,"data":{"currentPage":1,"pageSize":20,"total":1,"totalPage":2,"items":[loan_row("loan-1","bar-1",0,"normal")]}}).to_string(),
            json!({"code":7,"data":{"currentPage":1,"pageSize":20,"total":1,"totalPage":1,"items":[loan_row("loan-1","bar-1",0,"normal")]}}).to_string(),
            json!({"code":0,"data":{"currentPage":1,"pageSize":20,"total":1,"totalPage":1,"items":[{"loanId":"loan-1","title":"  "}]}}).to_string(),
            json!({"code":0,"data":{"currentPage":1,"pageSize":20,"total":1,"totalPage":1,"items":[loan_row("loan-1","bar-1",-1,"normal")]}}).to_string(),
            "not-json".into(),
        ];
        for body in cases {
            let steps = vec![Step::json(&format!("{LIB_LIST}?page=1&pageSize=20"), body)];
            let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
            assert!(super::super::current_loans(&mut client).await.is_err());
            assert_eq!(scenario.lock().unwrap().requests.len(), 1);
        }

        let mut duplicate = (1..=20)
            .map(|index| {
                loan_row(
                    &format!("loan-{index}"),
                    &format!("bar-{index}"),
                    0,
                    "normal",
                )
            })
            .collect::<Vec<_>>();
        duplicate.truncate(20);
        let steps = vec![
            Step::json(
                &format!("{LIB_LIST}?page=1&pageSize=20"),
                loan_page(1, 21, 2, &duplicate),
            ),
            Step::json(&format!("{LIB_MAX}?page=1&pageSize=20"), max_page(&[])),
            Step::json(
                &format!("{LIB_LIST}?page=2&pageSize=20"),
                loan_page(2, 21, 2, &[loan_row("loan-1", "bar-1", 0, "normal")]),
            ),
            Step::json(&format!("{LIB_MAX}?page=2&pageSize=20"), max_page(&[])),
        ];
        let (mut client, _, _) = runtime(ConnectionMode::Direct, steps);
        assert!(super::super::current_loans(&mut client).await.is_err());
    });
}

#[test]
fn 借阅列表空结果不回退到业务登录且缺少会话报认证错误() {
    block_on_test(async {
        let steps = vec![Step::json(
            &format!("{LIB_LIST}?page=1&pageSize=20"),
            json!({"code":0,"data":{"currentPage":1,"pageSize":20,"total":0,"totalPage":0,"items":[]}}).to_string(),
        )];
        let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
        let loans = super::super::current_loans(&mut client).await.unwrap();
        assert_eq!(loans.total, 0);
        assert_eq!(loans.entries.len(), 0);
        assert_eq!(scenario.lock().unwrap().requests.len(), 1);

        let mut expired = Step::json(&format!("{LIB_LIST}?page=1&pageSize=20"), "");
        expired.status = 401;
        let steps = vec![
            expired,
            Step::redirect(LIB_ENTRY, LIB_SSO),
            Step::html(LIB_SSO, "<html>统一认证登录</html>"),
        ];
        let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
        let error = super::super::current_loans(&mut client).await.unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
        assert_eq!(scenario.lock().unwrap().requests.len(), 3);
    });
}

fn renewal_runtime(list: String, max: String, renewal: Step) -> WarpRuntime {
    let mut listed = Step::json(&format!("{LIB_LIST}?page=1&pageSize=20"), list);
    listed.cookie =
        Some("meta-opac.session=fixture-loan; Path=/meta-local; Secure; HttpOnly".into());
    let steps = vec![
        listed,
        Step::json(&format!("{LIB_MAX}?page=1&pageSize=20"), max),
        renewal,
    ];
    runtime(ConnectionMode::Direct, steps)
}

type WarpRuntime = (ClientRuntime, Arc<Mutex<Scenario>>, Store);

#[test]
fn 借阅列表只使用已证明的嵌套条码形状() {
    block_on_test(async {
        let list = loan_page(
            1,
            2,
            1,
            &[loan_row("loan-1", "bar-1", 1, "normal"), {
                let mut row = loan_row("loan-2", "bar-2", 1, "normal");
                row.as_object_mut().unwrap().remove("item");
                row["barCode"] = serde_json::json!("bar-2");
                row
            }],
        );
        let (mut client, scenario, _) = runtime(
            ConnectionMode::Direct,
            vec![
                Step::json(&format!("{LIB_LIST}?page=1&pageSize=20"), list),
                Step::json(
                    &format!("{LIB_MAX}?page=1&pageSize=20"),
                    max_page(&[("bar-1", 3), ("bar-2", 3)]),
                ),
            ],
        );
        let loans = super::super::current_loans(&mut client).await.unwrap();
        assert_eq!(loans.entries[0].can_renew_times, Some(2));
        assert_eq!(loans.entries[1].can_renew_times, None);
        assert_eq!(scenario.lock().unwrap().requests.len(), 2);
    });
}

#[test]
fn 续借复核目标并只提交一个记录标识() {
    block_on_test(async {
        let list = loan_page(1, 1, 1, &[loan_row("loan-1", "bar-1", 1, "normal")]);
        let (mut client, scenario, _) = renewal_runtime(
            list.clone(),
            max_page(&[("bar-1", 3)]),
            Step::post(
                LIB_RENEW,
                r#"{"loanIds":["loan-1"],"source":1}"#,
                r#"{"code":0,"msg":null,"data":null}"#,
            ),
        );
        let result = super::super::renew(
            &mut client,
            crate::domain::LibraryLoanRenewRequest {
                loan_id: "loan-1".into(),
                due_date: Some("2026-12-01 23:59:00".into()),
                renew_times: Some(1),
                can_renew_times: Some(2),
            },
        )
        .await
        .unwrap();
        assert!(result.success);
        assert_eq!(result.loan_id, "loan-1");
        let scenario = scenario.lock().unwrap();
        assert!(scenario.steps.is_empty());
        let request = &scenario.requests[2];
        assert!(request.headers["Cookie"].contains("meta-opac.session=fixture-loan"));
        assert_eq!(
            request.headers.get("Content-Type").map(String::as_str),
            Some("application/json")
        );
        assert_eq!(
            request.headers.get("X-Hw-Lang").map(String::as_str),
            Some("chi")
        );
        assert_eq!("m", request.headers["X-Hw-explorer"]);
        assert_eq!("", request.headers["X-CSRF-TOKEN"]);
    });
}

#[test]
fn 续借拒绝已用尽或已消失的目标() {
    block_on_test(async {
        let list = loan_page(1, 1, 1, &[loan_row("loan-1", "bar-1", 3, "normal")]);
        let (mut client, scenario, _) = renewal_runtime(
            list,
            max_page(&[("bar-1", 3)]),
            Step::post(LIB_RENEW, "", ""),
        );
        let error = super::super::renew_preflight(&mut client, "loan-1")
            .await
            .unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::InvalidInput);
        assert_eq!(scenario.lock().unwrap().requests.len(), 2);

        let list = loan_page(1, 1, 1, &[loan_row("loan-1", "bar-1", 0, "normal")]);
        let (mut client, _, _) = renewal_runtime(
            list,
            max_page(&[("bar-1", 1)]),
            Step::post(LIB_RENEW, "", ""),
        );
        assert!(
            super::super::renew_preflight(&mut client, "loan-2")
                .await
                .is_err()
        );
    });
}

#[test]
fn 续借业务拒绝与结果未知分别归类() {
    use crate::error::ErrorCode::{BusinessRejected, OutcomeUnknown};

    block_on_test(async {
        let cases = [
            (
                200,
                r#"{"code":0,"msg":"不得公开的外层说明","data":{"loan-1":"META-403060: 不允许续借,未达到到期前续借天数"}}"#,
                BusinessRejected,
                Some("尚未进入续借窗口，请稍后再试"),
            ),
            (
                200,
                r#"{"code":1001,"msg":"读者测试甲当前不能续借","data":null}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"data":{"loan-1":"<script>不得公开</script>"}}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"data":{"loan-1":"不得公开: loan-1"}}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"data":{"loan-1":"不得公开: \u202e说明"}}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"data":{"loan-1":"不得公开\n说明"}}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"data":{"loan-1":{"message":"不得公开"}}}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"msg":"不得公开","data":{"loan-2":"不得公开的另一记录原因"}}"#,
                OutcomeUnknown,
                None,
            ),
            (
                200,
                r#"{"code":1001,"msg":"token: 不得公开","data":{"loan-1":"不得公开"}}"#,
                BusinessRejected,
                None,
            ),
            (
                200,
                r#"{"code":0,"data":"unexpected"}"#,
                OutcomeUnknown,
                None,
            ),
            (200, r#"{"data":null}"#, OutcomeUnknown, None),
            (200, r#"{"code":"1001","data":null}"#, OutcomeUnknown, None),
            (200, "not-json", OutcomeUnknown, None),
            (500, "", OutcomeUnknown, None),
        ];
        for (status, response, code, reason) in cases {
            let mut step = Step::post(LIB_RENEW, r#"{"loanIds":["loan-1"],"source":1}"#, response);
            step.status = status;
            let (mut client, _, _) = renewal_runtime(
                loan_page(1, 1, 1, &[loan_row("loan-1", "bar-1", 1, "normal")]),
                max_page(&[("bar-1", 3)]),
                step,
            );
            let error = super::super::renew(
                &mut client,
                crate::domain::LibraryLoanRenewRequest {
                    loan_id: "loan-1".into(),
                    due_date: Some("2026-12-01 23:59:00".into()),
                    renew_times: Some(1),
                    can_renew_times: Some(2),
                },
            )
            .await
            .unwrap_err();
            assert_eq!((error.code, error.retryable), (code, false));
            assert_eq!(error.private_display_message(), reason);
            assert!(!error.message.contains("不得公开"));
            if let Some(reason) = reason {
                assert!(!serde_json::to_string(&error).unwrap().contains(reason));
                assert!(!error.diagnostic().to_json().unwrap().contains(reason));
            }
        }
    });
}

#[test]
fn 借阅引导只接受嵌套图书馆入口的统一认证服务() {
    block_on_test(async {
        let mut expired = Step::json(&format!("{LIB_LIST}?page=1&pageSize=20"), "");
        expired.status = 401;
        let steps = vec![
            expired,
            Step::redirect(
                LIB_ENTRY,
                "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fit.buaa.edu.cn%2Fhome%2F",
            ),
        ];
        let (mut client, scenario, _) = runtime(ConnectionMode::Direct, steps);
        assert!(super::super::current_loans(&mut client).await.is_err());
        assert_eq!(scenario.lock().unwrap().requests.len(), 2);
    });
}
