use super::super::{get_terms, get_week, get_weeks};
use crate::domain::ConnectionMode;
use crate::error::Result;
use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
use async_trait::async_trait;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct Transport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    login_page: bool,
}
#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let direct = crate::connection::from_webvpn_url(&request.url)
            .unwrap_or_else(|_| request.url.clone());
        let url = url::Url::parse(&direct).unwrap();
        if url.path().ends_with("currentUser.do") {
            return Ok(HttpResponse::new(
                200,
                "https://byxt.buaa.edu.cn/jwapp/sys/byrhmhsy/index.do",
                Vec::new(),
            ));
        }
        assert_eq!(url.host_str(), Some("gsmis.buaa.edu.cn"));
        if url.path().ends_with("index.do") {
            assert_eq!(request.method, HttpMethod::Get);
            if self.login_page {
                return Ok(HttpResponse::new(
                    200,
                    request.url,
                    b"<title>CAS Login</title>synthetic-private".to_vec(),
                ));
            }
            if url.query().is_none() {
                let mut response = HttpResponse::new(302, request.url, Vec::new());
                response
                    .headers
                    .insert("Location".into(), vec![format!("{direct}?ready=1")]);
                return Ok(response);
            }
            return Ok(HttpResponse::new(
                200,
                request.url,
                b"<html>ready</html>".to_vec(),
            ));
        }
        assert_eq!(request.method, HttpMethod::Post);
        assert_eq!(
            request.headers["Accept"],
            "application/json, text/javascript, */*; q=0.01"
        );
        assert_eq!(request.headers["X-Requested-With"], "XMLHttpRequest");
        assert!(request.headers["Referer"].contains("d.buaa.edu.cn"));
        let body = if url.path().ends_with("kfdxnxqcx.do") {
            assert!(request.body.is_empty());
            assert!(!request.headers.contains_key("Content-Type"));
            r#"{"code":"0","datas":{"kfdxnxqcx":{"totalSize":1,"rows":[{"XNXQDM":"20261","XNXQDM_DISPLAY":"示例学期"}]}}}"#.to_owned()
        } else {
            assert!(url.path().ends_with("loadXskbData.do"));
            assert_eq!(
                request.headers["Content-Type"],
                "application/x-www-form-urlencoded"
            );
            assert_eq!(request.body, b"ZC=&XNXQDM=20261&XH=&XQDM=");
            super::tests::BODY.to_owned()
        };
        Ok(HttpResponse::new(200, request.url, body.into_bytes()))
    }
}
fn client(
    label: &str,
    session: bool,
    login_page: bool,
) -> (
    ClientRuntime,
    Arc<Mutex<Vec<HttpRequest>>>,
    std::path::PathBuf,
) {
    let root = std::env::temp_dir().join(format!("ubaa-gsmis-{label}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    if session {
        store
            .save(&SessionSnapshot {
                mode: ConnectionMode::WebVpn,
                cookies: vec![],
                authenticated_at: 1000,
                last_activity: 1001,
            })
            .unwrap();
    }
    let requests = Arc::new(Mutex::new(Vec::new()));
    (
        ClientRuntime::new(
            ConnectionMode::WebVpn,
            Transport {
                requests: requests.clone(),
                login_page,
            },
            store,
        )
        .unwrap(),
        requests,
        root,
    )
}
#[test]
fn gsmis在webvpn精确请求并仅在成功后记忆来源() {
    let (mut client, requests, root) = client("success", true, false);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        assert_eq!(get_terms(&mut client).await.unwrap()[0].item_code, "20261");
        assert_eq!(get_weeks(&mut client, "20261").await.unwrap().len(), 4);
        assert_eq!(
            get_week(&mut client, "20261", 1)
                .await
                .unwrap()
                .section_times
                .len(),
            3
        );
        assert_eq!(
            requests
                .lock()
                .unwrap()
                .iter()
                .filter(|r| r.url.contains("currentUser.do"))
                .count(),
            1
        );
        assert!(
            requests
                .lock()
                .unwrap()
                .iter()
                .all(|r| r.url.starts_with("https://d.buaa.edu.cn/"))
        );
        client.clear_feature_state();
        get_terms(&mut client).await.unwrap();
        assert_eq!(
            requests
                .lock()
                .unwrap()
                .iter()
                .filter(|r| r.url.contains("currentUser.do"))
                .count(),
            2
        );
    });
    let _ = std::fs::remove_dir_all(root);
}
#[test]
fn gsmis认证失败不伪造空学期或成功来源且无会话零请求() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let (mut client, requests, root) = client("login", true, true);
    for _ in 0..2 {
        let error = runtime.block_on(get_terms(&mut client)).unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
        assert!(!error.message.contains("synthetic-private"));
    }
    assert!(!super::active(&client));
    assert_eq!(requests.lock().unwrap().len(), 4);
    let _ = std::fs::remove_dir_all(root);
    let (mut client, requests, root) = self::client("empty", false, false);
    assert!(runtime.block_on(get_terms(&mut client)).is_err());
    assert!(requests.lock().unwrap().is_empty());
    let _ = std::fs::remove_dir_all(root);
}
