use async_trait::async_trait;
use std::sync::{Arc, Mutex};
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    CgyyPurposeSource, CgyyReservationSelection, CgyyReservationSubmitRequest, ConnectionMode,
    Result, RouteClient,
};

#[test]
fn 用途类型上游失败时回退到冻结静态定义() {
    let root =
        std::env::temp_dir().join(format!("ubaa-cgyy-purpose-fallback-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, CgyyPurposeFallbackTransport, store)
            .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let result = runtime
        .block_on(client.cgyy_purpose_types_diagnostics())
        .unwrap();

    assert_eq!(result.data.items.len(), 10);
    assert_eq!(result.data.items[0].key, 1);
    assert_eq!(result.data.source, CgyyPurposeSource::StaticFallback);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 业务令牌失效时按旧版重建会话并只重放一次() {
    let root = std::env::temp_dir().join(format!("ubaa-cgyy-auth-retry-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        CgyyAuthRetryTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let sites = runtime.block_on(client.cgyy_sites()).unwrap().data;

    assert_eq!(sites.len(), 1);
    assert_eq!(sites[0].id, 101);
    let paths: Vec<_> = requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    assert_eq!(
        paths,
        vec![
            "/venue-zhjs-server/sso/manageLogin",
            "/venue-zhjs-server/api/login",
            "/venue-zhjs-server/api/front/website/venues",
            "/venue-zhjs-server/sso/manageLogin",
            "/venue-zhjs-server/api/login",
            "/venue-zhjs-server/api/front/website/venues",
        ]
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 同一客户端连续读取只建立一次场馆业务会话() {
    let root = std::env::temp_dir().join(format!("ubaa-cgyy-reuse-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        CgyyReuseTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    runtime.block_on(client.cgyy_sites()).unwrap();
    runtime.block_on(client.cgyy_sites()).unwrap();

    let requests = requests.lock().unwrap();
    assert_eq!(
        requests
            .iter()
            .filter(|request| url::Url::parse(&request.url).unwrap().path()
                == "/venue-zhjs-server/api/login")
            .count(),
        1
    );
    assert_eq!(
        requests
            .iter()
            .filter(|request| url::Url::parse(&request.url).unwrap().path()
                == "/venue-zhjs-server/api/front/website/venues")
            .count(),
        2
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn webvpn_从网关_cookie接口取得_cgyy_sso令牌() {
    let root = std::env::temp_dir().join(format!("ubaa-cgyy-webvpn-cookie-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::WebVpn,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        WebVpnGatewayCookieTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let sites = runtime.block_on(client.cgyy_sites()).unwrap().data;

    assert_eq!(sites[0].id, 101);
    let requests = requests.lock().unwrap();
    let gateway_cookie = requests
        .iter()
        .find(|request| {
            let url = url::Url::parse(&request.url).unwrap();
            url.host_str() == Some("d.buaa.edu.cn") && url.path() == "/wengine-vpn/cookie"
        })
        .expect("WebVPN Cgyy 登录应读取网关 Cookie 接口");
    let gateway_url = url::Url::parse(&gateway_cookie.url).unwrap();
    assert!(
        gateway_url
            .query_pairs()
            .any(|(name, value)| name == "method" && value == "get")
    );
    let login = requests
        .iter()
        .find(|request| request.url.contains("/venue-zhjs-server/api/login"))
        .expect("应发送 Cgyy 业务登录请求");
    assert_eq!(
        login.headers.get("Sso-Token").map(String::as_str),
        Some("sso-gateway-fixture")
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 场馆预约写链按冻结顺序发送验证码和最终表单() {
    let root = std::env::temp_dir().join(format!("ubaa-cgyy-write-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        CgyyWriteTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let mut request = CgyyReservationSubmitRequest::default();
    request.venue_site_id = 4;
    request.reservation_date = "2026-03-29".into();
    request.selections = vec![CgyyReservationSelection {
        space_id: 6,
        time_id: 242,
        venue_space_group_id: None,
    }];
    request.phone = "010-00000000".into();
    request.theme = "测试预约".into();
    request.purpose_type = 1;
    request.joiner_num = 1;
    request.activity_content = "测试内容".into();
    request.joiners = "测试人员".into();
    request.is_philosophy_social_sciences = false;
    request.is_off_school_joiner = false;
    let request = request.with_captcha_material("verification", "point-json", "captcha-token");
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.cgyy_submit_reservation(request))
        .unwrap()
        .data;
    assert!(result.success);

    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    assert_eq!(
        paths,
        vec![
            "/venue-zhjs-server/sso/manageLogin",
            "/venue-zhjs-server/api/login",
            "/venue-zhjs-server/api/reservation/day/info",
            "/venue-zhjs-server/api/reservation/order/info",
            "/venue-zhjs-server/api/captcha/check",
            "/venue-zhjs-server/api/reservation/order/submit",
        ]
    );
    for request in &requests[3..] {
        assert_eq!(
            request.headers.get("cgAuthorization").map(String::as_str),
            Some("access-fixture")
        );
    }
    let captcha = &requests[4];
    assert!(String::from_utf8_lossy(&captcha.body).contains("pointJson=point-json"));
    let submit = &requests[5];
    let body = String::from_utf8_lossy(&submit.body);
    assert!(body.contains("captchaVerification=verification"));
    let form: std::collections::BTreeMap<_, _> = url::form_urlencoded::parse(body.as_bytes())
        .into_owned()
        .collect();
    assert_eq!(
        form.get("reservationOrderJson").map(String::as_str),
        Some(r#"[{"spaceId":6,"timeId":242,"venueSpaceGroupId":null}]"#)
    );
    drop(requests);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 场馆取消写链发送签名路径和订单标识() {
    let root = std::env::temp_dir().join(format!("ubaa-cgyy-cancel-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        CgyyWriteTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime.block_on(client.cgyy_cancel_order(77)).unwrap().data;
    assert_eq!(result.message, "取消成功");
    let requests = requests.lock().unwrap();
    assert_eq!(requests.len(), 3);
    let cancel = &requests[2];
    let url = url::Url::parse(&cancel.url).unwrap();
    assert_eq!(url.path(), "/venue-zhjs-server/api/orders/new/cancel/77");
    assert!(cancel.body.is_empty());
    assert!(cancel.headers.contains_key("sign"));
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct CgyyWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[derive(Clone)]
struct WebVpnGatewayCookieTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for WebVpnGatewayCookieTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let parsed = url::Url::parse(&request.url).unwrap();
        let response = match (parsed.host_str(), parsed.path()) {
            (Some("d.buaa.edu.cn"), "/wengine-vpn/cookie") => HttpResponse::new(
                200,
                request.url,
                b"_zte_fp_=fixture-fingerprint; sso_buaa_zhjs_token=sso-gateway-fixture; logout_flag".to_vec(),
            ),
            (_, path) if path.ends_with("/venue-zhjs-server/sso/manageLogin") => {
                HttpResponse::new(200, request.url, Vec::new())
            }
            (_, path) if path.ends_with("/venue-zhjs-server/api/login") => {
                assert_eq!(
                    request.headers.get("Sso-Token").map(String::as_str),
                    Some("sso-gateway-fixture")
                );
                HttpResponse::new(
                    200,
                    request.url,
                    br#"{"code":200,"data":{"token":{"access_token":"webvpn-access"}}}"#
                        .to_vec(),
                )
            }
            (_, path) if path.ends_with("/venue-zhjs-server/api/front/website/venues") => {
                HttpResponse::new(
                    200,
                    request.url,
                    r#"{"code":200,"data":[{"id":101,"siteName":"A101","venueName":"场馆","campusName":"校区"}]}"#
                        .as_bytes()
                        .to_vec(),
                )
            }
            (_, path) => panic!("未预期的 WebVPN Cookie 请求: {path}"),
        };
        Ok(response)
    }
}

#[derive(Clone)]
struct CgyyAuthRetryTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

struct CgyyPurposeFallbackTransport;

#[derive(Clone)]
struct CgyyReuseTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for CgyyReuseTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let mut response = match path.as_str() {
            "/venue-zhjs-server/sso/manageLogin" => HttpResponse::new(200, request.url, Vec::new()),
            "/venue-zhjs-server/api/login" => HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"access-reuse"}}}"#
                    .to_vec(),
            ),
            "/venue-zhjs-server/api/front/website/venues" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":200,"data":[{"id":101,"siteName":"A101","venueName":"场馆","campusName":"校区"}]}"#
                    .as_bytes()
                    .to_vec(),
            ),
            _ => panic!("未预期的场馆复用请求: {path}"),
        };
        if path == "/venue-zhjs-server/sso/manageLogin" {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=sso-reuse; Path=/".into()],
            );
        }
        Ok(response)
    }
}

#[async_trait]
impl HttpTransport for CgyyPurposeFallbackTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let mut response = match path.as_str() {
            "/venue-zhjs-server/sso/manageLogin" => HttpResponse::new(200, request.url, Vec::new()),
            "/venue-zhjs-server/api/login" => HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"access-fixture"}}}"#.to_vec(),
            ),
            "/venue-zhjs-server/api/codes" => HttpResponse::new(
                502,
                request.url,
                br#"{"code":500,"message":"fixture upstream failure"}"#.to_vec(),
            ),
            _ => panic!("未预期的用途类型请求: {path}"),
        };
        if path.ends_with("/sso/manageLogin") {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=sso-fixture; Path=/".into()],
            );
        }
        Ok(response)
    }
}

#[async_trait]
impl HttpTransport for CgyyWriteTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let mut response = match path.as_str() {
            "/venue-zhjs-server/sso/manageLogin" => HttpResponse::new(200, request.url, Vec::new()),
            "/venue-zhjs-server/api/login" => HttpResponse::new(
                200,
                request.url,
                br#"{"code":200,"data":{"token":{"access_token":"access-fixture"}}}"#.to_vec(),
            ),
            "/venue-zhjs-server/api/reservation/day/info" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":200,"data":{"token":"reservation-fixture","reservationDateList":["2026-03-29"],"spaceTimeInfo":[{"id":242,"beginTime":"14:00","endTime":"15:35"}],"reservationDateSpaceInfo":{"2026-03-29":[{"id":6,"spaceName":"测试房间","venueSiteId":4,"242":{"reservationStatus":1,"tradeNo":null,"orderId":null,"takeUp":false}}]}}}"#.as_bytes().to_vec(),
            ),
            "/venue-zhjs-server/api/reservation/order/info" => HttpResponse::new(200, request.url, br#"{"code":200,"data":{}}"#.to_vec()),
            "/venue-zhjs-server/api/captcha/check" => HttpResponse::new(200, request.url, br#"{"code":200,"data":{"success":true}}"#.to_vec()),
            "/venue-zhjs-server/api/reservation/order/submit" => HttpResponse::new(200, request.url, r#"{"code":200,"message":"预约成功","data":{}}"#.as_bytes().to_vec()),
            path if path.starts_with("/venue-zhjs-server/api/orders/new/cancel/") => HttpResponse::new(200, request.url, r#"{"code":200,"message":"取消成功","data":null}"#.as_bytes().to_vec()),
            _ => panic!("未预期的场馆写请求: {path}"),
        };
        if path.ends_with("/sso/manageLogin") {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=sso-fixture; Path=/".into()],
            );
        }
        Ok(response)
    }
}

#[async_trait]
impl HttpTransport for CgyyAuthRetryTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let snapshot = self.requests.lock().unwrap().clone();
        let count_path = |expected: &str| {
            snapshot
                .iter()
                .filter(|request| url::Url::parse(&request.url).unwrap().path() == expected)
                .count()
        };
        let mut response = match path.as_str() {
            "/venue-zhjs-server/sso/manageLogin" =>
                HttpResponse::new(200, request.url, Vec::new()),
            "/venue-zhjs-server/api/login" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":200,"data":{"token":{"access_token":"access-fixture"}}}"#
                    .as_bytes()
                    .to_vec(),
            ),
            "/venue-zhjs-server/api/front/website/venues"
                if count_path("/venue-zhjs-server/api/front/website/venues") == 1 => {
                HttpResponse::new(401, request.url, Vec::new())
            }
            "/venue-zhjs-server/api/front/website/venues" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":200,"data":[{"id":101,"siteName":"A101","venueName":"沙河研讨室","campusName":"沙河校区"}]}"#
                    .as_bytes()
                    .to_vec(),
            ),
            _ => panic!("未预期的场馆认证重试请求: {path}"),
        };
        if path == "/venue-zhjs-server/sso/manageLogin" {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=sso-fixture; Path=/".into()],
            );
        }
        Ok(response)
    }
}
