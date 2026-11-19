//! 校园卡充值链路的确定性回归：GET 取票 + POST 信封下单。
//!
//! 全部使用合成值，不访问学校。冻结来源没有同源协议，本测试只锁定本项目
//! 已验证的请求形状与解析边界。

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use serde_json::json;

use crate::domain::ConnectionMode;
use crate::error::Result;
use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession};

const CARD: &str = "https://m.icw.buaa.edu.cn";
const SERVICE: &str = "https://m.icw.buaa.edu.cn/card/home/sisUstbMiniReturnPage/112233/6/auth";
const OPENID: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const ORDERNO: &str = "0123456789abcdef0123456789abcdef";

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
    method: HttpMethod,
    url: String,
    status: u16,
    body: Vec<u8>,
    location: Option<String>,
}

impl Step {
    fn redirect(url: impl Into<String>, location: impl Into<String>) -> Self {
        Self {
            method: HttpMethod::Get,
            url: url.into(),
            status: 302,
            body: Vec::new(),
            location: Some(location.into()),
        }
    }

    fn post_json(url: impl Into<String>, payload: &serde_json::Value) -> Self {
        Self {
            method: HttpMethod::Post,
            url: url.into(),
            status: 200,
            body: serde_json::to_vec(
                &json!({ "datajson": super::envelope::seal(payload).unwrap() }),
            )
            .unwrap(),
            location: None,
        }
    }
}

struct Scenario {
    mode: ConnectionMode,
    steps: VecDeque<Step>,
    requests: Vec<HttpRequest>,
}

struct Transport(Arc<Mutex<Scenario>>);

#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let mut scenario = self.0.lock().unwrap();
        let step = scenario.steps.pop_front().expect("不应增加额外请求");
        assert_eq!(request.method, step.method);
        assert_eq!(
            request.url.starts_with("https://d.buaa.edu.cn/"),
            scenario.mode == ConnectionMode::WebVpn,
        );
        let direct = crate::connection::from_webvpn_url(&request.url)?;
        let direct = if let Some((path, query)) = direct.split_once("?_t=") {
            let (timestamp, rest) = query.split_once('&').unwrap();
            assert!(timestamp.parse::<u64>().is_ok());
            assert_eq!(
                request.headers.get("version").map(String::as_str),
                Some("v2")
            );
            format!("{path}?{rest}")
        } else {
            direct
        };
        assert_eq!(direct, step.url);
        let mut response = HttpResponse::new(step.status, &request.url, step.body);
        if let Some(location) = step.location {
            response
                .headers
                .insert("Location".into(), vec![route_url(scenario.mode, &location)]);
        }
        scenario.requests.push(request);
        Ok(response)
    }
}

fn runtime(steps: Vec<Step>) -> (ClientRuntime, Arc<Mutex<Scenario>>) {
    runtime_on_route(ConnectionMode::Direct, steps)
}

fn route_url(mode: ConnectionMode, url: &str) -> String {
    match mode {
        ConnectionMode::Direct => url.into(),
        ConnectionMode::WebVpn => crate::connection::to_webvpn_url(url).unwrap(),
    }
}

fn runtime_on_route(
    mode: ConnectionMode,
    steps: Vec<Step>,
) -> (ClientRuntime, Arc<Mutex<Scenario>>) {
    let scenario = Arc::new(Mutex::new(Scenario {
        mode,
        steps: steps.into(),
        requests: Vec::new(),
    }));
    let mut jar = CookieJar::default();
    let card = route_url(mode, CARD);
    let mut response = HttpResponse::new(200, &card, vec![]);
    response.headers.insert(
        "Set-Cookie".into(),
        vec![format!(
            "JSESSIONID=fixture-card; Path={}; Secure; HttpOnly",
            url::Url::parse(&card).unwrap().path()
        )],
    );
    jar.store_response(&response, &card, SystemTime::now())
        .unwrap();
    let store = Store(Arc::new(Mutex::new(VersionedSession {
        revision: 1,
        snapshot: Some(SessionSnapshot {
            mode,
            cookies: jar.cookies().to_vec(),
            authenticated_at: 1,
            last_activity: 1,
        }),
    })));
    (
        ClientRuntime::new(mode, Transport(scenario.clone()), store).unwrap(),
        scenario,
    )
}

fn login_url() -> String {
    let query = url::form_urlencoded::Serializer::new(String::new())
        .append_pair("service", SERVICE)
        .finish();
    format!("https://sso.buaa.edu.cn/login?{query}")
}

fn login_steps() -> Vec<Step> {
    vec![
        Step::redirect(login_url(), format!("{SERVICE}?ticket=ST-1-fixture")),
        Step::redirect(
            format!("{SERVICE}?ticket=ST-1-fixture"),
            format!("{CARD}/card/goIndex?openid={OPENID}&usertype=6"),
        ),
    ]
}

#[test]
fn 充值准备读取卡序号与余额且不公开openid() {
    block_on_test(async {
        let mut steps = login_steps();
        for balance in ["1.73", "2.73"] {
            steps.push(Step::post_json(
                format!("{CARD}/card/cardpay/openCardPay"),
                &json!({
                    "success": true,
                    "data": {
                        "cardPay": {"idserial": "25375059", "cardbal": balance},
                    },
                }),
            ));
        }
        let (mut client, scenario) = runtime(steps);
        let value = super::card::preflight(&mut client).await.unwrap();
        assert_eq!(value.idserial, "25375059");
        assert_eq!(value.balance, "1.73");
        let wire = serde_json::to_string(&value).unwrap();
        assert!(!wire.contains(OPENID), "openid 不得进入公开 DTO");

        let refreshed = super::card::preflight(&mut client).await.unwrap();
        assert_eq!(refreshed.balance, "2.73");
        assert!(scenario.lock().unwrap().steps.is_empty());
    });
}

#[test]
fn 下单只创建订单并交付同一商户收银台() {
    block_on_test(async {
        let cashier_url = format!("https://cashier.cc-pay.cn/cashier?id={ORDERNO}");
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let mut steps = login_steps();
            steps.push(Step::post_json(
                format!("{CARD}/card/recharge/rechargeByHct?openid={OPENID}"),
                &json!({
                    "success": true,
                    "resultData": {
                        "orderno": ORDERNO,
                        "partnerjourno": "2026010100000000001",
                        "mweb_url": cashier_url,
                    },
                }),
            ));
            let (mut client, scenario) = runtime_on_route(mode, steps);
            let order = super::recharge_order(&mut client, "25375059", "100")
                .await
                .unwrap();
            assert_eq!(order.orderno, ORDERNO);
            assert_eq!(order.amount_fen, "100");
            assert_eq!(order.cashier_url, cashier_url);

            let scenario = scenario.lock().unwrap();
            assert!(scenario.steps.is_empty());
            assert_eq!(scenario.requests.len(), 3);
            let request = &scenario.requests[2];
            let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
            let payload = super::envelope::open(body["datajson"].as_str().unwrap()).unwrap();
            assert_eq!(
                payload,
                json!({
                    "idserial": "25375059",
                    "txamt": "100",
                    "payway": "",
                    "openid": OPENID,
                    "payWay": "10",
                    "tradetype": "WAP",
                    "usertype": "1",
                    "orgid": "2",
                })
            );
        }
    });
}

#[test]
fn 未登录时在下单前停止() {
    block_on_test(async {
        let steps = vec![Step::redirect(login_url(), "https://sso.buaa.edu.cn/login")];
        let (mut client, scenario) = runtime(steps);
        let error = super::recharge_order(&mut client, "25375059", "100")
            .await
            .unwrap_err();
        assert_eq!(error.kind, crate::error::ErrorKind::Authentication);
        assert_eq!(scenario.lock().unwrap().requests.len(), 1);
    });
}

#[test]
fn 非收银台地址被拒绝() {
    block_on_test(async {
        for url in [
            "https://evil.example.com/pay",
            "https://cashier.cc-pay.cn.evil.example.com/pay",
            "https://cashier.cc-pay.cn@evil.example.com/pay",
            "https://cashier.cc-pay.cn/cashier?id=anotherorder",
        ] {
            let mut steps = login_steps();
            steps.push(Step::post_json(
                format!("{CARD}/card/recharge/rechargeByHct?openid={OPENID}"),
                &json!({
                    "success": true,
                    "resultData": {"orderno": ORDERNO, "mweb_url": url},
                }),
            ));
            let (mut client, scenario) = runtime(steps);
            let error = super::recharge_order(&mut client, "25375059", "100")
                .await
                .unwrap_err();
            assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
            assert!(scenario.lock().unwrap().steps.is_empty());
        }
    });
}

fn block_on_test(task: impl std::future::Future<Output = ()>) {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(task);
}
