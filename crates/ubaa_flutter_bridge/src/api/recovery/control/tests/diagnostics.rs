use super::*;
use std::sync::atomic::{AtomicBool, Ordering};
use ubaa_core::facade::testing::{HttpMethod, sso_fixture_response, sso_fixture_ticket};

const ACCOUNT: &str = "fixture-user";
const PRIOR: &str = "synthetic-confirmed-response";
const OTHER: &str = "synthetic-other-identity";
const RECOVERY: &str = "synthetic-password-recovery-response";

#[derive(Default)]
struct Scenario {
    other: AtomicBool,
    recovery: AtomicBool,
    pause_validation: AtomicBool,
    validation_started: tokio::sync::Notify,
    release_validation: tokio::sync::Notify,
    validation_released: tokio::sync::Notify,
}
struct School(Arc<Scenario>);

#[async_trait]
impl HttpTransport for School {
    async fn execute(&self, request: HttpRequest) -> core::Result<HttpResponse> {
        if let Some(ticket) = sso_fixture_ticket(&request) {
            return Ok(ticket);
        }
        let state = &self.0;
        let body = if request.url.contains("/serviceValidate?") {
            let other = state.other.load(Ordering::SeqCst);
            if state.pause_validation.load(Ordering::SeqCst) {
                state.validation_started.notify_one();
                state.release_validation.notified().await;
                state.validation_released.notify_one();
            }
            let (name, marker) = if other {
                (OTHER, OTHER)
            } else if state.recovery.load(Ordering::SeqCst) {
                (ACCOUNT, RECOVERY)
            } else {
                (ACCOUNT, PRIOR)
            };
            serde_json::json!({"user":name,"attributes":{"employeeNumber":[name],"name":[marker]}})
                .to_string()
        } else if request.method == HttpMethod::Get {
            r#"<form id="fm1"><input name="execution" value="synthetic-form"></form>"#.into()
        } else {
            RECOVERY.into()
        };
        Ok(sso_fixture_response(200, request.url, body.into_bytes()))
    }
}

fn bridge() -> (BridgeClient, Arc<Scenario>, ubaa_test_support::TestTempDir) {
    let root = ubaa_test_support::test_temp_dir("bridge_diagnostics_recovery").unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: core::ConnectionMode::Direct,
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1001,
        })
        .unwrap();
    let state = Arc::<Scenario>::default();
    let client = core::UbaaClient::with_routing(
        School(state.clone()),
        School(state.clone()),
        store,
        RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    (BridgeClient::from_core(client), state, root)
}

async fn verify(bridge: &BridgeClient) -> Result<BridgeRequiredSession, BridgeError> {
    let control = BridgeRequiredRecoveryControl::new(2000).unwrap();
    bridge
        .recover_required_session_controlled(BridgeRecoveryFeature::Schedule, &control)
        .await
}

#[tokio::test]
async fn 前置核验返回其他账号后重登只导出绑定账号的记录() {
    let (bridge, scenario, _root) = bridge();
    verify(&bridge).await.unwrap();
    assert!(bridge.export_raw_diagnostics().contains(PRIOR));
    scenario.other.store(true, Ordering::SeqCst);
    assert_eq!(
        verify(&bridge).await.unwrap_err().code,
        BridgeErrorCode::AuthenticationRequired
    );
    scenario.other.store(false, Ordering::SeqCst);
    scenario.recovery.store(true, Ordering::SeqCst);
    let control = BridgeRequiredRecoveryControl::new(2000).unwrap();
    bridge
        .login_required_route_controlled(
            BridgeConnectionMode::Direct,
            ACCOUNT.into(),
            "synthetic-password".into(),
            &control,
        )
        .await
        .unwrap();
    let report = bridge.export_raw_diagnostics();
    assert!(!report.contains(OTHER), "报告包含另一账号的验票响应");
    assert!(report.contains(PRIOR));
    assert!(report.contains(RECOVERY));
}

#[tokio::test]
async fn 受控密码恢复核验前不可导出且取消时保留原记录() {
    for cancelled in [true, false] {
        let (bridge, scenario, _root) = bridge();
        verify(&bridge).await.unwrap();
        scenario.recovery.store(true, Ordering::SeqCst);
        scenario.pause_validation.store(true, Ordering::SeqCst);
        let control = BridgeRequiredRecoveryControl::new(2000).unwrap();
        let login = bridge.login_required_route_controlled(
            BridgeConnectionMode::Direct,
            ACCOUNT.into(),
            "synthetic-password".into(),
            &control,
        );
        tokio::pin!(login);
        tokio::select! {
            () = scenario.validation_started.notified() => {},
            result = &mut login => panic!("预期等待验票：{result:?}"),
        }
        let report = bridge.export_raw_diagnostics();
        assert!(report.contains(PRIOR));
        assert!(!report.contains(RECOVERY), "身份未确认时泄露登录响应");
        if cancelled {
            control.cancel();
            assert_eq!(
                login.await.unwrap_err().code,
                BridgeErrorCode::OperationConflict
            );
        } else {
            scenario.release_validation.notify_one();
            login.await.unwrap();
        }
        let report = bridge.export_raw_diagnostics();
        assert!(report.contains(PRIOR));
        assert_eq!(report.contains(RECOVERY), !cancelled);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn 共享材料锁延迟核验时隐藏暂存并在核验失败后保留原记录() {
    use crate::api::shared_account::BridgeSharedAccount;

    let (bridge, scenario, root) = bridge();
    for (name, contents) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), contents).unwrap();
    }
    bridge
        .bind_shared_account(
            &BridgeSharedAccount::capture(root.to_string_lossy().into(), 1, true).unwrap(),
            Some(ACCOUNT.into()),
        )
        .await
        .unwrap();
    verify(&bridge).await.unwrap();
    scenario.recovery.store(true, Ordering::SeqCst);
    scenario.pause_validation.store(true, Ordering::SeqCst);
    let bridge = Arc::new(bridge);
    let login = tokio::spawn({
        let bridge = bridge.clone();
        async move {
            let control = BridgeRequiredRecoveryControl::new(2000).unwrap();
            bridge
                .login_required_route_controlled(
                    BridgeConnectionMode::Direct,
                    ACCOUNT.into(),
                    "synthetic-password".into(),
                    &control,
                )
                .await
        }
    });
    tokio::time::timeout(
        Duration::from_secs(2),
        scenario.validation_started.notified(),
    )
    .await
    .unwrap();
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(root.join("materials.lock"))
        .unwrap();
    lock.try_lock().unwrap();
    scenario.release_validation.notify_one();
    scenario.validation_released.notified().await;
    assert!(!login.is_finished());
    let report = bridge.export_raw_diagnostics();
    assert!(report.contains(PRIOR));
    assert!(!report.contains(RECOVERY));
    std::fs::write(root.join("account-generation.v1"), "UBAA1:2").unwrap();
    lock.unlock().unwrap();
    assert!(login.await.unwrap().is_err());
    let report = bridge.export_raw_diagnostics();
    assert!(report.contains(PRIOR));
    assert!(!report.contains(RECOVERY));
}

#[tokio::test]
async fn 首次恢复持久会话时核验结果必须匹配本机绑定账号才可导出() {
    use crate::api::shared_account::BridgeSharedAccount;

    let (bridge, scenario, root) = bridge();
    for (name, contents) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), contents).unwrap();
    }
    let binding = BridgeSharedAccount::capture(root.to_string_lossy().into(), 1, true).unwrap();
    bridge
        .bind_shared_account(&binding, Some(ACCOUNT.into()))
        .await
        .unwrap();
    scenario.other.store(true, Ordering::SeqCst);

    let profile = verify(&bridge).await.unwrap().profile;
    assert_eq!(profile.school_id.as_deref(), Some(OTHER));
    assert!(!bridge.export_raw_diagnostics().contains(OTHER));
}
