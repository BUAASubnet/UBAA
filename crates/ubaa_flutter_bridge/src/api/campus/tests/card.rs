use std::path::PathBuf;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

use super::{BridgeClient, BridgeConnectionMode, BridgeErrorCode, domain};
use domain::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpMethod, HttpRequest, HttpResponse,
    HttpTransport, RouteConfig, RouteSessionSnapshot, from_webvpn_url, sso_fixture_ticket,
};
use domain::{ConnectionMode, ErrorCode, ErrorKind, NetworkState, UbaaClient, UbaaError};

const CARD: &str = "https://m.icw.buaa.edu.cn";
const SERVICE: &str = "https://m.icw.buaa.edu.cn/card/home/sisUstbMiniReturnPage/112233/6/auth";
const OPENID: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const CARD_ID: &str = "25375059";
// 合成 JSON，使用固定测试密钥 0123456789abcdef 封装，不含真实订单或凭据。
const PREFLIGHT: &[u8] = br#"{"datajson":"9876543210fedcbagfVWr2PSaEthPFsRGZTf9ue62+opoAACtA3e324UEIfMrPVgFsVWBaUO6mIhJ7wSbiMND2kPuFJXqEkgnhDN7MK2P4KSZaUIiJYCHI1I8YM="}"#;
const ORDER: &[u8] = br#"{"datajson":"9876543210fedcbagfVWr2PSaEthPFsRGZTf9rDn2r9bNAlFWWmo+gVJDDnR1hzqMU1x0SJHx6DBmqDoeLz33YJG2hH05d9ibUoRJleFNxeygGGavfXOp5nnbHr18qVqzBN0NUjSVfaY1FkhEgbXMJwXXtoG/teGu715dVllythWwUOHaJtHBoJIJj8="}"#;

type Requests = Arc<Mutex<Vec<(ConnectionMode, HttpMethod, String)>>>;

struct CardTransport {
    route: ConnectionMode,
    requests: Requests,
    probe: Probe,
}

#[async_trait::async_trait]
impl HttpTransport for CardTransport {
    async fn execute(&self, request: HttpRequest) -> domain::Result<HttpResponse> {
        let direct = from_webvpn_url(&request.url)?;
        self.requests
            .lock()
            .unwrap()
            .push((self.route, request.method, direct.clone()));
        let direct = direct.as_str();
        if let Some(response) = sso_fixture_ticket(&request) {
            return Ok(response);
        }
        if direct.contains("/serviceValidate") {
            return Ok(HttpResponse::new(
                200,
                &request.url,
                br#"{"user":"fixture-user","attributes":{"employeeNumber":["TEST-0001"]}}"#
                    .to_vec(),
            ));
        }
        let redirect = |location: String| {
            let mut response = HttpResponse::new(302, &request.url, Vec::new());
            response.headers.insert("Location".into(), vec![location]);
            response
        };
        if direct.starts_with("https://sso.buaa.edu.cn/login?service=") {
            return Ok(redirect(format!("{SERVICE}?ticket=ST-card-fixture")));
        }
        if direct.starts_with(SERVICE) {
            return Ok(redirect(format!(
                "{CARD}/card/goIndex?openid={OPENID}&usertype=6"
            )));
        }
        if direct == format!("{CARD}/card/cardpay/openCardPay") {
            if self.route == ConnectionMode::Direct
                && self.probe.probe(Duration::ZERO) != NetworkState::Campus
            {
                return Err(UbaaError::new(
                    ErrorCode::NetworkError,
                    ErrorKind::Network,
                    true,
                    "合成卡站不可达",
                ));
            }
            return Ok(HttpResponse::new(200, &request.url, PREFLIGHT.to_vec()));
        }
        assert_eq!(request.method, HttpMethod::Post);
        assert_eq!(
            direct,
            format!("{CARD}/card/recharge/rechargeByHct?openid={OPENID}")
        );
        Ok(HttpResponse::new(200, &request.url, ORDER.to_vec()))
    }
}

#[derive(Clone)]
struct Probe(Arc<AtomicBool>);

impl GatewayProbe for Probe {
    fn probe(&self, _: Duration) -> NetworkState {
        if self.0.load(Ordering::SeqCst) {
            NetworkState::Campus
        } else {
            NetworkState::Unknown
        }
    }
}

struct Fixture {
    bridge: BridgeClient,
    root: PathBuf,
    probe: Probe,
    requests: Requests,
}

impl Fixture {
    fn new() -> Self {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/campus_card/tests")
            .join(uuid::Uuid::new_v4().to_string());
        let store = FileSessionStore::new(&root).unwrap();
        let session = RouteSessionSnapshot {
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1000,
        };
        store
            .save_dual(&DualSessionSnapshot::new(
                Some(session.clone()),
                Some(session),
            ))
            .unwrap();
        let requests = Requests::default();
        let probe = Probe(Arc::default());
        let transport = |route| CardTransport {
            route,
            requests: requests.clone(),
            probe: probe.clone(),
        };
        let bridge = BridgeClient::from_core(
            UbaaClient::with_routing_and_probe_ttl(
                transport(ConnectionMode::Direct),
                transport(ConnectionMode::WebVpn),
                store,
                RouteConfig::default(),
                probe.clone(),
                Duration::ZERO,
            )
            .unwrap(),
        );
        Self {
            bridge,
            root,
            probe,
            requests,
        }
    }

    fn order_routes(&self) -> Vec<ConnectionMode> {
        self.requests
            .lock()
            .unwrap()
            .iter()
            .filter_map(|(route, _, url)| {
                url.contains("/recharge/rechargeByHct?").then_some(*route)
            })
            .collect()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

#[tokio::test]
async fn 充值没有预检不得触网() {
    let fixture = Fixture::new();
    let error = fixture
        .bridge
        .campus_recharge_order(CARD_ID.into(), "100".into())
        .await
        .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(fixture.requests.lock().unwrap().is_empty());
}

#[tokio::test]
async fn 卡站自动回退后下单绑定预检实际路线与卡号() {
    let fixture = Fixture::new();
    let preflight = fixture.bridge.campus_recharge_preflight().await.unwrap();
    assert_eq!(preflight.data.idserial, CARD_ID);
    assert_eq!(preflight.route.resolved_route, BridgeConnectionMode::WebVpn);
    let wrong_id = fixture
        .bridge
        .campus_recharge_order("other-card".into(), "100".into())
        .await
        .unwrap_err();
    assert_eq!(wrong_id.code, BridgeErrorCode::OperationConflict);
    assert_eq!(fixture.order_routes(), [] as [ConnectionMode; 0]);
    let order = fixture
        .bridge
        .campus_recharge_order(preflight.data.idserial, "100".into())
        .await
        .unwrap();
    assert_eq!(order.route.resolved_route, BridgeConnectionMode::WebVpn);
    assert_eq!(fixture.order_routes(), [ConnectionMode::WebVpn]);
    let replay = fixture
        .bridge
        .campus_recharge_order(CARD_ID.into(), "100".into())
        .await
        .unwrap_err();
    assert_eq!(replay.code, BridgeErrorCode::OperationConflict);
    assert_eq!(fixture.order_routes(), [ConnectionMode::WebVpn]);
}

#[tokio::test]
async fn 充值换网后不沿新路线下单() {
    let fixture = Fixture::new();
    let preflight = fixture.bridge.campus_recharge_preflight().await.unwrap();
    assert_eq!(preflight.route.resolved_route, BridgeConnectionMode::WebVpn);
    fixture.probe.0.store(true, Ordering::SeqCst);
    let error = fixture
        .bridge
        .campus_recharge_order(preflight.data.idserial, "100".into())
        .await
        .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(fixture.order_routes(), [] as [ConnectionMode; 0]);
}

#[tokio::test]
async fn 同卡的新路线预检不覆盖旧绑定且可显式重新准备() {
    let fixture = Fixture::new();
    let prepared = fixture.bridge.campus_recharge_preflight().await.unwrap();
    fixture.probe.0.store(true, Ordering::SeqCst);
    let error = fixture
        .bridge
        .campus_recharge_preflight()
        .await
        .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::Direct));
    let stale = fixture
        .bridge
        .campus_recharge_order(prepared.data.idserial, "100".into())
        .await
        .unwrap_err();
    assert_eq!(stale.code, BridgeErrorCode::OperationConflict);
    assert_eq!(fixture.order_routes(), [] as [ConnectionMode; 0]);
    let prepared = fixture.bridge.campus_recharge_preflight().await.unwrap();
    assert_eq!(prepared.route.resolved_route, BridgeConnectionMode::Direct);
}

#[tokio::test]
async fn 充值会话修订改变后不得下单() {
    let fixture = Fixture::new();
    let preflight = fixture.bridge.campus_recharge_preflight().await.unwrap();
    let store = FileSessionStore::new(&fixture.root).unwrap();
    let current = store.load_dual().unwrap().unwrap();
    store.save_dual(&current).unwrap();
    let error = fixture
        .bridge
        .campus_recharge_order(preflight.data.idserial, "100".into())
        .await
        .unwrap_err();
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(fixture.order_routes(), [] as [ConnectionMode; 0]);
}
