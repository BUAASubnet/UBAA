//! 对象字节流的独立端口，不使用业务 Cookie 或隐式认证。
use crate::error::{Result, UbaaError};
use std::fs::File;

/// 单个请求读取的文件区间，正文不进入通用 HTTP DTO。
pub struct HttpFileRange {
    pub file: File,
    pub offset: u64,
    pub length: u64,
}
/// 每个流块检查取消与固定归属，并报告累计进度。
pub trait HttpTransferObserver: Send + Sync {
    /// # Errors
    /// 取消、关闭或固定归属失效时拒绝继续传输。
    fn check(&self) -> Result<()>;
    fn advance(&self, bytes: u64);
    fn set_total(&self, _bytes: u64) {}
}
pub(super) fn unavailable() -> UbaaError {
    UbaaError::invalid_input("当前传输端口不支持对象字节流")
}
