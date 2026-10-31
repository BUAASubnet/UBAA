//! 配置目录和锁文件的固定身份检查。路径别名归一化后使用同一锁。
use super::{LocalError, LocalResult};
use same_file::Handle;
use std::fs::{self, File, OpenOptions};
use std::path::{Component, Path, PathBuf};

pub(super) struct Paths {
    pub root: PathBuf,
    pub lock: File,
    root_handle: Handle,
    lock_handle: Handle,
}
impl Paths {
    pub fn open(path: &Path) -> LocalResult<Self> {
        #[cfg(not(unix))]
        {
            let _ = path;
            return Err(LocalError::MaterialUnavailable);
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
            let absolute = if path.is_absolute() {
                path.to_owned()
            } else {
                std::env::current_dir()
                    .map_err(|_| LocalError::Storage)?
                    .join(path)
            };
            inspect_components(&absolute)?;
            if !absolute.exists() {
                let mut builder = fs::DirBuilder::new();
                builder.recursive(true).mode(0o700);
                builder.create(&absolute).map_err(|_| LocalError::Storage)?;
            }
            inspect_components(&absolute)?;
            let root = fs::canonicalize(&absolute).map_err(|_| LocalError::Storage)?;
            private(&root, true)?;
            let root_handle = Handle::from_path(&root).map_err(|_| LocalError::Storage)?;
            let lock_path = root.join("cli-accounts.lock");
            let mut options = OpenOptions::new();
            options
                .read(true)
                .write(true)
                .create(true)
                .mode(0o600)
                .custom_flags(libc::O_NOFOLLOW);
            // 路径先后检查与同一文件身份比较，符号链接不能被接受为锁。
            if lock_path.symlink_metadata().is_ok() {
                private(&lock_path, false)?;
            }
            let lock = options.open(&lock_path).map_err(|_| LocalError::Storage)?;
            private(&lock_path, false)?;
            let lock_handle = Handle::from_file(lock.try_clone().map_err(|_| LocalError::Storage)?)
                .map_err(|_| LocalError::Storage)?;
            if lock_handle != Handle::from_path(&lock_path).map_err(|_| LocalError::Storage)? {
                return Err(LocalError::Storage);
            }
            let result = Self {
                root,
                lock,
                root_handle,
                lock_handle,
            };
            result.validate()?;
            Ok(result)
        }
    }
    pub fn validate(&self) -> LocalResult<()> {
        inspect_components(&self.root)?;
        private(&self.root, true)?;
        let lock_path = self.root.join("cli-accounts.lock");
        private(&lock_path, false)?;
        if self.root_handle != Handle::from_path(&self.root).map_err(|_| LocalError::Storage)?
            || self.lock_handle != Handle::from_path(&lock_path).map_err(|_| LocalError::Storage)?
        {
            return Err(LocalError::Storage);
        }
        Ok(())
    }
    pub fn identity(&self) -> LocalResult<String> {
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            let m = fs::metadata(&self.root).map_err(|_| LocalError::Storage)?;
            Ok(format!("{}:{}", m.dev(), m.ino()))
        }
        #[cfg(not(unix))]
        {
            Err(LocalError::MaterialUnavailable)
        }
    }
}
fn inspect_components(path: &Path) -> LocalResult<()> {
    let mut current = PathBuf::new();
    for part in path.components() {
        if matches!(part, Component::ParentDir) {
            current.pop();
        } else {
            current.push(part);
        }
        match fs::symlink_metadata(&current) {
            Ok(m) if m.file_type().is_symlink() => {
                // Core 既有私有路径允许 macOS 的固定系统祖先映射；配置目录本身仍拒绝链接。
                if !(cfg!(target_os = "macos")
                    && [Path::new("/var"), Path::new("/tmp")].contains(&current.as_path()))
                {
                    return Err(LocalError::Storage);
                }
            }
            Ok(m) if !m.is_dir() => return Err(LocalError::Storage),
            Ok(_) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Err(_) => return Err(LocalError::Storage),
        }
    }
    Ok(())
}
pub(super) fn private(path: &Path, directory: bool) -> LocalResult<()> {
    let m = fs::symlink_metadata(path).map_err(|_| LocalError::Storage)?;
    if m.file_type().is_symlink() || (directory && !m.is_dir()) || (!directory && !m.is_file()) {
        return Err(LocalError::Storage);
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if m.permissions().mode() & 0o077 != 0 {
            return Err(LocalError::Storage);
        }
    }
    Ok(())
}
