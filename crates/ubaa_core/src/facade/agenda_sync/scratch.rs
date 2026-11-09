use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};
pub(super) const LIMIT: u64 = 32 * 1024 * 1024;
pub(super) struct Scratch(PathBuf);
impl Scratch {
    pub(super) fn new(root: &Path) -> Result<Self> {
        if !root.is_absolute() {
            return Err(failed());
        }
        fs::create_dir_all(root).map_err(|_| failed())?;
        let path = root.join(uuid::Uuid::new_v4().to_string());
        let builder = fs::DirBuilder::new();
        #[cfg(unix)]
        let builder = {
            use std::os::unix::fs::DirBuilderExt;
            let mut builder = builder;
            builder.mode(0o700);
            builder
        };
        builder.create(&path).map_err(|_| failed())?;
        Ok(Self(path))
    }
    pub(super) fn path(&self) -> PathBuf {
        self.0.join("agenda.json")
    }
    pub(super) fn write(&self, bytes: &[u8]) -> Result<PathBuf> {
        if bytes.len() as u64 > LIMIT {
            return Err(failed());
        }
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let path = self.path();
        let mut file = options.open(&path).map_err(|_| failed())?;
        file.write_all(bytes).map_err(|_| failed())?;
        Ok(path)
    }
}
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
pub(super) fn failed() -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        "日程同步的本机临时文件不可用",
    )
}
