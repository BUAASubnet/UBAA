//! iHome 宿主入口，所有协议与凭据留在 Core。
#![allow(clippy::missing_errors_doc)]
use super::types::Operation;
use super::{RoutedResult, UbaaClient};
use crate::domain::{
    ConnectionMode, IhomeAppeal, IhomeConfig, IhomeNotice, IhomePage, IhomeQuery, IhomeReaction,
    ReadonlyFeature,
};
use crate::features::ihome;
impl UbaaClient {
    pub async fn ihome_page(&mut self, query: IhomeQuery) -> RoutedResult<IhomePage> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ihome))?;
        let result = ihome::get_page(self.runtime_for(route.mode), &query).await;
        self.finish_routed(route, result)
    }
    pub async fn ihome_detail(&mut self, id: i64, mine: bool) -> RoutedResult<IhomeAppeal> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ihome))?;
        let result = ihome::get_detail(self.runtime_for(route.mode), id, mine).await;
        self.finish_routed(route, result)
    }
    pub async fn ihome_config(&mut self) -> RoutedResult<IhomeConfig> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ihome))?;
        let result = ihome::get_config(self.runtime_for(route.mode)).await;
        self.finish_routed(route, result)
    }
    pub async fn ihome_notices(&mut self) -> RoutedResult<Vec<IhomeNotice>> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ihome))?;
        let result = ihome::get_notices(self.runtime_for(route.mode)).await;
        self.finish_routed(route, result)
    }
    pub async fn ihome_notice(&mut self, id: i64) -> RoutedResult<IhomeNotice> {
        let route = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ihome))?;
        let result = ihome::get_notice(self.runtime_for(route.mode), id).await;
        self.finish_routed(route, result)
    }
    /// 用户确认后固定路线，提交一次并回读目标状态；结果未知不重试。
    pub async fn ihome_set_reaction(
        &mut self,
        id: i64,
        reaction: IhomeReaction,
        enabled: bool,
        expected_route: ConnectionMode,
    ) -> RoutedResult<IhomeAppeal> {
        let route = self.resolve_write_route(ReadonlyFeature::Ihome, Some(expected_route))?;
        let runtime = self.runtime_for(route.mode);
        runtime.begin_non_idempotent_operation();
        let result = ihome::set_reaction(runtime, id, reaction, enabled).await;
        self.finish_routed_write(route, result)
    }
}
