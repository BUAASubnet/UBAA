//! 普通缓存刷新的账号检查、失败记录和发布收尾。
use super::{OfflineCache, OfflineReadError, OfflineRefresh, begin_refresh};
use crate::cache::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheResult, CacheScope,
};
use crate::domain::{ConnectionMode, ReadonlyFeature};
use crate::facade::{RouteResolution, RoutedResult, UbaaClient};

/// 在线读取与本地发布分别报告；部分结果可以保留此前的完整记录。
#[derive(Debug)]
pub struct CachedRefresh<T> {
    pub result: OfflineRefresh<T>,
    pub complete: bool,
    pub publication: Option<CachePublication>,
}

pub(in crate::facade) struct CacheRefresh<'cache> {
    cache: &'cache OfflineCache,
    pub(in crate::facade) resolution: RouteResolution,
    scope: CacheScope,
    ticket: Option<CacheReadTicket>,
    save_error: Option<CacheError>,
}

impl UbaaClient {
    pub(in crate::facade) async fn prepare_cached_refresh<'cache>(
        &mut self,
        cache: &'cache OfflineCache,
        feature: ReadonlyFeature,
        query: CacheQuery,
    ) -> Result<CacheRefresh<'cache>, OfflineReadError> {
        cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        CacheScope {
            route: ConnectionMode::Direct,
            query: query.clone(),
        }
        .validate()
        .map_err(OfflineReadError::Cache)?;
        let authenticated = self
            .recover_required_session(feature)
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = authenticated.resolution;
        if !cache.matches(&authenticated.data.user) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.deactivate().err(),
            });
        }
        let scope = CacheScope {
            route: resolution.mode,
            query,
        };
        let (ticket, save_error) = begin_refresh(cache, scope.clone())?;
        Ok(CacheRefresh {
            cache,
            resolution,
            scope,
            ticket,
            save_error,
        })
    }
}

impl CacheRefresh<'_> {
    pub(in crate::facade) fn read_result<T>(
        &self,
        result: RoutedResult<T>,
    ) -> Result<T, OfflineReadError> {
        result.map(|result| result.data).map_err(|error| {
            if let Some(ticket) = &self.ticket {
                self.cache.failure(ticket, chrono::Utc::now().timestamp());
            }
            OfflineReadError::Read(error)
        })
    }

    pub(in crate::facade) fn finish<T>(
        self,
        data: T,
        complete: bool,
        payload: impl FnOnce(&T) -> CachePayload,
    ) -> Result<CachedRefresh<T>, OfflineReadError> {
        let cache = self.cache;
        self.finish_with(data, complete, |ticket, data, now| {
            cache
                .repository(|repository| {
                    repository.publish(
                        ticket,
                        payload(data),
                        now,
                        if complete {
                            CacheCompleteness::Complete
                        } else {
                            CacheCompleteness::Partial
                        },
                    )
                })
                .map(|publication| (ticket.scope().clone(), publication))
        })
    }

    pub(in crate::facade) fn finish_with<T>(
        mut self,
        data: T,
        complete: bool,
        publish: impl FnOnce(&CacheReadTicket, &T, i64) -> CacheResult<(CacheScope, CachePublication)>,
    ) -> Result<CachedRefresh<T>, OfflineReadError> {
        let fetched_at = chrono::Utc::now().timestamp();
        let mut publication = None;
        if let Some(ticket) = &self.ticket {
            match publish(ticket, &data, fetched_at) {
                Ok((scope, value)) => {
                    self.scope = scope;
                    publication = Some(value);
                }
                Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                    return Err(OfflineReadError::Cache(error));
                }
                Err(error) => {
                    self.save_error = Some(error);
                    self.cache.failure(ticket, fetched_at);
                }
            }
        }
        Ok(CachedRefresh {
            result: OfflineRefresh {
                data,
                resolution: self.resolution,
                scope: self.scope,
                fetched_at,
                save_error: self.save_error,
            },
            complete,
            publication,
        })
    }
}
