use super::*;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use ubaa_core::facade::testing::{
    from_webvpn_url, sso_fixture_ticket, with_routing_in_config_directory,
};
use ubaa_core::facade::{CgyyPurposeSource, ErrorKind, RouteClient, UbaaError};

const PAGE: &[u8] = include_bytes!("../../../../../fixtures/readonly/campus-network-required.html");
const BYKC_LOGIN: &str = "/sscv/cas/login";
const BYKC_WRITE: &str = "/sscv/choseCourse";
const BYXT_PROBE: &str = "/jwapp/sys/homeapp/api/home/currentUser.do";
const SSO_VALIDATE: &str = "/serviceValidate";
const CGYY_CODES: &str = "/venue-zhjs-server/api/codes";
const BYKC_READ: &str = "/sscv/queryStatisticByUserId";

type Visits = Arc<Mutex<Vec<(ConnectionMode, String)>>>;

#[derive(Clone, Copy)]
enum Reply {
    Page,
    PaddedPage(usize),
    NonSuccess,
    JsonWithNotice,
    NormalShortHtml,
    Timeout,
}

struct Transport {
    mode: ConnectionMode,
    visits: Visits,
    blocked: Option<(&'static str, Reply)>,
}

#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = url::Url::parse(&from_webvpn_url(&request.url).unwrap()).unwrap();
        let path = url.path();
        self.visits.lock().unwrap().push((self.mode, path.into()));
        if let Some((target, reply)) = self.blocked
            && path == target
        {
            if matches!(reply, Reply::Timeout) {
                return Err(UbaaError::new(
                    ErrorCode::Timeout,
                    ErrorKind::Network,
                    true,
                    "合成 WebVPN 超时",
                ));
            }
            let body = match reply {
                Reply::Page | Reply::NonSuccess => PAGE.to_vec(),
                Reply::PaddedPage(size) => {
                    let mut body = PAGE.to_vec();
                    body.resize(size, b' ');
                    body
                }
                Reply::JsonWithNotice => {
                    r#"{"status":"0","data":{"validCount":0},"message":"请在校园网环境下访问"}"#
                        .as_bytes()
                        .to_vec()
                }
                Reply::NormalShortHtml => {
                    "<html><body><h1>请在校园网环境下访问</h1><p>课程说明</p></body></html>"
                        .as_bytes()
                        .to_vec()
                }
                Reply::Timeout => unreachable!(),
            };
            let status = if matches!(reply, Reply::NonSuccess) {
                503
            } else {
                200
            };
            let mut response = HttpResponse::new(status, request.url, body);
            let content_type = if matches!(reply, Reply::JsonWithNotice) {
                "application/json"
            } else {
                "text/html; charset=UTF-8"
            };
            response
                .headers
                .insert("Content-Type".into(), vec![content_type.into()]);
            return Ok(response);
        }
        if let Some(response) = sso_fixture_ticket(&request) {
            return Ok(response);
        }
        let body: &[u8] = match path {
            BYKC_LOGIN => {
                let mut response = HttpResponse::new(302, request.url, Vec::new());
                response.headers.insert("Location".into(), vec!["https://bykc.buaa.edu.cn/cas-login?token=fixture".into()]);
                return Ok(response);
            }
            BYKC_READ => br#"{"status":"0","data":{"validCount":0}}"#,
            "/venue-zhjs-server/sso/manageLogin" => {
                let mut response = HttpResponse::new(200, request.url, Vec::new());
                response.headers.insert("Set-Cookie".into(), vec!["sso_buaa_zhjs_token=fixture; Path=/".into()]);
                return Ok(response);
            }
            "/wengine-vpn/cookie" => b"sso_buaa_zhjs_token=fixture;",
            "/venue-zhjs-server/api/login" => br#"{"code":200,"data":{"token":{"access_token":"fixture"}}}"#,
            CGYY_CODES => r#"{"code":200,"data":[{"key":99,"name":"示例类"}]}"#.as_bytes(),
            "/sscv/queryCourseById" => r#"{"status":"0","data":{"id":42,"courseName":"可选课程","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":1,"courseMaxCount":10,"selected":false}}"#.as_bytes(),
            "/personal/frontend/data/info" => r#"{"e":0,"d":{"info":{"identity":"本科生","depart":"示例学院"}}}"#.as_bytes(),
            BYXT_PROBE => br#"{"code":"0","datas":{"userId":"synthetic-user"}}"#,
            "/jwapp/sys/homeapp/api/home/student/schoolCalendars.do" => include_bytes!("../../../../../fixtures/readonly/schedule-terms.json"),
            "/jwapp/sys/homeapp/index.do" => b"fixture landing",
            SSO_VALIDATE => br#"{"user":"fixture-user","attributes":{"employeeNumber":["TEST-0001"]}}"#,
            _ => panic!("未预期的合成请求路径：{path}"),
        };
        Ok(HttpResponse::new(200, request.url, body.to_vec()))
    }
}

struct Case {
    client: UbaaClient,
    root: crate::test_tmp::TestTempDir,
    visits: Visits,
}

impl Case {
    fn new(
        policy: RoutePolicy,
        direct: Option<(&'static str, Reply)>,
        vpn: Option<(&'static str, Reply)>,
    ) -> Self {
        Self::with_probe(policy, direct, vpn, CountingProbe(Arc::default()))
    }

    fn with_probe(
        policy: RoutePolicy,
        direct: Option<(&'static str, Reply)>,
        vpn: Option<(&'static str, Reply)>,
        probe: impl GatewayProbe + 'static,
    ) -> Self {
        let root =
            crate::test_tmp::test_temp_dir("ubaa_core_facade_campus_network_required").unwrap();
        let store = FileSessionStore::new(&root).unwrap();
        let slot = RouteSessionSnapshot {
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1000,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
        let visits = Visits::default();
        let transport = |mode, blocked| Transport {
            mode,
            visits: visits.clone(),
            blocked,
        };
        let mut client = with_routing_in_config_directory(
            transport(ConnectionMode::Direct, direct),
            transport(ConnectionMode::WebVpn, vpn),
            &root,
            probe,
        )
        .unwrap();
        client.set_default_route_policy(policy).unwrap();
        Self {
            client,
            root,
            visits,
        }
    }

    fn modes_for(&self, path: &str) -> Vec<ConnectionMode> {
        self.visits
            .lock()
            .unwrap()
            .iter()
            .filter_map(|(mode, visited)| (visited == path).then_some(*mode))
            .collect()
    }

    fn assert_remembered(&self, domain: &str, started_at: u64) {
        let recorded: serde_json::Value =
            serde_json::from_slice(&std::fs::read(self.root.join("domain_routes.json")).unwrap())
                .unwrap();
        let expires = recorded[domain].as_u64().expect("域名应写入偏好记录");
        assert!(expires.abs_diff(started_at + 86_400) <= 5);
        assert!(expires.abs_diff(now_seconds() + 86_400) <= 5);
    }
}

fn now_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

fn assert_campus_error(error: &UbaaError) {
    assert_eq!(error.code, ErrorCode::NetworkError, "{error}");
    assert_eq!(error.kind, ErrorKind::Network);
    assert_eq!(error.diagnostic().stage.as_deref(), Some("network"));
    assert_eq!(
        error.diagnostic().reason.as_deref(),
        Some("campus_network_required")
    );
    assert!(!error.retryable);
    assert!(error.message.contains("WebVPN"));
}

#[tokio::test]
async fn auto_博雅登录提示触发回退并记住域名() {
    let started_at = now_seconds();
    let mut case = Case::new(RoutePolicy::Auto, Some((BYKC_LOGIN, Reply::Page)), None);
    let result = case
        .client
        .bykc_statistics()
        .await
        .unwrap_or_else(|error| panic!("{error}"));
    assert_eq!(result.resolution.mode, ConnectionMode::WebVpn);
    assert!(result.resolution.diagnostic.used_fallback);
    assert_eq!(
        case.modes_for(BYKC_LOGIN),
        [ConnectionMode::Direct, ConnectionMode::WebVpn]
    );
    case.assert_remembered("bykc.buaa.edu.cn", started_at);
}

#[tokio::test]
async fn auto_教务身份探测提示触发回退并记住域名() {
    let started_at = now_seconds();
    let mut case = Case::new(RoutePolicy::Auto, Some((BYXT_PROBE, Reply::Page)), None);
    let result = case.client.schedule_terms().await.unwrap();
    assert_eq!(result.data[0].item_code, "2025-2026-1");
    assert_eq!(result.resolution.mode, ConnectionMode::WebVpn);
    assert!(result.resolution.diagnostic.used_fallback);
    assert_eq!(
        case.modes_for(BYXT_PROBE),
        [ConnectionMode::Direct, ConnectionMode::WebVpn]
    );
    case.assert_remembered("byxt.buaa.edu.cn", started_at);
}

#[tokio::test]
async fn 显式直连保留提示原因且不回退() {
    let mut case = Case::new(RoutePolicy::Direct, Some((BYKC_LOGIN, Reply::Page)), None);
    let error = case.client.bykc_statistics().await.unwrap_err();
    assert_campus_error(&error.error);
    assert!(!error.resolution.unwrap().diagnostic.used_fallback);
    assert_eq!(case.modes_for(BYKC_LOGIN), [ConnectionMode::Direct]);
}

#[tokio::test]
async fn auto_回退超时保留网关错误且不再重试() {
    let mut case = Case::new(
        RoutePolicy::Auto,
        Some((BYKC_LOGIN, Reply::Page)),
        Some((BYKC_LOGIN, Reply::Timeout)),
    );
    let error = case.client.bykc_statistics().await.unwrap_err();
    assert_eq!(
        case.modes_for(BYKC_LOGIN),
        [ConnectionMode::Direct, ConnectionMode::WebVpn]
    );
    assert!(error.resolution.unwrap().diagnostic.used_fallback);
    assert_eq!(error.error.code, ErrorCode::Timeout);
    assert!(!error.error.retryable);
    assert!(!case.root.join("domain_routes.json").exists());
}

#[tokio::test]
async fn 普通页面和显式网关收到提示均沿用原错误() {
    for (policy, direct, vpn, expected) in [
        (
            RoutePolicy::Auto,
            Some((BYKC_LOGIN, Reply::PaddedPage(1025))),
            None,
            ConnectionMode::Direct,
        ),
        (
            RoutePolicy::Auto,
            Some((BYKC_LOGIN, Reply::NormalShortHtml)),
            None,
            ConnectionMode::Direct,
        ),
        (
            RoutePolicy::WebVpn,
            None,
            Some((BYKC_LOGIN, Reply::Page)),
            ConnectionMode::WebVpn,
        ),
    ] {
        let mut case = Case::new(policy, direct, vpn);
        let error = case.client.bykc_statistics().await.unwrap_err();
        assert_eq!(error.error.code, ErrorCode::UpstreamChanged);
        assert!(!error.resolution.unwrap().diagnostic.used_fallback);
        assert_eq!(case.modes_for(BYKC_LOGIN), [expected]);
    }
}

#[tokio::test]
async fn 恰好一千零二十四字节仍识别且非成功状态和有效_json_不识别() {
    let mut case = Case::new(
        RoutePolicy::Direct,
        Some((BYKC_LOGIN, Reply::PaddedPage(1024))),
        None,
    );
    assert_campus_error(&case.client.bykc_statistics().await.unwrap_err().error);

    let mut case = Case::new(
        RoutePolicy::Direct,
        Some((BYKC_LOGIN, Reply::NonSuccess)),
        None,
    );
    let error = case.client.bykc_statistics().await.unwrap_err();
    assert_ne!(
        error.error.diagnostic().reason.as_deref(),
        Some("campus_network_required")
    );
    assert_eq!(case.modes_for(BYKC_LOGIN), [ConnectionMode::Direct]);

    let mut case = Case::new(
        RoutePolicy::Auto,
        Some((BYKC_READ, Reply::JsonWithNotice)),
        None,
    );
    assert!(
        !case
            .client
            .bykc_statistics()
            .await
            .unwrap()
            .resolution
            .diagnostic
            .used_fallback
    );
    assert_eq!(case.modes_for(BYKC_READ), [ConnectionMode::Direct]);
}

#[tokio::test]
async fn 校园网重探按当前网络决定是否回退() {
    struct Reprobe {
        calls: Arc<AtomicUsize>,
        next: NetworkState,
    }
    impl GatewayProbe for Reprobe {
        fn probe(&self, _: Duration) -> NetworkState {
            if self.calls.fetch_add(1, Ordering::SeqCst) == 0 {
                NetworkState::Campus
            } else {
                self.next
            }
        }
    }
    for next in [NetworkState::Campus, NetworkState::OffCampus] {
        let calls = Arc::new(AtomicUsize::new(0));
        let mut case = Case::with_probe(
            RoutePolicy::Auto,
            Some((BYKC_LOGIN, Reply::Page)),
            None,
            Reprobe {
                calls: calls.clone(),
                next,
            },
        );
        let result = case.client.bykc_statistics().await;
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        if next == NetworkState::Campus {
            assert_campus_error(&result.unwrap_err().error);
            assert_eq!(case.modes_for(BYKC_LOGIN), [ConnectionMode::Direct]);
            assert!(!case.root.join("domain_routes.json").exists());
        } else {
            let resolution = result.unwrap().resolution;
            assert!(resolution.diagnostic.used_fallback);
            assert_eq!(resolution.diagnostic.network, next);
            assert_eq!(
                case.modes_for(BYKC_LOGIN),
                [ConnectionMode::Direct, ConnectionMode::WebVpn]
            );
        }
    }
}

#[tokio::test]
async fn 研讨室用途共享回退且只确认上游成功() {
    for webvpn_reply in [Some((CGYY_CODES, Reply::Page)), None] {
        let started_at = now_seconds();
        let mut case = Case::new(
            RoutePolicy::Auto,
            Some((CGYY_CODES, Reply::Page)),
            webvpn_reply,
        );
        let result = case.client.cgyy_purpose_types_diagnostics().await.unwrap();
        assert_eq!(
            case.modes_for(CGYY_CODES),
            [ConnectionMode::Direct, ConnectionMode::WebVpn]
        );
        assert!(result.resolution.diagnostic.used_fallback);
        if webvpn_reply.is_some() {
            assert_eq!(result.data.source, CgyyPurposeSource::StaticFallback);
            assert!(!case.root.join("domain_routes.json").exists());
        } else {
            assert_eq!(result.data.source, CgyyPurposeSource::Upstream);
            assert_eq!(result.data.items[0].key, 99);
            case.assert_remembered("cgyy.buaa.edu.cn", started_at);
        }
    }
    let mut case = Case::new(RoutePolicy::Auto, Some((CGYY_CODES, Reply::Page)), None);
    let result = case.client.cgyy_purpose_types().await.unwrap();
    assert!(result.resolution.diagnostic.used_fallback);
    assert_eq!(result.data[0].key, 99);
}

#[tokio::test]
async fn 写入准备收到提示不发送最终请求也不回退() {
    let mut case = Case::new(RoutePolicy::Auto, Some((BYKC_LOGIN, Reply::Page)), None);
    let error = case.client.bykc_select_course(42).await.unwrap_err();
    assert_campus_error(&error.error);
    assert_eq!(case.modes_for(BYKC_LOGIN), [ConnectionMode::Direct]);
    assert_eq!(case.modes_for(BYKC_WRITE), Vec::<ConnectionMode>::new());
}

#[tokio::test]
async fn 固定路线读与云盘登录的提示不可重试() {
    let mut case = Case::new(
        RoutePolicy::Direct,
        Some(("/anyshare/oauth2/login", Reply::Page)),
        None,
    );
    assert_campus_error(&case.client.bhpan_login().await.unwrap_err());
    let transport = Transport {
        mode: ConnectionMode::Direct,
        blocked: Some(("/login", Reply::Page)),
        visits: Visits::default(),
    };
    let route_root = case.root.join("route-client");
    let store = FileSessionStore::new(&route_root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1000,
        })
        .unwrap();
    let mut route = RouteClient::with_transport(ConnectionMode::Direct, transport, store).unwrap();
    assert_campus_error(&route.ihome_config().await.unwrap_err());
    assert_campus_error(&route.finance_incomes().await.unwrap_err());
}

#[tokio::test]
async fn 写请求发送后收到提示结果未知且只发送一次() {
    let mut case = Case::new(RoutePolicy::Auto, Some((BYKC_WRITE, Reply::Page)), None);
    let error = case.client.bykc_select_course(42).await.unwrap_err();
    assert_eq!(case.modes_for(BYKC_WRITE), [ConnectionMode::Direct]);
    assert!(!error.resolution.unwrap().diagnostic.used_fallback);
    assert_eq!(error.error.code, ErrorCode::OutcomeUnknown);
    assert!(!error.error.retryable);
    assert_eq!(
        error.error.diagnostic().reason.as_deref(),
        Some("campus_network_required")
    );
    assert!(error.error.message.contains("结果未知"));
}

#[tokio::test]
async fn 会话检查返回的提示不可重试() {
    let mut case = Case::new(RoutePolicy::Direct, Some((SSO_VALIDATE, Reply::Page)), None);
    let outcome = case.client.auth_status().await.unwrap();
    let error = outcome.routes[0].error.as_ref().unwrap();
    assert_eq!(error.code, "network_error");
    assert_eq!(
        error.context.as_ref().unwrap().reason.as_deref(),
        Some("campus_network_required")
    );
    assert!(!error.retryable);
}
