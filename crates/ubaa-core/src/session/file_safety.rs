//! 会话文件与 Cookie 共用的文件系统和通用安全 helper。

use std::fs::{self, File, OpenOptions};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

const MAX_TEMP_FILE_ATTEMPTS: usize = 128;
static NEXT_TEMP_FILE: AtomicU64 = AtomicU64::new(0);

pub(super) fn create_temporary_file(parent: &Path) -> Result<(PathBuf, File)> {
    for _ in 0..MAX_TEMP_FILE_ATTEMPTS {
        let sequence = NEXT_TEMP_FILE.fetch_add(1, Ordering::Relaxed);
        let path = parent.join(format!(
            ".session.json.{}.{sequence}.tmp",
            std::process::id()
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        restrict_file_creation(&mut options);
        match options.open(&path) {
            Ok(file) => return Ok((path, file)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(_) => return Err(session_error("could not create temporary session file")),
        }
    }
    Err(session_error("could not allocate temporary session file"))
}

pub(super) fn validate_directory(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|_| session_error("could not inspect config directory"))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(session_error("config path is not a directory"));
    }
    Ok(())
}

pub(super) fn validate_regular_file(path: &Path, message: &'static str) -> Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(session_error(message))
        }
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(_) => Err(session_error("could not inspect session file")),
    }
}

pub(super) fn open_existing_session_file(path: &Path) -> Result<Option<File>> {
    let mut options = OpenOptions::new();
    options.read(true);
    prevent_symlink_following(&mut options);
    match options.open(path) {
        Ok(file) => {
            validate_open_regular_file(
                &file,
                "session path is not a regular file",
                "could not inspect session",
            )?;
            Ok(Some(file))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => {
            validate_regular_file(path, "session path is not a regular file")?;
            Err(session_error("could not read session"))
        }
    }
}

pub(super) fn validate_open_regular_file(
    file: &File,
    type_message: &'static str,
    inspect_message: &'static str,
) -> Result<()> {
    let metadata = file
        .metadata()
        .map_err(|_| session_error(inspect_message))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(session_error(type_message));
    }
    Ok(())
}

pub(super) fn prevent_symlink_following(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt as _;
        // Rust 1.95 标准库在不跟随链接打开文件时使用此 Win32 标志。
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    #[cfg(not(any(unix, windows)))]
    let _ = options;
}

pub(super) fn sync_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        File::open(path)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| session_error("could not sync config directory"))?;
    }
    #[cfg(windows)]
    {
        let metadata = fs::symlink_metadata(path)
            .map_err(|_| session_error("could not sync config directory"))?;
        if !metadata.file_type().is_dir() {
            return Err(session_error("could not sync config directory"));
        }
    }
    Ok(())
}

pub(super) fn path_matches(request: &str, cookie: &str) -> bool {
    if request == cookie {
        return true;
    }
    request
        .strip_prefix(cookie)
        .is_some_and(|rest| cookie.ends_with('/') || rest.starts_with('/'))
}

pub(super) fn domain_matches(host: &str, domain: &str) -> bool {
    host.eq_ignore_ascii_case(domain) || host.to_ascii_lowercase().ends_with(&format!(".{domain}"))
}

pub(super) fn header_values<'a>(
    headers: &'a std::collections::BTreeMap<String, Vec<String>>,
    name: &str,
) -> impl Iterator<Item = &'a str> {
    headers
        .iter()
        .filter(move |(key, _)| key.eq_ignore_ascii_case(name))
        .flat_map(|(_, values)| values.iter().map(String::as_str))
}

pub(super) fn unix_seconds(time: SystemTime) -> Result<i64> {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_secs()).unwrap_or(i64::MAX))
        .map_err(|_| session_error("system clock is before Unix epoch"))
}

pub(super) fn session_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

pub(super) fn restrict_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        File::open(path)
            .and_then(|directory| directory.set_permissions(fs::Permissions::from_mode(0o700)))
            .map_err(|_| session_error("could not restrict config directory"))?;
    }
    #[cfg(windows)]
    {
        let metadata = fs::symlink_metadata(path)
            .map_err(|_| session_error("could not restrict config directory"))?;
        if !metadata.file_type().is_dir() {
            return Err(session_error("could not restrict config directory"));
        }
    }
    Ok(())
}

pub(super) fn restrict_file_creation(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    #[cfg(not(unix))]
    let _ = options;
}

pub(super) fn restrict_open_file(file: &File, message: &'static str) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|_| session_error(message))?;
    }
    #[cfg(windows)]
    {
        let metadata = file.metadata().map_err(|_| session_error(message))?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(session_error(message));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 缺失会话目录不能通过限制与同步门禁() {
        let missing = std::env::temp_dir().join(format!(
            "ubaa-missing-session-directory-{}",
            std::process::id()
        ));
        assert!(restrict_directory(&missing).is_err());
        assert!(sync_directory(&missing).is_err());
    }
}
