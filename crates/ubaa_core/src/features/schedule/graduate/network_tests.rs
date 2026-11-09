use super::super::{get_terms, get_today_for_date, get_week, get_weeks};
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
    current_terms: String,
}
#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let direct = crate::connection::from_webvpn_url(&request.url)
            .unwrap_or_else(|_| request.url.clone());
        let url = url::Url::parse(&direct).unwrap();
        if url.host_str() == Some("it.buaa.edu.cn") {
            assert_eq!(url.path(), "/personal/frontend/data/info");
            return Ok(HttpResponse::new(
                200,
                request.url,
                r#"{"e":0,"d":{"info":{"identity":"研究生","depart":"示例学院"}}}"#
                    .as_bytes()
                    .to_vec(),
            ));
        }
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
        assert_eq!(
            request.headers["Referer"].starts_with("https://d.buaa.edu.cn/"),
            request.url.starts_with("https://d.buaa.edu.cn/")
        );
        let referer = crate::connection::from_webvpn_url(&request.headers["Referer"])
            .unwrap_or_else(|_| request.headers["Referer"].clone());
        let app = if url.path().contains("/wdksapp/") {
            "wdksapp"
        } else {
            "wdkbapp"
        };
        assert_eq!(
            referer,
            format!("https://gsmis.buaa.edu.cn/gsapp/sys/{app}/*default/index.do")
        );
        let body = if url.path().ends_with("kfdxnxqcx.do") {
            assert!(request.body.is_empty());
            assert!(!request.headers.contains_key("Content-Type"));
            r#"{"code":"0","datas":{"kfdxnxqcx":{"totalSize":2,"rows":[{"XNXQDM":"20262","XNXQDM_DISPLAY":"下一学期"},{"XNXQDM":"20261","XNXQDM_DISPLAY":"当前学期"}]}}}"#.to_owned()
        } else if url.path().ends_with("getXnxqList.do") {
            assert_eq!(
                request.headers["Content-Type"],
                "application/x-www-form-urlencoded"
            );
            assert!(request.body.is_empty());
            self.current_terms.clone()
        } else {
            assert!(url.path().ends_with("loadXskbData.do"));
            assert_eq!(
                request.headers["Content-Type"],
                "application/x-www-form-urlencoded"
            );
            if request.body == b"ZC=&XNXQDM=20262&XH=&XQDM=" {
                r#"{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}"#.to_owned()
            } else {
                assert_eq!(request.body, b"ZC=&XNXQDM=20261&XH=&XQDM=");
                super::tests::BODY.to_owned()
            }
        };
        Ok(HttpResponse::new(200, request.url, body.into_bytes()))
    }
}
fn client(
    label: &str,
    session: bool,
    login_page: bool,
    mode: ConnectionMode,
    current_terms: &str,
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
                mode,
                cookies: vec![],
                authenticated_at: 1000,
                last_activity: 1001,
            })
            .unwrap();
    }
    let requests = Arc::new(Mutex::new(Vec::new()));
    (
        ClientRuntime::new(
            mode,
            Transport {
                requests: requests.clone(),
                login_page,
                current_terms: current_terms.to_owned(),
            },
            store,
        )
        .unwrap(),
        requests,
        root,
    )
}
#[test]
fn gsmis按门户身份分流并在webvpn精确请求() {
    let (mut client, requests, root) = client(
        "success",
        true,
        false,
        ConnectionMode::WebVpn,
        CURRENT_TERMS,
    );
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let terms = get_terms(&mut client).await.unwrap();
        assert_eq!(
            terms.iter().find(|t| t.selected).unwrap().item_code,
            "20261"
        );
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
                .filter(|r| r.url.contains("/personal/frontend/data/info"))
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
                .filter(|r| r.url.contains("/personal/frontend/data/info"))
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
    let (mut client, requests, root) =
        client("login", true, true, ConnectionMode::WebVpn, CURRENT_TERMS);
    for _ in 0..2 {
        let error = runtime.block_on(get_terms(&mut client)).unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
        assert!(!error.message.contains("synthetic-private"));
    }

    assert_eq!(requests.lock().unwrap().len(), 3);
    let _ = std::fs::remove_dir_all(root);
    let (mut client, requests, root) =
        self::client("empty", false, false, ConnectionMode::WebVpn, CURRENT_TERMS);
    assert!(runtime.block_on(get_terms(&mut client)).is_err());
    assert!(requests.lock().unwrap().is_empty());
    let _ = std::fs::remove_dir_all(root);
}

const CURRENT_TERMS: &str = r#"{"datas":[{"DM":"20262","MC":"下一学期","SFDQXQ":"0"},{"DM":"20261","MC":"当前学期","SFDQXQ":"1"}]}"#;

#[test]
fn gsmis提前开放下一学期仍返回当前学期与今日课程() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let (mut client, requests, root) = client(
            &format!("current-{mode:?}"),
            true,
            false,
            mode,
            CURRENT_TERMS,
        );
        runtime.block_on(async {
            let terms = get_terms(&mut client).await.unwrap();
            assert_eq!(terms[0].item_code, "20262");
            assert!(!terms[0].selected);
            assert!(terms[1].selected);
            assert_eq!(
                get_today_for_date(&mut client, "2026-09-14")
                    .await
                    .unwrap()
                    .len(),
                1
            );
            client.clear_feature_state();
            assert_eq!(
                get_terms(&mut client)
                    .await
                    .unwrap()
                    .into_iter()
                    .find(|t| t.selected)
                    .unwrap()
                    .item_code,
                "20261"
            );
        });
        let requests = requests.lock().unwrap();
        assert!(
            requests
                .iter()
                .filter(|r| r.url.contains("loadXskbData.do"))
                .all(|r| r.body == b"ZC=&XNXQDM=20261&XH=&XQDM=")
        );
        assert!(requests.iter().all(
            |r| r.url.starts_with("https://d.buaa.edu.cn/") == (mode == ConnectionMode::WebVpn)
        ));
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn gsmis当前学期不明确时不请求其他学期课表() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for (index, terms) in [
        r#"{"datas":[]}"#,
        r#"{"datas":[{"DM":"20261","MC":"当前学期"}]}"#,
        r#"{"datas":[{"DM":"20261","MC":"学期一","SFDQXQ":"1"},{"DM":"20262","MC":"学期二","SFDQXQ":"1"}]}"#,
        r#"{"datas":[{"DM":"20253","MC":"尚未开放的当前学期","SFDQXQ":"1"}]}"#,
    ].iter().enumerate() {
        let (mut client, requests, root) = client(&format!("unknown-{index}"), true, false, ConnectionMode::Direct, terms);
        let error = runtime.block_on(get_terms(&mut client)).unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
        assert!(error.message.contains("当前学期"));
        assert!(!requests.lock().unwrap().iter().any(|r| r.url.contains("loadXskbData.do")));
        let _ = std::fs::remove_dir_all(root);
    }
}

#[test]
fn gsmis显式学期不依赖当前标志且当前空课表不回退() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let (mut client, requests, root) =
        client("explicit", true, false, ConnectionMode::Direct, "不可用");
    assert_eq!(
        runtime
            .block_on(get_week(&mut client, "20261", 2))
            .unwrap()
            .arranged_list
            .len(),
        1
    );
    assert!(
        !requests
            .lock()
            .unwrap()
            .iter()
            .any(|r| r.url.contains("wdksapp"))
    );
    let _ = std::fs::remove_dir_all(root);
    let terms = CURRENT_TERMS
        .replace("20262", "temporary")
        .replace("20261", "20262")
        .replace("temporary", "20261");
    let (mut client, requests, root) =
        self::client("current-empty", true, false, ConnectionMode::Direct, &terms);
    assert!(
        runtime
            .block_on(get_today_for_date(&mut client, "2026-09-14"))
            .unwrap()
            .is_empty()
    );
    assert!(
        requests
            .lock()
            .unwrap()
            .iter()
            .filter(|r| r.url.contains("loadXskbData.do"))
            .all(|r| r.body == b"ZC=&XNXQDM=20262&XH=&XQDM=")
    );
    let _ = std::fs::remove_dir_all(root);
}
