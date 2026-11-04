use super::{auth, wire};
use crate::domain::{ConnectionMode, SecretValue};
use crate::error::Result;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::FileSessionStore;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct Navigation(Arc<Mutex<VecDeque<Step>>>);
struct Step {
    url: String,
    status: u16,
    location: Option<&'static str>,
    cookie: Option<&'static str>,
    challenge: bool,
}
#[async_trait::async_trait]
impl HttpTransport for Navigation {
    async fn execute(&self, r: HttpRequest) -> Result<HttpResponse> {
        let step = self
            .0
            .lock()
            .unwrap()
            .pop_front()
            .expect("云盘认证不得访问未声明地址");
        assert_eq!(r.url, step.url);
        assert_eq!(r.method, crate::ports::HttpMethod::Get);
        if step.challenge {
            assert!(
                r.headers
                    .get("Cookie")
                    .is_some_and(|c| c.contains("login_challenge=fixture-challenge"))
            );
        }
        let mut response = HttpResponse::new(step.status, r.url, Vec::new());
        if let Some(location) = step.location {
            response
                .headers
                .insert("Location".into(), vec![location.into()]);
        }
        if let Some(cookie) = step.cookie {
            response
                .headers
                .insert("Set-Cookie".into(), vec![cookie.into()]);
        }
        Ok(response)
    }
}
impl Navigation {
    fn push(
        &self,
        url: &str,
        status: u16,
        location: Option<&'static str>,
        cookie: Option<&'static str>,
        challenge: bool,
    ) {
        self.0.lock().unwrap().push_back(Step {
            url: url.into(),
            status,
            location,
            cookie,
            challenge,
        });
    }
}
fn runtime(n: Navigation) -> (ClientRuntime, std::path::PathBuf) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/auth_tests")
        .join(uuid::Uuid::new_v4().to_string());
    let runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        n,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    (runtime, root)
}
fn run(f: impl std::future::Future<Output = ()>) {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(f);
}
#[test]
fn 云盘认证使用编码service并在回调后清理临时challenge() {
    run(async {
        let n = Navigation::default();
        n.push(
            "https://bhpan.buaa.edu.cn/anyshare/oauth2/login?redirect=%2Fanyshare%2Fzh-cn%2Fportal",
            303,
            Some("/oauth2/signin?login_challenge=fixture-challenge&ignored=fixture"),
            None,
            false,
        );
        n.push("https://bhpan.buaa.edu.cn/oauth2/signin?login_challenge=fixture-challenge&ignored=fixture",200,None,None,false);
        n.push("https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbhpan.buaa.edu.cn%2Foauth2%2Fsignin",302,Some("https://bhpan.buaa.edu.cn/anyshare/oauth2/login/callback"),None,false);
        n.push(
            "https://bhpan.buaa.edu.cn/anyshare/oauth2/login/callback",
            200,
            None,
            Some("client.oauth2_token=fixture-token; Path=/; Secure"),
            true,
        );
        let (mut runtime, root) = runtime(n.clone());
        let token: SecretValue = auth::login(&mut runtime).await.unwrap();
        assert_eq!(token.expose_secret(), "fixture-token");
        assert!(!format!("{token:?}").contains("fixture-token"));
        assert!(
            runtime
                .cookie_value("login_challenge", wire::ORIGIN)
                .unwrap()
                .is_none()
        );
        assert!(n.0.lock().unwrap().is_empty());
        drop(runtime);
        std::fs::remove_dir_all(root).unwrap();
    });
}
#[test]
fn 跨域回调和缺token立即失败且不重试() {
    run(async {
        for external in [true, false] {
            let n = Navigation::default();
            n.push("https://bhpan.buaa.edu.cn/anyshare/oauth2/login?redirect=%2Fanyshare%2Fzh-cn%2Fportal",302,Some(if external {"https://example.test/anyshare/oauth2/login/callback"}else{"/anyshare/oauth2/login/callback"}),None,false);
            if !external {
                n.push(
                    "https://bhpan.buaa.edu.cn/anyshare/oauth2/login/callback",
                    200,
                    None,
                    None,
                    false,
                );
                n.push(
                    "https://bhpan.buaa.edu.cn/anyshare/oauth2/login/refreshToken",
                    200,
                    None,
                    None,
                    false,
                );
            }
            let (mut runtime, root) = runtime(n.clone());
            assert!(auth::login(&mut runtime).await.is_err());
            assert!(n.0.lock().unwrap().is_empty());
            assert!(
                runtime
                    .cookie_value("login_challenge", wire::ORIGIN)
                    .unwrap()
                    .is_none()
            );
            drop(runtime);
            std::fs::remove_dir_all(root).unwrap();
        }
    });
}
