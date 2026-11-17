//! 普通缓存刷新的账号检查、失败记录和发布收尾。
use super::{OfflineCache, OfflineReadError, OfflineRefresh, begin_refresh};
use crate::cache::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheRecord, CacheResult, CacheScope, SharedReadRecovery,
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

pub(in crate::facade) struct SharedProjection<T> {
    pub(in crate::facade) encode: fn(&T) -> CachePayload,
    pub(in crate::facade) decode: fn(CachePayload) -> CacheResult<T>,
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
        &mut self,
        result: RoutedResult<T>,
    ) -> Result<T, OfflineReadError> {
        result
            .map(|result| {
                self.resolution = result.resolution;
                self.scope.route = result.resolution.mode;
                if let Some(ticket) = &mut self.ticket {
                    ticket.set_source_route(result.resolution.mode);
                }
                result.data
            })
            .map_err(|error| {
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
        payload: fn(&T) -> CachePayload,
    ) -> Result<CachedRefresh<T>, OfflineReadError> {
        self.finish_projected(data, complete, payload, None)
    }

    /// 仅显式接入的只读查询可用较新结果替换本次在线结果。
    pub(in crate::facade) fn finish_shared<T>(
        self,
        data: T,
        complete: bool,
        payload: fn(&T) -> CachePayload,
        from_cache: fn(CachePayload) -> CacheResult<T>,
    ) -> Result<CachedRefresh<T>, OfflineReadError> {
        self.finish_projected(
            data,
            complete,
            payload,
            Some(SharedProjection {
                encode: payload,
                decode: from_cache,
            }),
        )
    }

    fn finish_projected<T>(
        self,
        data: T,
        complete: bool,
        payload: fn(&T) -> CachePayload,
        shared: Option<SharedProjection<T>>,
    ) -> Result<CachedRefresh<T>, OfflineReadError> {
        let cache = self.cache;
        self.finish_with(
            data,
            complete,
            chrono::Utc::now().timestamp(),
            |ticket, data, now| {
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
            },
            shared,
        )
    }

    pub(in crate::facade) fn finish_with<T>(
        mut self,
        mut data: T,
        mut complete: bool,
        mut fetched_at: i64,
        mut publish: impl FnMut(
            &CacheReadTicket,
            &T,
            i64,
        ) -> CacheResult<(CacheScope, CachePublication)>,
        shared: Option<SharedProjection<T>>,
    ) -> Result<CachedRefresh<T>, OfflineReadError> {
        let mut publication = None;
        if let Some(ticket) = self.ticket.take() {
            let mut saved = publish(&ticket, &data, fetched_at);
            let mut recovered: Option<CacheRecord> = None;
            if saved == Err(CacheError::Superseded)
                && let Some(shared) = shared
            {
                let recover = |ticket, retry| {
                    self.cache
                        .repository(|repo| repo.recover_shared_read(ticket, retry))
                        .map_err(OfflineReadError::Cache)
                };
                match recover(&ticket, true)? {
                    SharedReadRecovery::Reuse(record) => {
                        publication = Some(CachePublication::Stored);
                        recovered = Some(record);
                    }
                    SharedReadRecovery::Retry(next) => {
                        saved = publish(&next, &data, fetched_at);
                        if saved == Err(CacheError::Superseded) {
                            recovered = match recover(&next, false)? {
                                SharedReadRecovery::Reuse(record) => Some(record),
                                SharedReadRecovery::Superseded(record) => record,
                                SharedReadRecovery::Retry(_) => unreachable!("本次不允许补发票据"),
                            };
                            self.save_error = Some(CacheError::Superseded);
                        } else if saved.is_err() {
                            self.cache.failure(&next, fetched_at);
                        }
                    }
                    SharedReadRecovery::Superseded(record) => {
                        recovered = record;
                        self.save_error = Some(CacheError::Superseded);
                    }
                }
                if let Some(record) = recovered {
                    self.resolution.mode = record.scope.route;
                    self.resolution.diagnostic.mode = record.scope.route;
                    self.scope = record.scope;
                    fetched_at = record.fetched_at;
                    complete = record.completeness == CacheCompleteness::Complete;
                    publication = publication.or(Some(CachePublication::Preserved));
                    data = (shared.decode)(record.payload).map_err(OfflineReadError::Cache)?;
                } else if self.save_error == Some(CacheError::Superseded) {
                    // 没有旧内容时仍展示这次已取得的数据，但撤销操作资格。
                    data =
                        (shared.decode)((shared.encode)(&data)).map_err(OfflineReadError::Cache)?;
                }
            } else if !matches!(
                saved,
                Ok(_) | Err(CacheError::Inactive | CacheError::Superseded)
            ) {
                self.cache.failure(&ticket, fetched_at);
            }
            if publication.is_none() {
                match saved {
                    Ok((scope, value)) => {
                        self.scope = scope;
                        publication = Some(value);
                    }
                    Err(error @ (CacheError::Inactive | CacheError::Superseded))
                        if self.save_error != Some(CacheError::Superseded) =>
                    {
                        return Err(OfflineReadError::Cache(error));
                    }
                    Err(error) => self.save_error = Some(error),
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
