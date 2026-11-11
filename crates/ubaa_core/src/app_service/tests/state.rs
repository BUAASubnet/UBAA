use super::{
    AppService, AppServiceConfig, BatchDisposition, Consent, FrozenBatch,
    types::{
        CounterDimensions, CounterEvent, CounterResult, Feature, Platform, Route, Surface,
        TelemetryEvent,
    },
};
use chrono::{DateTime, Utc};
use std::{
    convert::identity,
    path::{Path, PathBuf},
    process::Command,
};
use uuid::Uuid;

const LOOPBACK: &str = "http://127.0.0.1:8787";
const CHANNEL: &str = "github";
const VERSION: &str = "2.1.0-rc.1+15";
const EVENT: TelemetryEvent = TelemetryEvent::Counter(CounterDimensions {
    event: CounterEvent::FeatureLoaded,
    feature: Feature::Schedule,
    route: Route::Direct,
    result: CounterResult::Success,
});

fn now() -> DateTime<Utc> {
    "2026-11-10T16:00:00Z".parse().unwrap()
}

struct TestDirectory(PathBuf);

impl TestDirectory {
    fn new() -> Self {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/app_service/test_state")
            .join(Uuid::new_v4().to_string());
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).expect("清理合成 SQLite 测试目录");
    }
}

fn config() -> AppServiceConfig {
    AppServiceConfig::from_build(
        Some(LOOPBACK),
        Some(CHANNEL),
        Some(VERSION),
        Platform::Macos,
        false,
    )
}

fn open(path: &Path, surface: Surface) -> AppService {
    open_with_policy(path, surface, 1)
}

fn open_with_policy(path: &Path, surface: Surface, version: u32) -> AppService {
    AppService::open(path, config(), surface, version)
        .unwrap()
        .with_runtime(now, false)
}

fn install(app: &AppService) -> Uuid {
    app.snapshot().unwrap().install_id.unwrap()
}

fn queue(app: &AppService) {
    assert!(app.enqueue(&EVENT, None).unwrap());
}

fn freeze(app: &AppService) -> FrozenBatch {
    app.freeze_next().unwrap().expect("应有已冻结批次")
}

fn assert_send_blocked(app: &AppService, batch_id: Uuid) {
    let result: Option<()> = app
        .with_batch_for_send(batch_id, |_| panic!("禁止的批次进入传输层"))
        .unwrap();
    assert!(result.is_none());
}

#[test]
fn 图形首次启动默认启用且重启和政策升级保留关闭与撤回选择() {
    let root = TestDirectory::new();
    let command = open(root.path(), Surface::Command);
    assert!(!command.enqueue(&EVENT, None).unwrap());
    let gui = open(root.path(), Surface::Gui);
    let state = gui.snapshot().unwrap();
    assert_eq!(state.consent, Consent::Agreed(1));
    assert_eq!(state.telemetry_enabled, Some(true));
    let first_install = install(&gui);
    queue(&command);

    gui.set_telemetry(false).unwrap();
    let updated = open_with_policy(root.path(), Surface::Gui, 2);
    assert_eq!(updated.snapshot().unwrap().consent, Consent::Agreed(2));
    assert_eq!(updated.snapshot().unwrap().telemetry_enabled, Some(false));
    assert_eq!(install(&updated), first_install);
    assert!(!command.enqueue(&EVENT, None).unwrap());
    assert!(updated.freeze_next().unwrap().is_none());

    updated.enter_basic().unwrap();
    let restarted = open_with_policy(root.path(), Surface::Gui, 3);
    assert_eq!(restarted.snapshot().unwrap().consent, Consent::Basic);
    assert!(!restarted.snapshot().unwrap().can_bootstrap());
    assert!(!command.enqueue(&EVENT, None).unwrap());
}

#[test]
fn 关闭统计后接受新版政策仍关闭并保持队列为空() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    assert_eq!(gui.snapshot().unwrap().consent, Consent::Agreed(1));
    let first_install = install(&gui);
    assert_eq!(first_install.get_version(), Some(uuid::Version::Random));
    assert_eq!(gui.snapshot().unwrap().telemetry_enabled, Some(true));
    queue(&gui);
    let old_batch = freeze(&gui);
    queue(&gui);

    assert!(gui.set_telemetry(false).unwrap());
    assert!(gui.snapshot().unwrap().can_bootstrap());
    let gui = open_with_policy(root.path(), Surface::Gui, 2);
    let state = gui.snapshot().unwrap();
    assert_eq!(state.consent, Consent::Agreed(2));
    assert_eq!(state.telemetry_enabled, Some(false));
    assert!(state.can_bootstrap());
    assert!(!gui.enqueue(&EVENT, None).unwrap());
    assert_send_blocked(&gui, old_batch.id());
    assert!(gui.set_telemetry(true).unwrap());
    assert_eq!(install(&gui), first_install);
    assert!(gui.freeze_next().unwrap().is_none());
}

#[test]
fn 命令政策升级暂存原批次且撤回保留独立开关() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    gui.enter_basic().unwrap();
    let state = gui.snapshot().unwrap();
    assert_eq!(state.consent, Consent::Basic);
    assert_eq!(state.telemetry_enabled, Some(true));
    assert!(state.install_id.is_some());

    gui.agree(1).unwrap();
    queue(&gui);
    let old_batch = freeze(&gui);
    queue(&gui);
    let first_install = install(&gui);
    let command = open(root.path(), Surface::Command);
    let _updated = open_with_policy(root.path(), Surface::Command, 2);
    assert!(gui.agree(1).is_err());
    assert!(command.agree(2).is_err());
    assert_eq!(
        command.snapshot().unwrap().consent,
        Consent::ReconsentRequired(2)
    );
    assert!(!command.enqueue(&EVENT, None).unwrap());
    assert!(command.freeze_next().unwrap().is_none());
    assert_send_blocked(&command, old_batch.id());
    assert!(gui.snapshot().unwrap().can_erase());
    assert!(!command.snapshot().unwrap().can_erase());

    gui.agree(2).unwrap();
    assert_eq!(freeze(&command).id(), old_batch.id());
    assert!(
        command
            .finish_batch(old_batch.id(), BatchDisposition::Accepted)
            .unwrap()
    );
    let retained_pending = freeze(&command);
    assert!(command.snapshot().unwrap().can_telemetry());
    assert!(!command.snapshot().unwrap().can_bootstrap());
    gui.enter_basic().unwrap();
    let state = gui.snapshot().unwrap();
    assert_eq!(state.consent, Consent::Basic);
    assert_eq!(state.telemetry_enabled, Some(true));
    assert!(!state.can_bootstrap());
    assert!(state.can_erase());
    assert_send_blocked(&command, retained_pending.id());

    gui.agree(2).unwrap();
    assert_eq!(install(&gui), first_install);
    assert!(gui.freeze_next().unwrap().is_none());
    assert!(gui.set_telemetry(false).unwrap());
    gui.enter_basic().unwrap();
    gui.agree(2).unwrap();
    assert_eq!(gui.snapshot().unwrap().telemetry_enabled, Some(false));
}

#[test]
fn 基础模式只有图形进程可以交付已标记的删除() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    let command = open(root.path(), Surface::Command);
    gui.agree(1).unwrap();
    let first_install = install(&gui);
    gui.set_telemetry(false).unwrap();
    gui.enter_basic().unwrap();

    assert!(gui.pending_erase_for_send().unwrap().is_none());
    assert_eq!(gui.begin_erase().unwrap(), Some(first_install));
    assert_eq!(gui.pending_erase_for_send().unwrap(), Some(first_install));
    assert!(command.pending_erase_for_send().unwrap().is_none());

    gui.agree(1).unwrap();
    assert_eq!(
        command.pending_erase_for_send().unwrap(),
        Some(first_install)
    );
    assert!(!command.snapshot().unwrap().can_telemetry());
    assert_eq!(gui.snapshot().unwrap().telemetry_enabled, Some(false));
}

#[test]
fn 等待重试的503批次被关闭清除且重新开启后不发送() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    gui.agree(1).unwrap();
    queue(&gui);
    let batch = freeze(&gui);
    let response = gui
        .with_batch_for_send(batch.id(), |_| BatchDisposition::Retry)
        .unwrap()
        .unwrap();
    assert!(gui.finish_batch(batch.id(), response).unwrap());
    assert_eq!(freeze(&gui).id(), batch.id());

    let command = open(root.path(), Surface::Command);
    assert!(gui.set_telemetry(false).unwrap());
    assert!(gui.set_telemetry(true).unwrap());
    assert_send_blocked(&command, batch.id());
    assert!(command.freeze_next().unwrap().is_none());
}

#[test]
fn 另一连接关闭后旧状态不能用于入队冻结或发送() {
    let root = TestDirectory::new();
    let command = open(root.path(), Surface::Command);
    let gui = open(root.path(), Surface::Gui);
    gui.agree(1).unwrap();
    queue(&command);
    let batch_id = freeze(&command).id();
    let cached_open = command.snapshot().unwrap().can_telemetry();
    assert!(cached_open);

    assert!(gui.set_telemetry(false).unwrap());
    assert!(!command.enqueue(&EVENT, None).unwrap());
    assert!(command.freeze_next().unwrap().is_none());
    assert_send_blocked(&command, batch_id);

    assert!(gui.set_telemetry(true).unwrap());
    assert!(command.freeze_next().unwrap().is_none());
}

const PROCESS_ACTION: &str = "UBAA_APP_SERVICE_TEST_ACTION";
const PROCESS_ROOT: &str = "UBAA_APP_SERVICE_TEST_ROOT";
const PROCESS_INSTALL: &str = "UBAA_APP_SERVICE_TEST_INSTALL";
const PROCESS_BATCH: &str = "UBAA_APP_SERVICE_TEST_BATCH";

fn run_child(
    path: &Path,
    action: &str,
    install_id: Uuid,
    batch_id: Uuid,
    hard_close: Option<(&str, &str)>,
) {
    let (_, test_module) = module_path!().split_once("::").unwrap();
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .arg("--exact")
        .arg(format!("{test_module}::状态测试子进程"))
        .arg("--nocapture")
        .env(PROCESS_ROOT, path)
        .env(PROCESS_ACTION, action)
        .env(PROCESS_INSTALL, install_id.to_string())
        .env(PROCESS_BATCH, batch_id.to_string())
        .env_remove("CI")
        .env_remove("UBAA_TELEMETRY");
    if let Some((name, value)) = hard_close {
        command.env(name, value);
    }
    let output = command.output().unwrap();
    assert!(
        output.status.success()
            && String::from_utf8_lossy(&output.stdout).contains("应用服务子进程已完成检查"),
        "应用服务子进程未完成 {action}：{} {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn 状态测试子进程() {
    let Some(path) = std::env::var_os(PROCESS_ROOT) else {
        return;
    };
    let action = std::env::var(PROCESS_ACTION).unwrap();
    let old_install = std::env::var(PROCESS_INSTALL).unwrap().parse().unwrap();
    let batch_id = std::env::var(PROCESS_BATCH).unwrap().parse().unwrap();
    let surface = if action == "inspect-command" {
        Surface::Command
    } else {
        Surface::Gui
    };

    if action == "hard-close" {
        let app = AppService::open(Path::new(&path), config(), surface, 1).unwrap();
        let state = app.snapshot().unwrap();
        assert!(state.available);
        assert_eq!(state.telemetry_enabled, Some(true));
        assert!(state.can_bootstrap());
        assert!(state.can_erase());
        assert!(state.telemetry_hard_closed);
        assert!(!state.can_telemetry());
        assert!(!app.set_telemetry(true).unwrap());
        assert!(!app.enqueue(&EVENT, None).unwrap());
        assert!(app.freeze_next().unwrap().is_none());
        assert_send_blocked(&app, batch_id);
    } else {
        let app = open(Path::new(&path), surface);
        assert_eq!(install(&app), old_install);
        match action.as_str() {
            "mark" => assert_eq!(app.begin_erase().unwrap(), Some(old_install)),
            "finish" => {
                assert_eq!(app.begin_erase().unwrap(), Some(old_install));
                assert!(app.finish_erase(old_install).unwrap());
            }
            "inspect-gui" | "inspect-command" => {
                let state = app.snapshot().unwrap();
                assert_eq!(state.erasing_install_id, Some(old_install));
                assert!(state.can_erase());
                assert_eq!(app.pending_erase_for_send().unwrap(), Some(old_install));
                assert!(!app.enqueue(&EVENT, None).unwrap());
                assert!(app.freeze_next().unwrap().is_none());
                assert_send_blocked(&app, batch_id);
            }
            _ => panic!("未知的合成子进程操作"),
        }
    }
    println!("应用服务子进程已完成检查");
}

#[test]
fn 两个独立进程重启后仍禁止处理标记删除的旧批次() {
    let root = TestDirectory::new();
    let (old_install, batch_id) = {
        let gui = open(root.path(), Surface::Gui);
        gui.agree(1).unwrap();
        queue(&gui);
        let batch_id = freeze(&gui).id();
        queue(&gui);
        (install(&gui), batch_id)
    };

    run_child(root.path(), "mark", old_install, batch_id, None);
    run_child(root.path(), "inspect-command", old_install, batch_id, None);
    // 两种宿主分别退出，再由新的独立进程打开同一个配置目录。
    run_child(root.path(), "inspect-gui", old_install, batch_id, None);
    run_child(root.path(), "inspect-command", old_install, batch_id, None);

    let gui = open(root.path(), Surface::Gui);
    assert_eq!(
        gui.snapshot().unwrap().erasing_install_id,
        Some(old_install)
    );
    assert!(gui.finish_erase(old_install).unwrap());
    assert_ne!(install(&gui), old_install);
    assert!(gui.snapshot().unwrap().erasing_install_id.is_none());
    assert!(gui.freeze_next().unwrap().is_none());
}

#[test]
fn 传输期间另一进程删除后晚到的503不会恢复批次() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    gui.agree(1).unwrap();
    let old_install = install(&gui);
    queue(&gui);
    let old_batch = freeze(&gui);
    queue(&gui);

    let sending = gui
        .with_batch_for_send(old_batch.id(), identity)
        .unwrap()
        .unwrap();
    assert_eq!(sending.id(), old_batch.id());
    // 注入传输已接受请求，响应仍在等待；另一进程先完成删除。
    run_child(root.path(), "finish", old_install, sending.id(), None);

    assert!(
        !gui.finish_batch(old_batch.id(), BatchDisposition::Retry)
            .unwrap()
    );
    let state = gui.snapshot().unwrap();
    assert_ne!(state.install_id, Some(old_install));
    assert!(state.erasing_install_id.is_none());
    assert_eq!(state.telemetry_enabled, Some(true));
    assert_send_blocked(&gui, old_batch.id());
    assert!(gui.freeze_next().unwrap().is_none());

    queue(&gui);
    let new_batch = freeze(&gui);
    assert!(!gui.finish_erase(old_install).unwrap());
    assert_eq!(freeze(&gui).id(), new_batch.id());
}

#[test]
fn 两连接可并发交付同一冻结批次而晚到响应不创建行() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    let command = open(root.path(), Surface::Command);
    gui.agree(1).unwrap();
    queue(&gui);
    let id = freeze(&gui).id();
    let first = gui.with_batch_for_send(id, identity).unwrap().unwrap();
    // GUI 的响应未返回时，命令进程仍可把同一批次交给传输。
    let second = command.with_batch_for_send(id, identity).unwrap().unwrap();
    assert_eq!(first.id(), second.id());
    assert!(first.body() == second.body());
    assert!(
        command
            .finish_batch(id, BatchDisposition::Accepted)
            .unwrap()
    );
    assert!(!gui.finish_batch(id, BatchDisposition::Retry).unwrap());
    assert!(gui.freeze_next().unwrap().is_none());
}

#[test]
fn 丢弃响应只移除相应批次() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    gui.agree(1).unwrap();
    for disposition in [
        BatchDisposition::Accepted,
        BatchDisposition::InstallErased,
        BatchDisposition::InvalidPayload,
    ] {
        queue(&gui);
        let id = freeze(&gui).id();
        queue(&gui);
        assert!(gui.finish_batch(id, disposition).unwrap());
        assert!(!gui.finish_batch(id, disposition).unwrap());
        assert_send_blocked(&gui, id);

        let next = freeze(&gui).id();
        assert_ne!(id, next);
        assert!(gui.finish_batch(next, BatchDisposition::Accepted).unwrap());
    }
}

#[test]
fn 停用构建不会推进共享政策版本() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    gui.agree(1).unwrap();
    let config = AppServiceConfig::from_build(None, None, None, Platform::Macos, false);
    let disabled = AppService::open(root.path(), config, Surface::Gui, 2).unwrap();
    assert!(!disabled.snapshot().unwrap().available);
    assert_eq!(gui.snapshot().unwrap().consent, Consent::Agreed(1));
}

#[test]
fn 构建期配置无效时所有应用服务请求均停用() {
    let root = TestDirectory::new();
    let gui = open(root.path(), Surface::Gui);
    gui.agree(1).unwrap();
    queue(&gui);
    let id = freeze(&gui).id();

    for (url, channel, version, release) in [
        (None, Some(CHANNEL), Some(VERSION), false),
        (Some(LOOPBACK), None, Some(VERSION), false),
        (Some(LOOPBACK), Some("invalid"), Some(VERSION), false),
        (Some(LOOPBACK), Some(CHANNEL), None, false),
        (Some(LOOPBACK), Some(CHANNEL), Some(""), false),
        (Some(LOOPBACK), Some(CHANNEL), Some("1.0"), false),
        (
            Some("https://example.invalid"),
            Some(CHANNEL),
            Some(VERSION),
            false,
        ),
        (
            Some("http://example.invalid"),
            Some(CHANNEL),
            Some(VERSION),
            true,
        ),
        (
            Some("http://localhost.."),
            Some(CHANNEL),
            Some(VERSION),
            false,
        ),
        (
            Some("https://example.workers.dev.."),
            Some(CHANNEL),
            Some(VERSION),
            true,
        ),
        (
            Some("https://example.workers.dev"),
            Some(CHANNEL),
            Some(VERSION),
            true,
        ),
    ] {
        let config = AppServiceConfig::from_build(url, channel, version, Platform::Macos, release);
        let app = AppService::open(root.path(), config, Surface::Gui, 1)
            .unwrap()
            .with_runtime(now, false);
        let state = app.snapshot().unwrap();
        assert!(!state.available);
        assert!(!state.can_bootstrap());
        assert!(!state.can_erase());
        assert!(!state.can_telemetry());
        assert!(app.pending_erase_for_send().unwrap().is_none());
        assert!(!app.enqueue(&EVENT, None).unwrap());
        assert!(app.freeze_next().unwrap().is_none());
        assert_send_blocked(&app, id);
    }

    assert!(gui.finish_batch(id, BatchDisposition::Accepted).unwrap());
    assert!(gui.freeze_next().unwrap().is_none());
}

#[test]
fn 遥测环境硬关闭仍允许启动配置且不改保存的开关() {
    let root = TestDirectory::new();
    // 子进程读取真实运行时开关与时钟，准备一个与其同日的有效批次。
    let gui = AppService::open(root.path(), config(), Surface::Gui, 1)
        .unwrap()
        .with_runtime(Utc::now, false);
    gui.agree(1).unwrap();
    queue(&gui);
    let id = freeze(&gui).id();

    for reason in [("UBAA_TELEMETRY", "0"), ("CI", "0")] {
        run_child(root.path(), "hard-close", install(&gui), id, Some(reason));
    }

    assert_eq!(gui.snapshot().unwrap().telemetry_enabled, Some(true));
    assert!(gui.finish_batch(id, BatchDisposition::Accepted).unwrap());
    assert!(gui.freeze_next().unwrap().is_none());
}
