use crate::{cache::CacheError, error::UbaaError};

/// 本机存储与云盘错误分别保留，宿主无需从文案推断认证或超时。
#[derive(Debug)]
pub enum AgendaSyncError {
    Local(CacheError),
    Remote(UbaaError),
}
impl std::fmt::Display for AgendaSyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Local(_) => f.write_str("本机日程同步存储不可用"),
            Self::Remote(error) => error.fmt(f),
        }
    }
}
impl std::error::Error for AgendaSyncError {}
impl From<CacheError> for AgendaSyncError {
    fn from(value: CacheError) -> Self {
        Self::Local(value)
    }
}
