//! 测试程序专用共享材料后端，不编入生产二进制。
use super::*;
use std::process::{Child, Command};
struct FileTestMaterial(std::path::PathBuf);
impl Material for FileTestMaterial {
    fn read(&self, _: &str) -> LocalResult<Option<Vec<u8>>> {
        match std::fs::read(&self.0) {
            Ok(v) => Ok(Some(v)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(LocalError::MaterialUnavailable),
        }
    }
    fn write(&self, _: &str, data: &[u8]) -> LocalResult<()> {
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&self.0)
            .map_err(|_| LocalError::MaterialUnavailable)?;
        f.write_all(data)
            .and_then(|()| f.sync_all())
            .map_err(|_| LocalError::MaterialUnavailable)
    }
}
fn file_access(root: &Path) -> AgendaAccess {
    AgendaAccess::with_material(root, Box::new(FileTestMaterial(root.join("test-material"))))
        .unwrap()
}
fn child(root: &Path, action: &str) -> Child {
    Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "local_agenda::tests::concurrency::锁子进程",
            "--nocapture",
        ])
        .env("UBAA_SYNTHETIC_LOCK_ROOT", root)
        .env("UBAA_SYNTHETIC_LOCK_ACTION", action)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap()
}
#[test]
fn 锁子进程() {
    let Some(root) = std::env::var_os("UBAA_SYNTHETIC_LOCK_ROOT") else {
        return;
    };
    let root = std::path::PathBuf::from(root);
    let action = std::env::var("UBAA_SYNTHETIC_LOCK_ACTION").unwrap();
    std::fs::write(root.join(format!("started-{action}")), b"ready").unwrap();
    let mut access = file_access(&root);
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        if action == "logout" {
            access.revoke().unwrap();
            let (mut c, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
            c.logout().await.unwrap();
        } else {
            let id = if action == "a" {
                "fixture-a"
            } else {
                "fixture-b"
            };
            let (mut c, _) = client(&root, Some(id), Some(id));
            register(&mut access, &mut c, id).await;
        }
    });
}
fn started(root: &Path, action: &str) {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while !root.join(format!("started-{action}")).exists() {
        assert!(std::time::Instant::now() < deadline);
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}
#[test]
fn 两个进程登记串行且路径别名共享锁_读操作阻止退出() {
    let root = root();
    let guard = file_access(&root);
    let mut a = child(&root.join("."), "a");
    let mut b = child(&root, "b");
    started(&root, "a");
    started(&root, "b");
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert!(a.try_wait().unwrap().is_none());
    assert!(b.try_wait().unwrap().is_none());
    drop(guard);
    assert!(a.wait().unwrap().success());
    assert!(b.wait().unwrap().success());
    let a = file_access(&root);
    let index = a.active().unwrap();
    assert_eq!(index.accounts.len(), 2);
    let result = a.read_command(&AgendaCommand::Unsynced).unwrap();
    assert_eq!(result["count"], 0);
    let mut logout = child(&root, "logout");
    started(&root, "logout");
    std::thread::sleep(std::time::Duration::from_millis(100));
    assert!(logout.try_wait().unwrap().is_none());
    drop(a);
    assert!(logout.wait().unwrap().success());
    let a = file_access(&root);
    assert!(matches!(a.active(), Err(LocalError::RegistrationRequired)));
}
#[test]
fn 符号链接不能替代配置目录或锁() {
    use std::os::unix::fs::symlink;
    let root = root();
    let a = file_access(&root);
    drop(a);
    let alias = root.with_extension("alias");
    symlink(&root, &alias).unwrap();
    assert!(AgendaAccess::open(&alias).is_err());
    std::fs::remove_file(root.join("cli-accounts.lock")).unwrap();
    symlink(root.join("test-target"), root.join("cli-accounts.lock")).unwrap();
    assert!(AgendaAccess::open(&root).is_err());
}

#[test]
fn 旧进程的未消费身份票据跨退出重登后失效() {
    let root = root();
    let mut scope = file_access(&root);
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let (mut old, _) = client(&root, Some("fixture-a"), Some("fixture-a"));
    runtime.block_on(login(&mut old, "fixture-a"));
    let token = old.take_verified_login_identity().unwrap();
    drop(scope);
    assert!(child(&root, "logout").wait().unwrap().success());
    assert!(child(&root, "a").wait().unwrap().success());
    scope = file_access(&root);
    assert_eq!(
        scope.register(&mut old, &token),
        Err(LocalError::StaleIdentity)
    );
    assert_eq!(
        scope.read_command(&AgendaCommand::Unsynced).unwrap()["count"],
        0
    );
}
