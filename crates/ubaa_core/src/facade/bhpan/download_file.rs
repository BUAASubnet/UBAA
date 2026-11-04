use super::{BhpanTransfer, UbaaClient};
use crate::{
    domain::bhpan::{BhpanDownloadReceipt, BhpanTransferPhase},
    error::{Result, UbaaError},
    features::bhpan::{object, parse},
};
use std::{
    fs::{File, OpenOptions},
    path::{Path, PathBuf},
};

struct PendingFile {
    path: PathBuf,
    file: File,
}
impl PendingFile {
    fn create(destination: &Path, overwrite: bool) -> Result<Self> {
        if destination.file_name().is_none()
            || !overwrite && destination.try_exists().map_err(|_| local())?
        {
            return Err(UbaaError::invalid_input("下载目标已存在或路径无效"));
        }
        let parent = destination
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        let path = parent.join(format!(".ubaa-download-{}.part", uuid::Uuid::new_v4()));
        let mut options = OpenOptions::new();
        options.write(true).read(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let file = options.open(&path).map_err(|_| local())?;
        Ok(Self { path, file })
    }
    fn deliver(&self, destination: &Path, overwrite: bool) -> Result<()> {
        self.file.sync_all().map_err(|_| local())?;
        if overwrite {
            if let Ok(metadata) = std::fs::symlink_metadata(destination)
                && !metadata.is_file()
            {
                return Err(local());
            }
            std::fs::rename(&self.path, destination).map_err(|_| local())?;
        } else {
            std::fs::hard_link(&self.path, destination).map_err(|_| local())?;
        }
        #[cfg(unix)]
        {
            let parent = destination
                .parent()
                .filter(|path| !path.as_os_str().is_empty())
                .unwrap_or_else(|| Path::new("."));
            File::open(parent)
                .and_then(|directory| directory.sync_all())
                .map_err(|_| local())?;
        }
        Ok(())
    }
}
impl Drop for PendingFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}
fn local() -> UbaaError {
    UbaaError::invalid_input("本机下载文件无法交付，请检查所选位置")
}
pub(super) struct AuthorizedDownload {
    pub request: crate::ports::HttpRequest,
    pub batch: bool,
    pub expected: Option<u64>,
}
impl UbaaClient {
    /// 下载单文件或打包目录/多项，完整接收后才交付本机文件。
    /// # Errors
    /// 授权、对象响应、文件、取消或账号路线变化时停止并移除未交付正文。
    pub async fn bhpan_download(
        &mut self,
        handles: &[String],
        name: &str,
        destination: PathBuf,
        overwrite: bool,
        transfer: BhpanTransfer,
    ) -> Result<BhpanDownloadReceipt> {
        transfer.claim()?;
        self.bhpan_scope()?;
        let pending = PendingFile::create(&destination, overwrite)?;
        let result = self
            .download_inner(handles, name, &destination, overwrite, &pending, &transfer)
            .await;
        let progress = transfer.progress();
        let phase = if result.is_ok() {
            BhpanTransferPhase::Completed
        } else if progress.phase == BhpanTransferPhase::Cancelled {
            BhpanTransferPhase::Cancelled
        } else {
            BhpanTransferPhase::Failed
        };
        transfer.set(phase, progress.bytes, progress.total);
        result
    }
    async fn download_inner(
        &mut self,
        handles: &[String],
        name: &str,
        destination: &Path,
        overwrite: bool,
        pending: &PendingFile,
        transfer: &BhpanTransfer,
    ) -> Result<BhpanDownloadReceipt> {
        let binding = self.bhpan_binding();
        let (bytes, batch, expected) = tokio::select! {
            biased;
            error=transfer.cancelled()=>return Err(error),
            result=self.bhpan_download_authorization(handles,name)=>result?,
        };
        let request = object::download(&bytes, batch)?;
        self.bhpan_scope()?;
        crate::facade::operation_control::check()?;
        transfer.ensure_active()?;
        if self.bhpan.binding.as_ref() != Some(&binding) {
            return Err(UbaaError::invalid_input("下载所属账号或路线已变化"));
        }
        self.finish_download(
            AuthorizedDownload {
                request,
                batch,
                expected,
            },
            destination,
            overwrite,
            pending,
            transfer,
        )
        .await
    }
    pub(super) async fn download_authorized(
        &mut self,
        authorized: AuthorizedDownload,
        destination: PathBuf,
        overwrite: bool,
        transfer: &BhpanTransfer,
    ) -> Result<BhpanDownloadReceipt> {
        let pending = PendingFile::create(&destination, overwrite)?;
        let result = self
            .finish_download(authorized, &destination, overwrite, &pending, transfer)
            .await;
        let progress = transfer.progress();
        let phase = if result.is_ok() {
            BhpanTransferPhase::Completed
        } else if progress.phase == BhpanTransferPhase::Cancelled {
            BhpanTransferPhase::Cancelled
        } else {
            BhpanTransferPhase::Failed
        };
        transfer.set(phase, progress.bytes, progress.total);
        result
    }
    async fn finish_download(
        &mut self,
        authorized: AuthorizedDownload,
        destination: &Path,
        overwrite: bool,
        pending: &PendingFile,
        transfer: &BhpanTransfer,
    ) -> Result<BhpanDownloadReceipt> {
        let AuthorizedDownload {
            request,
            batch,
            expected,
        } = authorized;
        transfer.set(BhpanTransferPhase::Downloading, 0, expected.unwrap_or(0));
        let original = request.clone();
        let response = self
            .direct_runtime
            .object_download(
                request,
                pending.file.try_clone().map_err(|_| local())?,
                transfer,
            )
            .await?;
        object::success(&original, &response)?;
        let bytes = pending.file.metadata().map_err(|_| local())?.len();
        if expected.is_some_and(|expected| expected != bytes) || response.status != 200 {
            return Err(parse::invalid());
        }
        self.direct_runtime.ensure_session_revision()?;
        crate::facade::operation_control::check()?;
        transfer.ensure_active()?;
        let deliver = || {
            self.direct_runtime.ensure_session_revision()?;
            crate::facade::operation_control::check()?;
            transfer.ensure_active()?;
            pending.deliver(destination, overwrite)
        };
        if let Some(shared) = self.shared_account_guard() {
            shared.with_current(deliver)??;
        } else {
            deliver()?;
        }
        Ok(BhpanDownloadReceipt { bytes, batch })
    }
}
