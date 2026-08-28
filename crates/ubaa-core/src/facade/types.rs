//! Facade 的结果包装器与内部操作类型。

use crate::connection::RouteResolution;
use crate::domain::ReadonlyFeature;
use crate::error::UbaaError;

/// 普通操作成功结果及 Core 作出的路线决策。
#[derive(Clone, Debug)]
pub struct Routed<T> {
    /// 稳定的操作结果。
    pub data: T,
    /// 本次操作不可变的路由元数据。
    pub resolution: RouteResolution,
}

/// 普通操作失败；若已完成解析则包含路由元数据。
#[derive(Clone, Debug)]
pub struct RoutedError {
    /// 稳定的 Core 错误。
    pub error: UbaaError,
    /// 路由决策；仅在路线解析前失败时缺失。
    pub resolution: Option<RouteResolution>,
}

impl RoutedError {
    /// Core 作出路线决策后返回路由元数据。
    #[must_use]
    pub const fn resolution(&self) -> Option<&RouteResolution> {
        self.resolution.as_ref()
    }
}

impl std::fmt::Display for RoutedError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.error.fmt(formatter)
    }
}

impl std::error::Error for RoutedError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.error)
    }
}

#[derive(Clone, Copy)]
pub(crate) enum Operation {
    User,
    Feature(ReadonlyFeature),
}
