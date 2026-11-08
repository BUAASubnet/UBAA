//! 财务只读查询与账号加密快照。
#![allow(clippy::missing_errors_doc)]
use super::{CachedRefresh, OfflineCache, OfflineReadError, RoutedResult, UbaaClient};
use crate::cache::{CachePayload, CacheQuery, CacheScope};
use crate::domain::{ConnectionMode, FinanceIncomes, ReadonlyFeature};
impl UbaaClient {
    pub async fn finance_incomes(&mut self) -> RoutedResult<FinanceIncomes> {
        let route =
            self.resolve_operation(super::types::Operation::Feature(ReadonlyFeature::Finance))?;
        let (route, result) = crate::facade::routing::read_with_fallback!(
            self,
            route,
            crate::features::finance::incomes(self.runtime_for(route.mode)).await
        );
        self.finish_routed(route, result)
    }
    pub async fn refresh_cached_finance(
        &mut self,
        cache: &OfflineCache,
    ) -> Result<CachedRefresh<FinanceIncomes>, OfflineReadError> {
        let mut refresh = self
            .prepare_cached_refresh(cache, ReadonlyFeature::Finance, CacheQuery::FinanceIncomes)
            .await?;
        let data = refresh.read_result(self.finance_incomes().await)?;
        refresh.finish(data, true, |v| CachePayload::FinanceIncomes(v.clone()))
    }
}
impl OfflineCache {
    pub fn read_finance(
        &self,
        route: ConnectionMode,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: CacheQuery::FinanceIncomes,
            },
            chrono::Utc::now().timestamp(),
        )
    }
}
