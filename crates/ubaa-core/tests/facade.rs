use std::sync::Arc;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, NetworkState, ReadonlyFeature, Result, RoutePolicy, UbaaClient,
    YgdkClockinSubmitRequest, YgdkPhotoUpload, YgdkSubmitTarget,
};

#[path = "facade/bootstrap.rs"]
mod bootstrap;
#[path = "facade/cgyy.rs"]
mod cgyy;
#[path = "facade/routing.rs"]
mod routing;
#[path = "facade/ygdk.rs"]
mod ygdk;

#[test]
fn aggregate_facade_opens_without_config_or_session() {
    let root = test_root("fresh");
    let _ = std::fs::remove_dir_all(&root);

    let client = UbaaClient::open(&root).unwrap();

    assert!(client.active_routes().is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct CountingTransport(Arc<AtomicUsize>);

#[derive(Clone)]
struct TaggedTransport {
    calls: Arc<AtomicUsize>,
    status: u16,
}

#[derive(Clone)]
struct CgyyWebVpnTransport {
    requests: Arc<std::sync::Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for CgyyWebVpnTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let mut response = match path.as_str() {
            "/wengine-vpn/cookie" => HttpResponse::new(
                200,
                request.url.clone(),
                b"sso_buaa_zhjs_token=sso-webvpn;".to_vec(),
            ),
            path if path.ends_with("/venue-zhjs-server/sso/manageLogin") => {
                HttpResponse::new(200, request.url.clone(), Vec::new())
            }
            path if path.ends_with("/venue-zhjs-server/api/login") => HttpResponse::new(
                200,
                request.url.clone(),
                br#"{"code":200,"data":{"token":{"access_token":"webvpn-access"}}}"#
                    .to_vec(),
            ),
            path if path.ends_with("/venue-zhjs-server/api/front/website/venues") => {
                HttpResponse::new(
                    200,
                    request.url,
                    r#"{"code":200,"data":[{"id":101,"siteName":"WebVPN 场馆","venueName":"场馆","campusName":"校区"}]}"#
                        .as_bytes()
                        .to_vec(),
                )
            }
            _ => panic!("未预期的 WebVPN Cgyy 请求: {path}"),
        };
        if path.ends_with("/sso/manageLogin") {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=sso-webvpn; Path=/".into()],
            );
        }
        Ok(response)
    }
}

#[async_trait]
impl HttpTransport for TaggedTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Ok(HttpResponse::new(self.status, request.url, Vec::new()))
    }
}

#[async_trait]
impl HttpTransport for CountingTransport {
    async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        panic!("route readiness preflight must run before HTTP")
    }
}

#[derive(Clone)]
struct StaticTransport(HttpResponse);

#[async_trait]
impl HttpTransport for StaticTransport {
    async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
        Ok(self.0.clone())
    }
}

#[derive(Clone)]
struct EmptyJudgeTransport(Arc<AtomicUsize>);

#[async_trait]
impl HttpTransport for EmptyJudgeTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        if request.url == "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F"
        {
            let mut response = HttpResponse::new(302, request.url, Vec::new());
            response
                .headers
                .insert("Location".into(), vec!["https://judge.buaa.edu.cn/".into()]);
            return Ok(response);
        }
        if request.url == "https://judge.buaa.edu.cn/" {
            return Ok(HttpResponse::new(200, request.url, b"judge ready".to_vec()));
        }
        if request.url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" {
            return Ok(HttpResponse::new(200, request.url, b"no courses".to_vec()));
        }
        panic!("unexpected Judge facade request")
    }
}

#[derive(Clone)]
struct CountingProbe(Arc<AtomicUsize>);

impl GatewayProbe for CountingProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.0.fetch_add(1, Ordering::SeqCst);
        NetworkState::OffCampus
    }
}

struct NeverProbe;

struct CampusProbe;

impl GatewayProbe for CampusProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        NetworkState::Campus
    }
}

impl GatewayProbe for NeverProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        panic!("explicit policies must not run the gateway probe")
    }
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT_TEST_ROOT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-facade-{label}-{}-{}",
        std::process::id(),
        NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed)
    ))
}

fn valid_ygdk_submit_request() -> YgdkClockinSubmitRequest {
    YgdkClockinSubmitRequest {
        target: YgdkSubmitTarget {
            classify_id: 1,
            item_id: 2,
        },
        start_time: "2026-04-01 08:00".into(),
        end_time: "2026-04-01 09:00".into(),
        place: Some("操场".into()),
        share_to_square: false,
        photo: YgdkPhotoUpload {
            bytes: b"JPEG".to_vec(),
            file_name: "p.jpg".into(),
            mime_type: "image/jpeg".into(),
        },
    }
}
