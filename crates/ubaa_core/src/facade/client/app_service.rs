//! 应用服务的安装级入口，沿用 GUI 和 App 命令模式的配置目录。

use super::UbaaClient;
pub use crate::app_service::*;
use std::{path::Path, sync::Arc};

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
    /// 将宿主打开的安装服务绑定到两条学校路线，派生客户端继续使用同一门控。
    pub fn bind_app_service(&mut self, service: Arc<AppService>) {
        self.direct_runtime.app_service = Some(service.clone());
        self.webvpn_runtime.app_service = Some(service);
    }

    /// 宿主在为学校操作撤销旧绑定前，可先检查取消状态和已保存的更新门控。
    ///
    /// # Errors
    /// 操作已停止、门控生效或安装存储不可用时返回安全错误。
    pub fn check_school_requests(&self) -> crate::error::Result<()> {
        self.direct_runtime.check_school_requests()
    }

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

#[cfg(all(test, feature = "test-contract"))]
#[path = "update_gate_tests.rs"]
mod update_gate_tests;
