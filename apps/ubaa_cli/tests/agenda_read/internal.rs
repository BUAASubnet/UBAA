use super::*;
use std::sync::{Arc, Mutex};
#[path = "support.rs"]
mod support;
use crate::AgendaCommand;
use support::*;

#[derive(Clone, Default)]
struct MemoryMaterial(Arc<Mutex<Option<Vec<u8>>>>);
impl Material for MemoryMaterial {
    fn read(&self, _: &str) -> LocalResult<Option<Vec<u8>>> {
        Ok(self.0.lock().unwrap().clone())
    }
    fn write(&self, _: &str, data: &[u8]) -> LocalResult<()> {
        *self.0.lock().unwrap() = Some(data.to_vec());
        Ok(())
    }
}
fn access(root: &Path, material: &MemoryMaterial) -> AgendaAccess {
    AgendaAccess::with_material(root, Box::new(material.clone())).unwrap()
}
async fn register(access: &mut AgendaAccess, client: &mut UbaaClient, id: &str) {
    use clap::Parser;
    access.revoke().unwrap();
    let cli = crate::Cli::try_parse_from([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--username",
        id,
        "--password-stdin",
    ])
    .unwrap();
    let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
    let exit = crate::run_dual_login_with_agenda(
        cli,
        client,
        &mut std::io::Cursor::new(b"synthetic-only\n"),
        &mut stdout,
        &mut stderr,
        access,
    )
    .await;
    assert!(stderr.is_empty());
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["agendaRegistration"]["state"], "ready");
    if value["data"]["readiness"] == "all_ready" {
        assert_eq!(exit, 0);
    }
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    assert!(jsonschema::validator_for(&schema).unwrap().is_valid(&value));
}

#[tokio::test]
async fn 首登跨路线同账号复用退出恢复与账号隔离() {
    let root = root();
    let material = MemoryMaterial::default();
    let mut access = access(&root, &material);
    let (mut a, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    register(&mut access, &mut a, "fixture-a").await;
    let first = access.active().unwrap();
    let alias = first.accounts["fixture-a"].alias.clone();
    let item = item("甲的本机事项");
    let id = item.id;
    access
        .agenda(&first.accounts["fixture-a"])
        .unwrap()
        .create(item)
        .unwrap();
    access.revoke().unwrap();
    assert!(matches!(
        access.active(),
        Err(LocalError::RegistrationRequired)
    ));
    let (mut b, _) = client(&root, Some("fixture-b"), Some("fixture-b"));
    register(&mut access, &mut b, "fixture-b").await;
    assert_eq!(
        access.read_command(&AgendaCommand::Unsynced).unwrap()["count"],
        0
    );
    assert!(matches!(
        access.read_command(&AgendaCommand::Show { id }),
        Err(LocalError::NotFound)
    ));
    let (mut a, _) = client(&root, None, Some("fixture-a"));
    register(&mut access, &mut a, "fixture-a").await;
    let latest = access.active().unwrap();
    assert_eq!(latest.accounts["fixture-a"].alias, alias);
    assert_ne!(latest.epoch, first.epoch);
    assert_eq!(
        access.read_command(&AgendaCommand::Unsynced).unwrap()["count"],
        1
    );
    assert_eq!(
        access.read_command(&AgendaCommand::Show { id }).unwrap()["item"]["content"]["title"],
        "甲的本机事项"
    );
    // 缺少业务缓存密钥不妨碍本机读取。
    assert!(latest.accounts["fixture-a"].cache_key.is_none());
}
#[tokio::test]
async fn 能力只来自显式成功登录并绑定客户端与会话代次() {
    let root = root();
    let (mut a, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    assert!(a.take_verified_login_identity().is_err());
    login(&mut a, "fixture-a").await;
    let old = a.take_verified_login_identity().unwrap();
    assert!(a.take_verified_login_identity().is_err());
    a.auth_status().await.unwrap();
    assert!(a.take_verified_login_identity().is_err());
    assert!(a.validate_login_identity(&old).is_err());
    login(&mut a, "fixture-a").await;
    let old = a.take_verified_login_identity().unwrap();
    let (mut other, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    assert!(other.validate_login_identity(&old).is_err());
    other.logout().await.unwrap();
    login(&mut other, "fixture-a").await;
    assert!(a.validate_login_identity(&old).is_err());
    assert!(other.validate_login_identity(&old).is_err());
}
#[tokio::test]
async fn 两路线冲突或字段不符不能以首个资料登记() {
    for (direct, vpn, requested) in [
        (Some("fixture-a"), Some("fixture-b"), "fixture-a"),
        (Some(""), Some(""), "fixture-a"),
        (Some("fixture-b"), None, "fixture-a"),
    ] {
        let root = root();
        let (mut c, _) = client(&root, direct, vpn);
        let _ = login(&mut c, requested).await;
        assert!(c.take_verified_login_identity().is_err());
    }
}
#[tokio::test]
async fn 旧会话材料丢失损坏与权限失败均保留原库() {
    let root = root();
    let material = MemoryMaterial::default();
    let mut a = access(&root, &material);
    let (mut c, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    login(&mut c, "fixture-a").await;
    assert!(matches!(
        a.read_command(&AgendaCommand::Unsynced),
        Err(LocalError::RegistrationRequired)
    ));
    let token = c.take_verified_login_identity().unwrap();
    a.register(&mut c, &token).unwrap();
    let index = a.active().unwrap();
    let db = root
        .join("agenda")
        .join(format!("{}.sqlite", index.accounts["fixture-a"].alias));
    let before = std::fs::read(&db).unwrap();
    let saved = material.0.lock().unwrap().clone();
    *material.0.lock().unwrap() = None;
    assert!(matches!(a.active(), Err(LocalError::MaterialCorrupt)));
    *material.0.lock().unwrap() = Some(b"broken".to_vec());
    assert!(matches!(a.active(), Err(LocalError::MaterialCorrupt)));
    assert_eq!(std::fs::read(&db).unwrap(), before);
    *material.0.lock().unwrap() = saved;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(
            root.join("cli-accounts.lock"),
            std::fs::Permissions::from_mode(0o644),
        )
        .unwrap();
        assert!(matches!(a.active(), Err(LocalError::Storage)));
    }
}
#[tokio::test]
async fn 目录替换和初始化中断失败关闭() {
    let root = root();
    let material = MemoryMaterial::default();
    let a = access(&root, &material);
    let moved = root.with_extension("moved");
    std::fs::rename(&root, &moved).unwrap();
    std::fs::create_dir(&root).unwrap();
    assert!(matches!(a.load(), Err(LocalError::Storage)));
    drop(a);
    std::fs::remove_dir(&root).unwrap();
    std::fs::rename(&moved, &root).unwrap();
    let a = access(&root, &material);
    a.initialize().unwrap();
    a.begin_transition().unwrap();
    assert!(matches!(a.load(), Err(LocalError::MaterialCorrupt)));
}

#[tokio::test]
async fn 已消费能力不能在再次撤销后恢复活动选择() {
    let root = root();
    let material = MemoryMaterial::default();
    let mut a = access(&root, &material);
    let (mut c, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    login(&mut c, "fixture-a").await;
    let token = c.take_verified_login_identity().unwrap();
    a.register(&mut c, &token).unwrap();
    a.revoke().unwrap();
    assert_eq!(a.register(&mut c, &token), Err(LocalError::StaleIdentity));
}

#[derive(Clone)]
struct FailingMaterial {
    memory: MemoryMaterial,
    fail: Arc<std::sync::atomic::AtomicBool>,
    after_write: bool,
}
impl Material for FailingMaterial {
    fn read(&self, scope: &str) -> LocalResult<Option<Vec<u8>>> {
        self.memory.read(scope)
    }
    fn write(&self, scope: &str, data: &[u8]) -> LocalResult<()> {
        if self.fail.load(std::sync::atomic::Ordering::SeqCst) {
            if self.after_write {
                self.memory.write(scope, data)?;
            }
            return Err(LocalError::MaterialUnavailable);
        }
        self.memory.write(scope, data)
    }
}
#[tokio::test]
async fn 写入失败和已写入但回执失败都不能恢复活动读取() {
    for after_write in [false, true] {
        let root = root();
        let memory = MemoryMaterial::default();
        let fail = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let provider = FailingMaterial {
            memory: memory.clone(),
            fail: fail.clone(),
            after_write,
        };
        let mut a = AgendaAccess::with_material(&root, Box::new(provider)).unwrap();
        let (mut c, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
        register(&mut a, &mut c, "fixture-a").await;
        fail.store(true, std::sync::atomic::Ordering::SeqCst);
        assert_eq!(a.revoke(), Err(LocalError::MaterialUnavailable));
        assert!(matches!(a.active(), Err(LocalError::MaterialCorrupt)));
        drop(a);
        let a = access(&root, &memory);
        assert!(matches!(a.active(), Err(LocalError::MaterialCorrupt)));
    }
}

#[path = "concurrency.rs"]
mod concurrency;

#[tokio::test]
async fn 认证成功但登记失败必须独立序列化并返回失败退出码() {
    use clap::Parser;
    let root = root();
    let memory = MemoryMaterial::default();
    let fail = Arc::new(std::sync::atomic::AtomicBool::new(true));
    let mut a = AgendaAccess::with_material(
        &root,
        Box::new(FailingMaterial {
            memory,
            fail,
            after_write: false,
        }),
    )
    .unwrap();
    let (mut c, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    let cli = crate::Cli::try_parse_from([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--username",
        "fixture-a",
        "--password-stdin",
    ])
    .unwrap();
    let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
    let code = crate::run_dual_login_with_agenda(
        cli,
        &mut c,
        &mut std::io::Cursor::new(b"synthetic-only\n"),
        &mut stdout,
        &mut stderr,
        &mut a,
    )
    .await;
    assert_eq!(code, 7);
    assert!(stderr.is_empty());
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["readiness"], "all_ready");
    assert_eq!(value["agendaRegistration"]["state"], "failed");
    assert_eq!(
        value["agendaRegistration"]["error"]["code"],
        "material_unavailable"
    );
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    assert!(jsonschema::validator_for(&schema).unwrap().is_valid(&value));
    assert!(matches!(a.active(), Err(LocalError::MaterialCorrupt)));
}

#[tokio::test]
async fn 部分成功不能认领失败路线保留的旧账号槽位() {
    let root = root();
    let (mut old, calls) = client(&root, Some("fixture-a"), Some("fixture-a"));
    login(&mut old, "fixture-a").await;
    let mut c = UbaaClient::with_routing(
        LoginMock {
            identity: Some("fixture-b"),
            calls: calls.clone(),
            failure_status: 401,
        },
        LoginMock {
            identity: None,
            calls,
            failure_status: 503,
        },
        ubaa_test_support::FileSessionStore::new(&root).unwrap(),
        ubaa_test_support::RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    assert_eq!(
        login(&mut c, "fixture-b").await.readiness,
        ubaa_core::facade::LoginReadiness::Partial
    );
    assert!(c.take_verified_login_identity().is_err());
}

struct SessionWriteFailure {
    root: std::path::PathBuf,
    inner: LoginMock,
}
#[async_trait::async_trait]
impl ubaa_test_support::HttpTransport for SessionWriteFailure {
    async fn execute(
        &self,
        request: ubaa_test_support::HttpRequest,
    ) -> ubaa_core::facade::Result<ubaa_test_support::HttpResponse> {
        if request.url.contains("/api/uc/status") {
            let _ = std::fs::create_dir(self.root.join("session.json"));
        }
        ubaa_test_support::HttpTransport::execute(&self.inner, request).await
    }
}
#[tokio::test]
async fn 学校状态成功但会话持久化失败不能登记() {
    let root = root();
    let memory = MemoryMaterial::default();
    let mut scope = access(&root, &memory);
    scope.revoke().unwrap();
    let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let mock = LoginMock {
        identity: Some("fixture-a"),
        calls,
        failure_status: 401,
    };
    let mut c = UbaaClient::with_routing(
        SessionWriteFailure {
            root: root.clone(),
            inner: mock.clone(),
        },
        mock,
        ubaa_test_support::FileSessionStore::new(&root).unwrap(),
        ubaa_test_support::RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();
    let _ = c
        .login(ubaa_core::facade::DualLoginInput {
            username: "fixture-a".into(),
            password: ubaa_core::facade::SecretValue::new("synthetic-only"),
        })
        .await;
    assert!(c.take_verified_login_identity().is_err());
    assert!(matches!(
        scope.active(),
        Err(LocalError::RegistrationRequired)
    ));
    assert!(memory.0.lock().unwrap().is_none());
}

struct UnsupportedMaterial;
impl Material for UnsupportedMaterial {
    fn supported(&self) -> bool {
        false
    }
    fn read(&self, _: &str) -> LocalResult<Option<Vec<u8>>> {
        Err(LocalError::MaterialUnavailable)
    }
    fn write(&self, _: &str, _: &[u8]) -> LocalResult<()> {
        Err(LocalError::MaterialUnavailable)
    }
}
#[tokio::test]
async fn 未登记平台材料不可用仍可进入原有认证() {
    use clap::Parser;
    let root = root();
    let mut access = AgendaAccess::with_material(&root, Box::new(UnsupportedMaterial)).unwrap();
    access.revoke().expect("未启用日程不能阻断原有认证");
    let (mut client, calls) = client(&root, Some("fixture-a"), Some("fixture-a"));
    let cli = crate::Cli::try_parse_from([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--username",
        "fixture-a",
        "--password-stdin",
    ])
    .unwrap();
    let (mut out, mut err) = (Vec::new(), Vec::new());
    assert_eq!(
        crate::run_dual_login_with_agenda(
            cli,
            &mut client,
            &mut std::io::Cursor::new(b"synthetic-only\n"),
            &mut out,
            &mut err,
            &mut access
        )
        .await,
        7
    );
    let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(value["ok"], true);
    assert_eq!(
        value["agendaRegistration"]["error"]["code"],
        "material_unavailable"
    );
    assert!(calls.load(std::sync::atomic::Ordering::SeqCst) > 0);
    assert!(!root.join("agenda").exists());
    assert!(access.anchor().unwrap().is_empty());
    // 同一隔离目录已有旧认证双槽，退出仍可到达 Mock backend。
    access.revoke().unwrap();
    client.logout().await.unwrap();
    assert!(client.active_routes().is_empty());
    access.revoke().unwrap();
    let mut diagnostic = ubaa_core::facade::RouteClient::with_transport(
        ubaa_core::facade::ConnectionMode::Direct,
        LoginMock {
            identity: Some("fixture-a"),
            calls: calls.clone(),
            failure_status: 401,
        },
        ubaa_test_support::FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let cli = crate::Cli::try_parse_from([
        "ubaa",
        "--json",
        "auth",
        "login",
        "--mode",
        "direct",
        "--username",
        "fixture-a",
        "--password-stdin",
    ])
    .unwrap();
    let (mut out, mut err) = (Vec::new(), Vec::new());
    assert_eq!(
        crate::run_with_backend(
            cli,
            &mut diagnostic,
            &mut std::io::Cursor::new(b"synthetic-only\n"),
            &mut out,
            &mut err
        )
        .await,
        0
    );
    assert!(access.anchor().unwrap().is_empty());
}

#[test]
fn 不支持材料时所有已有日程痕迹均失败关闭() {
    for name in ["anchor", "cli-accounts.pending", "agenda", "business-cache"] {
        let root = root();
        let mut access = AgendaAccess::with_material(&root, Box::new(UnsupportedMaterial)).unwrap();
        if name == "anchor" {
            let mut file = access.paths.lock.try_clone().unwrap();
            file.write_all(b"broken-or-managed-anchor").unwrap();
        } else if name.ends_with("pending") {
            std::fs::write(root.join(name), []).unwrap();
        } else {
            std::fs::create_dir(root.join(name)).unwrap();
        }
        assert_eq!(access.revoke(), Err(LocalError::MaterialUnavailable));
    }
}

#[derive(Clone)]
struct LimitedMaterial {
    memory: MemoryMaterial,
    limit: Arc<std::sync::atomic::AtomicUsize>,
}
impl Material for LimitedMaterial {
    fn read(&self, scope: &str) -> LocalResult<Option<Vec<u8>>> {
        self.memory.read(scope)
    }
    fn write(&self, scope: &str, data: &[u8]) -> LocalResult<()> {
        self.check_write(data)?;
        self.memory.write(scope, data)
    }
    fn check_write(&self, data: &[u8]) -> LocalResult<()> {
        if data.len() > self.limit.load(std::sync::atomic::Ordering::SeqCst) {
            Err(LocalError::MaterialUnavailable)
        } else {
            Ok(())
        }
    }
}
#[tokio::test]
async fn 索引容量预检在过渡前拒绝且保留旧映射与密钥() {
    let root = root();
    let memory = MemoryMaterial::default();
    let limit = Arc::new(std::sync::atomic::AtomicUsize::new(usize::MAX));
    let mut a = AgendaAccess::with_material(
        &root,
        Box::new(LimitedMaterial {
            memory: memory.clone(),
            limit: limit.clone(),
        }),
    )
    .unwrap();
    let (mut c, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    register(&mut a, &mut c, "fixture-a").await;
    let mut index = a.active().unwrap();
    index.accounts.get_mut("fixture-a").unwrap().cache_key = Some(vec![19; 32]);
    a.save(&index).unwrap();
    a.revoke().unwrap();
    let before = memory.0.lock().unwrap().clone().unwrap();
    limit.store(before.len(), std::sync::atomic::Ordering::SeqCst);
    let (mut b, _) = client(&root, Some("fixture-b"), Some("fixture-b"));
    login(&mut b, "fixture-b").await;
    let token = b.take_verified_login_identity().unwrap();
    assert_eq!(
        a.register(&mut b, &token),
        Err(LocalError::MaterialUnavailable)
    );
    assert_eq!(memory.0.lock().unwrap().as_deref(), Some(before.as_slice()));
    assert!(!root.join("cli-accounts.pending").exists());
    assert_eq!(
        a.load().unwrap().unwrap().accounts["fixture-a"].cache_key,
        Some(vec![19; 32])
    );
    assert_eq!(
        PlatformMaterial.check_write(&vec![0; material::MAX_DATA + 1]),
        Err(LocalError::MaterialUnavailable)
    );
}
