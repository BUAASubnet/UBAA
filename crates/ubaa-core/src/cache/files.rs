//! 缓存私有目录和数据库路径检查；不改变会话目录内容。
use super::{CacheError, CacheResult};
use std::{
    fs,
    path::{Path, PathBuf},
};

pub(super) fn database_path(root: &Path, account: &str) -> CacheResult<PathBuf> {
    if !root.is_absolute() || account.len() != 32 || !account.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(CacheError::InvalidInput);
    }
    validate_directory(root)?;
    // macOS 的 /var 等系统祖先路径可能是链接；先验证调用方目录，再固定真实父路径。
    let dir = root
        .canonicalize()
        .map_err(|_| CacheError::Unavailable)?
        .join("business-cache");
    if !dir.exists() {
        let mut builder = fs::DirBuilder::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt as _;
            builder.mode(0o700);
        }
        match builder.create(&dir) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(_) => return Err(CacheError::Unavailable),
        }
    }
    validate_directory(&dir)?;
    let path = dir.join(format!("{}.sqlite", account.to_ascii_lowercase()));
    for suffix in ["", "-journal", "-wal", "-shm"] {
        let candidate = dir.join(format!(
            "{}{suffix}",
            path.file_name()
                .ok_or(CacheError::InvalidInput)?
                .to_string_lossy()
        ));
        match fs::symlink_metadata(candidate) {
            Ok(meta) if !meta.is_file() || meta.file_type().is_symlink() => {
                return Err(CacheError::Unavailable);
            }
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
                return Err(CacheError::Unavailable);
            }
            _ => {}
        }
    }
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
    match options.open(&path) {
        Ok(file) => file.sync_all().map_err(|_| CacheError::Unavailable)?,
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(_) => return Err(CacheError::Unavailable),
    }
    Ok(path)
}
fn validate_directory(path: &Path) -> CacheResult<()> {
    let meta = fs::symlink_metadata(path).map_err(|_| CacheError::Unavailable)?;
    if meta.file_type().is_symlink() || !meta.is_dir() {
        return Err(CacheError::Unavailable);
    }
    Ok(())
}
