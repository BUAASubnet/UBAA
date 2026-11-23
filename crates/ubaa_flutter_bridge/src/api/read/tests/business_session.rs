//! 用合成 CAS 与业务响应验证只读 worker 的跨进程业务会话缓存。
use crate::api::client::{BridgeClient, BridgeConnectionMode};
use std::path::{Path, PathBuf};
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst},
};
use tokio::sync::Notify;
use ubaa_core::facade::{NetworkState, UbaaClient};
use ubaa_test_support::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    Result, RouteConfig, RouteSessionSnapshot, StoredCookie, from_webvpn_url, to_webvpn_url,
};

const SIDE_CAR: &str = "business_session.json";
const LOCK: &str = ".business_session.lock";
const CHILD_TEST: &str = "api::read::tests::business_session::业务会话合成子进程";
const ACCOUNT: &str = "fixture-user";
const BYXT_LANDING: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-fixture";

struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不探测");
    }
}

#[derive(Clone, Default)]
struct PortalTransport {
    state: Arc<Requests>,
    other_account: bool,
    anonymous_byxt: bool,
    anonymous_portal: bool,
    ready_file: Option<PathBuf>,
}

#[derive(Default)]
struct Requests {
    byxt: AtomicUsize,
    portal: AtomicUsize,
    portal_info: AtomicUsize,
    reject_byxt: AtomicBool,
    reject_portal: AtomicBool,
    pause_old_byxt: AtomicBool,
    fail_byxt_activation: AtomicBool,
    paused: Notify,
    resume: Notify,
}

impl PortalTransport {
    fn activations(&self) -> (usize, usize) {
        (self.state.byxt.load(SeqCst), self.state.portal.load(SeqCst))
    }
}

struct FixtureRequest {
    request: HttpRequest,
    direct: String,
}
impl FixtureRequest {
    fn via_vpn(&self) -> bool {
        self.request.url != self.direct
    }

    fn cookie(&self, value: &str) -> bool {
        self.request
            .headers
            .get("Cookie")
            .is_some_and(|header| header.split("; ").any(|part| part == value))
    }

    fn respond(&self, status: u16, body: &str) -> HttpResponse {
        HttpResponse::new(status, &self.request.url, body.as_bytes().to_vec())
    }

    fn redirect(&self, location: &str, wrap: bool) -> HttpResponse {
        let target = if wrap && self.via_vpn() {
            to_webvpn_url(location).unwrap()
        } else {
            location.to_owned()
        };
        let mut response = self.respond(302, "");
        response.headers.insert("Location".into(), vec![target]);
        response
    }

    fn mint(&self, name: &str, value: &str) -> HttpResponse {
        let path = if self.via_vpn() {
            format!(
                "/{}/",
                self.request
                    .url
                    .split('/')
                    .skip(3)
                    .take(2)
                    .collect::<Vec<_>>()
                    .join("/")
            )
        } else {
            "/".into()
        };
        let mut response = self.respond(200, "");
        response.headers.insert(
            "Set-Cookie".into(),
            vec![format!("{name}={value}; Path={path}; Secure")],
        );
        response
    }
}

impl PortalTransport {
    fn portal(&self, call: &FixtureRequest) -> HttpResponse {
        const HOME: &str = "https://it.buaa.edu.cn/home/";
        if call.direct.contains("/personal/frontend/data/info") {
            self.state.portal_info.fetch_add(1, SeqCst);
            if self.anonymous_portal
                || call.cookie("fixture_portal=renewed")
                || (call.cookie("fixture_portal=valid") && !self.state.reject_portal.load(SeqCst))
            {
                return call.respond(
                    200,
                    r#"{"e":0,"d":{"info":{"identity":"本科生","depart":"示例学院"}}}"#,
                );
            }
            if call.cookie("fixture_portal=valid") {
                return call.respond(401, "");
            }
            return call.respond(200, r#"{"e":10013}"#);
        }
        if call
            .direct
            .starts_with("https://it.buaa.edu.cn/manage/common/login/index?")
        {
            self.state.portal.fetch_add(1, SeqCst);
            return call.redirect(HOME, true);
        }
        assert_eq!(call.direct, HOME);
        let value = if self.state.reject_portal.load(SeqCst) {
            assert!(
                !call.cookie("fixture_portal=valid"),
                "门户激活携带已被拒绝的 Cookie"
            );
            "renewed"
        } else {
            "valid"
        };
        call.mint("fixture_portal", value)
    }

    async fn byxt(&self, call: &FixtureRequest) -> HttpResponse {
        if call.direct.contains("currentUser.do") {
            if self.state.pause_old_byxt.swap(false, SeqCst) {
                assert!(
                    call.cookie("fixture_byxt=valid"),
                    "考试未使用此前播种的材料"
                );
                self.state.paused.notify_one();
                self.state.resume.notified().await;
                return call.respond(401, "");
            }
            if self.anonymous_byxt
                || call.cookie("fixture_byxt=renewed")
                || (call.cookie("fixture_byxt=valid") && !self.state.reject_byxt.load(SeqCst))
            {
                return call.respond(200, r#"{"code":"0","datas":{"userId":"fixture-user"}}"#);
            }
            return call.respond(401, "");
        }
        if call.direct == BYXT_LANDING {
            self.state.byxt.fetch_add(1, SeqCst);
            let value = if self.state.reject_byxt.load(SeqCst) {
                assert!(
                    !call.cookie("fixture_byxt=valid"),
                    "教务激活携带已被拒绝的 Cookie"
                );
                "renewed"
            } else {
                "valid"
            };
            if self.state.fail_byxt_activation.swap(false, SeqCst) {
                return call.respond(500, "");
            }
            return call.mint("fixture_byxt", value);
        }
        assert!(
            call.direct.contains("teachingSchedule/detail.do") || call.direct.contains("exams.do")
        );
        assert!(
            self.anonymous_byxt
                || call.cookie("fixture_byxt=valid")
                || call.cookie("fixture_byxt=renewed")
        );
        if let Some(path) = &self.ready_file {
            std::fs::write(path, []).unwrap();
            wait_for_file(&path.with_file_name("write-now"));
        }
        call.respond(200, r#"{"code":"0","datas":[]}"#)
    }
}

#[async_trait::async_trait]
impl HttpTransport for PortalTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let direct = from_webvpn_url(&request.url).unwrap();
        let call = FixtureRequest { request, direct };
        let url = call.direct.as_str();
        Ok(
            if url == "https://d.buaa.edu.cn/" || url == "https://sso.buaa.edu.cn/logout" {
                call.respond(200, "")
            } else if url.contains("/serviceValidate?") {
                let account = if self.other_account {
                    "fixture-other"
                } else {
                    ACCOUNT
                };
                call.respond(
                    200,
                    &format!(
                        r#"{{"user":"{account}","attributes":{{"employeeNumber":["{account}"]}}}}"#
                    ),
                )
            } else if url == "https://sso.buaa.edu.cn/login"
                || url.starts_with("https://sso.buaa.edu.cn/login?service=")
            {
                if url.contains("cas_login%3Dtrue") {
                    call.redirect("https://d.buaa.edu.cn/", false)
                } else {
                    call.redirect(BYXT_LANDING, true)
                }
            } else if url.starts_with("https://it.buaa.edu.cn/") {
                self.portal(&call)
            } else if url.starts_with("https://byxt.buaa.edu.cn/") {
                self.byxt(&call).await
            } else {
                panic!("收到未登记的合成请求");
            },
        )
    }
}

fn wait_for_file(path: &Path) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    while !path.is_file() {
        assert!(std::time::Instant::now() < deadline, "并发写入进程未就绪");
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
}

struct Fixture(ubaa_test_support::TestTempDir, FileSessionStore);
impl Fixture {
    fn new() -> Self {
        Self::in_task("biz_cache")
    }

    fn in_task(_task: &str) -> Self {
        let root =
            ubaa_test_support::test_temp_dir("ubaa_flutter_bridge_api_read_business_session")
                .unwrap();
        let store = FileSessionStore::new(&root).unwrap();
        let now = chrono::Utc::now().timestamp();
        let auth_cookie = |name: &str, domain: &str| StoredCookie {
            name: name.into(),
            value: "valid".into(),
            domain: domain.into(),
            path: "/".into(),
            secure: true,
            host_only: true,
            expires_at: None,
            created_at: now,
            max_age: None,
        };
        store
            .save_dual(&DualSessionSnapshot::new(
                Some(RouteSessionSnapshot {
                    cookies: vec![
                        auth_cookie("fixture_uc", "uc.buaa.edu.cn"),
                        auth_cookie("fixture_sso", "sso.buaa.edu.cn"),
                    ],
                    authenticated_at: now,
                    last_activity: now,
                }),
                Some(RouteSessionSnapshot {
                    cookies: vec![auth_cookie("fixture_gateway", "d.buaa.edu.cn")],
                    authenticated_at: now,
                    last_activity: now,
                }),
            ))
            .unwrap();
        Self(root, store)
    }

    fn cache(&self) -> PathBuf {
        self.0.join(SIDE_CAR)
    }

    fn contents(&self) -> String {
        std::fs::read_to_string(self.cache()).expect("成功读取应写入业务会话缓存")
    }

    fn assert_tombstone(&self) {
        let document: serde_json::Value = serde_json::from_str(&self.contents()).unwrap();
        let fields = document.as_object().unwrap();
        assert_eq!(fields.len(), 3);
        assert_eq!(document["schema"], 2);
        for key in ["clear_nonces", "content_versions"] {
            let routes = document[key].as_object().unwrap();
            assert_eq!(routes.len(), 2);
            for route in ["direct", "webvpn"] {
                assert_eq!(routes[route].as_array().unwrap().len(), 16);
            }
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(self.cache())
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
    }

    fn revision(&self) -> u64 {
        self.1.load_dual_versioned().unwrap().revision
    }
}
fn core(
    store: FileSessionStore,
    policy: &str,
    transport: &(impl HttpTransport + Clone + 'static),
) -> UbaaClient {
    UbaaClient::with_routing(
        transport.clone(),
        transport.clone(),
        store,
        RouteConfig::parse(&format!("[route]\ndefault = \"{policy}\"")).unwrap(),
        NoProbe,
    )
    .unwrap()
}

async fn restored(
    store: FileSessionStore,
    policy: &str,
    transport: &(impl HttpTransport + Clone + 'static),
) -> BridgeClient {
    let mut client = core(store, policy, transport);
    client
        .recover_connection_session()
        .await
        .expect("合成 SSO 身份核验");
    BridgeClient::from_core(client)
}

#[test]
fn 业务会话_连接恢复后重开复用教务和门户() {
    let fixture = Fixture::new();
    for task in ["cold", "restored"] {
        let output = child_command(&fixture, task).output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stdout)
        );
    }
}

#[tokio::test]
async fn 业务会话_账号未核验时不播种也不写回() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    restored(fixture.1.clone(), "direct", &transport)
        .await
        .schedule_today()
        .await
        .unwrap();
    let initial = fixture.contents();
    let unverified = BridgeClient::from_core(core(fixture.1.clone(), "direct", &transport));
    unverified.schedule_today().await.unwrap();
    assert_eq!(transport.activations(), (2, 2));
    assert_eq!(fixture.contents(), initial);
}

#[tokio::test]
async fn 业务会话_考试组同步已派生时的后续缓存版本() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    drop(
        bridge
            .inner
            .read(Some(crate::api::read_pool::ReadGroup::Exam))
            .await
            .unwrap(),
    );
    bridge.schedule_today().await.unwrap();
    bridge
        .exam_arrangement("fixture-term".into())
        .await
        .unwrap();
    assert_eq!(transport.activations(), (1, 1));
}

#[tokio::test]
async fn 业务会话_被拒绝后只激活一次并保存新材料() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    restored(fixture.1.clone(), "direct", &transport)
        .await
        .schedule_today()
        .await
        .unwrap();
    // 学生身份到期后必须再次读取门户，覆盖 Portal Cookie 被拒的路径。
    let mut document: serde_json::Value = serde_json::from_str(&fixture.contents()).unwrap();
    document["routes"]["direct"]["identity"]["saved_at"] = 0.into();
    std::fs::write(fixture.cache(), document.to_string()).unwrap();
    transport.state.reject_byxt.store(true, SeqCst);
    transport.state.reject_portal.store(true, SeqCst);
    for _ in 0..2 {
        restored(fixture.1.clone(), "direct", &transport)
            .await
            .schedule_today()
            .await
            .unwrap();
    }
    assert_eq!(transport.activations(), (2, 2));
    assert_eq!(fixture.contents().matches("renewed").count(), 2);
}

#[tokio::test]
async fn 业务会话_迟到拒绝保留其他读取组的新材料() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge.schedule_today().await.unwrap();
    {
        transport.state.pause_old_byxt.store(true, SeqCst);
        let exam = bridge.exam_arrangement("fixture-term".into());
        tokio::pin!(exam);
        tokio::select! {
            () = transport.state.paused.notified() => {},
            _ = &mut exam => panic!("考试未持有被拒绝响应"),
        }
        transport.state.reject_byxt.store(true, SeqCst);
        bridge.schedule_today().await.unwrap();
        transport.state.fail_byxt_activation.store(true, SeqCst);
        transport.state.resume.notify_one();
        assert!(exam.await.is_err());
    }
    drop(bridge);
    let before = transport.activations();
    restored(fixture.1.clone(), "direct", &transport)
        .await
        .schedule_today()
        .await
        .unwrap();
    assert_eq!(before, (3, 1));
    assert_eq!(transport.activations(), before);
}

#[tokio::test]
async fn 业务会话_登录切换账号和注销分别失效() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge.schedule_today().await.unwrap();
    bridge
        .login_required_route(
            BridgeConnectionMode::Direct,
            ACCOUNT.into(),
            "fixture-input".into(),
        )
        .await
        .unwrap();
    bridge.schedule_today().await.unwrap();
    assert_eq!(transport.activations(), (2, 2));
    drop(bridge);
    let other = PortalTransport {
        other_account: true,
        ..transport.clone()
    };
    let other_bridge = restored(fixture.1.clone(), "direct", &other).await;
    other_bridge.schedule_today().await.unwrap();
    assert_eq!(other.activations(), (3, 3));
    other_bridge.logout().await.unwrap();
    fixture.assert_tombstone();
    assert!(other_bridge.schedule_today().await.is_err());
}

#[tokio::test]
async fn 业务会话_设置清除后弃用旧读取组() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge.schedule_today().await.unwrap();
    let revision = fixture.revision();
    bridge.clear_business_session_cache().await;
    fixture.assert_tombstone();
    bridge.schedule_today().await.unwrap();
    assert_eq!(transport.activations(), (2, 2));
    assert_eq!(fixture.revision(), revision);
}

#[tokio::test]
async fn 业务会话_策略改变后两个路线都重新激活() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    for mode in ["direct", "webvpn"] {
        restored(fixture.1.clone(), mode, &transport)
            .await
            .schedule_today()
            .await
            .unwrap();
    }
    let mut primary = UbaaClient::open(&fixture.0).unwrap();
    primary
        .set_default_route_policy(ubaa_core::facade::RoutePolicy::Direct)
        .unwrap();
    for mode in ["direct", "webvpn"] {
        restored(fixture.1.clone(), mode, &transport)
            .await
            .schedule_today()
            .await
            .unwrap();
    }
    assert_eq!(transport.activations(), (4, 4));
    assert!(fixture.cache().is_file());
}

#[tokio::test]
async fn 业务会话_损坏超限版本与账号不符时重新生成() {
    for variant in 0..4 {
        let fixture = Fixture::new();
        let transport = PortalTransport::default();
        restored(fixture.1.clone(), "direct", &transport)
            .await
            .schedule_today()
            .await
            .unwrap();
        let valid = fixture.contents();
        let invalid = match variant {
            0 => "{".into(),
            1 => format!("{valid}{}", " ".repeat(256 * 1024)),
            2 => valid.replace("\"schema\":2", "\"schema\":3"),
            _ => valid.replace(ACCOUNT, "fixture-other"),
        };
        assert_ne!(valid, invalid);
        std::fs::write(fixture.cache(), invalid.as_bytes()).unwrap();
        restored(fixture.1.clone(), "direct", &transport)
            .await
            .schedule_today()
            .await
            .unwrap();
        assert_eq!(transport.activations(), (2, 2));
        assert_ne!(fixture.contents(), invalid);
    }
}

#[test]
fn 业务会话_写回失败只记录一次且在线成功() {
    let fixture = Fixture::new();
    std::fs::create_dir(fixture.0.join(LOCK)).unwrap();
    let output = child_command(&fixture, "io-error").output().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(!fixture.cache().exists());
    let diagnostics = String::from_utf8(output.stderr).unwrap();
    assert_eq!(diagnostics.matches("业务会话缓存写回失败").count(), 1);
    assert!(!diagnostics.contains(ACCOUNT));
}

#[cfg(unix)]
#[tokio::test]
async fn 业务会话_旁车锁繁忙时在线结果先返回() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    let held = std::fs::File::create(fixture.0.join(LOCK)).unwrap();
    held.lock().unwrap();
    let started = std::time::Instant::now();
    bridge.schedule_today().await.unwrap();
    let elapsed = started.elapsed();
    drop(held);
    drop(bridge);
    assert!(
        elapsed < std::time::Duration::from_secs(1),
        "读取等待了旁车锁"
    );
    assert!(fixture.cache().is_file());
}

#[tokio::test]
async fn 业务会话_外部替换会话后丢弃旧读取的写回() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let mut primary = core(fixture.1.clone(), "direct", &transport);
    primary.recover_connection_session().await.unwrap();
    let mut worker = primary.fork_parallel_readonly().unwrap();
    let result = worker.schedule_today().await.unwrap();
    let newer = fixture.1.load_dual().unwrap().unwrap();
    fixture.1.save_dual(&newer).unwrap();
    let revision = fixture.revision();
    // 先替换主会话，再提交旧读取结果，固定在写回预检之前发生修订变化。
    worker.persist_business_session(result.resolution.mode);
    drop(worker);
    drop(primary);
    assert!(!fixture.cache().exists());
    assert_eq!(fixture.revision(), revision);
}

#[tokio::test]
async fn 业务会话_路线隔离且排除主认证与通用网关材料() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    for mode in ["direct", "webvpn", "direct", "webvpn"] {
        restored(fixture.1.clone(), mode, &transport)
            .await
            .schedule_today()
            .await
            .unwrap();
    }
    assert_eq!(transport.activations(), (2, 2));
    let content = fixture.contents();
    for excluded in ["fixture_sso", "fixture_uc", "fixture_gateway"] {
        assert!(!content.contains(excluded));
    }
    assert_eq!(content.matches("fixture_byxt").count(), 2);
    assert_eq!(content.matches("fixture_portal").count(), 2);
}

#[tokio::test]
async fn 业务会话_读组写回不推进双槽修订() {
    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    let revision = fixture.revision();
    let main = std::fs::read(fixture.1.path()).unwrap();
    bridge.schedule_today().await.unwrap();
    bridge
        .exam_arrangement("fixture-term".into())
        .await
        .unwrap();
    drop(bridge);
    assert_eq!(fixture.revision(), revision);
    assert_eq!(std::fs::read(fixture.1.path()).unwrap(), main);
    assert!(fixture.cache().is_file());
}

#[cfg(unix)]
#[tokio::test]
async fn 业务会话_拒绝符号链接并按私有权限原子替换() {
    use std::os::unix::fs::{MetadataExt, PermissionsExt, symlink};

    let fixture = Fixture::new();
    let transport = PortalTransport::default();
    let target = fixture.0.join("unrelated");
    std::fs::write(&target, b"fixture-target").unwrap();
    symlink(&target, fixture.cache()).unwrap();
    restored(fixture.1.clone(), "direct", &transport)
        .await
        .schedule_today()
        .await
        .unwrap();
    assert!(fixture.cache().symlink_metadata().unwrap().is_symlink());
    assert_eq!(std::fs::read(&target).unwrap(), b"fixture-target");
    std::fs::remove_file(fixture.cache()).unwrap();
    let bridge = restored(fixture.1.clone(), "direct", &transport).await;
    bridge.schedule_today().await.unwrap();
    wait_for_file(&fixture.cache());
    assert_eq!(
        fixture.0.metadata().unwrap().permissions().mode() & 0o777,
        0o700
    );
    for path in [fixture.cache(), fixture.0.join(LOCK)] {
        assert_eq!(path.metadata().unwrap().permissions().mode() & 0o777, 0o600);
    }
    let held = std::fs::File::open(fixture.cache()).unwrap();
    let prior_inode = held.metadata().unwrap().ino();
    transport.state.reject_byxt.store(true, SeqCst);
    bridge.schedule_today().await.unwrap();
    drop(bridge);
    assert_ne!(fixture.cache().metadata().unwrap().ino(), prior_inode);
    assert!(fixture.contents().contains("renewed"));
}

fn child_command(fixture: &Fixture, task: &str) -> std::process::Command {
    let mut command = std::process::Command::new(std::env::current_exe().unwrap());
    command
        .args(["--ignored", "--exact", "--nocapture", CHILD_TEST])
        .env("UBAA_FIXTURE_CACHE_ROOT", fixture.0.path())
        .env("UBAA_FIXTURE_CACHE_TASK", task);
    command
}

#[test]
#[ignore = "由跨进程及诊断测试启动"]
fn 业务会话合成子进程() {
    let Some(root) = std::env::var_os("UBAA_FIXTURE_CACHE_ROOT").map(PathBuf::from) else {
        return;
    };
    let task = std::env::var("UBAA_FIXTURE_CACHE_TASK").unwrap();
    if task == "io-error" {
        tracing::subscriber::set_global_default(
            tracing_subscriber::fmt()
                .with_ansi(false)
                .without_time()
                .with_writer(std::io::stderr)
                .finish(),
        )
        .unwrap();
    }
    let transport = PortalTransport {
        anonymous_byxt: task == "portal",
        anonymous_portal: task == "byxt",
        ready_file: matches!(task.as_str(), "portal" | "byxt").then(|| root.join(&task)),
        ..PortalTransport::default()
    };
    let store = FileSessionStore::new(root).unwrap();
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            restored(store, "direct", &transport)
                .await
                .schedule_today()
                .await
                .unwrap();
        });
    match task.as_str() {
        "cold" => assert_eq!(transport.activations(), (1, 1)),
        "restored" => assert_eq!(transport.activations(), (0, 0)),
        _ => {}
    }
}

#[test]
fn 业务会话_两进程同时写入同路线不同范围() {
    let fixture = Fixture::new();
    let mut children = ["byxt", "portal"].map(|task| {
        child_command(&fixture, task)
            .stdout(std::process::Stdio::piped())
            .spawn()
            .unwrap()
    });
    wait_for_file(&fixture.0.join("byxt"));
    wait_for_file(&fixture.0.join("portal"));
    std::fs::write(fixture.0.join("write-now"), []).unwrap();
    for child in &mut children {
        assert!(child.wait().unwrap().success());
    }
    let content = fixture.contents();
    for kept in ["fixture_byxt", "fixture_portal"] {
        assert!(content.contains(kept));
    }
}

#[path = "business_session_p2.rs"]
mod p2;
