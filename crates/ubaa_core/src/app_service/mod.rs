//! 应用服务的安装状态和遥测队列。

mod bootstrap;
mod bootstrap_response;
mod config;
mod privacy;
mod queue;
mod service;
mod sqlite;
mod state;
mod transport;
mod types;
mod upload;
mod version;

pub use bootstrap_response::{
    AppAnnouncement, AppAnnouncementLevel, AppBootstrapView, AppUpdateStatus, AppUpdateView,
};
pub use config::AppServiceConfig;
pub use queue::{BatchDisposition, FrozenBatch};
pub use service::{AppService, ConfirmedAccount};
pub use state::{AppServiceState, Consent};
pub use types::*;
pub use upload::{EraseAttempt, UploadAttempt};

/// Core 与应用服务 Worker 交换的接口载荷版本。
pub const APP_SERVICE_SCHEMA_VERSION: u32 = 1;

pub type AppServiceResult<T> = Result<T, AppServiceError>;

/// 不含路径、SQL 或请求内容的本机应用服务错误。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppServiceError {
    StorageUnavailable,
    UnsupportedSchema,
    InvalidPolicy,
    GuiRequired,
    InvalidPayload,
    TransportUnavailable,
}

impl std::fmt::Display for AppServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::StorageUnavailable => "应用服务数据库不可用",
            Self::UnsupportedSchema => "应用服务数据库版本不受支持",
            Self::InvalidPolicy => "隐私政策版本无效或过旧",
            Self::GuiRequired => "此操作需要图形界面",
            Self::InvalidPayload => "应用服务载荷无效",
            Self::TransportUnavailable => "应用服务传输不可用",
        })
    }
}

impl std::error::Error for AppServiceError {}

#[cfg(test)]
#[path = "tests/sqlite.rs"]
mod sqlite_tests;
#[cfg(test)]
#[path = "tests/state.rs"]
mod state_tests;
