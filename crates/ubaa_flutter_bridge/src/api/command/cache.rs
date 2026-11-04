//! 命令复用 App 的 typed 缓存刷新；不允许宿主写任意缓存正文。
use ubaa_core::facade as core;
pub(super) fn project<T, D>(
    value: Result<core::OfflineRefresh<D>, core::OfflineReadError>,
    extract: impl FnOnce(D) -> Option<T>,
) -> core::RoutedResult<T> {
    let value = value.map_err(error)?;
    if value.save_error.is_some() {
        tracing::warn!("本次在线结果未写入本机缓存");
    }
    let data = extract(value.data).ok_or_else(|| core::RoutedError {
        error: core::UbaaError::new(
            core::ErrorCode::InternalError,
            core::ErrorKind::Internal,
            false,
            "缓存刷新结果类型不匹配",
        ),
        resolution: Some(value.resolution),
    })?;
    Ok(core::Routed {
        data,
        resolution: value.resolution,
    })
}
fn error(value: core::OfflineReadError) -> core::RoutedError {
    match value {
        core::OfflineReadError::Read(error) => error,
        core::OfflineReadError::IdentityMismatch { resolution, .. } => core::RoutedError {
            error: core::UbaaError::new(
                core::ErrorCode::PermissionDenied,
                core::ErrorKind::Authentication,
                false,
                "本机缓存与会话账号不一致",
            ),
            resolution: Some(resolution),
        },
        core::OfflineReadError::Cache(_) => core::RoutedError {
            error: core::UbaaError::new(
                core::ErrorCode::InternalError,
                core::ErrorKind::Internal,
                false,
                "本机缓存已失效或不可用",
            ),
            resolution: None,
        },
    }
}

mod projection;
pub(super) use projection::*;
