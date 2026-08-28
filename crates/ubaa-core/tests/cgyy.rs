use ubaa_core::features::cgyy::{
    parse_day_info, parse_order_detail, parse_orders, parse_purpose_types, parse_sites,
};

use async_trait::async_trait;
use std::sync::{Arc, Mutex};
use ubaa_core::domain::{CgyyReservationSelection, CgyyReservationSubmitRequest, ConnectionMode};
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

#[test]
fn 解析场馆站点和用途类型() {
    let sites = parse_sites(include_str!("../../../fixtures/readonly/cgyy-sites.json")).unwrap();
    assert_eq!(sites[0].id, 4);
    assert_eq!(sites[0].site_name, "二层");
    let purposes = parse_purpose_types(r#"{"code":200,"data":[]}"#).unwrap();
    assert_eq!(purposes.len(), 10);
    assert_eq!(purposes[2].key, 3);
}

#[test]
fn 状态二的时段不可预约() {
    let body = include_str!("../../../fixtures/readonly/cgyy-day.json");
    let result = parse_day_info(body, 4, "2026-03-29").unwrap();
    assert_eq!(result.time_slots[0].label, "14:00-15:35");
    assert!(!result.spaces[0].slots[0].is_reservable);
}

#[test]
fn 解析订单分页和详情完整字段() {
    let body = include_str!("../../../fixtures/readonly/cgyy-orders.json");
    let page = parse_orders(body).unwrap();
    assert_eq!(
        page.content[0].purpose_type_name.as_deref(),
        Some("学术研讨类（竞赛、答辩、展示等小组讨论）")
    );
    assert_eq!(page.content[0].check_content.as_deref(), Some("材料不完整"));
    let detail =
        parse_order_detail(r#"{"code":200,"data":{"id":9,"theme":"课程讨论","joinerNum":3}}"#)
            .unwrap();
    assert_eq!(detail.theme.as_deref(), Some("课程讨论"));
    assert_eq!(detail.joiner_num, Some(3));
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
    let request = CgyyReservationSubmitRequest {
        venue_site_id: 4,
        reservation_date: "2026-03-29".into(),
        selections: vec![CgyyReservationSelection {
            space_id: 6,
            time_id: 242,
            venue_space_group_id: None,
        }],
        phone: "010-00000000".into(),
        theme: "测试预约".into(),
        purpose_type: 1,
        joiner_num: 1,
        activity_content: "测试内容".into(),
        joiners: "测试人员".into(),
        is_philosophy_social_sciences: false,
        is_off_school_joiner: false,
        captcha_verification: "verification".into(),
        captcha_point_json: "point-json".into(),
        captcha_token: "captcha-token".into(),
        ..Default::default()
    };
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

#[async_trait]
impl HttpTransport for CgyyWriteTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
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
