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

#[test]
fn 评教激活临时失败按冻结实现回退为空结果() {
    let root = std::env::temp_dir().join(format!("ubaa-evaluation-fallback-{}", std::process::id()));
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
    let mut client = RouteClient::with_transport(ConnectionMode::Direct, EvaluationFallbackTransport, store).unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    let response = runtime.block_on(client.evaluation_all()).unwrap().data;
    assert!(response.courses.is_empty());
    assert_eq!(response.progress.total_courses, 0);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 自动评教按冻结顺序读取题目并提交课程结果() {
    let root = std::env::temp_dir().join(format!("ubaa-evaluation-auto-{}", std::process::id()));
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
        EvaluationAutoTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let course = ubaa_core::domain::EvaluationCourse {
        rwid: "rw-safe".into(),
        wjid: "wj-safe".into(),
        kcdm: "kc-safe".into(),
        kcmc: "课程".into(),
        bpmc: "教师".into(),
        msid: "ms-safe".into(),
        zdmc: Some("STID".into()),
        ..Default::default()
    };
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime
        .block_on(client.evaluation_submit_courses(vec![course]))
        .unwrap()
        .data;
    assert_eq!(result.len(), 1);
    assert!(result[0].success);
    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    assert_eq!(
        paths,
        vec![
            "/pjxt/cas",
            "/pjxt/evaluationMethodSix/reviseQuestionnairePattern",
            "/pjxt/evaluationMethodSix/getQuestionnaireTopic",
            "/pjxt/evaluationMethodSix/submitSaveEvaluation",
        ]
    );
    let revise: serde_json::Value = serde_json::from_slice(&requests[1].body).unwrap();
    assert_eq!(revise["rwid"], "rw-safe");
    let submit: serde_json::Value = serde_json::from_slice(&requests[3].body).unwrap();
    assert_eq!(submit["pjzt"], "1");
    assert_eq!(submit["pjjglist"][0]["pjdf"], 93);
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct EvaluationAutoTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

struct EvaluationFallbackTransport;

#[async_trait]
impl HttpTransport for EvaluationFallbackTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        if path == "/pjxt/cas" {
            return Ok(HttpResponse::new(503, request.url, Vec::new()));
        }
        Err(test_error("unexpected evaluation fallback path"))
    }
}

#[async_trait]
impl HttpTransport for EvaluationAutoTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        let path = url::Url::parse(&request.url)
            .map_err(|_| test_error("invalid test URL"))?
            .path()
            .to_owned();
        self.requests.lock().unwrap().push(request.clone());
        let body = match path.as_str() {
            "/pjxt/cas" => br"{}".to_vec(),
            "/pjxt/evaluationMethodSix/reviseQuestionnairePattern" =>
                br#"{"code":200,"result":{}}"#.to_vec(),
            "/pjxt/evaluationMethodSix/getQuestionnaireTopic" => br#"{"code":200,"result":{"pjmap":{},"pjxtPjjgPjjgckb":[{"pjid":"pj-safe","kcdm":"kc-safe","pjfs":"1"}],"pjxtWjWjbReturnEntity":{"wjzblist":[{"tklist":[{"tmid":"tm-safe","tmlx":"1","tmxxlist":[{"tmxxid":"opt-safe"}]}]}]}}}"#.to_vec(),
            "/pjxt/evaluationMethodSix/submitSaveEvaluation" =>
                br#"{"code":200,"message":"ok"}"#.to_vec(),
            _ => return Err(test_error("unexpected evaluation path")),
        };
        Ok(HttpResponse::new(200, request.url, body))
    }
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
