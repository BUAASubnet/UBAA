use super::cloud_print::{PAGE, QUEUE_PAGE, upload_result};
use crate::domain::ConnectionMode;
use crate::error::ErrorCode;
use crate::ports::HttpResponse;

fn upload_reply(location: Option<&str>) -> HttpResponse {
    let mut reply = HttpResponse::new(302, PAGE, Vec::new());
    if let Some(location) = location {
        reply
            .headers
            .insert("Location".into(), vec![location.into()]);
    }
    reply
}

#[test]
fn cloud_print_upload_requires_an_explicit_result_on_the_queue_origin() {
    for location in [
        None,
        Some(QUEUE_PAGE),
        Some("https://example.invalid/client/new/cprintPc/printDoc.html?code=0"),
        Some("/client/new/cprintPc/printDoc.html?code=0&code=1"),
    ] {
        let error = upload_result(&upload_reply(location), ConnectionMode::Direct).unwrap_err();
        assert_eq!(error.code, ErrorCode::OutcomeUnknown);
        assert!(!error.retryable);
    }
    upload_result(
        &upload_reply(Some(
            "/client/new/cprintPc/printDoc.html?t=100&code=0&message=",
        )),
        ConnectionMode::Direct,
    )
    .unwrap();
}

#[test]
fn cloud_print_upstream_refusal_does_not_expose_untrusted_detail() {
    let error = upload_result(
        &upload_reply(Some(
            "/client/new/cprintPc/printDoc.html?code=4&message=fixture-private-value",
        )),
        ConnectionMode::Direct,
    )
    .unwrap_err();
    assert_ne!(error.code, ErrorCode::OutcomeUnknown);
    assert!(!error.message.contains("fixture-private-value"));
}

#[test]
fn cloud_print_webvpn_upload_requires_a_business_queue_redirect() {
    let route = ConnectionMode::WebVpn;
    let wrap = |url: &str| crate::connection::to_webvpn_url(url).unwrap();
    let mut reply = upload_reply(None);
    reply.final_url = wrap(super::cloud_print::endpoint("CloudPrint/Upload").as_str());
    let success = wrap(&format!("{QUEUE_PAGE}?code=0"));
    let unrelated = wrap("https://sso.buaa.edu.cn/client/new/cprintPc/printDoc.html?code=0");
    for (location, valid) in [
        (success.as_str(), true),
        (url::Url::parse(&success).unwrap().path(), false),
        ("/client/new/cprintPc/printDoc.html?code=0", true),
        ("/login?code=0", false),
        (unrelated.as_str(), false),
    ] {
        reply
            .headers
            .insert("Location".into(), vec![location.into()]);
        if valid {
            upload_result(&reply, route).unwrap();
        } else {
            assert_eq!(
                upload_result(&reply, route).unwrap_err().code,
                ErrorCode::OutcomeUnknown
            );
        }
    }
}

#[test]
fn cloud_print_uses_four_lanes_and_reuses_the_first_available_lane() {
    use futures_util::{FutureExt as _, future::poll_fn};
    use std::cell::RefCell;
    use std::task::Poll;
    use tokio::sync::Notify;

    let gates: Vec<_> = (0..6).map(|_| Notify::new()).collect();
    let sent = RefCell::new(Vec::new());
    let batch = crate::facade::cloud_print::run_four_ordered((0..6).collect(), |index| {
        let gates = &gates;
        let sent = &sent;
        async move {
            sent.borrow_mut().push(index);
            gates[index].notified().await;
            if index == 1 {
                Err(ErrorCode::OutcomeUnknown)
            } else {
                Ok(index)
            }
        }
    });
    let mut batch = std::pin::pin!(batch);
    assert!(batch.as_mut().now_or_never().is_none());
    assert_eq!(*sent.borrow(), [0, 1, 2, 3]);
    gates[1].notify_one();
    assert!(batch.as_mut().now_or_never().is_none());
    assert_eq!(
        *sent.borrow(),
        [0, 1, 2, 3, 4],
        "一个较早的慢任务不应占用已释放的通道"
    );
    for gate in &gates {
        gate.notify_one();
    }
    let result = poll_fn(|cx| match batch.as_mut().poll(cx) {
        Poll::Ready(result) => Poll::Ready(result),
        Poll::Pending => panic!("所有响应已经放行"),
    })
    .now_or_never()
    .unwrap();
    assert_eq!(
        result,
        [
            Ok(0),
            Err(ErrorCode::OutcomeUnknown),
            Ok(2),
            Ok(3),
            Ok(4),
            Ok(5)
        ]
    );
    assert_eq!(
        *sent.borrow(),
        [0, 1, 2, 3, 4, 5],
        "结果未知的文件也只提交一次"
    );
}

mod cas {
    use super::{HttpResponse, PAGE};
    use crate::domain::ConnectionMode;
    use crate::ports::{HttpMethod, HttpRequest, HttpTransport};
    use crate::runtime::ClientRuntime;
    use crate::session::{
        CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession,
    };
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    use serde_json::{Value, json};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::SystemTime;

    #[derive(Clone)]
    struct Store(VersionedSession);
    impl SessionStore for Store {
        fn load_versioned(&self) -> crate::error::Result<VersionedSession> {
            Ok(self.0.clone())
        }
        fn compare_exchange(
            &self,
            _: u64,
            _: Option<&SessionSnapshot>,
        ) -> crate::error::Result<SessionMutation> {
            panic!("云打印不能持久化学校或打印站 Cookie");
        }
    }

    const CALLBACK: &str = "/api/client/Auth/SSOLogin";

    fn bootstrap_json() -> Value {
        let mut bootstrap =
            url::Url::parse("https://print.lib.buaa.edu.cn/authcenter/toLoginPage").unwrap();
        bootstrap
            .query_pairs_mut()
            .append_pair(
                "redirectUrl",
                &format!("http://print.lib.buaa.edu.cn{CALLBACK}"),
            )
            .append_pair(
                "targetPageUrl",
                &STANDARD.encode(format!("{PAGE}?sessionId=synthetic")),
            );
        json!({"code":0,"result":bootstrap.as_str()})
    }

    fn reply(
        url: &str,
        body: &Value,
        location: Option<String>,
        cookie: Option<&str>,
    ) -> HttpResponse {
        let mut response = HttpResponse::new(
            if location.is_some() { 302 } else { 200 },
            url,
            body.to_string().into_bytes(),
        );
        if let Some(location) = location {
            response.headers.insert("Location".into(), vec![location]);
        }
        if let Some(cookie) = cookie {
            response
                .headers
                .insert("Set-Cookie".into(), vec![cookie.into()]);
        }
        response
    }

    struct Transport(AtomicUsize, ConnectionMode);
    #[async_trait::async_trait]
    impl HttpTransport for Transport {
        #[allow(clippy::too_many_lines)]
        async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
            const TARGET: &str =
                "https://print.lib.buaa.edu.cn/authcenter/doAuth/0123456789abcdef0123456789abcdef";
            const UNI_ENTRY: &str = "/api/client/Auth/UniEntry";
            let step = self.0.fetch_add(1, Ordering::SeqCst);
            let webvpn = self.1 == ConnectionMode::WebVpn;
            let wrap = |target: &str| crate::connection::to_webvpn_url(target).unwrap();
            let direct_url = crate::connection::from_webvpn_url(&request.url).unwrap();
            let url = url::Url::parse(&direct_url).unwrap();
            if webvpn {
                assert_eq!(request.url, wrap(&direct_url));
            }
            let cookie = request.headers.get("Cookie").map_or("", String::as_str);
            if step == 4 {
                assert_eq!(url.host_str(), Some("sso.buaa.edu.cn"));
                assert!(cookie.contains("fixture-cas"));
            } else {
                assert_eq!(url.host_str(), Some("print.lib.buaa.edu.cn"));
                assert!(!cookie.contains("fixture-cas"));
            }
            let (path, body, location, new_cookie) = match step {
                0 => (
                    "/client/new/cprintPc/cprint.html",
                    json!(null),
                    None,
                    Some("SESSIONID=fixture-print; Path=/; Secure"),
                ),
                1 | 9
                    if request.method != HttpMethod::Post
                        || !request.body.is_empty()
                        || request.headers.get("Content-Length").map(String::as_str)
                            != Some("0") =>
                {
                    return Ok(HttpResponse::new(411, &request.url, Vec::new()));
                }
                1 => ("/api/client/Auth/Check", json!({"code":4}), None, None),
                2 => {
                    let page = if webvpn { wrap(PAGE) } else { PAGE.into() };
                    assert_eq!(url.query_pairs().next().unwrap().1, page);
                    ("/api/client/Auth/SSoPage", bootstrap_json(), None, None)
                }
                3 => {
                    let mut sso = url::Url::parse("https://sso.buaa.edu.cn/login").unwrap();
                    sso.query_pairs_mut().append_pair("service", TARGET);
                    (
                        "/authcenter/toLoginPage",
                        json!(null),
                        Some(sso.to_string()),
                        None,
                    )
                }
                4 => (
                    "/login",
                    json!(null),
                    Some(format!("{TARGET}?ticket=ST-fixture")),
                    Some("SSO_TEST=fixture-cas-response; Domain=buaa.edu.cn; Path=/; Secure"),
                ),
                5 => (
                    "/authcenter/doAuth/0123456789abcdef0123456789abcdef",
                    json!(null),
                    Some(format!("http://print.lib.buaa.edu.cn{CALLBACK}?fixture=1")),
                    None,
                ),
                6 => (
                    CALLBACK,
                    json!(null),
                    Some(format!(
                        "{UNI_ENTRY}?SessionId=fixture-entry&Func=fixture-function"
                    )),
                    Some("SESSIONID=fixture-continued; Path=/; Secure"),
                ),
                7 => {
                    assert_eq!(request.method, HttpMethod::Get);
                    assert_eq!(
                        url.query(),
                        Some("SessionId=fixture-entry&Func=fixture-function")
                    );
                    assert!(cookie.contains("SESSIONID=fixture-continued"));
                    (
                        UNI_ENTRY,
                        json!(null),
                        Some(PAGE.into()),
                        Some("OSESSIONID=fixture-auth; Path=/; Secure"),
                    )
                }
                8 => ("/client/new/cprintPc/cprint.html", json!(null), None, None),
                9 => {
                    assert!(cookie.contains("OSESSIONID=fixture-auth"));
                    (
                        "/api/client/Auth/Check",
                        json!({"code":0,"result":{"szLogonName":"fixture-account"}}),
                        None,
                        None,
                    )
                }
                _ => panic!("额外的请求"),
            };
            assert_eq!(url.path(), path);
            let location = location.map(|target| {
                if webvpn && target.starts_with("https://") {
                    wrap(&target)
                } else {
                    target
                }
            });
            let cookie = if webvpn {
                new_cookie.filter(|_| step != 4).map(|cookie| {
                    let print = wrap("https://print.lib.buaa.edu.cn/");
                    let path = url::Url::parse(&print).unwrap().path().to_owned();
                    cookie.replace("Path=/;", &format!("Path={path};"))
                })
            } else {
                new_cookie.map(str::to_owned)
            };
            Ok(reply(&request.url, &body, location, cookie.as_deref()))
        }
    }

    #[tokio::test]
    async fn cloud_print_cas_completes_unified_entry_without_mixing_cookies() {
        const SSO: &str = "https://sso.buaa.edu.cn/login";
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            check_cas(mode, SSO).await;
        }
    }

    async fn check_cas(mode: ConnectionMode, sso_url: &str) {
        let webvpn = mode == ConnectionMode::WebVpn;
        let (origin, cookie) = if webvpn {
            let origin = crate::connection::to_webvpn_url(sso_url).unwrap();
            let path = origin.strip_prefix("https://d.buaa.edu.cn").unwrap();
            let prefix = path.strip_suffix("login").unwrap();
            let cookie = format!("CASTGC=fixture-cas; Path={prefix}; Secure");
            (origin, cookie)
        } else {
            (
                sso_url.into(),
                "CASTGC=fixture-cas; Domain=buaa.edu.cn; Path=/; Secure".into(),
            )
        };
        let mut jar = CookieJar::default();
        let mut response = HttpResponse::new(200, &origin, Vec::new());
        response.headers.insert("Set-Cookie".into(), vec![cookie]);
        jar.store_response(&response, &origin, SystemTime::now())
            .unwrap();
        let parent = ClientRuntime::new(
            mode,
            Transport(AtomicUsize::new(0), mode),
            Store(VersionedSession {
                revision: 1,
                snapshot: Some(SessionSnapshot {
                    mode,
                    authenticated_at: 1,
                    last_activity: 1,
                    cookies: jar.cookies().to_vec(),
                }),
            }),
        )
        .unwrap();
        let mut print = parent.fork_with_cookie_filter(|_| webvpn);
        let mut sso = (!webvpn).then(|| parent.fork_with_cookie_filter(|_| true));
        super::super::cloud_print::auth::login(&mut print, sso.as_mut())
            .await
            .unwrap();
    }
}

#[test]
fn cloud_print_station_uses_website_status_masks_and_deduplicates_paper_sizes() {
    use serde_json::json;
    let row = json!({
        "szName": "合成设备", "dwStatus": 5, "dwProperty": 13,
        "dwTrayPaper1": 9, "dwTrayPaper2": 9, "dwTrayPaper3": 8
    });
    let station =
        super::cloud_print::read::station(&row, Some(&json!({"szName":"合成打印点"}))).unwrap();
    assert_eq!(station.state, "不可用");
    assert_eq!(station.group.as_deref(), Some("合成打印点"));
    assert_eq!(station.papers, ["A4", "A3"]);
    assert_eq!(station.capabilities, ["打印", "扫描", "彩色"]);
}
