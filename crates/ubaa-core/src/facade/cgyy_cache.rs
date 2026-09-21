//! 场馆只读持久范围不恢复学校写资格，静态用途回退不替换旧动态结果。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheScope,
    CgyyDayInfo, CgyyOrder, CgyyOrdersPage, CgyyPurposeSource, CgyyPurposeTypes, CgyyVenueSite,
    ConnectionMode, OfflineCache, OfflineReadError, OfflineRefresh, ReadonlyFeature, UbaaClient,
};
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CgyyCacheQuery {
    Sites,
    Purposes,
    Day { site_id: i32, date: String },
    Orders { page: i32, size: i32 },
    Detail { order_id: i32 },
}
impl CgyyCacheQuery {
    /// 请求范围原样入键，不补当前日期、不折叠分页。
    #[must_use]
    pub fn cache_query(&self) -> CacheQuery {
        match self {
            Self::Sites => CacheQuery::CgyySites,
            Self::Purposes => CacheQuery::CgyyPurposes,
            Self::Day { site_id, date } => CacheQuery::CgyyDay {
                site_id: *site_id,
                date: date.clone(),
            },
            Self::Orders { page, size } => CacheQuery::CgyyOrders {
                page: *page,
                size: *size,
            },
            Self::Detail { order_id } => CacheQuery::CgyyDetail {
                order_id: *order_id,
            },
        }
    }
}
/// 在线字段保留既有资格；落盘必须经过只读白名单。
#[derive(Clone, Debug)]
pub enum CgyyReadData {
    Sites(Vec<CgyyVenueSite>),
    Purposes(CgyyPurposeTypes),
    Day(CgyyDayInfo),
    Orders(CgyyOrdersPage),
    Detail(Box<CgyyOrder>),
}
impl CgyyReadData {
    fn readonly_payload(&self) -> CachePayload {
        match self {
            Self::Sites(v) => CachePayload::CgyySites(v.clone()),
            Self::Purposes(v) => CachePayload::CgyyPurposes(v.clone()),
            Self::Day(v) => CachePayload::CgyyDay(v.clone().into()),
            Self::Orders(v) => CachePayload::CgyyOrders(v.clone().into()),
            Self::Detail(v) => CachePayload::CgyyDetail(v.as_ref().clone().into()),
        }
    }
}
#[derive(Debug)]
pub struct CgyyRefresh {
    pub result: OfflineRefresh<CgyyReadData>,
    pub complete: bool,
    /// 本次 Stored 与保留此前记录的 Preserved 分开报告。
    pub publication: Option<CachePublication>,
}
impl OfflineCache {
    /// 读取明确查询范围的缓存，不获取网络锁或恢复学校写资格。
    ///
    /// # Errors
    /// 参数、账号栅栏或存储错误按本地缓存分类返回。
    pub fn read_cgyy(
        &self,
        route: ConnectionMode,
        query: &CgyyCacheQuery,
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
    /// 身份核对后沿原协议读取，使用明确查询日期，部分结果不替换旧完整集合。
    ///
    /// # Errors
    /// 原认证/业务失败保持分类；账号不符、退出和请求被替代不可降级。
    pub async fn refresh_cached_cgyy(
        &mut self,
        cache: &OfflineCache,
        query: CgyyCacheQuery,
    ) -> Result<CgyyRefresh, OfflineReadError> {
        let cache_query = query.cache_query();
        CacheScope {
            route: ConnectionMode::Direct,
            query: cache_query.clone(),
        }
        .validate()
        .map_err(OfflineReadError::Cache)?;
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Cgyy)
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
        let read = query.read(runtime).await;
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
        Ok(CgyyRefresh {
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

impl CgyyCacheQuery {
    async fn read(
        self,
        runtime: &mut crate::runtime::ClientRuntime,
    ) -> crate::error::Result<(CgyyReadData, bool)> {
        match self {
            CgyyCacheQuery::Sites => crate::features::cgyy::get_sites(runtime)
                .await
                .map(|data| (CgyyReadData::Sites(data), true)),
            CgyyCacheQuery::Purposes => {
                crate::features::cgyy::get_purpose_types_with_source(runtime)
                    .await
                    .map(|(items, source)| {
                        (
                            CgyyReadData::Purposes(CgyyPurposeTypes { items, source }),
                            source == CgyyPurposeSource::Upstream,
                        )
                    })
            }
            CgyyCacheQuery::Day { site_id, date } => {
                crate::features::cgyy::get_day_info(runtime, site_id, &date)
                    .await
                    .map(|data| {
                        let complete =
                            data.venue_site_id == site_id && data.reservation_date == date;
                        (CgyyReadData::Day(data), complete)
                    })
            }
            CgyyCacheQuery::Orders { page, size } => {
                crate::features::cgyy::get_orders(runtime, page, size)
                    .await
                    .map(|data| (CgyyReadData::Orders(data), true))
            }
            CgyyCacheQuery::Detail { order_id } => {
                crate::features::cgyy::get_order_detail(runtime, order_id)
                    .await
                    .map(|data| {
                        let complete = data.id == order_id;
                        (CgyyReadData::Detail(Box::new(data)), complete)
                    })
            }
        }
    }
}
