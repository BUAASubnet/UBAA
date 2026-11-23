//! 门户资料与校园账户的在线只读入口。
use super::super::types::Operation;
use crate::domain::{
    CampusMetrics, LibraryLoan, LibraryLoans, NetworkUsage, PortalProfile, ReadonlyFeature,
};
use crate::facade::{RoutedResult, UbaaClient};

impl UbaaClient {
    /// 查询门户身份与学院。
    ///
    /// # Errors
    /// 路线、会话、业务登录、网络或解析错误时返回安全错误。
    pub async fn portal_profile(&mut self) -> RoutedResult<PortalProfile> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Portal))?;
        let (route, result) = crate::facade::routing::read_with_fallback!(
            self,
            route,
            crate::features::campus::get_profile(self.runtime_for(route.mode)).await
        );
        self.finish_routed(route, result)
    }

    /// 查询五项校园账户指标，业务错误分别保留在对应项中。
    ///
    /// # Errors
    /// 公共配置、业务登录、会话所有权或路线失败时返回整体错误。
    pub async fn campus_metrics(&mut self) -> RoutedResult<CampusMetrics> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Portal))?;
        let (route, result) = crate::facade::routing::read_with_fallback!(
            self,
            route,
            crate::features::campus::get_metrics(self.runtime_for(route.mode)).await
        );
        self.finish_routed(route, result)
    }

    /// 查询网络产品的已用及剩余流量，保留原始单位。
    ///
    /// # Errors
    /// 路线、会话、业务登录、网络或 HTML 结构错误时返回安全错误。
    pub async fn network_usage(&mut self) -> RoutedResult<NetworkUsage> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Network))?;
        let (route, result) = crate::facade::routing::read_with_fallback!(
            self,
            route,
            crate::features::campus::get_usage(self.runtime_for(route.mode)).await
        );
        self.finish_routed(route, result)
    }
}

impl UbaaClient {
    /// 复用当前路线的 SSO 会话查看当前借阅。
    ///
    /// # Errors
    /// 路线、会话、网络或借阅响应无效时返回错误。
    pub async fn current_library_loans(&mut self) -> RoutedResult<LibraryLoans> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Library))?;
        let result = self
            .network_control()
            .run_read(
                route.mode,
                false,
                Box::pin(crate::features::campus::current_loans(
                    self.runtime_for(route.mode),
                )),
            )
            .await;
        self.finish_routed(route, result)
    }

    /// 只读复核单本续借目标；不会发送写请求。
    ///
    /// # Errors
    /// 路线、会话、目标已变化或借阅响应无效时返回带路线信息的错误。
    pub async fn preflight_library_loan_renew(
        &mut self,
        loan_id: &str,
    ) -> RoutedResult<LibraryLoan> {
        self.guard_latest_routed()?;
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Library))?;
        let result =
            crate::features::campus::renew_preflight(self.runtime_for(route.mode), loan_id).await;
        self.finish_routed(route, result)
    }
}
