use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    BykcSignRequest, ConnectionMode, ErrorCode, ErrorKind, Result, RouteClient, UbaaError,
};

#[path = "bykc/write_authority.rs"]
mod write_authority;

#[test]
fn 博雅选课写链发送加密正文和双令牌头() {
    let root = std::env::temp_dir().join(format!("ubaa-bykc-write-{}", std::process::id()));
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
        BykcWriteTransport {
            requests: Arc::clone(&requests),
            detail_calls: Arc::new(AtomicUsize::new(0)),
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.bykc_select_course(42))
        .unwrap()
        .data;
    assert_eq!(result.message, "ok");
    assert_eq!(
        runtime
            .block_on(client.bykc_deselect_course(42))
            .unwrap()
            .data
            .message,
        "ok"
    );
    assert_eq!(
        runtime
            .block_on(client.bykc_sign_course(BykcSignRequest {
                course_id: 42,
                lat: Some(39.9),
                lng: Some(116.3),
                sign_type: 1,
            }))
            .unwrap()
            .data
            .message,
        "ok"
    );

    let requests = requests.lock().unwrap();
    assert_eq!(requests.len(), 8);
    let login = url::Url::parse(&requests[0].url).unwrap();
    assert_eq!(login.path(), "/sscv/cas/login");
    assert_eq!(
        requests
            .iter()
            .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
            .collect::<Vec<_>>(),
        [
            "/sscv/cas/login",
            "/sscv/queryCourseById",
            "/sscv/choseCourse",
            "/sscv/queryCourseById",
            "/sscv/delChosenCourse",
            "/sscv/getAllConfig",
            "/sscv/queryChosenCourse",
            "/sscv/signCourseByUser",
        ]
    );
    for (request, path) in [
        (&requests[2], "/sscv/choseCourse"),
        (&requests[4], "/sscv/delChosenCourse"),
        (&requests[7], "/sscv/signCourseByUser"),
    ] {
        let url = url::Url::parse(&request.url).unwrap();
        assert_eq!(url.path(), path);
        assert!(!request.body.is_empty());
        assert_eq!(
            request.headers.get("auth_token").map(String::as_str),
            Some("token-safe")
        );
        assert_eq!(
            request.headers.get("authtoken").map(String::as_str),
            Some("token-safe")
        );
        assert!(request.headers.contains_key("ak"));
        assert!(request.headers.contains_key("sk"));
        assert!(request.headers.contains_key("ts"));
    }
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 博雅签到写入前重读当前学期资格并形成坐标() {
    let root =
        std::env::temp_dir().join(format!("ubaa-bykc-sign-preflight-{}", std::process::id()));
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
        BykcSignPreflightTransport {
            requests: Arc::clone(&requests),
            include_pass: true,
            include_inline_config: false,
            mutate_store_after_chosen: None,
            sign_response_body: br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            all_config_response_body: None,
            string_status_fields: false,
            chosen_response_body: None,
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let result = runtime
        .block_on(client.bykc_sign_course(BykcSignRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        }))
        .expect("资格明确且有正半径签到点时应提交")
        .data;

    assert_eq!(result.message, "ok");
    let paths = requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(
        paths,
        [
            "/sscv/cas/login",
            "/sscv/getAllConfig",
            "/sscv/queryChosenCourse",
            "/sscv/queryCourseById",
            "/sscv/signCourseByUser",
        ]
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 博雅签到资格字段缺失时不发送写请求() {
    let root = std::env::temp_dir().join(format!("ubaa-bykc-sign-unknown-{}", std::process::id()));
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
        BykcSignPreflightTransport {
            requests: Arc::clone(&requests),
            include_pass: false,
            include_inline_config: true,
            mutate_store_after_chosen: None,
            sign_response_body: br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            all_config_response_body: None,
            string_status_fields: false,
            chosen_response_body: None,
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime
        .block_on(client.bykc_sign_course(BykcSignRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        }))
        .expect_err("资格字段缺失时必须拒绝");

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    let paths = requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(
        paths,
        [
            "/sscv/cas/login",
            "/sscv/getAllConfig",
            "/sscv/queryChosenCourse",
        ]
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 博雅签到预检期间会话变化时不发送写请求() {
    let root = std::env::temp_dir().join(format!("ubaa-bykc-sign-revision-{}", std::process::id()));
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
        BykcSignPreflightTransport {
            requests: Arc::clone(&requests),
            include_pass: true,
            include_inline_config: true,
            mutate_store_after_chosen: Some(store.clone()),
            sign_response_body: br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
            all_config_response_body: None,
            string_status_fields: false,
            chosen_response_body: None,
        },
        store,
    )
    .unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    let error = runtime
        .block_on(client.bykc_sign_course(BykcSignRequest {
            course_id: 42,
            lat: None,
            lng: None,
            sign_type: 1,
        }))
        .expect_err("会话归属变化后不得发送博雅签到");

    assert_eq!(error.code, ErrorCode::InternalError);
    let paths = requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(
        paths,
        [
            "/sscv/cas/login",
            "/sscv/getAllConfig",
            "/sscv/queryChosenCourse",
        ]
    );
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 博雅签到_status_成功且_data_缺失或为_null_时保持确定成功() {
    for (case, response_body) in [
        ("missing", br#"{"status":"0"}"#.as_slice()),
        ("null", br#"{"status":"0","data":null}"#.as_slice()),
    ] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-bykc-sign-empty-data-{case}-{}",
            std::process::id()
        ));
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
            BykcSignPreflightTransport {
                requests: Arc::clone(&requests),
                include_pass: true,
                include_inline_config: true,
                mutate_store_after_chosen: None,
                sign_response_body: response_body.to_vec(),
                all_config_response_body: None,
                string_status_fields: false,
                chosen_response_body: None,
            },
            store,
        )
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let result = runtime
            .block_on(client.bykc_sign_course(BykcSignRequest {
                course_id: 42,
                lat: None,
                lng: None,
                sign_type: 1,
            }))
            .expect("冻结签到只要求成功 status")
            .data;

        assert_eq!(result.message, "签到成功", "{case}");
        let paths = requests
            .lock()
            .unwrap()
            .iter()
            .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
            .collect::<Vec<_>>();
        assert_eq!(
            paths,
            [
                "/sscv/cas/login",
                "/sscv/getAllConfig",
                "/sscv/queryChosenCourse",
                "/sscv/signCourseByUser",
            ]
        );
        let _ = std::fs::remove_dir_all(root);
    }
}

struct StrictSignPreflightCase {
    name: &'static str,
    all_config_response: Option<serde_json::Value>,
    string_status_fields: bool,
    chosen_response_body: Option<Vec<u8>>,
    expected_paths: Vec<&'static str>,
}

fn strict_sign_preflight_cases() -> Vec<StrictSignPreflightCase> {
    let semester = serde_json::json!({
        "semester": [{
            "semesterStartDate": "2000-01-01 00:00:00",
            "semesterEndDate": "2999-12-31 23:59:59"
        }]
    });
    let direct_array = serde_json::json!({
        "status": "0",
        "data": [{
            "id": 9,
            "checkin": 0,
            "pass": 0,
            "courseInfo": {
                "id": 42,
                "courseName": "错误数组包装",
                "courseSignConfig": sign_config_json()
            }
        }]
    });
    vec![
        StrictSignPreflightCase {
            name: "missing-status",
            all_config_response: Some(
                serde_json::json!({"success": true, "data": semester.clone()}),
            ),
            string_status_fields: false,
            chosen_response_body: None,
            expected_paths: vec!["/sscv/cas/login", "/sscv/getAllConfig"],
        },
        StrictSignPreflightCase {
            name: "numeric-status",
            all_config_response: Some(
                serde_json::json!({"status": 0, "success": true, "data": semester.clone()}),
            ),
            string_status_fields: false,
            chosen_response_body: None,
            expected_paths: vec!["/sscv/cas/login", "/sscv/getAllConfig"],
        },
        StrictSignPreflightCase {
            name: "nonzero-status",
            all_config_response: Some(
                serde_json::json!({"status": "1", "success": true, "data": semester.clone()}),
            ),
            string_status_fields: false,
            chosen_response_body: None,
            expected_paths: vec!["/sscv/cas/login", "/sscv/getAllConfig"],
        },
        StrictSignPreflightCase {
            name: "result-only",
            all_config_response: Some(
                serde_json::json!({"status": "0", "result": semester.clone()}),
            ),
            string_status_fields: false,
            chosen_response_body: None,
            expected_paths: vec!["/sscv/cas/login", "/sscv/getAllConfig"],
        },
        StrictSignPreflightCase {
            name: "string-status-fields",
            all_config_response: None,
            string_status_fields: true,
            chosen_response_body: None,
            expected_paths: vec![
                "/sscv/cas/login",
                "/sscv/getAllConfig",
                "/sscv/queryChosenCourse",
            ],
        },
        StrictSignPreflightCase {
            name: "direct-array",
            all_config_response: None,
            string_status_fields: false,
            chosen_response_body: Some(direct_array.to_string().into_bytes()),
            expected_paths: vec![
                "/sscv/cas/login",
                "/sscv/getAllConfig",
                "/sscv/queryChosenCourse",
            ],
        },
    ]
}

#[test]
fn 博雅签到写前核对拒绝宽松信封与畸形资格且不发送写请求() {
    for test_case in strict_sign_preflight_cases() {
        let case = test_case.name;
        let root = std::env::temp_dir().join(format!(
            "ubaa-bykc-sign-strict-preflight-{case}-{}",
            std::process::id()
        ));
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
            BykcSignPreflightTransport {
                requests: Arc::clone(&requests),
                include_pass: true,
                include_inline_config: true,
                mutate_store_after_chosen: None,
                sign_response_body: br#"{"status":"0"}"#.to_vec(),
                all_config_response_body: test_case
                    .all_config_response
                    .map(|response| response.to_string().into_bytes()),
                string_status_fields: test_case.string_status_fields,
                chosen_response_body: test_case.chosen_response_body,
            },
            store,
        )
        .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let error = runtime
            .block_on(client.bykc_sign_course(BykcSignRequest {
                course_id: 42,
                lat: None,
                lng: None,
                sign_type: 1,
            }))
            .expect_err("宽松配置信封不得成为签到资格证据");

        assert_eq!(error.code, ErrorCode::UpstreamChanged, "{case}");
        assert!(!error.retryable, "{case}");
        let paths = requests
            .lock()
            .unwrap()
            .iter()
            .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
            .collect::<Vec<_>>();
        assert_eq!(
            paths, test_case.expected_paths,
            "{case} 不得继续读取资格或发送写请求"
        );
        let _ = std::fs::remove_dir_all(root);
    }
}

#[derive(Clone)]
struct BykcWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    detail_calls: Arc<AtomicUsize>,
}

#[async_trait]
impl HttpTransport for BykcWriteTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        self.requests.lock().unwrap().push(request.clone());
        match path.as_str() {
            "/sscv/cas/login" => Ok(HttpResponse::new(
                302,
                "https://bykc.buaa.edu.cn/sscv/cas/login?token=token-safe",
                Vec::new(),
            )),
            "/sscv/choseCourse" | "/sscv/delChosenCourse" | "/sscv/signCourseByUser" => {
                Ok(HttpResponse::new(
                    200,
                    request.url,
                    br#"{"status":"0","data":{"message":"ok"}}"#.to_vec(),
                ))
            }
            "/sscv/queryCourseById" => {
                let body = match self.detail_calls.fetch_add(1, Ordering::SeqCst) {
                    0 => r#"{"status":"0","data":{"id":42,"courseName":"可选课程","courseStartDate":"2999-01-01 00:00:00","courseSelectStartDate":"2000-01-01 00:00:00","courseSelectEndDate":"2999-01-01 00:00:00","courseCurrentCount":1,"courseMaxCount":10,"selected":false}}"#.as_bytes().to_vec(),
                    1 => r#"{"status":"0","data":{"id":42,"courseName":"可退课程","courseStartDate":"2999-01-01 00:00:00","selected":true}}"#.as_bytes().to_vec(),
                    _ => return Err(test_error("unexpected bykc detail request")),
                };
                Ok(HttpResponse::new(200, request.url, body))
            }
            "/sscv/getAllConfig" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"status":"0","data":{"semester":[{"semesterStartDate":"2000-01-01 00:00:00","semesterEndDate":"2999-12-31 23:59:59"}]}}"#.to_vec(),
            )),
            "/sscv/queryChosenCourse" => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"status":"0","data":{"courseList":[{"id":9,"checkin":0,"pass":0,"courseInfo":{"id":42,"courseName":"safe course","courseSignConfig":"{\"signStartDate\":\"2000-01-01 00:00:00\",\"signEndDate\":\"2999-12-31 23:59:59\",\"signOutStartDate\":\"2000-01-01 00:00:00\",\"signOutEndDate\":\"2999-12-31 23:59:59\",\"signPointList\":[{\"lat\":39.9,\"lng\":116.3,\"radius\":100.0}]}"}}]}}"#.to_vec(),
            )),
            _ => Err(test_error("unexpected bykc path")),
        }
    }
}

#[derive(Clone)]
struct BykcSignPreflightTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    include_pass: bool,
    include_inline_config: bool,
    mutate_store_after_chosen: Option<FileSessionStore>,
    sign_response_body: Vec<u8>,
    all_config_response_body: Option<Vec<u8>>,
    string_status_fields: bool,
    chosen_response_body: Option<Vec<u8>>,
}

#[async_trait]
impl HttpTransport for BykcSignPreflightTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        self.requests.lock().unwrap().push(request.clone());
        let body = match path.as_str() {
            "/sscv/cas/login" => {
                return Ok(HttpResponse::new(
                    302,
                    "https://bykc.buaa.edu.cn/sscv/cas/login?token=token-safe",
                    Vec::new(),
                ));
            }
            "/sscv/getAllConfig" => {
                if let Some(body) = &self.all_config_response_body {
                    return Ok(HttpResponse::new(200, request.url, body.clone()));
                }
                serde_json::json!({
                    "status": "0",
                    "data": {"semester": [{
                        "semesterStartDate": "2000-01-01 00:00:00",
                        "semesterEndDate": "2999-12-31 23:59:59"
                    }]}
                })
            }
            "/sscv/queryChosenCourse" => {
                if let Some(body) = &self.chosen_response_body {
                    return Ok(HttpResponse::new(200, request.url, body.clone()));
                }
                let mut course_info = serde_json::json!({
                    "id": 42,
                    "courseName": "脱敏资格课程"
                });
                if self.include_inline_config {
                    course_info.as_object_mut().expect("课程详情对象").insert(
                        "courseSignConfig".to_owned(),
                        serde_json::json!(sign_config_json()),
                    );
                }
                let mut chosen = serde_json::json!({
                    "id": 9,
                    "checkin": if self.string_status_fields {
                        serde_json::json!("0")
                    } else {
                        serde_json::json!(0)
                    },
                    "courseInfo": course_info
                });
                if self.include_pass {
                    chosen.as_object_mut().expect("已选课程对象").insert(
                        "pass".to_owned(),
                        if self.string_status_fields {
                            serde_json::json!("0")
                        } else {
                            serde_json::json!(0)
                        },
                    );
                }
                if let Some(store) = &self.mutate_store_after_chosen {
                    store.save(&SessionSnapshot {
                        mode: ConnectionMode::Direct,
                        cookies: Vec::new(),
                        authenticated_at: 2_000,
                        last_activity: 2_001,
                    })?;
                }
                serde_json::json!({
                    "status": "0",
                    "data": {"courseList": [chosen]}
                })
            }
            "/sscv/queryCourseById" => serde_json::json!({
                "status": "0",
                "data": {
                    "id": 42,
                    "courseSignConfig": sign_config_json()
                }
            }),
            "/sscv/signCourseByUser" => {
                return Ok(HttpResponse::new(
                    200,
                    request.url,
                    self.sign_response_body.clone(),
                ));
            }
            _ => return Err(test_error("unexpected bykc path")),
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.to_string().into_bytes(),
        ))
    }
}

fn sign_config_json() -> String {
    serde_json::json!({
        "signStartDate": "2000-01-01 00:00:00",
        "signEndDate": "2999-12-31 23:59:59",
        "signOutStartDate": "2000-01-01 00:00:00",
        "signOutEndDate": "2999-12-31 23:59:59",
        "signPointList": [{
            "lat": 39.9,
            "lng": 116.3,
            "radius": 100.0
        }]
    })
    .to_string()
}

fn test_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}
