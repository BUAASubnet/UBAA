//! 应用服务的安装状态和遥测队列。

mod config;
mod privacy;
mod queue;
mod service;
mod sqlite;
mod state;
mod types;

pub use config::AppServiceConfig;
pub use queue::{BatchDisposition, FrozenBatch};
pub use service::{AppService, ConfirmedAccount};
pub use state::{AppServiceState, Consent};
pub use types::*;

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
}

impl std::fmt::Display for AppServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::StorageUnavailable => "应用服务数据库不可用",
            Self::UnsupportedSchema => "应用服务数据库版本不受支持",
            Self::InvalidPolicy => "隐私政策版本无效或过旧",
            Self::GuiRequired => "此操作需要图形界面",
            Self::InvalidPayload => "遥测载荷无法编码",
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
