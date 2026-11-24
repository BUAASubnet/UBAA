use crate::{
    domain::bhpan::{BhpanTransferPhase as Phase, transfer::BhpanTransfer},
    error::{Result, UbaaError},
};
use md5::{Digest, Md5};
use std::{
    path::{Path, PathBuf},
    time::SystemTime,
};
use tokio::{
    fs::File,
    io::{AsyncReadExt, AsyncSeekExt},
};

pub(super) struct Source {
    path: PathBuf,
    pub(super) name: String,
    pub(super) size: u64,
    pub(super) md5: String,
    modified: SystemTime,
}

impl Source {
    pub(super) async fn open(
        path: &Path,
        allowed: &[String],
        progress: &BhpanTransfer,
    ) -> Result<Self> {
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.chars().any(char::is_control))
            .ok_or_else(|| UbaaError::invalid_input("文件名无效"))?;
        let extension = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
        if !allowed
            .iter()
            .any(|ext| ext.trim_start_matches('.').eq_ignore_ascii_case(extension))
        {
            return Err(UbaaError::invalid_input("作业不允许该文件扩展名"));
        }
        let mut file = File::open(path).await.map_err(|_| unreadable())?;
        let meta = file.metadata().await.map_err(|_| unreadable())?;
        let size = meta.len();
        if !meta.is_file() || size == 0 || size > 100 * 1024 * 1024 {
            return Err(UbaaError::invalid_input(
                "请选择非空且不超过 100 MiB 的普通文件",
            ));
        }
        let modified = meta.modified().map_err(|_| unreadable())?;
        let md5 = digest(&mut file, size, progress).await?;
        Ok(Self {
            path: path.into(),
            name: name.into(),
            size,
            md5,
            modified,
        })
    }
    pub(super) async fn verify(&self, progress: &BhpanTransfer) -> Result<File> {
        let mut file = File::open(&self.path).await.map_err(|_| changed())?;
        self.check_metadata(&file).await?;
        if digest(&mut file, self.size, progress).await? != self.md5 {
            return Err(changed());
        }
        file.rewind().await.map_err(|_| unreadable())?;
        Ok(file)
    }
    pub(super) async fn check_metadata(&self, file: &File) -> Result<()> {
        let meta = file.metadata().await.map_err(|_| changed())?;
        if meta.len() != self.size || meta.modified().ok() != Some(self.modified) {
            return Err(changed());
        }
        Ok(())
    }
}
async fn digest(file: &mut File, size: u64, progress: &BhpanTransfer) -> Result<String> {
    progress.set(Phase::HashingFull, 0, size);
    let mut buffer = vec![0u8; 65536];
    let mut hash = Md5::new();
    let mut total = 0;
    loop {
        progress.ensure_active()?;
        let read = file.read(&mut buffer).await.map_err(|_| unreadable())?;
        if read == 0 {
            break;
        }
        total += read as u64;
        if total > size {
            return Err(changed());
        }
        hash.update(&buffer[..read]);
        progress.advance(read as u64);
    }
    if total != size {
        return Err(changed());
    }
    Ok(hex::encode(hash.finalize()))
}
pub(super) fn unreadable() -> UbaaError {
    UbaaError::invalid_input("无法读取所选文件")
}
fn changed() -> UbaaError {
    UbaaError::invalid_input("文件已变化，请重新准备")
        .with_diagnostic("confirmation", "spoc_file_changed")
}
