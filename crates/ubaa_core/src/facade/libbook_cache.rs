//! 图书馆精确查询持久化；展示状态不恢复预约或取消资格。
use super::{
    CachePayload, CacheQuery, CacheScope, ConnectionMode, LibBookArea, LibBookAreaDetail,
    LibBookBookingsPage, LibBookLibrary, LibBookSeat, OfflineCache, OfflineReadError,
    ReadonlyFeature, UbaaClient,
};
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LibBookCacheQuery {
    Libraries {
        day: String,
    },
    Areas {
        premises_id: String,
        storey_id: Option<String>,
        day: String,
    },
    AreaDetail {
        area_id: String,
    },
    Seats {
        area_id: String,
        day: String,
        start_time: String,
        end_time: String,
    },
    Bookings {
        page: i32,
        limit: i32,
    },
}
impl LibBookCacheQuery {
    /// 原样保存完整请求，不推断日期、时段或下一页。
    #[must_use]
    pub fn cache_query(&self) -> CacheQuery {
        match self {
            Self::Libraries { day } => CacheQuery::LibBookLibraries { day: day.clone() },
            Self::Areas {
                premises_id,
                storey_id,
                day,
            } => CacheQuery::LibBookAreas {
                premises_id: premises_id.clone(),
                storey_id: storey_id.clone(),
                day: day.clone(),
            },
            Self::AreaDetail { area_id } => CacheQuery::LibBookAreaDetail {
                area_id: area_id.clone(),
            },
            Self::Seats {
                area_id,
                day,
                start_time,
                end_time,
            } => CacheQuery::LibBookSeats {
                area_id: area_id.clone(),
                day: day.clone(),
                start_time: start_time.clone(),
                end_time: end_time.clone(),
            },
            Self::Bookings { page, limit } => CacheQuery::LibBookBookings {
                page: *page,
                limit: *limit,
            },
        }
    }
}
/// 在线资格保持原合同，落盘另经只读白名单。
#[derive(Clone, Debug)]
pub enum LibBookReadData {
    Libraries(Vec<LibBookLibrary>),
    Areas(Vec<LibBookArea>),
    AreaDetail(LibBookAreaDetail),
    Seats(Vec<LibBookSeat>),
    Bookings(LibBookBookingsPage),
}
impl LibBookReadData {
    fn readonly_payload(&self) -> CachePayload {
        match self {
            Self::Libraries(v) => CachePayload::LibBookLibraries(v.clone()),
            Self::Areas(v) => CachePayload::LibBookAreas(v.clone()),
            Self::AreaDetail(v) => CachePayload::LibBookAreaDetail(v.clone()),
            Self::Seats(v) => {
                CachePayload::LibBookSeats(v.iter().cloned().map(Into::into).collect())
            }
            Self::Bookings(v) => CachePayload::LibBookBookings(v.clone().into()),
        }
    }
}
pub type LibBookRefresh = super::CachedRefresh<LibBookReadData>;
impl OfflineCache {
    /// 读取明确查询范围的缓存，不获取网络锁或恢复学校写资格。
    ///
    /// # Errors
    /// 参数、账号栅栏或存储错误按本地缓存分类返回。
    pub fn read_libbook(
        &self,
        route: ConnectionMode,
        query: &LibBookCacheQuery,
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
    pub async fn refresh_cached_libbook(
        &mut self,
        cache: &OfflineCache,
        query: LibBookCacheQuery,
    ) -> Result<LibBookRefresh, OfflineReadError> {
        let refresh = self
            .prepare_cached_refresh(cache, ReadonlyFeature::LibBook, query.cache_query())
            .await?;
        let resolution = refresh.resolution;
        let runtime = self.runtime_for(resolution.mode);
        let read = query.read(runtime).await;
        let (data, complete) = refresh.read_result(self.finish_routed(resolution, read))?;
        refresh.finish(data, complete, LibBookReadData::readonly_payload)
    }
}

impl LibBookCacheQuery {
    async fn read(
        self,
        runtime: &mut crate::runtime::ClientRuntime,
    ) -> crate::error::Result<(LibBookReadData, bool)> {
        use crate::features::libbook;
        match self {
            Self::Libraries { day } => libbook::get_libraries_observed(runtime, &day)
                .await
                .map(|(v, complete)| (LibBookReadData::Libraries(v), complete)),
            Self::Areas {
                premises_id,
                storey_id,
                day,
            } => libbook::get_areas_observed(runtime, &premises_id, storey_id.as_deref(), &day)
                .await
                .map(|(v, complete)| (LibBookReadData::Areas(v), complete)),
            Self::AreaDetail { area_id } => {
                libbook::get_area_detail_with_schedule_observed(runtime, &area_id)
                    .await
                    .map(|(v, observed)| {
                        let complete = observed && v.id == area_id;
                        (LibBookReadData::AreaDetail(v), complete)
                    })
            }
            Self::Seats {
                area_id,
                day,
                start_time,
                end_time,
            } => libbook::get_seats_observed(runtime, &area_id, &day, &start_time, &end_time)
                .await
                .map(|(v, complete)| (LibBookReadData::Seats(v), complete)),
            Self::Bookings { page, limit } => libbook::get_bookings_observed(runtime, page, limit)
                .await
                .map(|(v, observed)| {
                    let complete = observed && v.page == page && v.limit == limit;
                    (LibBookReadData::Bookings(v), complete)
                }),
        }
    }
}
