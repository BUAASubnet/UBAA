use super::*;
use std::sync::Mutex;
use tokio::sync::Notify;
use ubaa_core::facade::{DualLoginInput, LoginReadiness, RequiredRecoveryControl, SecretValue};

#[derive(Clone, Default)]
struct 合成传输 {
    status: Arc<Mutex<u16>>,
    gate: Arc<Mutex<Option<Arc<Gate>>>>,
}

#[derive(Default)]
struct Gate {
    started: Notify,
    finish: Notify,
}

#[async_trait]
impl HttpTransport for 合成传输 {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        if let Some(response) = ubaa_core::facade::testing::sso_fixture_ticket(&request) {
            return Ok(response);
        }
        let url = ubaa_core::facade::testing::from_webvpn_url(&request.url)
            .unwrap_or_else(|_| request.url.clone());
        let status = if url.contains("/serviceValidate?") {
            *self.status.lock().unwrap()
        } else if url.starts_with("https://sso.buaa.edu.cn/login") {
            302
        } else {
            assert!(
                url.contains("/api/login")
                    || url.contains("/wengine-vpn/cookie")
                    || url.ends_with("/logout")
            );
            200
        };
        let gate = if url.contains("/serviceValidate?") {
            self.gate.lock().unwrap().take()
        } else {
            None
        };
        if let Some(gate) = gate {
            gate.started.notify_one();
            gate.finish.notified().await;
        }
        Ok(ubaa_core::facade::testing::sso_fixture_response(status, request.url, br#"{"code":0,"data":{"schoolid":"fixture-a","username":"fixture-a","name":"synthetic"}}"#.to_vec()))
    }
}

fn 输入() -> DualLoginInput {
    DualLoginInput {
        username: "fixture-a".into(),
        password: SecretValue::new("synthetic-only"),
    }
}

async fn 客户端(policy: &str) -> (UbaaClient, 合成传输) {
    let transport = 合成传输::default();
    *transport.status.lock().unwrap() = 200;
    let root = test_root("identity");
    RouteConfig::parse(&format!(
        r#"[route]
default = "{policy}"
"#
    ))
    .unwrap()
    .save(&root)
    .unwrap();
    let mut client = ubaa_core::facade::testing::with_routing_in_config_directory(
        transport.clone(),
        transport.clone(),
        &root,
        NeverProbe,
    )
    .unwrap();
    assert_eq!(
        client.login(输入()).await.unwrap().readiness,
        LoginReadiness::AllReady
    );
    (client, transport)
}

#[tokio::test]
async fn 同代派生401撤销父已取身份能力() {
    for route in ["direct", "webvpn"] {
        let (mut parent, transport) = 客户端(route).await;
        let old = parent.take_verified_login_identity().unwrap();
        let mut child = parent.fork_parallel_readonly().unwrap();
        *transport.status.lock().unwrap() = 401;
        let error = child
            .recover_required_session(ReadonlyFeature::Schedule)
            .await
            .unwrap_err();
        assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
        assert!(
            parent.validate_login_identity(&old).is_err(),
            "派生明确401后仍接受旧能力"
        );
    }
}

#[tokio::test]
async fn 同代派生401撤销父未取身份能力() {
    for route in ["direct", "webvpn"] {
        let (mut parent, transport) = 客户端(route).await;
        let mut child = parent.fork_parallel_readonly().unwrap();
        *transport.status.lock().unwrap() = 401;
        let error = child
            .recover_required_session(ReadonlyFeature::Schedule)
            .await
            .unwrap_err();
        assert_eq!(error.error.code, ErrorCode::AuthenticationRequired);
        assert!(
            parent.take_verified_login_identity().is_err(),
            "派生明确401后仍签发旧能力"
        );
    }
}

#[tokio::test]
async fn 正常刷新和临时503保留已取与未取能力() {
    for route in ["direct", "webvpn"] {
        for taken in [false, true] {
            let (mut parent, transport) = 客户端(route).await;
            let old = taken.then(|| parent.take_verified_login_identity().unwrap());
            parent
                .recover_required_session(ReadonlyFeature::Schedule)
                .await
                .unwrap();
            let mut child = parent.fork_parallel_readonly().unwrap();
            child
                .recover_required_session(ReadonlyFeature::Schedule)
                .await
                .unwrap();
            *transport.status.lock().unwrap() = 503;
            let error = child
                .recover_required_session(ReadonlyFeature::Schedule)
                .await
                .unwrap_err();
            assert_eq!(error.error.code, ErrorCode::UpstreamUnavailable);
            assert!(error.error.retryable);
            let old = old.unwrap_or_else(|| parent.take_verified_login_identity().unwrap());
            assert_eq!(parent.validate_login_identity(&old).unwrap(), "fixture-a");
        }
    }
}

#[tokio::test]
async fn 旧派生在途401不撤销重登能力或新读取归属() {
    for route in ["direct", "webvpn"] {
        for logout in [false, true] {
            let (mut parent, transport) = 客户端(route).await;
            let old = parent.take_verified_login_identity().unwrap();
            let mut child = parent.fork_parallel_readonly().unwrap();
            let gate = Arc::new(Gate::default());
            *transport.status.lock().unwrap() = 401;
            *transport.gate.lock().unwrap() = Some(gate.clone());
            let mut pending = Box::pin(child.recover_required_session(ReadonlyFeature::Schedule));
            tokio::select! {
                () = gate.started.notified() => {},
                result = &mut pending => panic!("旧请求必须先进入传输：{result:?}"),
            }
            *transport.status.lock().unwrap() = 200;
            if logout {
                parent.logout().await.unwrap();
            }
            assert_eq!(
                parent.login(输入()).await.unwrap().readiness,
                LoginReadiness::AllReady
            );
            let fresh = parent.take_verified_login_identity().unwrap();
            let mut fresh_child = parent.fork_parallel_readonly().unwrap();
            gate.finish.notify_one();
            assert_eq!(
                pending.await.unwrap_err().error.code,
                ErrorCode::AuthenticationRequired
            );
            assert!(parent.validate_login_identity(&old).is_err());
            assert_eq!(parent.validate_login_identity(&fresh).unwrap(), "fixture-a");
            assert!(
                fresh_child
                    .synchronize_parallel_readonly(&mut parent)
                    .unwrap(),
                "旧响应不得清除新父功能代次"
            );
            fresh_child
                .recover_required_session(ReadonlyFeature::Schedule)
                .await
                .unwrap();
        }
    }
}

#[tokio::test]
async fn 并行兄弟同代失效会拒绝兄弟交付() {
    for route in ["direct", "webvpn"] {
        let (mut parent, transport) = 客户端(route).await;
        let mut first = parent.fork_parallel_readonly().unwrap();
        let mut second = parent.fork_parallel_readonly().unwrap();
        *transport.status.lock().unwrap() = 401;
        assert_eq!(
            first
                .recover_required_session(ReadonlyFeature::Schedule)
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::AuthenticationRequired
        );
        *transport.status.lock().unwrap() = 200;
        assert_eq!(
            second
                .recover_required_session(ReadonlyFeature::Schedule)
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::AuthenticationRequired
        );
        assert!(parent.take_verified_login_identity().is_err());
    }
}

#[tokio::test]
async fn 普通子句柄释放保留父能力且拒绝公开嵌套派生() {
    let (mut parent, _) = 客户端("direct").await;
    let old = parent.take_verified_login_identity().unwrap();
    let mut child = parent.fork_parallel_readonly().unwrap();
    assert!(child.fork_parallel_readonly().is_err());
    assert!(child.logout().await.is_err());
    drop(child);
    assert_eq!(parent.validate_login_identity(&old).unwrap(), "fixture-a");
}

#[tokio::test]
async fn 子恢复取消或到期不扩大为共享认证撤销() {
    for cancelled in [true, false] {
        let (mut parent, transport) = 客户端("direct").await;
        let old = parent.take_verified_login_identity().unwrap();
        let mut child = parent.fork_parallel_readonly().unwrap();
        let gate = Arc::new(Gate::default());
        *transport.gate.lock().unwrap() = Some(gate.clone());
        let control = RequiredRecoveryControl::new(Duration::from_secs(2)).unwrap();
        let mut pending = Box::pin(child.recover_required_session_controlled(
            ReadonlyFeature::Schedule,
            control.claim().unwrap(),
        ));
        tokio::select! {
            () = gate.started.notified() => {},
            result = &mut pending => panic!("受控请求必须先挂起：{result:?}"),
        }
        if cancelled {
            control.cancel();
        }
        assert_eq!(
            pending.await.unwrap_err().error.code,
            if cancelled {
                ErrorCode::InternalError
            } else {
                ErrorCode::Timeout
            }
        );
        assert_eq!(parent.validate_login_identity(&old).unwrap(), "fixture-a");
    }
}

#[tokio::test]
async fn 首页校验复用拒绝派生撤销和外部身份更新() {
    for route in ["direct", "webvpn"] {
        let (mut parent, transport) = 客户端(route).await;
        parent.begin_read_recovery_batch();
        parent
            .recover_required_session(ReadonlyFeature::Schedule)
            .await
            .unwrap();
        let mut child = parent.fork_parallel_readonly().unwrap();
        *transport.status.lock().unwrap() = 401;
        assert!(
            child
                .recover_required_session(ReadonlyFeature::Signin)
                .await
                .is_err()
        );
        assert!(
            parent
                .recover_required_session(ReadonlyFeature::Judge)
                .await
                .is_err()
        );
    }
}

#[tokio::test]
async fn 首页校验复用在重新登录和路线变化后重新取身份() {
    let (mut client, transport) = 客户端("direct").await;
    client.begin_read_recovery_batch();
    client
        .recover_required_session(ReadonlyFeature::Schedule)
        .await
        .unwrap();
    client.login(输入()).await.unwrap();
    *transport.status.lock().unwrap() = 503;
    assert!(
        client
            .recover_required_session(ReadonlyFeature::Judge)
            .await
            .is_err()
    );
    *transport.status.lock().unwrap() = 200;
    client
        .recover_required_session(ReadonlyFeature::Schedule)
        .await
        .unwrap();
    client
        .set_default_route_policy(ubaa_core::facade::RoutePolicy::WebVpn)
        .unwrap();
    *transport.status.lock().unwrap() = 503;
    assert!(
        client
            .recover_required_session(ReadonlyFeature::Signin)
            .await
            .is_err()
    );
}
