//! 门户资料与校园账户的在线只读入口。
use super::super::types::Operation;
use crate::domain::{CampusMetrics, NetworkUsage, PortalProfile, ReadonlyFeature};
use crate::facade::{RoutedResult, UbaaClient};

impl UbaaClient {
    /// 查询门户身份与学院。
    ///
    /// # Errors
    /// 路线、会话、业务登录、网络或解析错误时返回安全错误。
    pub async fn portal_profile(&mut self) -> RoutedResult<PortalProfile> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Portal))?;
        let result = crate::features::campus::get_profile(self.runtime_for(route.mode)).await;
        self.finish_routed(route, result)
    }

    /// 查询五项校园账户指标，业务错误分别保留在对应项中。
    ///
    /// # Errors
    /// 公共配置、业务登录、会话所有权或路线失败时返回整体错误。
    pub async fn campus_metrics(&mut self) -> RoutedResult<CampusMetrics> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Portal))?;
        let result = crate::features::campus::get_metrics(self.runtime_for(route.mode)).await;
        self.finish_routed(route, result)
    }

    /// 查询网络产品的已用及剩余流量，保留原始单位。
    ///
    /// # Errors
    /// 路线、会话、业务登录、网络或 HTML 结构错误时返回安全错误。
    pub async fn network_usage(&mut self) -> RoutedResult<NetworkUsage> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Network))?;
        let result = crate::features::campus::get_usage(self.runtime_for(route.mode)).await;
        self.finish_routed(route, result)
    }
}
