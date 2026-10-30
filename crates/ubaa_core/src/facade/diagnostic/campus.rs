//! 门户与网费的固定路线诊断入口。
use super::RouteClient;
use crate::domain::{CampusMetrics, FeatureResult, NetworkUsage, PortalProfile};
use crate::error::Result;

impl RouteClient {
    /// 在固定路线查询门户资料。
    ///
    /// # Errors
    /// 会话、业务登录、传输或格式错误时失败。
    pub async fn portal_profile(&mut self) -> Result<FeatureResult<PortalProfile>> {
        self.guard_session_ownership()?;
        let result = crate::features::campus::get_profile(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 在固定路线查询五项指标。
    ///
    /// # Errors
    /// 公共配置、会话、业务登录或传输失败时返回整体错误。
    pub async fn campus_metrics(&mut self) -> Result<FeatureResult<CampusMetrics>> {
        self.guard_session_ownership()?;
        let result = crate::features::campus::get_metrics(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }

    /// 在固定路线查询产品流量。
    ///
    /// # Errors
    /// 会话、业务登录、传输或格式错误时失败。
    pub async fn network_usage(&mut self) -> Result<FeatureResult<NetworkUsage>> {
        self.guard_session_ownership()?;
        let result = crate::features::campus::get_usage(&mut self.runtime).await;
        let data = self.finish_readonly_operation(result)?;
        Ok(crate::features::feature_result(&self.runtime, data))
    }
}
