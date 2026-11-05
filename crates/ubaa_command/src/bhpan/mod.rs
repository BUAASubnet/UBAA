//! 公共云盘命令执行与安全输出，所有上游协议调用仍由 Core 完成。
mod execute;
mod navigation;
pub(crate) use navigation::components as validate_path;
mod output;
use crate::{BhpanArgs, BhpanCommand, bhpan_password};
pub use execute::execute_bhpan;
pub use output::{BhpanEntry, BhpanOutput, BhpanShareEntry};
use ubaa_core::facade::{Result, SecretValue, UbaaError};

/// 准备阶段捕获输入，恢复不会重新读取密码或接受已变化的本机文件。
#[derive(Clone)]
pub struct BhpanPreparedInput {
    pub(crate) password: SecretValue,
    transfer: Option<ubaa_core::facade::bhpan::BhpanTransfer>,
    file: Option<(std::path::PathBuf, u64, std::time::SystemTime)>,
}
impl BhpanPreparedInput {
    /// 在账号材料初始化前读取本机元数据。
    /// # Errors
    /// 密码格式或文件不可读时拒绝。
    pub fn capture(args: &BhpanArgs, bytes: &[u8]) -> Result<Self> {
        let file = if let BhpanCommand::UploadFast { file, .. }
        | BhpanCommand::Upload { file, .. } = &args.command
        {
            let metadata =
                std::fs::metadata(file).map_err(|_| UbaaError::invalid_input("上传文件不可读"))?;
            Some((
                file.clone(),
                metadata.len(),
                metadata
                    .modified()
                    .map_err(|_| UbaaError::invalid_input("无法读取文件修改时间"))?,
            ))
        } else {
            None
        };
        Ok(Self {
            password: bhpan_password(bytes)?,
            file,
            transfer: None,
        })
    }
    /// 将本次运行的取消与进度控制附加到输入快照，不改变文件或密码。
    #[must_use]
    pub fn with_transfer(&self, transfer: ubaa_core::facade::bhpan::BhpanTransfer) -> Self {
        let mut input = self.clone();
        input.transfer = Some(transfer);
        input
    }
    pub(crate) fn transfer(&self) -> ubaa_core::facade::bhpan::BhpanTransfer {
        self.transfer.clone().unwrap_or_default()
    }
    pub(crate) fn check_file(&self) -> Result<()> {
        if let Some((path, length, modified)) = &self.file {
            let current =
                std::fs::metadata(path).map_err(|_| UbaaError::invalid_input("上传文件不可读"))?;
            if current.len() != *length || current.modified().ok() != Some(*modified) {
                return Err(UbaaError::invalid_input("上传文件自输入准备后已变化"));
            }
        }
        Ok(())
    }
}

/// 终端进度不包含文件内容、对象地址或头值。
#[must_use]
pub fn progress_line(progress: &ubaa_core::facade::BhpanTransferProgress) -> String {
    use ubaa_core::facade::BhpanTransferPhase as P;
    let phase = match progress.phase {
        P::Queued => "排队",
        P::HashingMini => "计算检查摘要",
        P::HashingFull => "计算完整摘要",
        P::Checking => "检查秒传",
        P::AwaitingConfirmation => "等待确认",
        P::Submitting => "正在提交",
        P::Completed => "传输完成",
        P::Cancelled => "任务已取消",
        P::Failed => "传输失败",
        P::OutcomeUnknown => "上传结果待核对",
        P::Blocked => "不支持秒传",
        P::Uploading => "正在上传",
        P::Downloading => "正在下载",
        P::Finalizing => "完成登记",
    };
    if progress.total == 0 {
        format!("北航云盘：{phase}，已传输 {} 字节\n", progress.bytes)
    } else {
        format!(
            "北航云盘：{phase}，{} / {} 字节\n",
            progress.bytes, progress.total
        )
    }
}
