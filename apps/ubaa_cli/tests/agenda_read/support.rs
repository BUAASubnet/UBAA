use async_trait::async_trait;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use ubaa_core::facade::{
    AgendaContent, AgendaItem, AgendaKind, AgendaTime, DualLoginInput, SecretValue, UbaaClient,
};
use ubaa_test_support::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, from_webvpn_url,
};
use uuid::Uuid;

#[derive(Clone)]
pub struct LoginMock {
    pub identity: Option<&'static str>,
    pub calls: Arc<AtomicUsize>,
    pub failure_status: u16,
}
#[async_trait]
impl HttpTransport for LoginMock {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::facade::Result<HttpResponse> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let direct = from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
        if direct.ends_with("/login") && direct.contains("sso.buaa.edu.cn") {
            return Ok(HttpResponse::new(302, request.url, Vec::new()));
        }
        if direct.contains("/api/uc/status") || direct.contains("/api/uc/userinfo") {
            let Some(id) = self.identity else {
                return Ok(HttpResponse::new(
                    self.failure_status,
                    request.url,
                    Vec::new(),
                ));
            };
            let body = serde_json::json!({"code":0,"data":{"schoolid":id,"username":id,"name":"合成账号"}});
            return Ok(HttpResponse::new(
                200,
                request.url,
                serde_json::to_vec(&body).unwrap(),
            ));
        }
        if direct.contains("/api/login")
            || direct.contains("/wengine-vpn/cookie")
            || direct.ends_with("/logout")
        {
            return Ok(HttpResponse::new(200, request.url, Vec::new()));
        }
        panic!("Mock 收到未登记的请求路径");
    }
}
pub fn root() -> PathBuf {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_cli_a_fix")
        .join(Uuid::new_v4().simple().to_string());
    std::fs::create_dir_all(&root).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
    }
    root.canonicalize().unwrap()
}
pub fn client(
    root: &Path,
    direct: Option<&'static str>,
    webvpn: Option<&'static str>,
) -> (UbaaClient, Arc<AtomicUsize>) {
    let calls = Arc::new(AtomicUsize::new(0));
    (
        UbaaClient::with_routing(
            LoginMock {
                identity: direct,
                failure_status: 401,
                calls: calls.clone(),
            },
            LoginMock {
                identity: webvpn,
                failure_status: 401,
                calls: calls.clone(),
            },
            FileSessionStore::new(root).unwrap(),
            ubaa_test_support::RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
            NeverProbe,
        )
        .unwrap(),
        calls,
    )
}
pub async fn login(client: &mut UbaaClient, id: &str) -> ubaa_core::facade::LoginOutcome {
    client
        .login(DualLoginInput {
            username: id.into(),
            password: SecretValue::new("synthetic-only"),
        })
        .await
        .unwrap()
}
pub fn item(title: &str) -> AgendaItem {
    let now =
        AgendaTime::new(chrono::DateTime::parse_from_rfc3339("2026-11-01T10:00:00+08:00").unwrap());
    AgendaItem::new(
        AgendaContent {
            kind: AgendaKind::Task,
            title: title.into(),
            location: None,
            notes: None,
            color: None,
            start: None,
            end: None,
            all_day: false,
            due: None,
        },
        now,
    )
}

pub struct NeverProbe;
impl ubaa_test_support::GatewayProbe for NeverProbe {
    fn probe(&self, _: std::time::Duration) -> ubaa_core::facade::NetworkState {
        panic!("固定路线不得探测学校网络")
    }
}
