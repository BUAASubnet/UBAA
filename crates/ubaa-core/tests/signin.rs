use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{ConnectionMode, ErrorCode, ErrorKind, Result, RouteClient, UbaaError};

#[test]
fn 签到写链按冻结顺序获取会话时间戳并提交表单() {
    let root = std::env::temp_dir().join(format!("ubaa-signin-write-{}", std::process::id()));
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
        SigninWriteTransport {
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
        .block_on(client.signin_perform("course-safe"))
        .unwrap()
        .data;
    assert!(result.success);
    assert_eq!(result.code, 0);

    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    assert_eq!(
        paths,
        vec![
            "/",
            "/eschool/app/user/login_buaa.do",
            "/app/common/get_timestamp.action",
            "/eschool/app/course/stu_scan_sign.action",
        ]
    );
    let submit = &requests[3];
    let url = url::Url::parse(&submit.url).unwrap();
    assert_eq!(
        url.query_pairs()
            .find(|(k, _)| k == "courseSchedId")
            .unwrap()
            .1,
        "course-safe"
    );
    assert_eq!(
        url.query_pairs().find(|(k, _)| k == "timestamp").unwrap().1,
        "1700000000000"
    );
    assert!(String::from_utf8_lossy(&submit.body).contains("id=course-safe"));
    assert_eq!(
        submit.headers.get("sessionId").map(String::as_str),
        Some("student-safe")
    );
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct SigninWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for SigninWriteTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        self.requests.lock().unwrap().push(request.clone());
        let response = match path.as_str() {
            "/" => HttpResponse::new(
                200,
                "https://iclass.buaa.edu.cn:8346/?loginName=student-safe",
                Vec::new(),
            ),
            "/eschool/app/user/login_buaa.do" => HttpResponse::new(
                200,
                request.url,
                br#"{"STATUS":"0","result":{"id":"student-safe"}}"#.to_vec(),
            ),
            "/app/common/get_timestamp.action" => HttpResponse::new(
                200,
                request.url,
                br#"{"timestamp":"1700000000000"}"#.to_vec(),
            ),
            "/eschool/app/course/stu_scan_sign.action" => HttpResponse::new(
                200,
                request.url,
                br#"{"STATUS":0,"stuSignStatus":1,"message":"ok"}"#.to_vec(),
            ),
            _ => return Err(test_error("unexpected signin path")),
        };
        Ok(response)
    }
}

fn test_error(message: &'static str) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}
