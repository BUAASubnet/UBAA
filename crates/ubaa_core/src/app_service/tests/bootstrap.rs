use super::{AppBootstrapView, AppService, AppUpdateStatus, compare_versions, parse_response};
use crate::{
    app_service::{AppServiceConfig, Channel, Platform, Surface},
    error::Result,
    ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport},
};
use async_trait::async_trait;
use chrono::{DateTime, TimeDelta, Utc};
use serde_json::{Value, json};
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use tokio::sync::oneshot;
use uuid::Uuid;

struct TestDirectory(PathBuf);

impl TestDirectory {
    fn new() -> Self {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/app_service/test_bootstrap")
            .join(Uuid::new_v4().to_string());
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn open(
        &self,
        channel: &str,
        version: &str,
        surface: Surface,
        policy: u32,
        clock: &Arc<Mutex<DateTime<Utc>>>,
    ) -> AppService {
        let clock = Arc::clone(clock);
        AppService::open(
            &self.0,
            AppServiceConfig::from_build(
                Some("http://127.0.0.1:8787"),
                Some(channel),
                Some(version),
                Platform::Android,
                false,
            ),
            surface,
            policy,
        )
        .unwrap()
        .with_runtime(move || *clock.lock().unwrap(), true)
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}

fn clock() -> Arc<Mutex<DateTime<Utc>>> {
    Arc::new(Mutex::new("2026-11-11T00:00:00Z".parse().unwrap()))
}

fn bootstrap_fixtures() -> Value {
    serde_json::from_str(include_str!(
        "../../../../../fixtures/app_service/bootstrap.json"
    ))
    .unwrap()
}

fn response_case(name: &str) -> Value {
    bootstrap_fixtures()["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["name"] == name)
        .unwrap()["payload"]
        .clone()
}

#[test]
fn 版本顺序使用共享样例() {
    let fixture: Vec<Value> = serde_json::from_str(include_str!(
        "../../../../../fixtures/app_service/version_order.json"
    ))
    .unwrap();
    for entry in fixture {
        let left = entry["left"].as_str().unwrap();
        let right = entry["right"].as_str().unwrap();
        let expected = entry["order"].as_i64().unwrap();
        assert_eq!(
            compare_versions(left, right) as i64,
            expected,
            "{left} vs {right}"
        );
    }
}

#[test]
fn 启动配置使用共享的向前兼容样例() {
    for entry in bootstrap_fixtures()["cases"].as_array().unwrap() {
        if entry["schema"] != "bootstrapResponse" {
            continue;
        }
        let actual = parse_response(
            &serde_json::to_vec(&entry["payload"]).unwrap(),
            Channel::Github,
        );
        assert_eq!(
            actual.is_some(),
            entry["valid"] == true,
            "{}",
            entry["name"]
        );
        if let Some(response) = actual {
            assert_eq!(json!(response.update.status), entry["effectiveStatus"]);
            assert_eq!(
                json!(
                    response
                        .announcements
                        .iter()
                        .map(|item| &item.id)
                        .collect::<Vec<_>>()
                ),
                entry["acceptedAnnouncementIds"]
            );
        }
    }
}

struct Mock {
    requests: Mutex<Vec<HttpRequest>>,
    status: u16,
    body: Vec<u8>,
}

impl Mock {
    fn response(status: u16, body: &Value) -> Self {
        Self {
            requests: Mutex::new(Vec::new()),
            status,
            body: serde_json::to_vec(body).unwrap(),
        }
    }

    fn named(name: &str) -> Self {
        Self::response(200, &response_case(name))
    }

    fn count(&self) -> usize {
        self.requests.lock().unwrap().len()
    }
}

#[async_trait]
impl HttpTransport for Mock {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let response = HttpResponse::new(self.status, &request.url, self.body.clone());
        self.requests.lock().unwrap().push(request);
        Ok(response)
    }
}

fn active(view: &AppBootstrapView) -> bool {
    view.update
        .as_ref()
        .is_some_and(|update| update.gate_active)
}

#[tokio::test]
async fn 启动刷新隔离身份并按六小时节流且命令模式只读门控() {
    let dir = TestDirectory::new();
    let clock = clock();
    let gui = dir.open("github", "1.9.0+9", Surface::Gui, 1, &clock);
    let required = Mock::named("未知顶层字段不妨碍识别更新要求");
    assert!(
        gui.refresh_bootstrap_with(&required, true)
            .await
            .unwrap()
            .update
            .is_none()
    );
    assert_eq!(required.count(), 0);
    gui.agree(1).unwrap();
    assert!(!gui.snapshot().unwrap().can_telemetry());
    assert!(active(
        &gui.refresh_bootstrap_with(&required, true).await.unwrap()
    ));
    {
        let requests = required.requests.lock().unwrap();
        let request = &requests[0];
        assert_eq!(request.method, HttpMethod::Get);
        assert_eq!(
            request.url,
            "http://127.0.0.1:8787/v1/bootstrap?schema=1&platform=android&channel=github&version=1.9.0%2B9"
        );
        assert!(request.headers.is_empty());
        assert!(request.body.is_empty());
    }
    let restarted = dir.open("github", "1.9.0+9", Surface::Gui, 1, &clock);
    assert!(active(&restarted.bootstrap_view().unwrap()));
    *clock.lock().unwrap() += TimeDelta::seconds(6 * 60 * 60 - 1);
    assert!(active(
        &restarted
            .refresh_bootstrap_with(&required, false)
            .await
            .unwrap()
    ));
    assert_eq!(required.count(), 1);
    *clock.lock().unwrap() += TimeDelta::seconds(1);
    assert!(active(
        &restarted
            .refresh_bootstrap_with(&required, false)
            .await
            .unwrap()
    ));
    let command = dir.open("github", "1.9.0+9", Surface::Command, 1, &clock);
    assert!(command.update_gate_active().unwrap());
    assert!(active(
        &command
            .refresh_bootstrap_with(&required, true)
            .await
            .unwrap()
    ));
    assert_eq!(required.count(), 2);
    let other = dir.open("app_store", "1.9.0+9", Surface::Command, 1, &clock);
    let upgraded = dir.open("github", "2.0.0", Surface::Command, 1, &clock);
    assert!(!other.update_gate_active().unwrap());
    assert!(!upgraded.update_gate_active().unwrap());
    let upgraded_view = upgraded.bootstrap_view().unwrap();
    assert_eq!(
        upgraded_view.update.unwrap().status,
        AppUpdateStatus::Unknown
    );
    assert!(upgraded_view.announcements.is_empty());
}

#[tokio::test]
async fn 门控在撤回时停用并在重新同意刷新失败或未知状态时保留旧记录() {
    let dir = TestDirectory::new();
    let clock = clock();
    let gui = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    gui.agree(1).unwrap();
    let required = Mock::named("未知顶层字段不妨碍识别更新要求");
    assert!(active(
        &gui.refresh_bootstrap_with(&required, true).await.unwrap()
    ));
    let new_policy = dir.open("github", "1.9.0", Surface::Gui, 2, &clock);
    assert!(!gui.update_gate_active().unwrap());
    assert!(
        new_policy
            .refresh_bootstrap_with(&required, true)
            .await
            .unwrap()
            .update
            .is_none()
    );
    assert_eq!(required.count(), 1);
    gui.enter_basic().unwrap();
    assert!(!new_policy.update_gate_active().unwrap());
    new_policy.agree(2).unwrap();
    assert!(gui.update_gate_active().unwrap());

    let failure = Mock::response(503, &json!({}));
    assert!(active(
        &new_policy
            .refresh_bootstrap_with(&failure, true)
            .await
            .unwrap()
    ));
    assert_eq!(failure.count(), 1);
    for invalid in ["已知接口版本错误", "已知版本字段不是正式版本"] {
        assert!(active(
            &new_policy
                .refresh_bootstrap_with(&Mock::named(invalid), true)
                .await
                .unwrap()
        ));
    }
    let unknown = Mock::named("未知状态和无法识别的单条公告");
    let view = new_policy
        .refresh_bootstrap_with(&unknown, true)
        .await
        .unwrap();
    let update = view.update.unwrap();
    assert_eq!(update.status, AppUpdateStatus::Unknown);
    assert!(update.gate_active);
    assert_eq!(update.min_supported_version.as_deref(), Some("2.0.0"));
    assert_eq!(
        update.url.as_deref(),
        Some("https://example.invalid/releases")
    );
    assert_eq!(view.announcements.len(), 1);

    let unknown = Mock::named("未配置渠道返回空更新字段");
    let view = new_policy
        .refresh_bootstrap_with(&unknown, true)
        .await
        .unwrap();
    assert!(active(&view));
    assert!(view.update.unwrap().url.is_some());
    let available = Mock::named("更新和公告");
    assert!(!active(
        &new_policy
            .refresh_bootstrap_with(&available, true)
            .await
            .unwrap()
    ));
    assert!(!gui.update_gate_active().unwrap());
}

#[tokio::test]
async fn 公告已读与忽略版本跨重启且公告在本机到期() {
    let dir = TestDirectory::new();
    let clock = clock();
    let gui = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    gui.agree(1).unwrap();
    let payload = response_case("更新和公告");
    let mut second = payload["announcements"][0].clone();
    second["id"] = json!("2026-11-10-002");
    second["ends_at"] = json!("2026-11-11T00:00:01Z");
    let mut all = payload.clone();
    all["announcements"].as_array_mut().unwrap().push(second);
    let transport = Mock::response(200, &all);
    let view = gui.refresh_bootstrap_with(&transport, true).await.unwrap();
    assert_eq!(view.announcements.len(), 2);
    assert!(!view.update.unwrap().available_dismissed);
    gui.mark_announcement_read("2026-11-10-001").unwrap();
    gui.dismiss_update_available("2.1.0+15").unwrap();
    drop(gui);

    let gui = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    let view = gui.bootstrap_view().unwrap();
    assert_eq!(view.announcements[0].id, "2026-11-10-002");
    assert!(view.update.unwrap().available_dismissed);
    *clock.lock().unwrap() += TimeDelta::seconds(1);
    assert!(gui.bootstrap_view().unwrap().announcements.is_empty());
    all["update"]["latest_version"] = json!("2.1.0+16");
    let view = gui
        .refresh_bootstrap_with(&Mock::response(200, &all), true)
        .await
        .unwrap();
    assert!(!view.update.unwrap().available_dismissed);
}

struct Delayed {
    started: Mutex<Option<oneshot::Sender<()>>>,
    resume: tokio::sync::Mutex<oneshot::Receiver<()>>,
    body: Vec<u8>,
}

#[async_trait]
impl HttpTransport for Delayed {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.started
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .send(())
            .unwrap();
        (&mut *self.resume.lock().await).await.unwrap();
        Ok(HttpResponse::new(200, request.url, self.body.clone()))
    }
}

#[tokio::test]
async fn 撤回前启动的响应不会在重新同意后改变记录() {
    let dir = TestDirectory::new();
    let clock = clock();
    let gui = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    let other = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    gui.agree(1).unwrap();
    let required = Mock::named("未知顶层字段不妨碍识别更新要求");
    assert!(active(
        &gui.refresh_bootstrap_with(&required, true).await.unwrap()
    ));

    let (started_tx, started_rx) = oneshot::channel();
    let (resume_tx, resume_rx) = oneshot::channel();
    let transport = Delayed {
        started: Mutex::new(Some(started_tx)),
        resume: tokio::sync::Mutex::new(resume_rx),
        body: serde_json::to_vec(&response_case("更新和公告")).unwrap(),
    };
    let (view, ()) = tokio::join!(gui.refresh_bootstrap_with(&transport, true), async {
        started_rx.await.unwrap();
        other.enter_basic().unwrap();
        other.agree(1).unwrap();
        resume_tx.send(()).unwrap();
    });
    assert!(active(&view.unwrap()));
    assert!(other.update_gate_active().unwrap());
}

#[test]
fn 必需字段和商店链接按已知取值校验() {
    let mut payload = response_case("更新和公告");
    let check = |value: &Value, channel| {
        parse_response(&serde_json::to_vec(value).unwrap(), channel).is_some()
    };
    assert!(!check(&payload, Channel::AppStore));
    payload["update"]["url"] = json!("https://apps.apple.com/app/id123");
    assert!(check(&payload, Channel::AppStore));
    payload["update"]["url"] = json!("https://apps.apple.com.example.invalid/app/id123");
    assert!(!check(&payload, Channel::AppStore));
    payload["update"]["url"] = json!("https://appgallery.cloud.huawei.com/ag/n/app/test");
    assert!(check(&payload, Channel::AppGallery));
    payload["update"]["url"] = json!("https://appgallery.huawei.com/#/app/test");
    assert!(check(&payload, Channel::AppGallery));

    payload["update"]["latest_version"] = Value::Null;
    assert!(!check(&payload, Channel::AppGallery));
    payload["update"]["status"] = json!("update_required");
    payload["update"]["min_supported_version"] = Value::Null;
    assert!(!check(&payload, Channel::AppGallery));
    payload["update"]["min_supported_version"] = json!("2.0.0");
    assert!(check(&payload, Channel::AppGallery));
    payload["update"]
        .as_object_mut()
        .unwrap()
        .remove("latest_version");
    assert!(!check(&payload, Channel::AppGallery));
}

#[tokio::test]
async fn 成功响应明确解除门控且旧请求不能覆盖新响应() {
    let dir = TestDirectory::new();
    let clock = clock();
    let first = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    let second = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    first.agree(1).unwrap();
    let required = Mock::named("未知顶层字段不妨碍识别更新要求");
    assert!(active(
        &first.refresh_bootstrap_with(&required, true).await.unwrap()
    ));
    let mut update = response_case("更新和公告");
    update["update"]["status"] = json!("up_to_date");
    update["update"]["release_notes"] = Value::Null;
    let up_to_date = Mock::response(200, &update);
    let (started_tx, started_rx) = oneshot::channel();
    let (resume_tx, resume_rx) = oneshot::channel();
    let transport = Delayed {
        started: Mutex::new(Some(started_tx)),
        resume: tokio::sync::Mutex::new(resume_rx),
        body: required.body.clone(),
    };
    let (view, ()) = tokio::join!(first.refresh_bootstrap_with(&transport, true), async {
        started_rx.await.unwrap();
        assert!(!active(
            &second
                .refresh_bootstrap_with(&up_to_date, true)
                .await
                .unwrap()
        ));
        resume_tx.send(()).unwrap();
    });
    assert_eq!(
        view.unwrap().update.unwrap().status,
        AppUpdateStatus::UpToDate
    );
    assert!(!first.update_gate_active().unwrap());
}

struct Hanging;

#[async_trait]
impl HttpTransport for Hanging {
    async fn execute(&self, _: HttpRequest) -> Result<HttpResponse> {
        std::future::pending().await
    }
}

#[tokio::test]
async fn 启动配置五秒超时后保留门控() {
    use std::time::{Duration, Instant};
    let dir = TestDirectory::new();
    let clock = clock();
    let gui = dir.open("github", "1.9.0", Surface::Gui, 1, &clock);
    gui.agree(1).unwrap();
    let required = Mock::named("未知顶层字段不妨碍识别更新要求");
    assert!(active(
        &gui.refresh_bootstrap_with(&required, true).await.unwrap()
    ));

    let started = Instant::now();
    let view = tokio::time::timeout(
        Duration::from_secs(8),
        gui.refresh_bootstrap_with(&Hanging, true),
    )
    .await
    .unwrap()
    .unwrap();
    assert!(started.elapsed() >= Duration::from_secs(5));
    assert!(active(&view));
}
