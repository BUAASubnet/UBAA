use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    ActionEligibility, ConnectionMode, LibBookCancelRequest, LibBookReserveRequest, Result,
    RouteClient,
};

#[path = "libbook/cancel_authority.rs"]
mod cancel_authority;
#[path = "libbook/write_authority.rs"]
mod write_authority;

#[test]
fn 图书馆查询完成八跳内的_cas_换票并复用独立令牌() {
    let root = std::env::temp_dir().join(format!("ubaa-libbook-http-{}", std::process::id()));
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
        MockLibBookTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let libraries = runtime
        .block_on(client.libbook_libraries("2026-08-27"))
        .unwrap()
        .data;
    assert_eq!(libraries[0].storeys[0].name, "一层");
    let areas = runtime
        .block_on(client.libbook_areas("9", Some("10"), "2026-08-27"))
        .unwrap()
        .data;
    assert_eq!(areas[0].area_name, "学院路");
    let detail = runtime
        .block_on(client.libbook_area_detail("8"))
        .unwrap()
        .data;
    assert_eq!(detail.available_dates, vec!["2026-08-27"]);
    let seats = runtime
        .block_on(client.libbook_seats("8", "2026-08-27", "08:00", "23:00"))
        .unwrap()
        .data;
    assert_eq!(seats[0].reserve_eligibility, ActionEligibility::Allowed);
    assert_eq!(seats[0].reserve_target.as_deref(), Some("s1"));
    let bookings = runtime
        .block_on(client.libbook_bookings(1, 20))
        .unwrap()
        .data;
    assert_eq!(bookings.total, 1);

    let requests = requests.lock().unwrap();
    let login_requests = requests
        .iter()
        .filter(|request| request.url.ends_with("/v4/login/user"))
        .count();
    assert_eq!(login_requests, 1);
    let business = requests
        .iter()
        .find(|request| request.url.ends_with("/v4/space/pcTopFor"))
        .unwrap();
    assert_eq!(
        business.headers.get("Authorization"),
        Some(&"bearerfixture-token".to_owned())
    );
    assert!(String::from_utf8_lossy(&business.body).contains("2026-08-27"));
    drop(requests);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 图书馆预约取消写链发送冻结加密请求() {
    let root = std::env::temp_dir().join(format!("ubaa-libbook-write-{}", std::process::id()));
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
        MockLibBookTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.libbook_reserve(LibBookReserveRequest {
            area_id: "8".into(),
            seat_id: "s1".into(),
            day: "2026-08-27".into(),
            segment: "t1".into(),
            start_time: "08:00".into(),
            end_time: "23:00".into(),
        }))
        .unwrap()
        .data;
    assert!(result.success);
    let cancelled = runtime
        .block_on(client.libbook_cancel_booking(LibBookCancelRequest {
            booking_id: "booking-1".into(),
            page: 1,
            limit: 20,
        }))
        .unwrap()
        .data;
    assert!(cancelled.success);

    let requests = requests.lock().unwrap();
    let confirm = requests
        .iter()
        .find(|request| request.url.ends_with("/v4/space/confirm"))
        .expect("应发送预约请求");
    let confirm_json: serde_json::Value = serde_json::from_slice(&confirm.body).unwrap();
    assert!(
        confirm_json["aesjson"]
            .as_str()
            .is_some_and(|value| !value.is_empty())
    );
    let cancel = requests
        .iter()
        .find(|request| request.url.ends_with("/v4/space/cancel"))
        .expect("应发送取消请求");
    assert!(String::from_utf8_lossy(&cancel.body).contains("booking-1"));
    drop(requests);
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct MockLibBookTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for MockLibBookTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        let response = match path.as_str() {
            "/login" => {
                let mut response = HttpResponse::new(302, request.url, Vec::new());
                response.headers.insert(
                    "Location".into(),
                    vec!["https://booking.lib.buaa.edu.cn/v4/login/cas?ticket=ST-fixture".into()],
                );
                response
            }
            "/v4/login/cas" => {
                let mut response = HttpResponse::new(302, request.url, Vec::new());
                response.headers.insert(
                    "Location".into(),
                    vec!["https://booking.lib.buaa.edu.cn/h5/index.html#/cas/?cas=cas-fixture".into()],
                );
                response
            }
            "/v4/login/user" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":0,"data":{"member":{"token":"fixture-token"}}}"#.as_bytes().to_vec(),
            ),
            "/v4/space/pcTopFor" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":1,"data":{"list":[{"id":"9","name":"图书馆","free_num":3,"total_num":10,"children":[{"id":"10","name":"一层","free_num":3,"total_num":10}]}]}}"#.as_bytes().to_vec(),
            ),
            "/v4/space/pick" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":1,"data":{"area":[{"id":"8","name":"分区","area":"学院路"}]}}"#.as_bytes().to_vec(),
            ),
            "/v4/Space/map" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":1,"data":{"area":{"id":"8","name":"分区"},"date":{"list":[{"day":"2026-08-27","times":[{"id":"t1","start":"08:00","end":"23:00"}]}]}}}"#.as_bytes().to_vec(),
            ),
            "/v4/Space/seat" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":1,"data":{"list":[{"id":"s1","name":"座位","no":"001","status":"1","status_name":"可用"}]}}"#.as_bytes().to_vec(),
            ),
            "/v4/member/seat" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":1,"data":{"data":[{"id":"booking-1","nameMerge":"分区 / 001","no":"001","status":1,"status_name":"已预约"}],"total":1,"current_page":1,"per_page":20}}"#.as_bytes().to_vec(),
            ),
            "/v4/space/confirm" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":0,"data":{"success":true,"message":"预约成功"}}"#.as_bytes().to_vec(),
            ),
            "/v4/space/cancel" => HttpResponse::new(
                200,
                request.url,
                r#"{"code":0,"message":"取消成功","data":{"success":true}}"#.as_bytes().to_vec(),
            ),
            _ => panic!("未预期的图书馆请求: {}", request.url),
        };
        Ok(response)
    }
}
