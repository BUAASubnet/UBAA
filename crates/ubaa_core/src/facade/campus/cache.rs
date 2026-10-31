//! “我的”页的门户资料、账户指标与流量快照；先读本地，再在线刷新。
use super::{
    CachePayload, CacheQuery, CacheScope, CachedCampusMetrics, CampusMetrics, ConnectionMode,
    NetworkUsage, OfflineCache, OfflineReadError, PortalProfile, ReadonlyFeature, UbaaClient,
};

/// 三个固定范围，按实际路线分别保存。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CampusCacheQuery {
    Profile,
    Metrics,
    NetworkUsage,
}
impl CampusCacheQuery {
    #[must_use]
    pub fn cache_query(self) -> CacheQuery {
        match self {
            Self::Profile => CacheQuery::CampusProfile,
            Self::Metrics => CacheQuery::CampusMetrics,
            Self::NetworkUsage => CacheQuery::NetworkUsage,
        }
    }
    fn feature(self) -> ReadonlyFeature {
        match self {
            Self::Profile | Self::Metrics => ReadonlyFeature::Portal,
            Self::NetworkUsage => ReadonlyFeature::Network,
        }
    }
}

/// 在线结果；指标另附与旧快照合并后的逐项最近成功值。
#[derive(Clone, Debug)]
pub enum CampusReadData {
    Profile(PortalProfile),
    Metrics(Box<CampusMetricsRead>),
    NetworkUsage(NetworkUsage),
}
/// 本次在线指标与合并后的逐项最近成功值。
#[derive(Clone, Debug)]
pub struct CampusMetricsRead {
    pub online: CampusMetrics,
    pub snapshot: CachedCampusMetrics,
}
pub type CampusRefresh = super::CachedRefresh<CampusReadData>;

impl OfflineCache {
    /// 读取本地快照，不获取网络锁。
    ///
    /// # Errors
    /// 账号栅栏或存储错误按本地缓存分类返回。
    pub fn read_campus(
        &self,
        route: ConnectionMode,
        query: CampusCacheQuery,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: query.cache_query(),
            },
            chrono::Utc::now().timestamp(),
        )
    }
}

impl UbaaClient {
    /// 身份核对后在线读取并保存快照；保存失败不影响在线结果。
    ///
    /// # Errors
    /// 原认证/业务失败保持分类；账号不符、退出和请求被替代不可降级。
    pub async fn refresh_cached_campus(
        &mut self,
        cache: &OfflineCache,
        query: CampusCacheQuery,
    ) -> Result<CampusRefresh, OfflineReadError> {
        let refresh = self
            .prepare_cached_refresh(cache, query.feature(), query.cache_query())
            .await?;
        let resolution = refresh.resolution;
        let runtime = self.runtime_for(resolution.mode);
        match query {
            CampusCacheQuery::Profile => {
                let read = crate::features::campus::get_profile(runtime).await;
                let data = refresh.read_result(self.finish_routed(resolution, read))?;
                refresh.finish(CampusReadData::Profile(data), true, |data| match data {
                    CampusReadData::Profile(value) => CachePayload::CampusProfile(value.clone()),
                    _ => unreachable!("门户资料刷新只产生资料结果"),
                })
            }
            CampusCacheQuery::NetworkUsage => {
                let read = crate::features::campus::get_usage(runtime).await;
                let data = refresh.read_result(self.finish_routed(resolution, read))?;
                refresh.finish(
                    CampusReadData::NetworkUsage(data),
                    true,
                    |data| match data {
                        CampusReadData::NetworkUsage(value) => {
                            CachePayload::NetworkUsage(value.clone())
                        }
                        _ => unreachable!("流量刷新只产生流量结果"),
                    },
                )
            }
            CampusCacheQuery::Metrics => {
                let read = crate::features::campus::get_metrics(runtime).await;
                let online = refresh.read_result(self.finish_routed(resolution, read))?;
                // 旧快照读取失败时按无旧值处理，只影响逐项回退，不阻断在线结果。
                let previous = cache
                    .read_campus(resolution.mode, CampusCacheQuery::Metrics)
                    .ok()
                    .flatten()
                    .and_then(|record| match record.payload {
                        CachePayload::CampusMetrics(value) => Some(value),
                        _ => None,
                    });
                let snapshot = CachedCampusMetrics::merge(previous.as_ref(), &online);
                let complete = snapshot.is_complete();
                refresh.finish(
                    CampusReadData::Metrics(Box::new(CampusMetricsRead { online, snapshot })),
                    complete,
                    |data| match data {
                        CampusReadData::Metrics(read) => {
                            CachePayload::CampusMetrics(read.snapshot.clone())
                        }
                        _ => unreachable!("指标刷新只产生指标结果"),
                    },
                )
            }
        }
    }
}
