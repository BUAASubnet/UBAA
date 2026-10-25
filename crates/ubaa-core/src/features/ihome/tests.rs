use super::*;
use crate::domain::ConnectionMode;
#[test]
fn ihome_公共与本人筛选独立() {
    let q = IhomeQuery {
        scope: IhomeScope::Mine,
        filter: IhomeFilter::Unreplied,
        keyword: "不得发送".into(),
        ..IhomeQuery::default()
    };
    let url = page_url(&q).unwrap();
    assert!(url.contains("my_appreal"));
    assert!(url.contains("is_reply=0"));
    assert!(!url.contains("keyword"));
    assert!(page_url(&IhomeQuery { page: 0, ..q }).is_err());
}
#[test]
fn ihome_回调保留尾斜杠且拒绝外部跳转() {
    assert_eq!(
        auth::callback("http://i.buaa.edu.cn/web/#/login?type=0&token=fixture")
            .unwrap()
            .1
            .as_deref(),
        Some("fixture")
    );
    assert!(auth::callback("https://example.org/web/#/login?type=0&token=fixture").is_err());
    assert!(
        auth::callback("https://i.buaa.edu.cn/web#/login?type=0&token=fixture")
            .unwrap()
            .1
            .is_none()
    );
    let url =
        crate::connection::to_webvpn_url("https://i.buaa.edu.cn/web/#/login?type=0&token=fixture")
            .unwrap();
    assert_eq!(auth::callback(&url).unwrap().1.as_deref(), Some("fixture"));
}
#[test]
fn ihome_失效令牌不能回写() {
    let state = crate::internal::route_state::IhomeState::default();
    let generation = state.snapshot().0;
    state.clear();
    assert!(!state.store(generation, "fixture".into()));
    assert!(state.snapshot().1.is_none());
}

use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
use std::sync::{Arc, Mutex};
#[derive(Default)]
#[allow(clippy::struct_excessive_bools)]
struct Scenario {
    requests: Vec<HttpRequest>,
    followed: bool,
    supported: bool,
    support_enabled: bool,
    posts: usize,
    logins: usize,
    unauthorized: usize,
    lose_post: bool,
    lose_readback: bool,
    external: bool,
}
struct Transport(Arc<Mutex<Scenario>>);
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let original = crate::connection::from_webvpn_url(&request.url)?;
        let url = url::Url::parse(&original).unwrap();
        let mut s = self.0.lock().unwrap();
        s.requests.push(request.clone());
        let mut response = HttpResponse {
            status: 200,
            final_url: request.url.clone(),
            headers: std::collections::BTreeMap::default(),
            body: vec![],
        };
        if url.host_str() == Some("sso.buaa.edu.cn") {
            s.logins += 1;
            assert!(!request.headers.contains_key("Authorization"));
            assert_eq!(
                url.query_pairs().find(|(k, _)| k == "service").unwrap().1,
                "http://i.buaa.edu.cn/api/authLogin"
            );
            response.status = 302;
            response.headers.insert(
                "Location".into(),
                vec![if s.external {
                    "https://example.org/steal".into()
                } else {
                    "http://i.buaa.edu.cn/api/authLogin?ticket=fixture-ticket".into()
                }],
            );
            return Ok(response);
        }
        if url.path() == "/api/authLogin" {
            assert_eq!(url.scheme(), "https");
            assert!(!request.headers.contains_key("Authorization"));
            assert_eq!(url.query_pairs().count(), 1);
            response.status = 302;
            response.headers.insert(
                "Location".into(),
                vec!["https://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token".into()],
            );
            return Ok(response);
        }
        assert_eq!(
            request.headers.get("Authorization").map(String::as_str),
            Some("Bearer fixture-token")
        );
        assert!(url.fragment().is_none());
        if s.unauthorized > 0 {
            s.unauthorized -= 1;
            response.status = 401;
            return Ok(response);
        }
        if request.method == HttpMethod::Post {
            s.posts += 1;
            if url.path() == "/api/appeal_follow/42" {
                assert_eq!(request.body, b"{}");
                s.followed = !s.followed;
            } else {
                assert_eq!(url.path(), "/api/appeal/appeal_praise/42");
                assert!(request.body.is_empty());
                assert!(!request.headers.contains_key("Content-Type"));
                s.supported = !s.supported;
            }
            if s.lose_post {
                return Err(UbaaError::new(
                    ErrorCode::NetworkError,
                    ErrorKind::Network,
                    false,
                    "模拟响应丢失",
                ));
            }
        } else if s.posts > 0 && s.lose_readback {
            return Err(UbaaError::new(
                ErrorCode::Timeout,
                ErrorKind::Network,
                false,
                "模拟回读失败",
            ));
        }
        let appeal = serde_json::json!({"id":42,"content":"测试诉求","is_follow":i32::from(s.followed),"is_praise":i32::from(s.supported)});
        let data = if url.path() == "/api/general_set_more" {
            let keys: Vec<_> = url
                .query_pairs()
                .map(|(k, v)| (k.into_owned(), v.into_owned()))
                .collect();
            assert_eq!(
                keys,
                vec![
                    ("key[]".into(), "fabulous".into()),
                    ("key[]".into(), "fabulous_show".into())
                ]
            );
            serde_json::json!([{"key":"fabulous","value":if s.support_enabled{"1"}else{"0"}},{"key":"fabulous_show","value":"支持"}])
        } else if url.path() == "/api/mobile/types" {
            assert_eq!(url.query(), Some("type_mark=SQLB"));
            serde_json::json!({"SQLB":[{"id":1,"type_name":"诉求"}]})
        } else if url.path() == "/api/appeal" {
            serde_json::json!({"current_page":1,"last_page":2,"total":2,"data":[appeal]})
        } else {
            appeal
        };
        response.body =
            serde_json::to_vec(&serde_json::json!({"code":20000,"success":true,"data":data}))
                .unwrap();
        Ok(response)
    }
}
fn fixture(
    mode: ConnectionMode,
    scenario: Scenario,
) -> (ClientRuntime, Arc<Mutex<Scenario>>, std::path::PathBuf) {
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let root = std::env::temp_dir().join(format!(
        "ubaa-ihome-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    let current = store.load_versioned().unwrap();
    store
        .compare_exchange(
            current.revision,
            Some(&SessionSnapshot {
                mode,
                cookies: vec![],
                authenticated_at: 1000,
                last_activity: 1001,
            }),
        )
        .unwrap();
    let state = Arc::new(Mutex::new(scenario));
    let runtime = ClientRuntime::new(mode, Transport(Arc::clone(&state)), store).unwrap();
    (runtime, state, root)
}
#[test]
fn ihome_两路线认证搜索及401有界重试() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
                let (mut runtime, state, _root) = fixture(
                    mode,
                    Scenario {
                        unauthorized: 1,
                        ..Scenario::default()
                    },
                );
                let result = get_page(
                    &mut runtime,
                    &IhomeQuery {
                        keyword: "校园 回复".into(),
                        category_id: Some(7),
                        filter: IhomeFilter::Replied,
                        ..IhomeQuery::default()
                    },
                )
                .await
                .unwrap();
                assert_eq!(result.entries[0].appeal.id, 42);
                let s = state.lock().unwrap();
                assert_eq!(s.logins, 2);
                assert_eq!(s.requests.len(), 6);
                let business =
                    crate::connection::from_webvpn_url(&s.requests.last().unwrap().url).unwrap();
                let url = url::Url::parse(&business).unwrap();
                let params: std::collections::BTreeMap<_, _> = url.query_pairs().collect();
                assert_eq!(params["keyword"], "校园 回复");
                assert_eq!(params["sqlb_id"], "7");
                assert_eq!(params["reply"], "1");
                if mode == ConnectionMode::WebVpn {
                    assert!(
                        s.requests
                            .iter()
                            .all(|r| r.url.starts_with("https://d.buaa.edu.cn/"))
                    );
                }
            }
            let (mut runtime, state, _root) = fixture(
                ConnectionMode::Direct,
                Scenario {
                    unauthorized: 2,
                    ..Scenario::default()
                },
            );
            assert!(get_detail(&mut runtime, 42, false).await.is_err());
            assert_eq!(state.lock().unwrap().requests.len(), 6);
        });
}
#[test]
fn ihome_阻止外部登录跳转() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let (mut runtime, state, _root) = fixture(
                ConnectionMode::Direct,
                Scenario {
                    external: true,
                    ..Scenario::default()
                },
            );
            assert!(get_detail(&mut runtime, 42, false).await.is_err());
            assert_eq!(state.lock().unwrap().requests.len(), 1);
        });
}
#[test]
fn ihome_切换丢失响应后回查且相同目标不重复提交() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let (mut runtime, state, _root) = fixture(
                ConnectionMode::Direct,
                Scenario {
                    lose_post: true,
                    ..Scenario::default()
                },
            );
            runtime.begin_non_idempotent_operation();
            assert_eq!(
                set_reaction(&mut runtime, 42, IhomeReaction::Follow, true)
                    .await
                    .unwrap()
                    .is_followed,
                Some(true)
            );
            assert_eq!(
                set_reaction(&mut runtime, 42, IhomeReaction::Follow, true)
                    .await
                    .unwrap()
                    .is_followed,
                Some(true)
            );
            assert_eq!(state.lock().unwrap().posts, 1);
        });
}
#[test]
fn ihome_写后回查失败保持未知且不重发() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let (mut runtime, state, _root) = fixture(
                ConnectionMode::Direct,
                Scenario {
                    lose_post: true,
                    lose_readback: true,
                    ..Scenario::default()
                },
            );
            runtime.begin_non_idempotent_operation();
            assert_eq!(
                set_reaction(&mut runtime, 42, IhomeReaction::Follow, true)
                    .await
                    .unwrap_err()
                    .code,
                ErrorCode::OutcomeUnknown
            );
            assert_eq!(state.lock().unwrap().posts, 1);
        });
}

#[test]
fn ihome_支持受平台开关约束且只提交一次无正文请求() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            for enabled in [false, true] {
                let (mut runtime, state, _root) = fixture(
                    ConnectionMode::Direct,
                    Scenario {
                        support_enabled: enabled,
                        ..Scenario::default()
                    },
                );
                runtime.begin_non_idempotent_operation();
                let result = set_reaction(&mut runtime, 42, IhomeReaction::Support, true).await;
                if enabled {
                    assert_eq!(result.unwrap().is_supported, Some(true));
                } else {
                    assert_eq!(result.unwrap_err().code, ErrorCode::InvalidInput);
                }
                assert_eq!(state.lock().unwrap().posts, usize::from(enabled));
            }
        });
}
