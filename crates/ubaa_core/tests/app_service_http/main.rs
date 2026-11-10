//! 由本地联调脚本显式运行，使用生产 Core 传输访问回环地址。

use std::{
    env, fs,
    net::Ipv4Addr,
    path::{Path, PathBuf},
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

#[tokio::test]
#[ignore = "由 scripts/tests/app_service/http_e2e.py 启动本地 Worker 与 D1 后执行"]
async fn upload_retry_and_erase_over_http() {
    assert!(env::var_os("CI").is_none_or(|value| value.is_empty()));
    let port = test_port("UBAA_APP_SERVICE_TEST_PORT");
    let url = format!("http://{}:{port}", Ipv4Addr::LOCALHOST);
    let root = PathBuf::from(env::var_os("UBAA_APP_SERVICE_TEST_STATE").expect("缺少隔离配置目录"));
    reject_untrusted_certificate(&root).await;
    let config = test_config(&url);
    let client = UbaaClient::open(&root).expect("打开隔离配置目录");
    let gui = client
        .open_app_service(config.clone(), Surface::Gui, 1)
        .unwrap();
    gui.agree(1).unwrap();
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
    let relay = reqwest::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(10))
        .build()
        .unwrap();
    let (late, lost_erase) = tokio::join!(gui.upload_once(), async {
        // 等 HTTP 中继收到旧批次再发删除；中继等 D1 删除提交后才转发旧批次。
        assert_eq!(
            relay
                .get(format!("{url}/inflight"))
                .send()
                .await
                .unwrap()
                .status(),
            204,
        );
        gui.erase_once().await.unwrap()
    });
    assert_eq!(
        late.unwrap().last_batch,
        Some(BatchDisposition::InstallErased)
    );
    assert_eq!(lost_erase, EraseAttempt::Pending);
    assert!(gui.snapshot().unwrap().erasing_install_id == old_install);
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
    app.agree(1).unwrap();
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
