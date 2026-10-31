//! CLI 独立 macOS Keychain 材料。通过固定系统工具调用，不使用 shell，不在 argv 放正文。
use super::{LocalError, LocalResult};
pub(super) trait Material {
    fn read(&self, scope: &str) -> LocalResult<Option<Vec<u8>>>;
    fn write(&self, scope: &str, data: &[u8]) -> LocalResult<()>;
}
pub(super) struct PlatformMaterial;
#[cfg(target_os = "macos")]
const SERVICE: &str = "cn.edu.ubaa.cli.local-accounts.v1";
impl Material for PlatformMaterial {
    fn read(&self, scope: &str) -> LocalResult<Option<Vec<u8>>> {
        #[cfg(target_os = "macos")]
        {
            let output = execute(
                &["find-generic-password", "-s", SERVICE, "-a", scope, "-w"],
                None,
            )?;
            if output.status.code() == Some(44) {
                return Ok(None);
            }
            if !output.status.success() {
                return Err(LocalError::MaterialUnavailable);
            }
            let mut value = output.stdout;
            if value.last() == Some(&b'\n') {
                value.pop();
            }
            Ok(Some(value))
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = scope;
            Err(LocalError::MaterialUnavailable)
        }
    }
    fn write(&self, scope: &str, data: &[u8]) -> LocalResult<()> {
        #[cfg(target_os = "macos")]
        {
            let value = std::str::from_utf8(data).map_err(|_| LocalError::MaterialCorrupt)?;
            // security 的交互命令解析器按引号分词；JSON 中的换行已转义。正文只通过 stdin 交付。
            let command = format!(
                "add-generic-password -U -s '{}' -a '{}' -w '{}'\n",
                SERVICE,
                scope,
                value.replace('\'', "'\\''")
            );
            let output = execute(&["-q", "-i"], Some(command.as_bytes()))?;
            if !output.status.success() || self.read(scope)?.as_deref() != Some(data) {
                return Err(LocalError::MaterialUnavailable);
            }
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (scope, data);
            Err(LocalError::MaterialUnavailable)
        }
    }
}
#[cfg(target_os = "macos")]
fn execute(arguments: &[&str], input: Option<&[u8]>) -> LocalResult<std::process::Output> {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let mut child = Command::new("/usr/bin/security")
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
