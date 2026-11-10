//! 应用服务的安装级入口，沿用 GUI 和 App 命令模式的配置目录。

use super::UbaaClient;
pub use crate::app_service::*;
use std::path::Path;

/// 在宿主配置目录中打开安装服务，无需初始化学校会话或传输。
///
/// # Errors
/// 政策版本无效，或安装数据库无法打开时返回错误。
pub fn open_installation(
    directory: &Path,
    config: AppServiceConfig,
    surface: Surface,
    policy_version: u32,
) -> AppServiceResult<AppService> {
    AppService::open(directory, config, surface, policy_version)
}

impl UbaaClient {
    /// 从本客户端的宿主配置目录打开应用服务数据库。
    ///
    /// # Errors
    /// 客户端未绑定持久目录，或安装数据库无法打开时返回错误。
    pub fn open_app_service(
        &self,
        config: AppServiceConfig,
        surface: Surface,
        policy_version: u32,
    ) -> AppServiceResult<AppService> {
        let directory = self
            .config_dir
            .as_deref()
            .ok_or(AppServiceError::StorageUnavailable)?;
        open_installation(directory, config, surface, policy_version)
    }
}
