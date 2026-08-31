//! CLI 对 Core 路由决策的安全上下文投影。

use ubaa_core::domain::{ConnectionMode, RoutePolicy};
use ubaa_core::facade::{NetworkState, RouteDiagnostic, RouteResolution};
use ubaa_core::output::{CliFeature, ResolvedRoutedJsonMeta};

/// Core 门面完成路由解析后返回的安全路由决策上下文。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ReadonlyRouteContext {
    /// 当前功能实际使用的路由策略。
    pub policy: RoutePolicy,
    /// 决策所用的网关可达状态；未探测时为未知。
    pub network: NetworkState,
    /// 回退前选择的路由。
    pub initial_route: ConnectionMode,
    /// 回退后选择的路由。
    pub resolved_route: ConnectionMode,
    /// 是否发生了就绪路由回退。
    pub used_fallback: bool,
}

impl ReadonlyRouteContext {
    pub(crate) fn explicit(mode: ConnectionMode) -> Self {
        Self {
            policy: match mode {
                ConnectionMode::Direct => RoutePolicy::Direct,
                ConnectionMode::WebVpn => RoutePolicy::WebVpn,
            },
            network: NetworkState::Unknown,
            initial_route: mode,
            resolved_route: mode,
            used_fallback: false,
        }
    }

    pub(crate) fn meta(
        self,
        feature: CliFeature,
        resolved_route: ConnectionMode,
    ) -> ResolvedRoutedJsonMeta {
        ResolvedRoutedJsonMeta::from_resolution(feature, self.resolution(resolved_route))
    }

    pub(crate) fn resolution(self, resolved_route: ConnectionMode) -> RouteResolution {
        RouteResolution {
            mode: resolved_route,
            policy: self.policy,
            diagnostic: RouteDiagnostic {
                network: self.network,
                initial_route: self.initial_route,
                mode: resolved_route,
                used_fallback: self.used_fallback,
            },
        }
    }
}

impl From<RouteResolution> for ReadonlyRouteContext {
    fn from(resolution: RouteResolution) -> Self {
        Self {
            policy: resolution.policy,
            network: resolution.diagnostic.network,
            initial_route: resolution.diagnostic.initial_route,
            resolved_route: resolution.mode,
            used_fallback: resolution.diagnostic.used_fallback,
        }
    }
}
