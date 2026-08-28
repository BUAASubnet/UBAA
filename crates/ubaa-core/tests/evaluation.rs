use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::domain::ConnectionMode;
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

#[test]
fn 评教提交通过路线客户端发送冻结_json信封() {
    let root = std::env::temp_dir().join(format!("ubaa-evaluation-write-{}", std::process::id()));
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
        EvaluationWriteTransport {
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
        .block_on(client.evaluation_submit(vec![serde_json::json!({
            "pjid": "pj-safe",
            "pjdf": 93,
        })]))
        .unwrap()
        .data;
    assert!(result[0].success);

    let requests = requests.lock().unwrap();
    assert_eq!(requests.len(), 1);
    let request = &requests[0];
    assert!(
        request
            .url
            .ends_with("/pjxt/evaluationMethodSix/submitSaveEvaluation")
    );
    assert_eq!(
        request.headers.get("Content-Type").map(String::as_str),
        Some("application/json")
    );
    assert_eq!(
        request.headers.get("X-Requested-With").map(String::as_str),
        Some("XMLHttpRequest")
    );
    let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
    assert_eq!(body["pjidlist"], serde_json::json!([]));
    assert_eq!(body["pjzt"], "1");
    assert_eq!(body["pjjglist"][0]["pjdf"], 93);
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct EvaluationWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for EvaluationWriteTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        if path != "/pjxt/evaluationMethodSix/submitSaveEvaluation" {
            return Err(test_error("unexpected evaluation path"));
        }
        Ok(HttpResponse::new(
            200,
            request.url,
            br#"{"code":200,"message":"ok"}"#.to_vec(),
        ))
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
