//! CLI 独立 macOS Keychain 材料。原生调用隔离于同一 CLI 的有界子进程。
use super::{LocalError, LocalResult};
// 沿用既有读取上限；在任何过渡标记或材料修改前预检完整索引。
pub(super) const MAX_DATA: usize = 1_048_576;
pub(super) trait Material {
    fn supported(&self) -> bool {
        true
    }
    fn check_write(&self, data: &[u8]) -> LocalResult<()> {
        if data.len() > MAX_DATA {
            Err(LocalError::MaterialUnavailable)
        } else {
            Ok(())
        }
    }
    fn read(&self, scope: &str) -> LocalResult<Option<Vec<u8>>>;
    fn write(&self, scope: &str, data: &[u8]) -> LocalResult<()>;
}
pub(super) struct PlatformMaterial;
#[cfg(target_os = "macos")]
const SERVICE: &str = "cn.edu.ubaa.cli.local-accounts.v1";
impl Material for PlatformMaterial {
    fn supported(&self) -> bool {
        cfg!(target_os = "macos")
    }
    fn read(&self, scope: &str) -> LocalResult<Option<Vec<u8>>> {
        #[cfg(target_os = "macos")]
        {
            let output = execute(&["read", scope], None)?;
            if output.status.code() == Some(44) {
                return Ok(None);
            }
            if !output.status.success() {
                return Err(LocalError::MaterialUnavailable);
            }
            Ok(Some(output.stdout))
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = scope;
            Err(LocalError::MaterialUnavailable)
        }
    }
    fn write(&self, scope: &str, data: &[u8]) -> LocalResult<()> {
        self.check_write(data)?;
        #[cfg(target_os = "macos")]
        {
            let output = execute(&["write", scope], Some(data))?;
            if !output.status.success() || self.read(scope)?.as_deref() != Some(data) {
                return Err(LocalError::MaterialUnavailable);
            }
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = scope;
            Err(LocalError::MaterialUnavailable)
        }
    }
}
/// 同一二进制的内部原生材料进程入口。正文仅经管道传递，无 provider 切换配置。
#[doc(hidden)]
#[must_use]
pub fn keychain_worker() -> Option<i32> {
    let args: Vec<_> = std::env::args_os().collect();
    if args
        .get(1)
        .is_none_or(|arg| arg != "--internal-keychain-worker")
    {
        return None;
    }
    #[cfg(target_os = "macos")]
    {
        Some(native_worker(&args).unwrap_or(7))
    }
    #[cfg(not(target_os = "macos"))]
    {
        Some(7)
    }
}
#[cfg(target_os = "macos")]
fn native_worker(args: &[std::ffi::OsString]) -> LocalResult<i32> {
    use security_framework::{os::macos::keychain::SecKeychain, passwords};
    use std::io::{Read, Write};
    if args.len() != 4 {
        return Err(LocalError::MaterialUnavailable);
    }
    let scope = args[3]
        .to_str()
        .filter(|value| value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit()))
        .ok_or(LocalError::MaterialUnavailable)?;
    // 只影响这个短命工作进程。拒绝系统交互，保留条目已有访问控制。
    let _interaction =
        SecKeychain::disable_user_interaction().map_err(|_| LocalError::MaterialUnavailable)?;
    match args[2].to_str() {
        Some("read") => match passwords::get_generic_password(SERVICE, scope) {
            Ok(data) if data.len() <= MAX_DATA => {
                std::io::stdout()
                    .lock()
                    .write_all(&data)
                    .map_err(|_| LocalError::MaterialUnavailable)?;
                Ok(0)
            }
            Err(error) if error.code() == -25300 => Ok(44),
            _ => Err(LocalError::MaterialUnavailable),
        },
        Some("write") => {
            let mut data = Vec::new();
            std::io::stdin()
                .lock()
                .take((MAX_DATA + 1) as u64)
                .read_to_end(&mut data)
                .map_err(|_| LocalError::MaterialUnavailable)?;
            PlatformMaterial.check_write(&data)?;
            passwords::set_generic_password(SERVICE, scope, &data)
                .map_err(|_| LocalError::MaterialUnavailable)?;
            Ok(0)
        }
        _ => Err(LocalError::MaterialUnavailable),
    }
}
#[cfg(target_os = "macos")]
fn execute(arguments: &[&str], input: Option<&[u8]>) -> LocalResult<std::process::Output> {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let mut child =
        Command::new(std::env::current_exe().map_err(|_| LocalError::MaterialUnavailable)?)
            .arg("--internal-keychain-worker")
            .args(arguments)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|_| LocalError::MaterialUnavailable)?;
    let stdin = child.stdin.take().ok_or(LocalError::MaterialUnavailable)?;
    let data = input.map(<[u8]>::to_vec);
    let writer = std::thread::spawn(move || {
        let mut stdin = stdin;
        if let Some(data) = data {
            stdin.write_all(&data)
        } else {
            Ok(())
        }
    });
    let stdout = child.stdout.take().ok_or(LocalError::MaterialUnavailable)?;
    let stderr = child.stderr.take().ok_or(LocalError::MaterialUnavailable)?;
    let out = std::thread::spawn(move || {
        use std::io::Read;
        let mut data = Vec::new();
        stdout.take(1_048_577).read_to_end(&mut data).map(|_| data)
    });
    let err = std::thread::spawn(move || {
        use std::io::Read;
        let mut data = Vec::new();
        stderr.take(16_385).read_to_end(&mut data).map(|_| data)
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let status = loop {
        if let Some(status) = child
            .try_wait()
            .map_err(|_| LocalError::MaterialUnavailable)?
        {
            break status;
        }
        if std::time::Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            let _ = writer.join();
            let _ = out.join();
            let _ = err.join();
            return Err(LocalError::MaterialUnavailable);
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    };
    writer
        .join()
        .map_err(|_| LocalError::MaterialUnavailable)?
        .map_err(|_| LocalError::MaterialUnavailable)?;
    let stdout = out
        .join()
        .map_err(|_| LocalError::MaterialUnavailable)?
        .map_err(|_| LocalError::MaterialUnavailable)?;
    let stderr = err
        .join()
        .map_err(|_| LocalError::MaterialUnavailable)?
        .map_err(|_| LocalError::MaterialUnavailable)?;
    if stdout.len() > 1_048_576 || stderr.len() > 16_384 {
        return Err(LocalError::MaterialUnavailable);
    }
    Ok(std::process::Output {
        status,
        stdout,
        stderr,
    })
}
