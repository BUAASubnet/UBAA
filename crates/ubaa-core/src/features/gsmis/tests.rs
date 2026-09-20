use super::*;
use crate::domain::ConnectionMode;
use crate::ports::{HttpMethod, HttpTransport};
use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
use std::sync::{Arc, Mutex};

struct Transport<F>(F);

#[test]
fn unknown_identity_blocks_all_academic_requests_before_network() {
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        for account in [None, Some("623231143"), Some("unknown")] {
            let (mut client, path) = runtime(mode, |_| {
                panic!("unknown identity must not send academic requests")
            });
            client.remember_account_name(account);
            executor.block_on(async {
                assert!(
                    crate::features::schedule::get_terms(&mut client)
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::schedule::get_exam_terms(&mut client)
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::schedule::get_weeks(&mut client, "20261")
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::schedule::get_week(&mut client, "2026-2027-1", 1)
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::schedule::get_today(&mut client)
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::schedule::get_exam(&mut client, "20261")
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::grades::get_grades(&mut client, "20261")
                        .await
                        .is_err()
                );
                assert!(
                    crate::features::grades::get_overview(&mut client)
                        .await
                        .is_err()
                );
            });
            let _ = std::fs::remove_dir_all(path);
        }
    }
}

#[test]
fn known_student_identity_never_switches_system_on_failure() {
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for (mode, account) in [ConnectionMode::Direct, ConnectionMode::WebVpn]
        .into_iter()
        .flat_map(|mode| {
            [
                "19000001",
                "SY2600001",
                "sy2600001",
                "Sy2600001",
                "ZY2600001",
                "BY2600001",
            ]
            .into_iter()
            .map(move |account| (mode, account))
        })
    {
        let graduate = account.starts_with(|c: char| c.is_ascii_alphabetic());
        let term = if graduate { "20261" } else { "2026-2027-1" };
        let allowed = if graduate {
            vec!["https://gsmis.buaa.edu.cn/"]
        } else {
            vec!["https://byxt.buaa.edu.cn/", "https://app.buaa.edu.cn/"]
        }
        .into_iter()
        .map(|url| {
            if mode == ConnectionMode::WebVpn {
                crate::connection::to_webvpn_url(url).unwrap()
            } else {
                url.to_owned()
            }
        })
        .collect::<Vec<_>>();
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let recorded = Arc::clone(&calls);
        let (mut client, path) = runtime(mode, move |request| {
            assert!(
                allowed.iter().any(|prefix| request.url.starts_with(prefix)),
                "wrong academic system or route for {account} in {mode:?}"
            );
            recorded.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            Ok(HttpResponse::new(503, request.url, vec![]))
        });
        client.remember_account_name(Some(account));
        assert!(
            executor
                .block_on(crate::features::schedule::get_terms(&mut client))
                .is_err()
        );
        assert!(
            executor
                .block_on(crate::features::schedule::get_exam_terms(&mut client))
                .is_err()
        );
        assert!(
            executor
                .block_on(crate::features::schedule::get_week(&mut client, term, 1))
                .is_err()
        );
        assert!(
            executor
                .block_on(crate::features::schedule::get_weeks(&mut client, term))
                .is_err()
        );
        assert!(
            executor
                .block_on(crate::features::schedule::get_today(&mut client))
                .is_err()
        );
        assert!(
            executor
                .block_on(crate::features::schedule::get_exam(&mut client, term))
                .is_err()
        );
        assert!(
            executor
                .block_on(crate::features::grades::get_grades(&mut client, term))
                .is_err()
        );
        if graduate {
            assert!(
                executor
                    .block_on(crate::features::grades::get_overview(&mut client))
                    .is_err()
            );
        }
        assert!(calls.load(std::sync::atomic::Ordering::Relaxed) >= 7);
        let _ = std::fs::remove_dir_all(path);
    }
}

#[test]
fn academic_queries_use_confirmed_identity() {
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for undergraduate in [false, true] {
        let (mut client, path) = runtime(ConnectionMode::Direct, move |request| {
            let body = if request.url.ends_with("currentUser.do") {
                "{}"
            } else if request.url.ends_with("schoolCalendars.do") {
                if undergraduate {
                    r#"{"code":"0","datas":[{"itemCode":"2026-2027-1","itemName":"Fixture","selected":true,"itemIndex":0}]}"#
                } else {
                    r#"{"code":"0","datas":[]}"#
                }
            } else {
                assert!(
                    !undergraduate,
                    "usable undergraduate terms must keep the undergraduate route"
                );
                if request.url.ends_with("index.do") {
                    "<html>GSMIS</html>"
                } else if request.url.ends_with("getXnxqList.do") {
                    r#"{"datas":[{"DM":"20261","MC":"Fixture","SFDQXQ":"1"}]}"#
                } else if request.url.ends_with("getWdksxx.do") {
                    assert_eq!(request.body, b"xnxqdm=20261");
                    r#"{"success":true,"countKs":0,"countKcks":0,"countJk":0}"#
                } else {
                    assert!(request.url.ends_with("xscjcx.do"));
                    r#"{"code":0,"datas":{"xscjcx":{"totalSize":0,"pageNumber":1,"rows":[]}}}"#
                }
            };
            Ok(HttpResponse::new(
                200,
                request.url,
                body.as_bytes().to_vec(),
            ))
        });
        client.remember_account_name(Some(if undergraduate {
            "19000001"
        } else {
            "SY2600001"
        }));
        let terms = executor
            .block_on(crate::features::schedule::get_exam_terms(&mut client))
            .unwrap();
        assert_eq!(
            terms[0].item_code,
            if undergraduate {
                "2026-2027-1"
            } else {
                "20261"
            }
        );
        if !undergraduate {
            let exams = executor
                .block_on(crate::features::schedule::get_exam(
                    &mut client,
                    &terms[0].item_code,
                ))
                .unwrap();
            assert!(exams.arranged.is_empty());
        }
        let grades = executor
            .block_on(crate::features::grades::get_overview(&mut client))
            .unwrap();
        assert_eq!(grades.graduate, !undergraduate);
        assert_eq!(grades.statistics.is_some(), !undergraduate);
        if let Some(stats) = grades.statistics {
            assert!(stats.gpa.is_none());
            assert!(stats.gpa_credits.abs() < f64::EPSILON);
        }
        let _ = std::fs::remove_dir_all(path);
    }
}

#[test]
fn gsmis_review_authentication_failures_never_fallback() {
    let (mut client, path) = runtime(ConnectionMode::Direct, |request| {
        assert!(
            request.url.contains("byxt.buaa.edu.cn"),
            "authentication expiry must not probe GSMIS"
        );
        let status = if request.url.ends_with("currentUser.do") {
            200
        } else {
            401
        };
        Ok(HttpResponse::new(status, request.url, b"{}".to_vec()))
    });
    client.remember_account_name(Some("19000001"));
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(crate::features::schedule::get_terms(&mut client));
    let _ = std::fs::remove_dir_all(path);
    assert_eq!(result.unwrap_err().code, ErrorCode::AuthenticationRequired);
}

#[test]
fn gsmis_review_today_only_loads_latest_term() {
    let count = Arc::new(Mutex::new(0));
    let observed = Arc::clone(&count);
    let (mut client, path) = runtime(ConnectionMode::Direct, move |request| {
        let body = if request.url.ends_with("index.do") {
            "<html>GSMIS</html>"
        } else if request.url.ends_with("kfdxnxqcx.do") {
            r#"{"code":0,"datas":{"kfdxnxqcx":{"totalSize":2,"rows":[{"XNXQDM":"20253","XNXQDM_DISPLAY":"Historical"},{"XNXQDM":"20261","XNXQDM_DISPLAY":"Latest"}]}}}"#
        } else {
            assert!(request.url.ends_with("loadXskbData.do"));
            *observed.lock().unwrap() += 1;
            let params: std::collections::BTreeMap<_, _> =
                url::form_urlencoded::parse(&request.body)
                    .into_owned()
                    .collect();
            if params.get("XNXQDM").map(String::as_str) == Some("20261") {
                r#"{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}"#
            } else {
                "historical data is invalid"
            }
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
    });
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(today(&mut client));
    let _ = std::fs::remove_dir_all(path);
    assert!(result.unwrap().is_empty());
    assert_eq!(*count.lock().unwrap(), 1);
}
#[async_trait::async_trait]
impl<F: Fn(HttpRequest) -> Result<HttpResponse> + Send + Sync> HttpTransport for Transport<F> {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        (self.0)(request)
    }
}

fn runtime<F: Fn(HttpRequest) -> Result<HttpResponse> + Send + Sync + 'static>(
    mode: ConnectionMode,
    handler: F,
) -> (ClientRuntime, std::path::PathBuf) {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let path = std::env::temp_dir().join(format!(
        "gsmis-http-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let store = FileSessionStore::new(&path).unwrap();
    store
        .compare_exchange(
            store.load_versioned().unwrap().revision,
            Some(&SessionSnapshot {
                mode,
                cookies: vec![],
                authenticated_at: 1,
                last_activity: 1,
            }),
        )
        .unwrap();
    let mut client = ClientRuntime::new(mode, Transport(handler), store).unwrap();
    client.remember_account_name(Some("SY2600001"));
    (client, path)
}

#[test]
fn gsmis_request_chain_transforms_urls_referer_and_scopes_cookies_in_both_modes() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let calls = Arc::new(Mutex::new(Vec::new()));
        let saved = Arc::clone(&calls);
        let map_url = move |url: &str| {
            if mode == ConnectionMode::WebVpn {
                crate::connection::to_webvpn_url(url).unwrap()
            } else {
                url.into()
            }
        };
        let app = "https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do";
        let (mut client, path) = runtime(mode, move |request| {
            let mut calls = saved.lock().unwrap();
            calls.push(request.clone());
            let mut response = HttpResponse::new(200, request.url.clone(), Vec::new());
            match calls.len() {
                1 => {
                    assert_eq!(request.url, map_url(app));
                    response.status = 302;
                    response.headers.insert(
                        "Location".into(),
                        vec!["https://sso.buaa.edu.cn/login?service=fixture".into()],
                    );
                }
                2 => {
                    assert_eq!(
                        request.url,
                        map_url("https://sso.buaa.edu.cn/login?service=fixture")
                    );
                    assert!(!request.headers.contains_key("Cookie"));
                    response.status = 302;
                    response.headers.insert("Location".into(), vec![app.into()]);
                }
                3 => {
                    assert_eq!(request.url, map_url(app));
                    let cookie_path = url::Url::parse(&request.url)
                        .unwrap()
                        .path()
                        .rsplit_once('/')
                        .unwrap()
                        .0
                        .to_owned();
                    response.headers.insert(
                        "Set-Cookie".into(),
                        vec![format!("FixtureSession=value; Path={cookie_path}; Secure")],
                    );
                    response.body = b"<html>GSMIS</html>".to_vec();
                }
                4 => {
                    assert_eq!(request.method, HttpMethod::Post);
                    assert_eq!(
                        request.url,
                        map_url(
                            "https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/kfdxnxqcx.do"
                        )
                    );
                    assert_eq!(request.headers.get("Referer"), Some(&map_url(app)));
                    assert_eq!(
                        request.headers.get("X-Requested-With").map(String::as_str),
                        Some("XMLHttpRequest")
                    );
                    assert!(request.body.is_empty());
                    assert!(!request.headers.contains_key("Content-Type"));
                    // A cookie scoped to /*default is not broadened to /modules.
                    assert!(!request.headers.contains_key("Cookie"));
                    response.body =
                        br#"{"code":0,"datas":{"kfdxnxqcx":{"totalSize":0,"rows":[]}}}"#.to_vec();
                }
                _ => panic!("unexpected request"),
            }
            Ok(response)
        });
        let result = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(terms(&mut client));
        let _ = std::fs::remove_dir_all(path);
        assert!(result.unwrap().is_empty());
        assert_eq!(calls.lock().unwrap().len(), 4);
    }
}

#[test]
fn gsmis_undergraduate_failure_requires_successful_business_capability() {
    for status in [403, 500] {
        let (mut client, path) = runtime(ConnectionMode::Direct, move |request| {
            if request.url.contains("byxt.buaa.edu.cn") {
                return Ok(HttpResponse::new(status, request.url, b"{}".to_vec()));
            }
            let body = if request.url.ends_with("index.do") {
                "<html>GSMIS</html>"
            } else {
                r#"{"code":0,"datas":{"kfdxnxqcx":{"totalSize":0,"rows":[]}}}"#
            };
            Ok(HttpResponse::new(
                200,
                request.url,
                body.as_bytes().to_vec(),
            ))
        });
        let result = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(crate::features::schedule::get_terms(&mut client));
        let _ = std::fs::remove_dir_all(path);
        assert!(result.unwrap().is_empty());
    }
}

#[test]
fn gsmis_exam_terms_are_independent_and_grade_missing_pages_fail() {
    let (mut client, path) = runtime(ConnectionMode::Direct, |request| {
        assert!(request.url.contains("wdksapp"));
        let body = if request.method == HttpMethod::Get {
            "<html>GSMIS</html>"
        } else {
            assert!(request.url.ends_with("getXnxqList.do"));
            assert!(request.body.is_empty());
            r#"{"datas":[{"DM":"20253","MC":"Historical","SFDQXQ":"1"}]}"#
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
    });
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    assert_eq!(
        executor.block_on(exam_terms(&mut client)).unwrap()[0].item_code,
        "20253"
    );
    let _ = std::fs::remove_dir_all(path);
    for problem in ["missing", "total", "page", "duplicate"] {
        let (mut client, path) = runtime(ConnectionMode::Direct, move |request| {
            assert!(request.url.contains("wdcjapp"));
            let body = if request.method == HttpMethod::Get {
                "<html>GSMIS</html>".into()
            } else {
                assert!(request.url.ends_with("xscjcx.do"));
                let params: std::collections::BTreeMap<_, _> =
                    url::form_urlencoded::parse(&request.body)
                        .into_owned()
                        .collect();
                let page: i32 = params["pageNumber"].parse().unwrap();
                let rows: Vec<_> = if page == 1 {
                    (1..=12)
                        .map(|i| serde_json::json!({"WID":format!("fixture-{i}")}))
                        .collect()
                } else if problem == "missing" {
                    vec![]
                } else {
                    vec![
                        serde_json::json!({"WID":if problem == "duplicate" {"fixture-1"} else {"fixture-13"}}),
                    ]
                };
                serde_json::json!({"code":0,"datas":{"xscjcx":{"totalSize":if page==2 && problem=="total" {14} else {13},"pageNumber":if page==2 && problem=="page" {1} else {page},"rows":rows}}}).to_string()
            };
            Ok(HttpResponse::new(200, request.url, body.into_bytes()))
        });
        assert!(executor.block_on(grades(&mut client)).is_err());
        let _ = std::fs::remove_dir_all(path);
    }
}

#[test]
fn gsmis_login_and_http_errors_are_safe() {
    for body in ["<title>CAS Login</title>", "<input name='execution'>"] {
        let response = HttpResponse::new(
            200,
            "https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do",
            body.as_bytes().to_vec(),
        );
        assert_eq!(
            check(&response).unwrap_err().code,
            ErrorCode::AuthenticationRequired
        );
    }
    let response = HttpResponse::new(403, "https://gsmis.buaa.edu.cn/", b"private-body".to_vec());
    let error = check(&response).unwrap_err();
    assert!(error.message.contains("403"));
    assert!(!error.message.contains("private-body"));
}

#[test]
fn gsmis_grade_overview_does_not_treat_html_portal_as_undergraduate_identity() {
    let (mut client, path) = runtime(ConnectionMode::Direct, |request| {
        let body = if request.url.contains("byxt.buaa.edu.cn") || request.url.ends_with("index.do")
        {
            "<html>portal</html>"
        } else {
            assert!(request.url.ends_with("xscjcx.do"));
            r#"{"code":0,"datas":{"xscjcx":{"totalSize":0,"pageNumber":1,"rows":[]}}}"#
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
    });
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(crate::features::grades::get_overview(&mut client));
    let _ = std::fs::remove_dir_all(path);
    assert!(result.unwrap().graduate);
}
