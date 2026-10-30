//! 首页待办的在线内容与只读持久投影分离，部分失败不覆盖旧完整集合。
use super::{
    CacheCompleteness, CachePayload, CachePublication, CacheQuery, CacheScope, ConnectionMode,
    OfflineCache, OfflineReadError, ReadonlyFeature, SigninClass, SpocAssignmentDetail,
    SpocAssignments, UbaaClient, YgdkOverview,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HomeQuery {
    SigninToday,
    SpocAssignments,
    SpocDetail { assignment_id: String },
    YgdkOverview,
}
mod spoc;
mod spoc_scan;
mod ygdk;
pub use spoc_scan::{
    SpocDetailScan, SpocDetailScanBatch, SpocScan, SpocScanBatch, SpocScanCancellation,
};

impl HomeQuery {
    fn cache_query(&self, now: i64) -> super::CacheResult<CacheQuery> {
        Ok(match self {
            Self::SigninToday => CacheQuery::SigninToday {
                date: crate::time::shanghai_compact_date(std::time::SystemTime::now()),
            },
            Self::SpocAssignments => CacheQuery::SpocSelection,
            Self::SpocDetail { assignment_id } => CacheQuery::SpocDetail {
                assignment_id: assignment_id.clone(),
            },
            Self::YgdkOverview => ygdk::selection_scope(ConnectionMode::Direct, now)?.query,
        })
    }
    const fn feature(&self) -> ReadonlyFeature {
        match self {
            Self::SigninToday => ReadonlyFeature::Signin,
            Self::SpocAssignments | Self::SpocDetail { .. } => ReadonlyFeature::Spoc,
            Self::YgdkOverview => ReadonlyFeature::Ygdk,
        }
    }
}
/// 仅本次在线结果保留实时操作信息；不可直接作为持久载荷。
#[derive(Clone, Debug)]
pub enum HomeReadData {
    Signin(Vec<SigninClass>),
    SpocAssignments(SpocAssignments),
    SpocDetail(SpocAssignmentDetail),
    YgdkOverview(YgdkOverview),
}
impl HomeReadData {
    fn readonly_payload(&self) -> CachePayload {
        match self {
            Self::Signin(classes) => {
                CachePayload::SigninToday(classes.iter().cloned().map(Into::into).collect())
            }
            Self::SpocAssignments(value) => CachePayload::SpocAssignments(value.clone()),
            Self::SpocDetail(value) => CachePayload::SpocDetail(Box::new(value.clone())),
            Self::YgdkOverview(value) => CachePayload::YgdkOverview(value.clone().into()),
        }
    }
}
pub type HomeRefresh = super::CachedRefresh<HomeReadData>;
impl OfflineCache {
    /// 读取当前日期/视图的精确缓存，不获取网络锁或恢复学校写资格。
    ///
    /// # Errors
    /// 参数、账号栅栏或存储错误按本地缓存分类返回。
    pub fn read_home(
        &self,
        route: ConnectionMode,
        query: &HomeQuery,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        let now = chrono::Utc::now().timestamp();
        if matches!(query, HomeQuery::SpocAssignments) {
            return spoc::read(self, route, now);
        }
        if matches!(query, HomeQuery::YgdkOverview) {
            return ygdk::read(self, route, now);
        }
        self.read(
            &CacheScope {
                route,
                query: query.cache_query(now)?,
            },
            now,
        )
    }
}
impl UbaaClient {
    /// 身份核对后沿原协议读取，日期只捕获一次，部分结果不替换旧完整集合。
    ///
    /// # Errors
    /// 原认证/业务失败保持分类；账号不符、退出和请求被替代不可降级。
    pub async fn refresh_cached_home(
        &mut self,
        cache: &OfflineCache,
        query: HomeQuery,
    ) -> Result<HomeRefresh, OfflineReadError> {
        if matches!(query, HomeQuery::SpocAssignments) {
            return self.refresh_spoc_scan(cache).await;
        }
        if let HomeQuery::SpocDetail { assignment_id } = &query {
            return self.refresh_spoc_detail_scan(cache, assignment_id).await;
        }
        let began_at = chrono::Utc::now().timestamp();
        let cache_query = query
            .cache_query(began_at)
            .map_err(OfflineReadError::Cache)?;
        let refresh = self
            .prepare_cached_refresh(cache, query.feature(), cache_query.clone())
            .await?;
        let resolution = refresh.resolution;
        let runtime = self.runtime_for(resolution.mode);
        let read = if let CacheQuery::SigninToday { date } = cache_query {
            crate::features::signin::get_today_for_date(runtime, &date)
                .await
                .map(|data| (HomeReadData::Signin(data), true))
        } else {
            crate::features::ygdk::get_overview_observed(runtime)
                .await
                .map(|(data, complete)| (HomeReadData::YgdkOverview(data), complete))
        };
        let (data, mut complete) = refresh.read_result(self.finish_routed(resolution, read))?;
        if let HomeReadData::YgdkOverview(value) = &data {
            complete &= value.summary.term_id.is_some_and(|id| id > 0);
        }
        refresh.finish_with(data, complete, |ticket, data, fetched_at| {
            publish_home(cache, ticket, data, began_at, fetched_at, complete)
        })
    }
}

#[cfg(test)]
mod tests;

fn publish_home(
    cache: &OfflineCache,
    ticket: &super::CacheReadTicket,
    data: &HomeReadData,
    began_at: i64,
    fetched_at: i64,
    complete: bool,
) -> super::CacheResult<(CacheScope, CachePublication)> {
    if let HomeReadData::YgdkOverview(value) = data {
        return ygdk::publish(
            cache,
            ticket,
            &value.clone().into(),
            began_at,
            fetched_at,
            complete,
        );
    }
    cache.repository(|repository| {
        repository
            .publish(
                ticket,
                data.readonly_payload(),
                fetched_at,
                if complete {
                    CacheCompleteness::Complete
                } else {
                    CacheCompleteness::Partial
                },
            )
            .map(|publication| (ticket.scope().clone(), publication))
    })
}
