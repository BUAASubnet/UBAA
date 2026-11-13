use super::*;
use crate::api::client::{BridgeConnectionMode, BridgeErrorCode};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};
use std::time::Duration;
use ubaa_core::facade::testing::from_webvpn_url;
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, NetworkState, RoutePolicy, UbaaClient,
};
use ubaa_test_support::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    Result, RouteConfig, RouteSessionSnapshot,
};

struct Probe;
impl GatewayProbe for Probe {
    fn probe(&self, _: Duration) -> NetworkState {
        NetworkState::OffCampus
    }
}

#[derive(Clone, Default)]
struct Transport {
    direct_failure: bool,
    read_failure: bool,
    requests: Arc<AtomicUsize>,
    visits: Arc<Mutex<Vec<ConnectionMode>>>,
    writes: Arc<AtomicUsize>,
}
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.fetch_add(1, Ordering::SeqCst);
        let upstream = from_webvpn_url(&request.url).unwrap();
        let (host, path) = upstream
            .strip_prefix("https://")
            .unwrap()
            .split_once('/')
            .unwrap();
        let path = format!("/{}", path.split('?').next().unwrap());
        let vpn = request.url.starts_with("https://d.buaa.edu.cn/");
        let mode = if vpn {
            ConnectionMode::WebVpn
        } else {
            ConnectionMode::Direct
        };
        let mut response = HttpResponse::new(200, request.url.clone(), vec![]);
        if host == "sso.buaa.edu.cn" {
            if path.as_str() == "/login" {
                response.status = 302;
                response.headers.insert("Location".into(), vec!["https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-print-fixture".into()]);
            } else {
                assert_eq!(path.as_str(), "/serviceValidate");
                response.body =
                    br#"{"user":"fixture-user","attributes":{"employeeNumber":["TEST-0001"]}}"#
                        .to_vec();
            }
            return Ok(response);
        }
        assert_eq!(host, "print.lib.buaa.edu.cn");
        self.visits.lock().unwrap().push(mode);
        if self.direct_failure && !vpn {
            return Err(UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "合成网络失败",
            ));
        }
        response.body = match path.as_str() {
            "/client/new/cprintPc/cprint.html" => vec![],
            "/api/client/Auth/Check" => br#"{"code":0,"result":{"szLogonName":"TEST-0001"}}"#.to_vec(),
            "/api/client/PrintJob/Get" | "/api/client/Scan/Get" if self.read_failure => {
                return Err(UbaaError::new(ErrorCode::UpstreamChanged, ErrorKind::Upstream, false, "合成读取失败"));
            }
            "/api/client/PrintJob/Get" => br#"{"code":0,"result":[
                {"dwJobId":15,"szJobName":"first.pdf","dwCreateDate":"20261113","dwCreateTime":"123456","dwCopies":1,"szPaperDetail":"[]"},
                {"dwJobId":16,"szJobName":"second.pdf","dwCreateDate":"20261113","dwCreateTime":"123456","dwCopies":1,"szPaperDetail":"[]"}
            ]}"#.to_vec(),
            "/api/client/PrintJob/Del" => {
                self.writes.fetch_add(1, Ordering::SeqCst);
                let body = String::from_utf8(request.body).unwrap();
                if body.contains(r#""dwJobId":"16""#) { return Err(UbaaError::new(ErrorCode::NetworkError, ErrorKind::Network, true, "合成发送后断网")); }
                br#"{"code":0}"#.to_vec()
            }
            "/api/client/CloudPrint/Upload" => {
                self.writes.fetch_add(1, Ordering::SeqCst);
                return Err(UbaaError::new(ErrorCode::NetworkError, ErrorKind::Network, true, "合成发送后断网"));
            }
            path => panic!("未登记的合成请求：{path}"),
        };
        Ok(response)
    }
}

fn client(
    policy: RoutePolicy,
    sessions: bool,
    transport: &Transport,
) -> (BridgeClient, std::path::PathBuf) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/cloud_print_route/tests")
        .join(uuid::Uuid::new_v4().to_string());
    let store = FileSessionStore::new(&root).unwrap();
    if sessions {
        let slot = RouteSessionSnapshot {
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1000,
        };
        store
            .save_dual(&DualSessionSnapshot::new(Some(slot.clone()), Some(slot)))
            .unwrap();
    }
    let mut config = RouteConfig::default();
    config.default = policy;
    (
        BridgeClient::from_core(
            UbaaClient::with_routing(transport.clone(), transport.clone(), store, config, Probe)
                .unwrap(),
        ),
        root,
    )
}

fn options() -> BridgePrintOptions {
    BridgePrintOptions {
        color: false,
        paper: BridgePrintPaper::A4,
        duplex: BridgePrintDuplex::Single,
        copies: 1,
        from_page: None,
        to_page: None,
    }
}

#[tokio::test]
async fn 各云打印接口缺会话时保留所需路线且不发请求() {
    for (policy, expected) in [
        (RoutePolicy::Direct, BridgeConnectionMode::Direct),
        (RoutePolicy::WebVpn, BridgeConnectionMode::WebVpn),
    ] {
        let transport = Transport::default();
        let (bridge, root) = client(policy, false, &transport);
        let errors = [
            bridge.cloud_print_documents(false).await.err().unwrap(),
            bridge
                .cloud_print_preview("15".into(), 1)
                .await
                .err()
                .unwrap(),
            bridge.cloud_print_scan("15".into()).await.err().unwrap(),
            bridge
                .cloud_print_scan_pdf(vec!["15".into(), "16".into()])
                .await
                .err()
                .unwrap(),
            bridge.cloud_print_stations().await.err().unwrap(),
            bridge
                .cloud_print_records(
                    "20260101".into(),
                    "20261113".into(),
                    BridgePrintRecordKind::Print,
                    1,
                )
                .await
                .err()
                .unwrap(),
            bridge
                .cloud_print_upload(
                    vec![BridgePrintFile {
                        path: "unused.pdf".into(),
                        name: "unused.pdf".into(),
                    }],
                    options(),
                )
                .await
                .err()
                .unwrap(),
            bridge
                .cloud_print_delete(false, vec!["15".into()])
                .await
                .err()
                .unwrap(),
        ];
        for error in errors {
            assert_eq!(error.code, BridgeErrorCode::AuthenticationRequired);
            assert_eq!(error.resolved_route, Some(expected));
        }
        assert_eq!(transport.requests.load(Ordering::SeqCst), 0);
        bridge.dispose().await.unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn 自动回退后的失败标注网关且保留原错误分类() {
    let transport = Transport {
        direct_failure: true,
        read_failure: true,
        ..Transport::default()
    };
    let (bridge, root) = client(RoutePolicy::Auto, true, &transport);
    let error = bridge.cloud_print_documents(false).await.err().unwrap();
    assert_eq!(error.code, BridgeErrorCode::UpstreamChanged);
    assert!(!error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::WebVpn));
    assert_eq!(
        *transport.visits.lock().unwrap(),
        [
            ConnectionMode::Direct,
            ConnectionMode::WebVpn,
            ConnectionMode::WebVpn,
            ConnectionMode::WebVpn
        ]
    );
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 上传删除逐项错误保留固定路线且发送后不重试() {
    for (policy, expected) in [
        (RoutePolicy::Direct, BridgeConnectionMode::Direct),
        (RoutePolicy::Auto, BridgeConnectionMode::Direct),
        (RoutePolicy::WebVpn, BridgeConnectionMode::WebVpn),
    ] {
        let transport = Transport::default();
        let (bridge, root) = client(policy, true, &transport);
        let result = bridge
            .cloud_print_delete(false, vec!["15".into(), "16".into()])
            .await
            .unwrap();
        assert!(result[0].is_none());
        let error = result[1].as_ref().unwrap();
        assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
        assert!(!error.retryable);
        assert_eq!(error.resolved_route, Some(expected));
        assert_eq!(transport.writes.load(Ordering::SeqCst), 2);
        let file = root.join("fixture.pdf");
        std::fs::write(&file, b"%PDF-1.7\n%%EOF\n").unwrap();
        let result = bridge
            .cloud_print_upload(
                vec![BridgePrintFile {
                    path: file.to_string_lossy().into(),
                    name: "fixture.pdf".into(),
                }],
                options(),
            )
            .await
            .unwrap();
        let error = result[0].as_ref().unwrap();
        assert_eq!(error.code, BridgeErrorCode::OutcomeUnknown);
        assert!(!error.retryable);
        assert_eq!(error.resolved_route, Some(expected));
        assert_eq!(transport.writes.load(Ordering::SeqCst), 3);
        bridge.dispose().await.unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn 选路前的本地参数错误不伪造路线() {
    let transport = Transport::default();
    let (bridge, root) = client(RoutePolicy::WebVpn, true, &transport);
    let mut incomplete = options();
    incomplete.from_page = Some(1);
    let errors = [
        bridge
            .cloud_print_upload(vec![], incomplete)
            .await
            .err()
            .unwrap(),
        bridge
            .cloud_print_upload(vec![], options())
            .await
            .err()
            .unwrap(),
        bridge
            .cloud_print_delete(false, vec![])
            .await
            .err()
            .unwrap(),
        bridge
            .cloud_print_scan_pdf(vec!["15".into()])
            .await
            .err()
            .unwrap(),
    ];
    for error in errors {
        assert_eq!(error.code, BridgeErrorCode::InvalidInput);
        assert_eq!(error.resolved_route, None);
    }
    assert_eq!(transport.requests.load(Ordering::SeqCst), 0);
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}
