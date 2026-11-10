use super::{AppService, BatchDisposition, EraseAttempt, UploadAttempt};
use crate::{
    app_service::{
        AppServiceConfig, Consent, CounterDimensions, CounterEvent, CounterResult, Feature,
        Platform, Route, Surface, TelemetryEvent,
    },
    error::{ErrorCode, ErrorKind, Result, UbaaError},
    ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport},
};
use async_trait::async_trait;
use std::{
    collections::VecDeque,
    path::{Path, PathBuf},
    process::Command,
    sync::Mutex,
    time::Duration,
};
use tokio::sync::oneshot;
use uuid::Uuid;

const ORIGIN: &str = "http://127.0.0.1:8787";

struct TestDirectory(PathBuf);

impl TestDirectory {
    fn new() -> Self {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/app_service/test_upload")
            .join(Uuid::new_v4().to_string());
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn open(&self, surface: Surface, hard_closed: bool) -> AppService {
        self.open_with(surface, hard_closed, Some(ORIGIN), 1)
    }

    fn open_with(
        &self,
        surface: Surface,
        hard_closed: bool,
        endpoint: Option<&str>,
        policy: u32,
    ) -> AppService {
        let config = AppServiceConfig::from_build(
            endpoint,
            Some("github"),
            Some("2.0.0"),
            Platform::Macos,
            false,
        );
        AppService::open(&self.0, config, surface, policy)
            .unwrap()
            .with_runtime(|| "2026-11-11T00:00:00Z".parse().unwrap(), hard_closed)
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}

fn enqueue(app: &AppService) {
    assert!(
        app.enqueue(
            &TelemetryEvent::Counter(CounterDimensions {
                event: CounterEvent::FeatureLoaded,
                feature: Feature::Schedule,
                route: Route::Direct,
                result: CounterResult::Success,
            }),
            None,
        )
        .unwrap()
    );
}

struct ScriptedTransport {
    statuses: Mutex<VecDeque<Option<u16>>>,
    requests: Mutex<Vec<HttpRequest>>,
}

impl ScriptedTransport {
    fn new(statuses: impl IntoIterator<Item = Option<u16>>) -> Self {
        Self {
            statuses: Mutex::new(statuses.into_iter().collect()),
            requests: Mutex::new(Vec::new()),
        }
    }

    fn take_requests(&self) -> Vec<HttpRequest> {
        std::mem::take(&mut *self.requests.lock().unwrap())
    }
}

#[async_trait]
impl HttpTransport for ScriptedTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = request.url.clone();
        self.requests.lock().unwrap().push(request);
        match self
            .statuses
            .lock()
            .unwrap()
            .pop_front()
            .expect("收到意外请求")
        {
            Some(status) => Ok(HttpResponse::new(status, url, Vec::new())),
            None => Err(UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "合成连接已断开",
            )),
        }
    }
}

#[tokio::test]
async fn 可重试响应保留原批次终态响应删除批次() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    gui.agree(1).unwrap();
    enqueue(&gui);
    let batch = gui.freeze_next().unwrap().unwrap();
    let transport = ScriptedTransport::new([Some(429), Some(503), None, Some(204)]);
    for _ in 0..3 {
        let attempt = gui.upload_with(&transport).await.unwrap();
        assert_eq!(attempt.batches_sent, 1);
        assert_eq!(attempt.last_batch, Some(BatchDisposition::Retry));
        assert_eq!(gui.freeze_next().unwrap().unwrap().id(), batch.id());
    }
    assert_eq!(
        gui.upload_with(&transport).await.unwrap().last_batch,
        Some(BatchDisposition::Accepted)
    );
    assert!(gui.freeze_next().unwrap().is_none());
    let requests = transport.take_requests();
    assert_eq!(requests.len(), 4);
    for request in requests {
        assert_eq!(request.method, HttpMethod::Post);
        assert_eq!(request.url, format!("{ORIGIN}/v1/telemetry"));
        assert_eq!(request.headers.len(), 1);
        assert_eq!(
            request.headers.get("content-type").unwrap(),
            "application/json"
        );
        assert!(request.body == batch.body());
    }

    for (status, disposition) in [
        (410, BatchDisposition::InstallErased),
        (400, BatchDisposition::InvalidPayload),
        (413, BatchDisposition::InvalidPayload),
    ] {
        enqueue(&gui);
        let transport = ScriptedTransport::new([Some(status)]);
        let result = gui.upload_with(&transport).await.unwrap();
        assert_eq!(result.last_batch, Some(disposition));
        assert!(gui.freeze_next().unwrap().is_none());
    }
}

#[tokio::test]
async fn 硬关闭不上传且仍允许删除已上传数据() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    gui.agree(1).unwrap();
    enqueue(&gui);
    drop(gui);

    let gui = root.open(Surface::Gui, true);
    let transport = ScriptedTransport::new([Some(204)]);
    assert_eq!(
        gui.upload_with(&transport).await.unwrap(),
        UploadAttempt::default()
    );
    assert!(transport.take_requests().is_empty());

    gui.begin_erase().unwrap().unwrap();
    assert_eq!(
        gui.upload_with(&transport).await.unwrap().erase,
        EraseAttempt::Completed
    );
    let requests = transport.take_requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].url, format!("{ORIGIN}/v1/telemetry/erase"));
    assert!(gui.snapshot().unwrap().erasing_install_id.is_none());
    assert!(gui.freeze_next().unwrap().is_none());
}

struct PausedTransport {
    handshake: Mutex<Option<(oneshot::Sender<HttpRequest>, oneshot::Receiver<()>)>>,
    status: u16,
}

#[async_trait]
impl HttpTransport for PausedTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = request.url.clone();
        let (sent, resume) = self.handshake.lock().unwrap().take().expect("收到意外请求");
        sent.send(request).unwrap();
        resume.await.unwrap();
        Ok(HttpResponse::new(self.status, url, Vec::new()))
    }
}

const UPLOAD_CHILD_ROLE: &str = "UBAA_APP_SERVICE_UPLOAD_CHILD_ROLE";
const UPLOAD_CHILD_PATH: &str = "UBAA_APP_SERVICE_UPLOAD_CHILD_PATH";

fn child(path: &Path, role: &str) {
    let (_, module) = module_path!().split_once("::").unwrap();
    let status = Command::new(std::env::current_exe().unwrap())
        .arg("--exact")
        .arg(format!("{module}::上传重试测试子进程"))
        .env(UPLOAD_CHILD_ROLE, role)
        .env(UPLOAD_CHILD_PATH, path)
        .status()
        .unwrap();
    assert!(status.success(), "子进程未完成 {role}");
}

#[tokio::test]
async fn 上传重试测试子进程() {
    let Ok(role) = std::env::var(UPLOAD_CHILD_ROLE) else {
        return;
    };
    let path = std::env::var_os(UPLOAD_CHILD_PATH).unwrap();
    let surface = if role == "initial-gui" {
        Surface::Gui
    } else {
        Surface::Command
    };
    let config = AppServiceConfig::from_build(
        Some(ORIGIN),
        Some("github"),
        Some("2.0.0"),
        Platform::Macos,
        false,
    );
    let app = AppService::open(Path::new(&path), config, surface, 1).unwrap();
    assert_eq!(app.snapshot().unwrap().consent, Consent::Basic);
    if surface == Surface::Gui {
        app.begin_erase().unwrap().unwrap();
        let transport = ScriptedTransport::new([None]);
        assert_eq!(
            app.upload_with(&transport).await.unwrap().erase,
            EraseAttempt::Pending
        );
        assert_eq!(transport.take_requests().len(), 1);
    } else {
        assert!(app.snapshot().unwrap().erasing_install_id.is_some());
        let transport = ScriptedTransport::new([]);
        assert_eq!(
            app.upload_with(&transport).await.unwrap(),
            UploadAttempt::default()
        );
        assert!(transport.take_requests().is_empty());
    }
}

#[tokio::test]
async fn 基础模式删除结果未知后重启仅图形宿主重试() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    gui.agree(1).unwrap();
    let old_install = gui.snapshot().unwrap().install_id.unwrap();
    gui.enter_basic().unwrap();
    drop(gui);

    child(&root.0, "initial-gui");
    let gui = root.open(Surface::Gui, false);
    assert_eq!(
        gui.snapshot().unwrap().erasing_install_id,
        Some(old_install)
    );
    let (sent, received) = oneshot::channel();
    let (unblock, resume) = oneshot::channel();
    let transport = PausedTransport {
        handshake: Mutex::new(Some((sent, resume))),
        status: 204,
    };
    let (gui_attempt, ()) = tokio::join!(gui.upload_with(&transport), async {
        let request = tokio::time::timeout(Duration::from_secs(3), received)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(request.url, format!("{ORIGIN}/v1/telemetry/erase"));
        let body = serde_json::from_slice::<serde_json::Value>(&request.body).unwrap();
        assert!(body == serde_json::json!({"schema": 1, "install_id": old_install}));
        // 图形宿主已发送、尚未收到响应时启动独立命令进程。
        child(&root.0, "parallel-command");
        unblock.send(()).unwrap();
    });
    assert_eq!(gui_attempt.unwrap().erase, EraseAttempt::Completed);
    assert!(gui.snapshot().unwrap().erasing_install_id.is_none());
    assert_ne!(gui.snapshot().unwrap().install_id, Some(old_install));
}

#[tokio::test]
async fn 上传等响应时另一连接可删除且晚到的503不会恢复批次() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    let other = root.open(Surface::Gui, false);
    gui.agree(1).unwrap();
    enqueue(&gui);
    let (sent, received) = oneshot::channel();
    let (unblock, resume) = oneshot::channel();
    let transport = PausedTransport {
        handshake: Mutex::new(Some((sent, resume))),
        status: 503,
    };
    let (attempt, ()) = tokio::join!(gui.upload_with(&transport), async {
        let request = tokio::time::timeout(Duration::from_secs(3), received)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(request.url, format!("{ORIGIN}/v1/telemetry"));
        let old = other.begin_erase().unwrap().unwrap();
        assert!(other.finish_erase(old).unwrap());
        unblock.send(()).unwrap();
    });
    assert_eq!(attempt.unwrap().last_batch, Some(BatchDisposition::Retry));
    assert!(gui.freeze_next().unwrap().is_none());
}

#[tokio::test]
async fn 命令宿主同意时先重试删除并阻止旧数据上报() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    let command = root.open(Surface::Command, false);
    gui.agree(1).unwrap();
    enqueue(&gui);
    let previous = gui.freeze_next().unwrap().unwrap();
    gui.begin_erase().unwrap().unwrap();
    let transport = ScriptedTransport::new([Some(503), Some(204)]);
    assert_eq!(
        command.upload_with(&transport).await.unwrap().erase,
        EraseAttempt::Pending
    );
    assert_eq!(
        command.snapshot().unwrap().erasing_install_id,
        Some(previous.install_id())
    );
    assert_eq!(
        command.upload_with(&transport).await.unwrap().erase,
        EraseAttempt::Completed
    );
    let requests = transport.take_requests();
    assert_eq!(requests.len(), 2);
    assert!(
        requests
            .iter()
            .all(|request| request.url == format!("{ORIGIN}/v1/telemetry/erase"))
    );
    assert!(command.freeze_next().unwrap().is_none());
}

#[tokio::test]
async fn 配置停用时不发删除或上传请求() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    gui.agree(1).unwrap();
    enqueue(&gui);
    gui.begin_erase().unwrap().unwrap();
    drop(gui);

    let gui = root.open_with(Surface::Gui, false, None, 1);
    let transport = ScriptedTransport::new([]);
    assert_eq!(
        gui.upload_with(&transport).await.unwrap(),
        UploadAttempt::default()
    );
    assert_eq!(gui.upload_once().await.unwrap(), UploadAttempt::default());
    assert_eq!(gui.erase_once().await.unwrap(), EraseAttempt::NotAttempted);
    assert!(transport.take_requests().is_empty());
    assert!(gui.snapshot().unwrap().erasing_install_id.is_some());
}

#[tokio::test]
async fn 最近交付尝试跨宿主共享且六小时后才能重试() {
    let root = TestDirectory::new();
    let gui = root.open(Surface::Gui, false);
    gui.agree(1).unwrap();
    let transport = ScriptedTransport::new([Some(503), Some(204)]);
    // 没有数据时不占用之后的交付机会。
    assert_eq!(
        gui.upload_scheduled_with(&transport, false, None)
            .await
            .unwrap()
            .batches_sent,
        0
    );
    enqueue(&gui);
    assert_eq!(
        gui.upload_scheduled_with(&transport, true, None)
            .await
            .unwrap()
            .batches_sent,
        1
    );
    let command = root
        .open(Surface::Command, false)
        .with_runtime(|| "2026-11-11T05:59:59Z".parse().unwrap(), false);
    assert_eq!(
        command
            .upload_scheduled_with(&transport, true, None)
            .await
            .unwrap()
            .batches_sent,
        0
    );
    let command = root
        .open(Surface::Command, false)
        .with_runtime(|| "2026-11-11T06:00:00Z".parse().unwrap(), false);
    assert_eq!(
        command
            .upload_scheduled_with(&transport, false, Some(Duration::ZERO))
            .await
            .unwrap()
            .batches_sent,
        0
    );
    assert_eq!(
        command
            .upload_scheduled_with(&transport, false, None)
            .await
            .unwrap()
            .batches_sent,
        1
    );
    assert_eq!(transport.take_requests().len(), 2);
}
