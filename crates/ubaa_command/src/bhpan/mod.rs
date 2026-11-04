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
#[derive(Clone, Debug)]
pub struct BhpanPreparedInput {
    pub(crate) password: SecretValue,
    file: Option<(std::path::PathBuf, u64, std::time::SystemTime)>,
}
impl BhpanPreparedInput {
    /// 在账号材料初始化前读取本机元数据。
    /// # Errors
    /// 密码格式或文件不可读时拒绝。
    pub fn capture(args: &BhpanArgs, bytes: &[u8]) -> Result<Self> {
        let file = if let BhpanCommand::UploadFast { file, .. } = &args.command {
            let metadata =
                std::fs::metadata(file).map_err(|_| UbaaError::invalid_input("秒传文件不可读"))?;
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
        })
    }
    pub(crate) fn check_file(&self) -> Result<()> {
        if let Some((path, length, modified)) = &self.file {
            let current =
                std::fs::metadata(path).map_err(|_| UbaaError::invalid_input("秒传文件不可读"))?;
            if current.len() != *length || current.modified().ok() != Some(*modified) {
                return Err(UbaaError::invalid_input("秒传文件自输入准备后已变化"));
            }
        }
        Ok(())
    }
}
