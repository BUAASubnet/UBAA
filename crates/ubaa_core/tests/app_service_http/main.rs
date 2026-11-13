//! 由本地联调脚本显式运行，使用生产 Core 传输访问回环地址。

use std::{
    env, fs,
    net::Ipv4Addr,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};
use ubaa_core::facade::{
    ErrorKind, SharedAccountGuard, UbaaClient,
    app_service::{
        AppServiceConfig, BatchDisposition, ConfirmedAccount, Consent, CounterDimensions,
        CounterEvent, CounterResult, EraseAttempt, ErrorDimensions, ErrorEvent, Feature, Platform,
        Route, Surface, TelemetryEvent, TimingBucket, TimingDimensions, TimingMetric,
    },
};

#[cfg(feature = "test-contract")]
#[tokio::test]
#[ignore = "由 scripts/tests/app_service/http_e2e.py 启动本地 Worker 与 KV 后执行"]
async fn bootstrap_and_gate_over_http() {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };
    use ubaa_core::facade::{
        ErrorCode, NetworkState,
        app_service::{AppAnnouncementLevel, AppUpdateStatus, open_installation},
        testing::{
            GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
            with_routing_in_config_directory,
        },
    };

    #[derive(Clone)]
    struct SchoolTransport(Arc<AtomicUsize>);

    #[async_trait::async_trait]
    impl HttpTransport for SchoolTransport {
        async fn execute(&self, _request: HttpRequest) -> ubaa_core::facade::Result<HttpResponse> {
            self.0.fetch_add(1, Ordering::SeqCst);
            panic!("更新门控生效时不得交付学校请求");
        }
    }

    struct SchoolProbe;

    impl GatewayProbe for SchoolProbe {
        fn probe(&self, _budget: Duration) -> NetworkState {
            panic!("更新门控生效时不得探测校园网关");
        }
    }

    assert!(env::var_os("CI").is_none_or(|value| value.is_empty()));
    let port = test_port("UBAA_APP_SERVICE_TEST_PORT");
    let url = format!("http://{}:{port}", Ipv4Addr::LOCALHOST);
    let root = PathBuf::from(env::var_os("UBAA_APP_SERVICE_TEST_STATE").expect("缺少隔离配置目录"))
        .join("bootstrap");
    fs::create_dir(&root).unwrap();
    let config = test_config(&url);
    let gui = open_installation(&root, config.clone(), Surface::Gui, 1).unwrap();
    assert_eq!(gui.snapshot().unwrap().consent, Consent::Agreed(1));
    assert!(gui.snapshot().unwrap().can_telemetry());
    gui.set_telemetry(false).unwrap();
    let view = gui.refresh_bootstrap(true).await.unwrap();
    let update = view.update.as_ref().unwrap();
    assert_eq!(update.status, AppUpdateStatus::UpdateRequired);
    assert_eq!(update.latest_version.as_deref(), Some("2.2.0+17"));
    assert_eq!(update.min_supported_version.as_deref(), Some("2.1.0"));
    assert_eq!(
        update.url.as_deref(),
        Some("https://example.invalid/download")
    );
    assert!(update.gate_active);
    assert_eq!(view.announcements.len(), 1);
    let announcement = &view.announcements[0];
    assert_eq!(announcement.level, AppAnnouncementLevel::Popup);
    assert_eq!(announcement.body, "合成公告正文");
    assert_eq!(gui.refresh_bootstrap(false).await.unwrap(), view);

    let count = Arc::new(AtomicUsize::new(0));
    let school = SchoolTransport(Arc::clone(&count));
    let mut client =
        with_routing_in_config_directory(school.clone(), school, &root, SchoolProbe).unwrap();
    let command = Arc::new(
        client
            .open_app_service(config.clone(), Surface::Command, 1)
            .unwrap(),
    );
    client.bind_app_service(Arc::clone(&command));
    assert_eq!(command.refresh_bootstrap(true).await.unwrap(), view);
    let blocked = client.auth_status().await.unwrap_err();
    assert_eq!(blocked.code, ErrorCode::UpdateRequired);
    assert!(!blocked.retryable);
    assert_eq!(count.load(Ordering::SeqCst), 0);

    gui.mark_announcement_read(&announcement.id).unwrap();
    drop(gui);
    let restarted = open_installation(&root, config, Surface::Gui, 1).unwrap();
    let persisted = restarted.bootstrap_view().unwrap();
    assert_eq!(persisted.update, view.update);
    assert_eq!(persisted.announcements.len(), 0);
}

#[tokio::test]
#[ignore = "由 scripts/tests/app_service/http_e2e.py 启动本地 Worker 与 D1 后执行"]
async fn upload_retry_and_erase_over_http() {
    assert!(env::var_os("CI").is_none_or(|value| value.is_empty()));
    let port = test_port("UBAA_APP_SERVICE_TEST_PORT");
    let url = format!("http://{}:{port}", Ipv4Addr::LOCALHOST);
    let root = PathBuf::from(env::var_os("UBAA_APP_SERVICE_TEST_STATE").expect("缺少隔离配置目录"));
    if env::var_os("UBAA_APP_SERVICE_TEST_ERASE_CHILD").is_some() {
        let client = UbaaClient::open(&root).unwrap();
        let gui = client
            .open_app_service(test_config(&url), Surface::Gui, 1)
            .unwrap();
        assert_eq!(gui.erase_once().await.unwrap(), EraseAttempt::Pending);
        return;
    }
    reject_untrusted_certificate(&root).await;
    let config = test_config(&url);
    let client = UbaaClient::open(&root).expect("打开隔离配置目录");
    let gui = client
        .open_app_service(config.clone(), Surface::Gui, 1)
        .unwrap();
    assert!(gui.snapshot().unwrap().can_telemetry());
    let old_install = gui.snapshot().unwrap().install_id;
    assert!(old_install.is_some());

    // 合成已确认账号归属，所有请求只经过本地应用服务。
    fs::write(root.join("materials.lock"), "").unwrap();
    fs::write(root.join("transaction.v1"), "UBAA1:C").unwrap();
    fs::write(root.join("account-generation.v1"), "UBAA1:1").unwrap();
    let account = ConfirmedAccount::from_bound_account(
        SharedAccountGuard::new(&root, 1).unwrap(),
        format!("TQ{:02}-SYNTHETIC", 24),
    );
    let counter = TelemetryEvent::Counter(CounterDimensions {
        event: CounterEvent::FeatureLoaded,
        feature: Feature::Schedule,
        route: Route::Direct,
        result: CounterResult::Success,
    });
    let error = TelemetryEvent::Error(ErrorDimensions {
        event: ErrorEvent::FeatureFailed,
        feature: Feature::Grades,
        route: Route::Webvpn,
        error_code: "parse_error".into(),
        error_kind: ErrorKind::Upstream,
        retryable: false,
        source: None,
    });
    let timing = TelemetryEvent::Timing(TimingDimensions {
        metric: TimingMetric::FeatureLoad,
        feature: Feature::Schedule,
        route: Route::Direct,
        bucket: TimingBucket::Lt1000,
    });
    for event in [&counter, &counter, &error, &timing] {
        assert!(gui.enqueue(event, Some(&account)).unwrap());
    }

    let lost = gui.upload_once().await.unwrap();
    assert_eq!(lost.last_batch, Some(BatchDisposition::Retry));
    let retried = gui.upload_once().await.unwrap();
    assert_eq!(retried.last_batch, Some(BatchDisposition::Accepted));
    assert!(gui.freeze_next().unwrap().is_none());

    assert!(gui.enqueue(&counter, Some(&account)).unwrap());
    let (late, ()) = tokio::join!(gui.upload_once(), erase_in_another_process(&url));
    assert_eq!(
        late.unwrap().last_batch,
        Some(BatchDisposition::InstallErased)
    );
    assert_eq!(gui.snapshot().unwrap().erasing_install_id, old_install);
    gui.enter_basic().unwrap();
    drop(gui);
    drop(client);

    let reopened = UbaaClient::open(&root).unwrap();
    let command = reopened
        .open_app_service(config.clone(), Surface::Command, 1)
        .unwrap();
    let gui = reopened.open_app_service(config, Surface::Gui, 1).unwrap();
    let (command_result, gui_result) = tokio::join!(command.upload_once(), gui.upload_once());
    let command_result = command_result.unwrap();
    assert_eq!(command_result.erase, EraseAttempt::NotAttempted);
    assert_eq!(command_result.batches_sent, 0);
    assert_eq!(gui_result.unwrap().erase, EraseAttempt::Completed);
    let state = gui.snapshot().unwrap();
    assert_eq!(state.consent, Consent::Basic);
    assert!(state.install_id.is_some() && state.install_id != old_install);
    assert!(state.erasing_install_id.is_none());
}

async fn erase_in_another_process(url: &str) {
    let relay = reqwest::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(10))
        .build()
        .unwrap();
    // 中继收到旧批次后再启动另一个进程删除；D1 删除提交后才转发旧批次。
    assert_eq!(
        relay
            .get(format!("{url}/inflight"))
            .send()
            .await
            .unwrap()
            .status(),
        204,
    );
    let status = tokio::task::spawn_blocking(|| {
        Command::new(env::current_exe().unwrap())
            .args(["--ignored", "--exact", "upload_retry_and_erase_over_http"])
            .env("UBAA_APP_SERVICE_TEST_ERASE_CHILD", "1")
            .status()
            .unwrap()
    })
    .await
    .unwrap();
    assert!(status.success());
}

fn test_port(name: &str) -> u16 {
    env::var(name)
        .expect("请运行本地联调脚本")
        .parse()
        .expect("本地联调端口必须是数字")
}

fn test_config(url: &str) -> AppServiceConfig {
    AppServiceConfig::from_build(
        Some(url),
        Some("github"),
        Some("2.1.0-rc.1+15"),
        Platform::Macos,
        false,
    )
}

async fn reject_untrusted_certificate(root: &Path) {
    let port = test_port("UBAA_APP_SERVICE_TEST_TLS_PORT");
    let url = format!("https://{}:{port}", Ipv4Addr::LOCALHOST);
    let directory = root.join("tls_probe");
    fs::create_dir(&directory).unwrap();
    let client = UbaaClient::open(&directory).unwrap();
    let app = client
        .open_app_service(test_config(&url), Surface::Gui, 1)
        .unwrap();
    assert!(app.snapshot().unwrap().can_telemetry());
    let counter = TelemetryEvent::Counter(CounterDimensions {
        event: CounterEvent::AppStarted,
        feature: Feature::App,
        route: Route::None,
        result: CounterResult::Success,
    });
    assert!(app.enqueue(&counter, None).unwrap());
    let batch = app.freeze_next().unwrap().unwrap();
    let upload = app.upload_once().await.unwrap();
    assert_eq!(upload.last_batch, Some(BatchDisposition::Retry));
    assert!(app.freeze_next().unwrap().unwrap().id() == batch.id());
}
