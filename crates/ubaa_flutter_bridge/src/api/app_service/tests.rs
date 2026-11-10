use super::*;
use uuid::Uuid;

pub(in crate::api) struct TestDirectory(std::path::PathBuf);

impl TestDirectory {
    pub(in crate::api) fn new() -> Self {
        Self(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../.ubaa_local/app_service/test_bridge")
                .join(Uuid::new_v4().to_string()),
        )
    }

    pub(in crate::api) async fn open(
        &self,
        surface: BridgeAppServiceSurface,
        policy: u32,
        configured: bool,
    ) -> BridgeAppService {
        BridgeAppService::open(
            self.0.to_string_lossy().into_owned(),
            configured.then(|| "http://127.0.0.1:8787".to_owned()),
            Some("github".into()),
            Some("2.1.0-rc.1+15".into()),
            BridgeAppServicePlatform::Linux,
            false,
            surface,
            policy,
        )
        .await
        .unwrap()
    }
}

pub(in crate::api) fn panic_payload(service: &BridgeAppService) -> Vec<u8> {
    // 等待独立工作线程完成，不在测试的 panic 钩子里碰队列。
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(batch) = service.inner.core.freeze_next().unwrap() {
            return batch.body().to_vec();
        }
        assert!(std::time::Instant::now() < deadline, "panic 应进入本机队列");
        std::thread::sleep(Duration::from_millis(5));
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}

#[tokio::test]
async fn 共享状态投影包含实际同意版本和独立开关() {
    let directory = TestDirectory::new();
    let gui = directory.open(BridgeAppServiceSurface::Gui, 1, true).await;
    let initial = gui.state().await.unwrap();
    assert_eq!(initial.consent, BridgeAppServiceConsent::Unasked);
    assert!(!initial.can_erase);
    assert_eq!(
        gui.erase().await.unwrap(),
        BridgeAppServiceEraseOutcome::Unavailable
    );
    let agreed = gui.agree().await.unwrap();
    assert_eq!(agreed.consent, BridgeAppServiceConsent::Agreed);
    assert_eq!(agreed.agreed_policy_version, Some(1));
    assert!(agreed.telemetry_enabled);
    assert!(agreed.can_erase);

    assert!(!gui.set_telemetry(false).await.unwrap().telemetry_enabled);
    let command = directory
        .open(BridgeAppServiceSurface::Command, 1, true)
        .await;
    assert!(!command.state().await.unwrap().telemetry_enabled);
    assert!(command.agree().await.is_err());
    assert!(
        !command
            .enqueue_counter(
                BridgeTelemetryCounter::AppStarted,
                BridgeTelemetryFeature::App,
                BridgeTelemetryRoute::None,
                BridgeTelemetryResult::Success
            )
            .await
            .unwrap()
    );

    let disabled = directory.open(BridgeAppServiceSurface::Gui, 2, false).await;
    assert!(!disabled.state().await.unwrap().available);
    assert_eq!(
        disabled.agree().await.unwrap().agreed_policy_version,
        Some(1)
    );
    assert_eq!(
        command.state().await.unwrap().consent,
        BridgeAppServiceConsent::Agreed
    );

    let next = directory.open(BridgeAppServiceSurface::Gui, 2, true).await;
    let state = next.state().await.unwrap();
    assert_eq!(state.policy_version, 2);
    assert_eq!(state.agreed_policy_version, Some(1));
    assert_eq!(state.consent, BridgeAppServiceConsent::ReconsentRequired);
    let state = next.agree().await.unwrap();
    assert_eq!(state.agreed_policy_version, Some(2));
    assert!(!state.telemetry_enabled);
    assert_eq!(
        next.enter_basic().await.unwrap().consent,
        BridgeAppServiceConsent::Basic
    );
    assert_eq!(
        command.state().await.unwrap().consent,
        BridgeAppServiceConsent::Basic
    );
}
