//! 将宿主的同一停止资格贯穿异步调用及同步发送边界。
use crate::error::Result;
use std::{future::Future, sync::Arc};

pub(crate) type OperationCheck = Arc<dyn Fn() -> Result<()> + Send + Sync>;
tokio::task_local! {
    static OPERATION: OperationCheck;
    static FAST_CONNECT: bool;
}

pub(crate) async fn with_fast_connect<T>(enabled: bool, work: impl Future<Output = T>) -> T {
    FAST_CONNECT.scope(enabled, work).await
}

pub(crate) fn fast_connect() -> bool {
    FAST_CONNECT.try_with(|enabled| *enabled).unwrap_or(false)
}

/// 在调用的发送边界检查宿主原有的期限与取消状态。
///
/// 检查随 Future 的轮询作用域生效，Future 完成、被丢弃或 panic 后自动撤销。
/// 检查函数必须读取原控制柄，不能重新计算期限。字节流保留同一检查函数。
pub async fn with_operation_control<T>(
    check: impl Fn() -> Result<()> + Send + Sync + 'static,
    work: impl Future<Output = T>,
) -> T {
    OPERATION.scope(Arc::new(check), work).await
}

pub(crate) fn current() -> Option<OperationCheck> {
    OPERATION.try_with(Arc::clone).ok()
}
pub(crate) fn check() -> Result<()> {
    OPERATION.try_with(|check| check()).unwrap_or(Ok(()))
}
