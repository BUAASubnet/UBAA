use super::*;
use serde_json::{Value, json};
use ubaa_core::facade::testing::{GatewayProbe, HttpMethod, RouteConfig};
use ubaa_core::facade::{NetworkState, UbaaClient};

#[derive(Clone)]
struct DetailTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    main: Value,
    config: Value,
    chosen: Value,
    fail: Option<&'static str>,
}

#[async_trait]
impl HttpTransport for DetailTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        self.requests.lock().unwrap().push(request.clone());
        if path.ends_with("/sscv/cas/login") {
            return Ok(HttpResponse::new(
                302,
                request
                    .url
                    .replace("/sscv/cas/login", "/cas-login?token=synthetic-detail"),
                Vec::new(),
            ));
        }
        let api = path.rsplit('/').next().unwrap();
        if self.fail == Some(api) {
            return Err(test_error("合成补查失败"));
        }
        let data = match api {
            "queryCourseById" => self.main.clone(),
            "getAllConfig" => self.config.clone(),
            "queryChosenCourse" => self.chosen.clone(),
            "queryStudentSemesterCourseByPage" => {
                json!({"content":[self.main.clone()],"totalElements":61,"totalPages":4,"size":20,"number":2})
            }
            _ => panic!("意外的合成请求"),
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            json!({"status":"0","data":data}).to_string().into_bytes(),
        ))
    }
}

struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _timeout: std::time::Duration) -> NetworkState {
        panic!("固定路线不得额外探测")
    }
}

struct Harness {
    client: UbaaClient,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    root: std::path::PathBuf,
}
impl Drop for Harness {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn make(
    mode: ConnectionMode,
    main: Value,
    config: Value,
    chosen: Value,
    fail: Option<&'static str>,
) -> Harness {
    static SERIAL: AtomicUsize = AtomicUsize::new(0);
    let root = std::env::temp_dir().join(format!(
        "ubaa-bykc-full-{}-{}",
        std::process::id(),
        SERIAL.fetch_add(1, Ordering::SeqCst)
    ));
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let transport = DetailTransport {
        requests: requests.clone(),
        main,
        config,
        chosen,
        fail,
    };
    let route = if mode == ConnectionMode::Direct {
        "direct"
    } else {
        "webvpn"
    };
    let client = UbaaClient::with_routing(
        transport.clone(),
        transport,
        store,
        RouteConfig::parse(&format!("[route]\ndefault = \"{route}\"\n")).unwrap(),
        NoProbe,
    )
    .unwrap();
    Harness {
        client,
        requests,
        root,
    }
}

fn main_course(selected: Value, sign: Value) -> Value {
    let mut value = json!({"id":71,"courseName":"合成课程","courseContact":"合成联系人"});
    value["selected"] = selected;
    value["courseSignConfig"] = sign;
    value
}

fn semester() -> Value {
    json!({"semester":[{"semesterStartDate":"2000-01-01 00:00:00","semesterEndDate":"2999-01-01 00:00:00"}]})
}
fn config_point(lat: i32) -> Value {
    json!(
        json!({"signStartDate":"2000-01-01 00:00:00","signEndDate":"2999-01-01 00:00:00",
        "signPointList":[{"lat":lat,"lng":20.0,"radius":10.0}]})
        .to_string()
    )
}
fn chosen() -> Value {
    json!({"courseList":[
        {"id":71,"checkin":1,"pass":1,"courseInfo":{"id":999,"courseSignConfig":config_point(99)}},
        {"id":7001,"checkin":5,"pass":0,"courseInfo":{"id":71,"courseName":"合成课程","courseSignConfig":config_point(30)}},
        {"id":7002,"checkin":1,"pass":1,"courseInfo":{"id":71,"courseSignConfig":config_point(40)}}]})
}
fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn paths(requests: &Arc<Mutex<Vec<HttpRequest>>>) -> Vec<String> {
    requests
        .lock()
        .unwrap()
        .iter()
        .map(|r| {
            url::Url::parse(&r.url)
                .unwrap()
                .path()
                .rsplit('/')
                .next()
                .unwrap()
                .to_owned()
        })
        .collect()
}

#[test]
fn 完整详情已选双路线顺序补查且主配置优先记录按内层课程首项匹配() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let mut h = make(
            mode,
            main_course(json!(true), config_point(10)),
            semester(),
            chosen(),
            None,
        );
        let result = runtime()
            .block_on(h.client.bykc_course_full_detail(71))
            .unwrap();
        assert_eq!(
            paths(&h.requests),
            [
                "login",
                "queryCourseById",
                "getAllConfig",
                "queryChosenCourse"
            ]
        );
        assert_eq!(result.resolution.mode, mode);
        let detail = result.data;
        let attendance = detail.attendance.unwrap();
        assert_eq!(
            (
                attendance.record_id,
                attendance.course_id,
                attendance.checkin,
                attendance.pass
            ),
            (7001, 71, Some(5), Some(0))
        );
        assert!((detail.sign_config.unwrap().sign_points[0].lat - 10.0).abs() < f64::EPSILON);
        assert!(detail.course.has_sign_points);
        for request in h.requests.lock().unwrap().iter().skip(1) {
            let url = url::Url::parse(&request.url).unwrap();
            assert_eq!(
                url.host_str(),
                Some(if mode == ConnectionMode::Direct {
                    "bykc.buaa.edu.cn"
                } else {
                    "d.buaa.edu.cn"
                })
            );
            assert_eq!(request.method, HttpMethod::Post);
            assert_eq!(
                request.headers.get("Content-Type").map(String::as_str),
                Some("application/json; charset=UTF-8")
            );
            assert!(
                request.headers.contains_key("auth_token")
                    && request.headers.contains_key("authtoken")
            );
            assert!(!request.body.is_empty());
        }
    }
}

#[test]
fn 完整详情仅严格已选才补查且旧详情保持单次主请求() {
    for selected in [json!(false), Value::Null, json!("true"), json!(1)] {
        let mut h = make(
            ConnectionMode::Direct,
            main_course(selected, Value::Null),
            semester(),
            chosen(),
            None,
        );
        let detail = runtime()
            .block_on(h.client.bykc_course_full_detail(71))
            .unwrap()
            .data;
        assert_eq!(paths(&h.requests), ["login", "queryCourseById"]);
        assert!(detail.attendance.is_none());
    }
    let mut h = make(
        ConnectionMode::Direct,
        main_course(json!(true), config_point(10)),
        semester(),
        chosen(),
        None,
    );
    runtime().block_on(h.client.bykc_course_detail(71)).unwrap();
    assert_eq!(paths(&h.requests), ["login", "queryCourseById"]);
}

#[test]
fn 完整详情主配置缺失或损坏才回退缺考勤保持未知() {
    for sign in [Value::Null, json!("坏配置")] {
        let mut list = chosen();
        let record = &mut list["courseList"][1];
        record.as_object_mut().unwrap().remove("checkin");
        record.as_object_mut().unwrap().remove("pass");
        let mut h = make(
            ConnectionMode::Direct,
            main_course(json!(true), sign),
            semester(),
            list,
            None,
        );
        let detail = runtime()
            .block_on(h.client.bykc_course_full_detail(71))
            .unwrap()
            .data;
        assert!((detail.sign_config.unwrap().sign_points[0].lat - 30.0).abs() < f64::EPSILON);
        let attendance = detail.attendance.unwrap();
        assert_eq!(
            (attendance.record_id, attendance.checkin, attendance.pass),
            (7001, None, None)
        );
        assert!(detail.course.has_sign_points);
    }
}

#[test]
fn 完整详情合法无匹配不丢主配置也不借其他课程配置() {
    for list in [
        json!([]),
        json!([{"id":71,"courseInfo":{"id":999,"courseSignConfig":config_point(99)}}]),
    ] {
        let mut h = make(
            ConnectionMode::Direct,
            main_course(json!(true), config_point(10)),
            semester(),
            json!({"courseList":list}),
            None,
        );
        let detail = runtime()
            .block_on(h.client.bykc_course_full_detail(71))
            .unwrap()
            .data;
        assert!(detail.attendance.is_none());
        assert!((detail.sign_config.unwrap().sign_points[0].lat - 10.0).abs() < f64::EPSILON);
    }
}

#[test]
fn 完整详情任一补查错误必须原子失败() {
    let cases = [
        (semester(), chosen(), Some("getAllConfig")),
        (json!({"semester":[]}), chosen(), None),
        (
            json!({"semester":[{"semesterEndDate":"2999-01-01 00:00:00"}]}),
            chosen(),
            None,
        ),
        (semester(), chosen(), Some("queryChosenCourse")),
        (semester(), json!({"courseList":{}}), None),
        (semester(), json!({"courseList":[null]}), None),
    ];
    for (config, records, fail) in cases {
        let mut h = make(
            ConnectionMode::Direct,
            main_course(json!(true), config_point(10)),
            config,
            records,
            fail,
        );
        assert!(
            runtime()
                .block_on(h.client.bykc_course_full_detail(71))
                .is_err(),
            "补查失败不得降级为空成功"
        );
    }
}

#[test]
fn 完整详情拒绝课程身份不符且不继续补查() {
    let mut h = make(
        ConnectionMode::Direct,
        main_course(json!(true), Value::Null),
        semester(),
        chosen(),
        None,
    );
    assert!(
        runtime()
            .block_on(h.client.bykc_course_full_detail(99))
            .is_err()
    );
    assert_eq!(paths(&h.requests), ["login", "queryCourseById"]);
}

#[test]
fn 完整显示配置不改变随后写前的已选配置优先级() {
    let mut main_config: Value = serde_json::from_str(config_point(10).as_str().unwrap()).unwrap();
    main_config["signStartDate"] = json!("2998-01-01 00:00:00");
    let mut records = chosen();
    records["courseList"][1]["checkin"] = json!(0);
    let mut h = make(
        ConnectionMode::Direct,
        main_course(json!(true), json!(main_config.to_string())),
        semester(),
        records,
        None,
    );
    let rt = runtime();
    let shown = rt
        .block_on(h.client.bykc_course_full_detail(71))
        .unwrap()
        .data;
    assert_eq!(
        shown.sign_config.unwrap().sign_start_date.as_deref(),
        Some("2998-01-01T00:00:00")
    );
    let authority = rt
        .block_on(h.client.preflight_bykc_sign_course(&BykcSignRequest {
            course_id: 71,
            sign_type: 1,
            lat: None,
            lng: None,
        }))
        .unwrap()
        .data;
    assert_eq!(authority.window_start, "2000-01-01 00:00:00");
    assert_eq!(
        paths(&h.requests),
        [
            "login",
            "queryCourseById",
            "getAllConfig",
            "queryChosenCourse",
            "getAllConfig",
            "queryChosenCourse"
        ]
    );
}

#[test]
fn 已选回退显示配置的畸形日期类型不成为有点配置() {
    let records = json!({"courseList":[{"id":7001,"courseInfo":{"id":71,"courseSignConfig":
        json!({"signEndDate":true,"signPointList":[{"lat":10,"lng":20}]}).to_string()}}]});
    let mut h = make(
        ConnectionMode::Direct,
        main_course(json!(true), Value::Null),
        semester(),
        records,
        None,
    );
    let detail = runtime()
        .block_on(h.client.bykc_course_full_detail(71))
        .unwrap()
        .data;
    assert!(detail.sign_config.is_none());
    assert!(!detail.course.has_sign_points);
    assert!(detail.attendance.is_some());
}
