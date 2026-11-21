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
    behavior: TransportBehavior,
    upload_gate: Option<Arc<UploadGate>>,
    requests: Arc<AtomicUsize>,
    visits: Arc<Mutex<Vec<ConnectionMode>>>,
    writes: Arc<AtomicUsize>,
}

struct UploadGate {
    requests: AtomicUsize,
    sent: tokio::sync::Barrier,
    campus_reply: tokio::sync::Semaphore,
}

#[derive(Clone, Copy, Default, Eq, PartialEq)]
enum TransportBehavior {
    #[default]
    Normal,
    AutoReadFailure,
    CampusBatch,
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
        if self.behavior == TransportBehavior::AutoReadFailure && !vpn {
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
            "/api/client/PrintJob/Get" | "/api/client/Scan/Get"
                if self.behavior == TransportBehavior::AutoReadFailure =>
            {
                return Err(UbaaError::new(ErrorCode::UpstreamChanged, ErrorKind::Upstream, false, "合成读取失败"));
            }
            "/api/client/PrintJob/Get" => br#"{"code":0,"result":[
                {"dwJobId":15,"szJobName":"first.pdf","dwCreateDate":"20261113","dwCreateTime":"123456","dwCopies":1,"szPaperDetail":"[]"},
                {"dwJobId":16,"szJobName":"second.pdf","dwCreateDate":"20261113","dwCreateTime":"123456","dwCopies":1,"szPaperDetail":"[]"},
                {"dwJobId":17,"szJobName":"third.pdf","dwCreateDate":"20261113","dwCreateTime":"123456","dwCopies":1,"szPaperDetail":"[]"}
            ]}"#.to_vec(),
            "/api/client/PrintJob/Del" => {
                self.writes.fetch_add(1, Ordering::SeqCst);
                let body = String::from_utf8(request.body).unwrap();
                if self.behavior == TransportBehavior::CampusBatch
                    && body.contains(r#""dwJobId":"16""#)
                {
                    return Ok(HttpResponse::new(
                        200,
                        request.url,
                        include_bytes!("../../../../../fixtures/readonly/campus-network-required.html").to_vec(),
                    ));
                }
                if body.contains(r#""dwJobId":"16""#) { return Err(UbaaError::new(ErrorCode::NetworkError, ErrorKind::Network, true, "合成发送后断网")); }
                br#"{"code":0}"#.to_vec()
            }
            "/api/client/CloudPrint/Upload" => {
                self.writes.fetch_add(1, Ordering::SeqCst);
                if self.behavior == TransportBehavior::CampusBatch {
                    return self.campus_upload_response(request).await;
                }
                return Err(UbaaError::new(ErrorCode::NetworkError, ErrorKind::Network, true, "合成发送后断网"));
            }
            path => panic!("未登记的合成请求：{path}"),
        };
        Ok(response)
    }
}

impl Transport {
    async fn campus_upload_response(&self, request: HttpRequest) -> Result<HttpResponse> {
        let gate = self.upload_gate.as_ref().unwrap();
        let index = gate.requests.fetch_add(1, Ordering::SeqCst);
        if index < 4 {
            gate.sent.wait().await;
        }
        let body = String::from_utf8_lossy(&request.body);
        if body.contains("filename=\"a.pdf\"") {
            gate.campus_reply.add_permits(3);
            return Ok(HttpResponse::new(
                200,
                request.url,
                include_bytes!("../../../../../fixtures/readonly/campus-network-required.html")
                    .to_vec(),
            ));
        }
        if index < 4 {
            gate.campus_reply.acquire().await.unwrap().forget();
        }
        let code = if body.contains("filename=\"b.pdf\"") {
            17
        } else {
            0
        };
        let mut response = HttpResponse::new(302, request.url, Vec::new());
        response.headers.insert(
            "Location".into(),
            vec![format!(
                "https://print.lib.buaa.edu.cn/client/new/cprintPc/printDoc.html?code={code}"
            )],
        );
        Ok(response)
    }
}

fn client(
    policy: RoutePolicy,
    sessions: bool,
    transport: &Transport,
) -> (BridgeClient, ubaa_test_support::TestTempDir) {
    let root = ubaa_test_support::test_temp_dir("ubaa_flutter_bridge_api_cloud_print").unwrap();
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
        behavior: TransportBehavior::AutoReadFailure,
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

fn campus_batch_transport() -> Transport {
    Transport {
        behavior: TransportBehavior::CampusBatch,
        upload_gate: Some(Arc::new(UploadGate {
            requests: AtomicUsize::new(0),
            sent: tokio::sync::Barrier::new(4),
            campus_reply: tokio::sync::Semaphore::new(0),
        })),
        ..Transport::default()
    }
}

#[tokio::test]
async fn 云打印批量删除按发送边界保留逐项结果() {
    let transport = campus_batch_transport();
    let (bridge, root) = client(RoutePolicy::Direct, true, &transport);
    let delete = bridge
        .cloud_print_delete(false, vec!["15".into(), "16".into(), "17".into()])
        .await
        .unwrap();
    assert!(delete[0].is_none());
    let sent = delete[1].as_ref().unwrap();
    assert_eq!(sent.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!sent.retryable);
    assert_eq!(
        error_reason(sent).as_deref(),
        Some("campus_network_required")
    );
    let unattempted = delete[2].as_ref().unwrap();
    assert_eq!(unattempted.code, BridgeErrorCode::NetworkError);
    assert!(!unattempted.retryable);
    assert!(unattempted.message.contains("未发送"));
    assert_eq!(
        error_reason(unattempted).as_deref(),
        Some("campus_network_required")
    );
    assert_eq!(transport.writes.load(Ordering::SeqCst), 2);
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 云打印批量上传停发排队任务并保留输入顺序() {
    let transport = campus_batch_transport();
    let (bridge, root) = client(RoutePolicy::Direct, true, &transport);
    let directory = root.join("uploads");
    std::fs::create_dir_all(&directory).unwrap();
    let files = ["a.pdf", "b.pdf", "c.pdf", "d.pdf", "e.pdf"]
        .into_iter()
        .map(|name| {
            let path = directory.join(name);
            std::fs::write(&path, b"%PDF-1.7\n%%EOF\n").unwrap();
            BridgePrintFile {
                path: path.to_string_lossy().into(),
                name: name.into(),
            }
        })
        .collect();
    let upload = tokio::time::timeout(
        Duration::from_secs(5),
        bridge.cloud_print_upload(files, options()),
    )
    .await
    .expect("首批四个上传应同时发送并全部收尾")
    .unwrap();
    assert_eq!(upload.len(), 5);
    assert_eq!(
        transport
            .upload_gate
            .as_ref()
            .unwrap()
            .requests
            .load(Ordering::SeqCst),
        4
    );
    assert_eq!(transport.writes.load(Ordering::SeqCst), 4);
    let sent = upload[0].as_ref().unwrap();
    assert_eq!(sent.code, BridgeErrorCode::OutcomeUnknown);
    assert!(!sent.retryable);
    assert_eq!(
        error_reason(sent).as_deref(),
        Some("campus_network_required")
    );
    let second = upload[1].as_ref().unwrap();
    assert_eq!(second.code, BridgeErrorCode::BusinessRejected);
    assert_eq!(error_upstream_code(second), Some(17));
    assert!(upload[2].is_none());
    assert!(upload[3].is_none());
    let unattempted = upload[4].as_ref().unwrap();
    assert_eq!(unattempted.code, BridgeErrorCode::NetworkError);
    assert!(!unattempted.retryable);
    assert_eq!(
        error_reason(unattempted).as_deref(),
        Some("campus_network_required")
    );
    assert_eq!(
        unattempted.message,
        "未发送：该服务当前仅限校园网访问，可切换到 WebVPN 后重试"
    );
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

fn error_reason(error: &BridgeError) -> Option<String> {
    error
        .diagnostic_json
        .as_deref()
        .and_then(ubaa_core::facade::ErrorDiagnostic::from_json)
        .and_then(|diagnostic| diagnostic.reason)
}

fn error_upstream_code(error: &BridgeError) -> Option<i64> {
    error
        .diagnostic_json
        .as_deref()
        .and_then(ubaa_core::facade::ErrorDiagnostic::from_json)
        .and_then(|diagnostic| diagnostic.upstream_code)
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
