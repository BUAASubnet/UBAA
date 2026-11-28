use crate::api::client::BridgeClient;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
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
    exam_dropped: Arc<AtomicBool>,
    lock_started: Arc<Notify>,
    finish_lock: Arc<Notify>,
    logout_started: Option<Arc<Notify>>,
    finish_logout: Arc<Notify>,
}

struct PendingExam(Arc<AtomicBool>);
impl Drop for PendingExam {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let body = if request.url.ends_with("/logout") {
            if let Some(started) = &self.logout_started {
                started.notify_one();
                self.finish_logout.notified().await;
            }
            "synthetic-logout-response"
        } else if request.url.contains("/sso/manageLogin") {
            let mut response = HttpResponse::new(200, request.url, Vec::new());
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["sso_buaa_zhjs_token=fixture-sso; Path=/venue-zhjs-server/".into()],
            );
            return Ok(response);
        } else if request.url.contains("/venue-zhjs-server/api/login") {
            r#"{"code":200,"data":{"token":{"access_token":"fixture-cgyy"}}}"#
        } else if request.url.contains("/api/orders/lock/code") {
            self.lock_started.notify_one();
            self.finish_lock.notified().await;
            r#"{"code":200,"data":{"qrCode":"fixture-lock"}}"#
        } else if request.url.contains("/personal/frontend/data/info") {
            r#"{"e":0,"d":{"info":{"identity":"本科生","depart":"示例学院"}}}"#
        } else if request.url.contains("currentUser.do") {
            r#"{"code":"0","datas":{"userId":"fixture-user"}}"#
        } else if request.url.contains("exams.do") {
            let _pending = PendingExam(self.exam_dropped.clone());
            self.exam_started.notify_one();
            self.finish_exam.notified().await;
            r#"{"code":"0","datas":[]}"#
        } else if request.url.contains("teachingSchedule/detail.do") {
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
async fn 本机退出立即清空诊断并拒绝迟到响应() {
    use futures_util::FutureExt;

    let root = ubaa_test_support::test_temp_dir("ubaa_logout_diagnostics").unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = Transport {
        logout_started: Some(Arc::new(Notify::new())),
        ..Transport::default()
    };
    let bridge = BridgeClient::from_core(
        UbaaClient::with_routing(
            transport.clone(),
            Transport::default(),
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
            NoProbe,
        )
        .unwrap(),
    );
    bridge.schedule_today().await.unwrap();
    assert!(
        bridge
            .export_raw_diagnostics()
            .contains("teachingSchedule/detail.do")
    );
    let exam = bridge.exam_arrangement("synthetic-term".into());
    tokio::pin!(exam);
    tokio::select! {
        () = transport.exam_started.notified() => {},
        result = &mut exam => panic!("考试应保持在途：{:?}", result.err()),
    }
    let logout = bridge.logout();
    tokio::pin!(logout);
    assert!(logout.as_mut().now_or_never().is_none());
    let empty = || {
        let report: serde_json::Value =
            serde_json::from_str(&bridge.export_raw_diagnostics()).unwrap();
        assert_eq!(report["records"], serde_json::json!([]));
        assert_eq!(report["started_requests"], 0);
    };
    empty();
    transport.finish_exam.notify_one();
    exam.await.unwrap();
    tokio::select! {
        () = transport.logout_started.as_ref().unwrap().notified() => {},
        result = &mut logout => panic!("远端退出应等待响应：{result:?}"),
    }
    empty();
    transport.finish_logout.notify_one();
    logout.await.unwrap();
    empty();
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 撤销门锁租约后课表可以在门锁响应前完成() {
    use crate::api::client::{BridgeErrorCode, BridgeRoutePolicy};

    let root = ubaa_test_support::test_temp_dir("ubaa_cancel_lock_display").unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let transport = Transport::default();
    let bridge = BridgeClient::from_core(
        UbaaClient::with_routing(
            transport.clone(),
            transport.clone(),
            store,
            RouteConfig::parse("[route]\ndefault = \"direct\"").unwrap(),
            NoProbe,
        )
        .unwrap(),
    );
    let before = bridge.route_settings().await.unwrap();
    let lease = bridge.open_cgyy_lock_display().await.unwrap();
    let lock_display = bridge.read_cgyy_lock_display(&lease);
    tokio::pin!(lock_display);
    tokio::time::timeout(crate::TEST_HANG_TIMEOUT, async {
        tokio::select! {
            () = transport.lock_started.notified() => {},
            result = &mut lock_display => panic!("门锁请求应已发送且正在等待响应：{result:?}"),
        }
    })
    .await
    .expect("门锁请求应到达合成 transport");

    lease.cancel();
    let schedule = tokio::time::timeout(crate::TEST_HANG_TIMEOUT, async {
        let (lock, schedule) = tokio::join!(&mut lock_display, bridge.schedule_today());
        assert_eq!(lock.unwrap_err().code, BridgeErrorCode::InvalidInput);
        schedule.unwrap();
    })
    .await;
    transport.finish_lock.notify_one();
    schedule.expect("撤销门锁租约后课表不应等待门锁响应");
    let after = bridge.route_settings().await.unwrap();
    assert_eq!(after.default_policy, BridgeRoutePolicy::Direct);
    assert_eq!(after.active_routes, before.active_routes);
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 换网与手动切换丢弃在途网络读取并立即释放客户端锁() {
    use crate::api::client::{BridgeErrorCode, BridgeRoutePolicy};
    use std::time::Duration;
    for manual in [false, true] {
        let root =
            ubaa_test_support::test_temp_dir("ubaa_flutter_bridge_api_read_concurrency").unwrap();
        std::fs::write(root.join("config.toml"), "[route]\ndefault = \"direct\"\n").unwrap();
        FileSessionStore::new(&root)
            .unwrap()
            .save(&SessionSnapshot {
                mode: ConnectionMode::Direct,
                cookies: vec![],
                authenticated_at: 1000,
                last_activity: 1001,
            })
            .unwrap();
        let transport = Transport::default();
        let core = ubaa_core::facade::testing::with_routing_in_config_directory(
            transport.clone(),
            transport.clone(),
            &root,
            NoProbe,
        )
        .unwrap();
        let bridge = BridgeClient::from_core(core);
        let exam = bridge.exam_arrangement("synthetic-term".into());
        tokio::pin!(exam);
        tokio::select! {
            () = transport.exam_started.notified() => {},
            result = &mut exam => panic!("考试必须已发送且等待响应：{:?}", result.err()),
        }
        if manual {
            let switching = bridge.set_default_route_policy(BridgeRoutePolicy::WebVpn);
            let (read, switched) = tokio::time::timeout(Duration::from_secs(1), async {
                tokio::join!(exam, switching)
            })
            .await
            .expect("切换不应等待原请求超时");
            assert_eq!(read.unwrap_err().code, BridgeErrorCode::NetworkError);
            assert_eq!(switched.unwrap().default_policy, BridgeRoutePolicy::WebVpn);
        } else {
            let change = bridge.begin_network_change(true, 30_000).unwrap();
            assert_eq!(
                tokio::time::timeout(Duration::from_secs(1), exam)
                    .await
                    .unwrap()
                    .unwrap_err()
                    .code,
                BridgeErrorCode::NetworkError
            );
            tokio::time::timeout(crate::TEST_HANG_TIMEOUT, bridge.route_settings())
                .await
                .unwrap()
                .unwrap();
            change.finish();
        }
        assert!(transport.exam_dropped.load(Ordering::SeqCst));
        bridge.dispose().await.unwrap();
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[tokio::test]
async fn 慢考试在途时签到和课表仍可完成() {
    let root =
        ubaa_test_support::test_temp_dir("ubaa_flutter_bridge_api_read_concurrency").unwrap();
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
    let signin = tokio::time::timeout(crate::TEST_HANG_TIMEOUT, bridge.signin_today()).await;
    let schedule = tokio::time::timeout(crate::TEST_HANG_TIMEOUT, bridge.schedule_today()).await;
    transport.finish_exam.notify_one();
    exam.await.unwrap();
    bridge.dispose().await.unwrap();
    std::fs::remove_dir_all(root).unwrap();
    assert!(signin.expect("签到不应等待慢考试").is_ok());
    assert!(schedule.expect("课表不应等待慢考试").is_ok());
}
