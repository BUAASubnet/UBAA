use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpMethod, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot,
    SessionStore, from_webvpn_url, to_webvpn_url,
};
use ubaa_core::facade::{ConnectionMode, Result, RouteClient};

const RESPONSE: &str = r#"{"code":1,"data":{"area":{"name":"合成分区"},"date":{"list":[{"day":"2026-09-04","times":[{"id":"first-slot","start":"08:00","end":"10:00"}]},{"day":"2026-09-05","times":[{"id":"second-slot","start":"14:00","end":"16:00"}]}]}}}"#;

#[test]
fn 图书馆日程两路线各一次原请求保留关联且旧详情形状不变() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-libbook-schedule-{}-{mode:?}",
            std::process::id()
        ));
        let store = FileSessionStore::new(&root).unwrap();
        store
            .save(&SessionSnapshot {
                mode,
                cookies: vec![],
                authenticated_at: 1_000,
                last_activity: 1_001,
            })
            .unwrap();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let mut client = RouteClient::with_transport(
            mode,
            ScheduleTransport {
                mode,
                requests: requests.clone(),
            },
            store,
        )
        .unwrap();
        let schedule = runtime
            .block_on(client.libbook_area_schedule("area-safe"))
            .unwrap()
            .data;
        assert_eq!(schedule.id, "area-safe");
        assert_eq!(schedule.days.len(), 2);
        assert_eq!(schedule.days[0].time_slots[0].id, "first-slot");
        let second = &schedule.days[1];
        assert_eq!(second.day, "2026-09-05");
        assert_eq!(
            (
                &second.time_slots[0].id[..],
                &second.time_slots[0].start[..],
                &second.time_slots[0].end[..]
            ),
            ("second-slot", "14:00", "16:00")
        );
        {
            let requests = requests.lock().unwrap();
            assert_eq!(requests.len(), 3, "多个日期不能重复认证或请求详情");
            let map = requests.last().unwrap();
            assert_eq!(map.method, HttpMethod::Post);
            assert_eq!(
                map.url,
                routed(mode, "https://booking.lib.buaa.edu.cn/v4/Space/map")
            );
            assert_eq!(
                serde_json::from_slice::<serde_json::Value>(&map.body).unwrap(),
                serde_json::json!({"id":"area-safe"})
            );
            for (name, expected) in [
                ("Accept", "application/json, text/plain, */*".to_owned()),
                ("Authorization", "bearerfixture-token".to_owned()),
                ("Origin", routed(mode, "https://booking.lib.buaa.edu.cn")),
                ("Referer", routed(mode, "https://booking.lib.buaa.edu.cn")),
                ("X-Requested-With", "XMLHttpRequest".to_owned()),
                ("Content-Type", "application/json".to_owned()),
                ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36".to_owned()),
            ] {
                assert_eq!(map.headers.get(name), Some(&expected), "{mode:?} {name}");
            }
        }
        let old = runtime
            .block_on(client.libbook_area_detail("area-safe"))
            .unwrap()
            .data;
        let value = serde_json::to_value(&old).unwrap();
        let mut keys = value
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect::<Vec<_>>();
        keys.sort_unstable();
        assert_eq!(keys, ["availableDates", "id", "name", "timeSlots"]);
        assert_eq!(old.available_dates, ["2026-09-04", "2026-09-05"]);
        assert_eq!(old.time_slots[0].id, "first-slot");
        assert_eq!(
            requests.lock().unwrap().len(),
            4,
            "旧方法仍复用当前路线会话"
        );
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}

fn routed(mode: ConnectionMode, url: &str) -> String {
    match mode {
        ConnectionMode::Direct => url.to_owned(),
        ConnectionMode::WebVpn => to_webvpn_url(url).unwrap(),
    }
}

struct ScheduleTransport {
    mode: ConnectionMode,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for ScheduleTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let original = from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
        let path = url::Url::parse(&original).unwrap().path().to_owned();
        Ok(match path.as_str() {
            "/login" => HttpResponse::new(
                200,
                routed(
                    self.mode,
                    "https://booking.lib.buaa.edu.cn/v4/login/cas?cas=fixture-cas",
                ),
                vec![],
            ),
            "/v4/login/user" => HttpResponse::new(
                200,
                request.url,
                br#"{"code":1,"data":{"member":{"token":"fixture-token"}}}"#.to_vec(),
            ),
            "/v4/Space/map" => HttpResponse::new(200, request.url, RESPONSE.as_bytes().to_vec()),
            _ => panic!("未预期的合成图书馆请求"),
        })
    }
}
