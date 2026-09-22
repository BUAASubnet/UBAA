//! 首页待办的在线内容与只读持久投影分离，部分失败不覆盖旧完整集合。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheScope,
    ConnectionMode, OfflineCache, OfflineReadError, OfflineRefresh, ReadonlyFeature, SigninClass,
    SpocAssignmentDetail, SpocAssignments, UbaaClient, YgdkOverview,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HomeQuery {
    SigninToday,
    SpocAssignments,
    SpocDetail { assignment_id: String },
    YgdkOverview,
}
impl HomeQuery {
    fn cache_query(&self) -> CacheQuery {
        match self {
            Self::SigninToday => CacheQuery::SigninToday {
                date: crate::features::signin::shanghai_date(),
            },
            Self::SpocAssignments => CacheQuery::SpocAssignments,
            Self::SpocDetail { assignment_id } => CacheQuery::SpocDetail {
                assignment_id: assignment_id.clone(),
            },
            Self::YgdkOverview => CacheQuery::YgdkOverview,
        }
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
#[derive(Debug)]
pub struct HomeRefresh {
    pub result: OfflineRefresh<HomeReadData>,
    pub complete: bool,
    /// Preserved 表示保留此前完整记录，不能声称本次部分内容已全部保存。
    pub publication: Option<CachePublication>,
}
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
    /// 身份核对后沿原协议读取，日期只捕获一次，部分结果不替换旧完整集合。
    ///
    /// # Errors
    /// 原认证/业务失败保持分类；账号不符、退出和请求被替代不可降级。
    pub async fn refresh_cached_home(
        &mut self,
        cache: &OfflineCache,
        query: HomeQuery,
    ) -> Result<HomeRefresh, OfflineReadError> {
        cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        let cache_query = validated_home_query(&query)?;
        let authenticated = self
            .recover_required_session(query.feature())
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
            query: cache_query,
        };
        let (ticket, mut save_error) = match cache.begin(scope.clone()) {
            Ok(ticket) => (Some(ticket), None),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                return Err(OfflineReadError::Cache(error));
            }
            Err(error) => (None, Some(error)),
        };
        let runtime = self.runtime_for(resolution.mode);
        let read = match query {
            HomeQuery::SigninToday => {
                let CacheQuery::SigninToday { date } = &scope.query else {
                    unreachable!()
                };
                crate::features::signin::get_today_for_date(runtime, date)
                    .await
                    .map(|data| (HomeReadData::Signin(data), true))
            }
            HomeQuery::SpocAssignments => crate::features::spoc::get_assignments_observed(runtime)
                .await
                .map(|(data, complete)| (HomeReadData::SpocAssignments(data.result), complete)),
            HomeQuery::SpocDetail { assignment_id } => {
                crate::features::spoc::get_assignment_detail_observed(runtime, &assignment_id)
                    .await
                    .map(|(data, complete)| (HomeReadData::SpocDetail(data), complete))
            }
            HomeQuery::YgdkOverview => crate::features::ygdk::get_overview_observed(runtime)
                .await
                .map(|(data, complete)| (HomeReadData::YgdkOverview(data), complete)),
        };
        let fetched_at = chrono::Utc::now().timestamp();
        let read = match self.finish_routed(resolution, read) {
            Ok(read) => read,
            Err(error) => {
                if let Some(ticket) = &ticket {
                    cache.failure(ticket, fetched_at);
                }
                return Err(OfflineReadError::Read(error));
            }
        };
        let (data, complete) = read.data;
        let mut publication = None;
        if let Some(ticket) = &ticket {
            let saved = cache.repository(|repository| {
                repository.publish(
                    ticket,
                    data.readonly_payload(),
                    fetched_at,
                    if complete {
                        CacheCompleteness::Complete
                    } else {
                        CacheCompleteness::Partial
                    },
                )
            });
            match saved {
                Ok(value) => publication = Some(value),
                Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                    return Err(OfflineReadError::Cache(error));
                }
                Err(error) => {
                    save_error = Some(error);
                    cache.failure(ticket, fetched_at);
                }
            }
        }
        Ok(HomeRefresh {
            result: OfflineRefresh {
                data,
                resolution,
                scope,
                fetched_at,
                save_error,
            },
            complete,
            publication,
        })
    }
}

fn validated_home_query(query: &HomeQuery) -> Result<CacheQuery, OfflineReadError> {
    let cached = query.cache_query();
    CacheScope {
        route: ConnectionMode::Direct,
        query: cached.clone(),
    }
    .validate()
    .map_err(OfflineReadError::Cache)?;
    Ok(cached)
}
