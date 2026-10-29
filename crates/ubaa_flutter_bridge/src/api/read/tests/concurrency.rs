use crate::api::client::BridgeClient;
use std::sync::Arc;
use tokio::sync::Notify;
use ubaa_core::facade::{ConnectionMode, NetworkState, UbaaClient};
use ubaa_test_support::{
    FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport, Result, RouteConfig,
    SessionSnapshot, SessionStore,
};

struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不探测");
    }
}

#[derive(Clone, Default)]
struct Transport {
    exam_started: Arc<Notify>,
    finish_exam: Arc<Notify>,
}

#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let body = if request.url.contains("currentUser.do") {
            r#"{"code":"0","datas":{"userId":"fixture-user"}}"#
        } else if request.url.contains("exams.do") {
            self.exam_started.notify_one();
            self.finish_exam.notified().await;
            r#"{"code":"0","datas":[]}"#
        } else if request.url.contains("get_stu_course_sched.action") {
            r#"{"STATUS":"0","result":[]}"#
        } else if request.url.contains("/app/user/login.action") {
            r#"{"STATUS":"0","result":{"id":"synthetic","sessionId":"synthetic"}}"#
        } else if request.url.contains("iclass.buaa.edu.cn") {
            return Ok(HttpResponse::new(
                200,
                "https://iclass.buaa.edu.cn:8346/?loginName=synthetic",
                Vec::new(),
            ));
        } else {
            panic!("未登记的合成请求");
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            body.as_bytes().to_vec(),
        ))
    }
}

#[tokio::test]
async fn 慢考试在途时签到仍可完成() {
    let root = std::env::temp_dir().join(format!("ubaa-read-parallel-{}", std::process::id()));
    let bridge = BridgeClient::open(root.to_string_lossy().into()).unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = Transport::default();
    *bridge.inner.lock().await = Some(
        UbaaClient::with_routing(
            transport.clone(),
            transport.clone(),
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"").unwrap(),
            NoProbe,
        )
        .unwrap(),
    );
    let exam = bridge.exam_arrangement("synthetic-term".into());
    tokio::pin!(exam);
    tokio::select! {
        () = transport.exam_started.notified() => {},
        result = &mut exam => panic!("考试应等待释放：{:?}", result.err()),
    }
    let signin =
        tokio::time::timeout(std::time::Duration::from_secs(1), bridge.signin_today()).await;
    transport.finish_exam.notify_one();
    exam.await.unwrap();
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
    assert!(signin.expect("签到不应等待慢考试").is_ok());
}
