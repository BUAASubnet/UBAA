use std::sync::{Arc, Mutex};

use async_trait::async_trait;

use crate::connection::{from_webvpn_url, to_webvpn_url};
use crate::domain::ConnectionMode;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{FileSessionStore, SessionMutation, SessionSnapshot, SessionStore};

#[test]
fn 包装跳转沿固定路线继续且回调令牌不再发请求() {
    for (case, mode, callback_is_final) in [
        ("direct-location", ConnectionMode::Direct, false),
        ("direct-final", ConnectionMode::Direct, true),
        ("vpn-location", ConnectionMode::WebVpn, false),
        ("vpn-final", ConnectionMode::WebVpn, true),
    ] {
        let root =
            std::env::temp_dir().join(format!("ubaa-bykc-redirect-{case}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).unwrap();
        let snapshot = SessionSnapshot {
            mode,
            cookies: vec![],
            authenticated_at: 1_000,
            last_activity: 1_001,
        };
        assert!(matches!(
            store
                .compare_exchange(store.load_versioned().unwrap().revision, Some(&snapshot))
                .unwrap(),
            SessionMutation::Applied { .. }
        ));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let mut runtime = ClientRuntime::new(
            mode,
            RedirectTransport {
                requests: Arc::clone(&requests),
                callback_is_final,
            },
            store,
        )
        .unwrap();
        let result = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(super::super::auth::ensure_login(&mut runtime))
            .unwrap();
        assert_eq!(result.token, "fixture-token");
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 2, "{case}");
        for request in requests.iter() {
            let parsed = url::Url::parse(&request.url).unwrap();
            assert_eq!(
                parsed.host_str() == Some("d.buaa.edu.cn"),
                mode == ConnectionMode::WebVpn,
                "{case}"
            );
            assert_ne!(
                url::Url::parse(&from_webvpn_url(&request.url).unwrap())
                    .unwrap()
                    .path(),
                "/cas-login"
            );
        }
        assert_eq!(
            url::Url::parse(&from_webvpn_url(&requests[1].url).unwrap())
                .unwrap()
                .host_str(),
            Some("sso.buaa.edu.cn")
        );
        let _ = std::fs::remove_dir_all(root);
    }
}

struct RedirectTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    callback_is_final: bool,
}

#[async_trait]
impl HttpTransport for RedirectTransport {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        let mut requests = self.requests.lock().unwrap();
        let count = requests.len();
        requests.push(request.clone());
        let target = match count {
            0 => to_webvpn_url("https://sso.buaa.edu.cn/login?service=fixture").unwrap(),
            1 => to_webvpn_url("https://bykc.buaa.edu.cn/cas-login?token=fixture-token").unwrap(),
            _ => panic!("回调令牌已可提取，不应继续请求"),
        };
        if count == 1 && self.callback_is_final {
            return Ok(HttpResponse::new(200, target, vec![]));
        }
        let mut response = HttpResponse::new(302, request.url, vec![]);
        response.headers.insert("location".into(), vec![target]);
        Ok(response)
    }
}
