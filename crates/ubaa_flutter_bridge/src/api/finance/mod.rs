//! 财务收入和离线快照的类型化桥接。
#![allow(clippy::missing_errors_doc)]
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use ubaa_core::facade as core;
#[derive(Clone)]
pub struct BridgeFinanceIncome {
    pub id: String,
    pub project: Option<String>,
    pub description: Option<String>,
    pub amount_cents: Option<i64>,
    pub tax_cents: Option<i64>,
    pub paid_cents: Option<i64>,
    pub tax_rate: Option<String>,
    pub recorded_date: Option<String>,
    pub year: Option<String>,
    pub month: Option<String>,
}
impl From<core::FinanceIncome> for BridgeFinanceIncome {
    fn from(v: core::FinanceIncome) -> Self {
        Self {
            id: v.id,
            project: v.project,
            description: v.description,
            amount_cents: v.amount_cents,
            tax_cents: v.tax_cents,
            paid_cents: v.paid_cents,
            tax_rate: v.tax_rate,
            recorded_date: v.recorded_date,
            year: v.year,
            month: v.month,
        }
    }
}
#[derive(Clone)]
pub struct BridgeFinanceIncomes {
    pub entries: Vec<BridgeFinanceIncome>,
    pub total: u32,
}
impl From<core::FinanceIncomes> for BridgeFinanceIncomes {
    fn from(v: core::FinanceIncomes) -> Self {
        Self {
            entries: v.entries.into_iter().map(Into::into).collect(),
            total: v.total,
        }
    }
}
pub struct BridgeFinanceResult {
    pub data: BridgeFinanceIncomes,
    pub route: BridgeRouteDecision,
}
pub struct BridgeFinanceRefresh {
    pub data: BridgeFinanceIncomes,
    pub route: BridgeRouteDecision,
    pub fetched_at: i64,
    pub saved_for_offline: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
pub struct BridgeCachedFinance {
    pub data: BridgeFinanceIncomes,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
}
impl BridgeClient {
    pub async fn finance_incomes(&self) -> Result<BridgeFinanceResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .finance_incomes()
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeFinanceResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
    pub async fn finance_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeFinanceRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .refresh_cached_finance(&cache.cache)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeFinanceRefresh {
                data: value.result.data.into(),
                route: map_route(value.result.resolution),
                fetched_at: value.result.fetched_at,
                saved_for_offline: value.result.save_error.is_none() && value.publication.is_some(),
                save_error: value.result.save_error.map(Into::into),
            })
        })
        .await
    }
}
impl BridgeOfflineCache {
    pub async fn read_finance(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedFinance>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_finance(route.into())
                .map_err(cache_error)?
                .map(|v| {
                    let core::CachePayload::FinanceIncomes(data) = v.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedFinance {
                        data: data.into(),
                        source_route: v.scope.route.into(),
                        fetched_at: v.fetched_at,
                    })
                })
                .transpose()
        })
        .await
    }
}
