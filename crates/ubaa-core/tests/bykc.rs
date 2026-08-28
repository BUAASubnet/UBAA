use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::domain::{BykcSignRequest, ConnectionMode};
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

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
    assert_eq!(requests.len(), 4);
    let login = url::Url::parse(&requests[0].url).unwrap();
    assert_eq!(login.path(), "/sscv/cas/login");
    for (request, path) in requests.iter().skip(1).zip([
        "/sscv/choseCourse",
        "/sscv/delChosenCourse",
        "/sscv/signCourseByUser",
    ]) {
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

#[derive(Clone)]
struct BykcWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for BykcWriteTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
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
            _ => Err(test_error("unexpected bykc path")),
        }
    }
}

fn test_error(message: &'static str) -> ubaa_core::error::UbaaError {
    ubaa_core::error::UbaaError::new(
        ubaa_core::error::ErrorCode::InternalError,
        ubaa_core::error::ErrorKind::Internal,
        false,
        message,
    )
}
