use super::{RoutedResult, UbaaClient, types::Operation};
use crate::domain::{HealthCloudPage, ReadonlyFeature};
use crate::features::health_cloud;

impl UbaaClient {
    /// 读取最新的体测年份及所选年份的成绩。
    ///
    /// # Errors
    /// 所选路线、业务认证或页面结构不可用时返回带路线的错误。
    pub async fn health_cloud_page(&mut self, year: Option<&str>) -> RoutedResult<HealthCloudPage> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::HealthCloud))?;
        let (route, result) = crate::facade::routing::read_with_fallback!(
            self,
            route,
            health_cloud::get(self.runtime_for(route.mode), year).await
        );
        self.finish_routed(route, result)
    }
}
