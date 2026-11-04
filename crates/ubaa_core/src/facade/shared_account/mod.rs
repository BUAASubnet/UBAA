//! 只用于撤销旧能力的本机版本检查，不签发学校身份或恢复许可。
use crate::error::{Result, UbaaError};
use std::{
    fs::{File, OpenOptions},
    io::Read,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

#[derive(Clone)]
pub struct SharedAccountGuard {
    directory: Arc<PathBuf>,
    expected: Arc<str>,
    revoked: Arc<AtomicBool>,
}

/// 仅覆盖同步本地事务或 transport 交付，不允许跨网络 await 持有。
pub(crate) struct SharedAccountPermit(File);
impl Drop for SharedAccountPermit {
    fn drop(&mut self) {
        #[cfg(target_os = "android")]
        let _ = fs2::FileExt::unlock(&self.0);
        #[cfg(not(target_os = "android"))]
        let _ = self.0.unlock();
    }
}
impl SharedAccountGuard {
    /// 参数必须来自同材料域已核对的持久快照；版本仅能缩短既有能力的生命期。
    ///
    /// # Errors
    /// 非绝对目录或非法代次返回本机冲突。
    pub fn new(directory: &Path, generation: u64) -> Result<Self> {
        if !directory.is_absolute() || generation == 0 {
            return Err(UbaaError::shared_account_conflict());
        }
        Ok(Self {
            directory: Arc::new(directory.to_owned()),
            expected: Arc::from(format!("UBAA1:{generation}")),
            revoked: Arc::new(AtomicBool::new(false)),
        })
    }
    /// 核对原版本，不采用外部更新。
    ///
    /// # Errors
    /// 版本变化、材料事务未完成、损坏或不可用均永久拒绝当前能力。
    pub fn check(&self) -> Result<()> {
        self.acquire().map(drop)
    }
    pub(crate) fn acquire(&self) -> Result<SharedAccountPermit> {
        if self.revoked.load(Ordering::SeqCst) {
            return Err(UbaaError::shared_account_conflict());
        }
        match self.acquire_inner() {
            Ok(permit) => Ok(permit),
            Err(error) => {
                self.revoked.store(true, Ordering::SeqCst);
                Err(error)
            }
        }
    }
    fn acquire_inner(&self) -> Result<SharedAccountPermit> {
        let root = self.directory.as_ref();
        let metadata = std::fs::symlink_metadata(root).map_err(conflict)?;
        if !metadata.is_dir() || metadata.file_type().is_symlink() {
            return Err(UbaaError::shared_account_conflict());
        }
        let file = open_regular(&root.join("materials.lock"))?;
        let deadline = Instant::now() + Duration::from_secs(5);
        while !try_shared(&file)? {
            if Instant::now() >= deadline {
                return Err(UbaaError::shared_account_conflict());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let permit = SharedAccountPermit(file);
        if read_small(&root.join("transaction.v1"))? != "UBAA1:C"
            || read_small(&root.join("account-generation.v1"))? != self.expected.as_ref()
        {
            return Err(UbaaError::shared_account_conflict());
        }
        Ok(permit)
    }
}
fn conflict(_: impl std::fmt::Debug) -> UbaaError {
    UbaaError::shared_account_conflict()
}
fn open_regular(path: &Path) -> Result<File> {
    let metadata = std::fs::symlink_metadata(path).map_err(conflict)?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err(UbaaError::shared_account_conflict());
    }
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        options.write(true).custom_flags(0x0020_0000);
    }
    let file = options.open(path).map_err(conflict)?;
    if !file.metadata().map_err(conflict)?.is_file() {
        return Err(UbaaError::shared_account_conflict());
    }
    Ok(file)
}
fn read_small(path: &Path) -> Result<String> {
    let mut value = String::new();
    open_regular(path)?
        .take(65)
        .read_to_string(&mut value)
        .map_err(conflict)?;
    if value.len() > 64 {
        return Err(UbaaError::shared_account_conflict());
    }
    Ok(value)
}
fn try_shared(file: &File) -> Result<bool> {
    #[cfg(target_os = "android")]
    return match fs2::FileExt::try_lock_shared(file) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => Ok(false),
        Err(error) => Err(conflict(error)),
    };
    #[cfg(not(target_os = "android"))]
    match file.try_lock_shared() {
        Ok(()) => Ok(true),
        Err(std::fs::TryLockError::WouldBlock) => Ok(false),
        Err(error) => Err(conflict(error)),
    }
}

#[cfg(test)]
mod tests;

/// 本进程客户端与其派生读取共用的关闭标记，不修改共享材料。
#[derive(Clone)]
pub struct ClientCloseControl {
    pub(crate) direct: Arc<AtomicBool>,
    pub(crate) webvpn: Arc<AtomicBool>,
}
impl ClientCloseControl {
    /// 同步撤销本客户端的未发送请求；已发送请求保留结果未知语义。
    pub fn close(&self) {
        self.direct.store(true, Ordering::SeqCst);
        self.webvpn.store(true, Ordering::SeqCst);
    }
}
