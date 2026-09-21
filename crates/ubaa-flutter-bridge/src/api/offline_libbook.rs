//! 图书馆只读缓存采用公开字段白名单，不恢复学校写资格。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{
    BridgeLibBookArea, BridgeLibBookAreaDetail, BridgeLibBookBookingsPage, BridgeLibBookLibrary,
    BridgeLibBookSeat, map_libbook_area_detail, map_libbook_areas, map_libbook_bookings,
    map_libbook_libraries, map_libbook_seats,
};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookSeat {
    pub id: String,
    pub name: String,
    pub no: String,
    pub status: Option<i32>,
    pub status_name: String,
}
fn map_cached_libbook_seat(v: core::CachedLibBookSeat) -> BridgeCachedLibBookSeat {
    BridgeCachedLibBookSeat {
        id: v.id,
        name: v.name,
        no: v.no,
        status: v.status,
        status_name: v.status_name,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookBooking {
    pub id: String,
    pub name_merge: String,
    pub area_name: String,
    pub seat_no: String,
    pub day: String,
    pub begin_time: String,
    pub end_time: String,
    pub status: Option<i32>,
    pub status_name: String,
}
fn map_cached_libbook_booking(v: core::CachedLibBookBooking) -> BridgeCachedLibBookBooking {
    BridgeCachedLibBookBooking {
        id: v.id,
        name_merge: v.name_merge,
        area_name: v.area_name,
        seat_no: v.seat_no,
        day: v.day,
        begin_time: v.begin_time,
        end_time: v.end_time,
        status: v.status,
        status_name: v.status_name,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookBookingsPage {
    pub bookings: Vec<BridgeCachedLibBookBooking>,
    pub page: i32,
    pub limit: i32,
    pub total: i32,
}
fn map_cached_libbook_bookings_page(
    v: core::CachedLibBookBookingsPage,
) -> BridgeCachedLibBookBookingsPage {
    BridgeCachedLibBookBookingsPage {
        bookings: v
            .bookings
            .into_iter()
            .map(map_cached_libbook_booking)
            .collect(),
        page: v.page,
        limit: v.limit,
        total: v.total,
    }
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookRefreshState {
    pub fetched_at: i64,
    pub complete: bool,
    pub saved_for_offline: bool,
    pub preserved_previous: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
fn refresh_state(v: &core::LibBookRefresh) -> BridgeLibBookRefreshState {
    BridgeLibBookRefreshState {
        fetched_at: v.result.fetched_at,
        complete: v.complete,
        saved_for_offline: v.publication == Some(core::CachePublication::Stored),
        preserved_previous: v.publication == Some(core::CachePublication::Preserved),
        save_error: v.result.save_error.map(Into::into),
    }
}
impl BridgeClient {
    async fn refresh_libbook_record(
        &self,
        cache: &BridgeOfflineCache,
        query: core::LibBookCacheQuery,
    ) -> Result<core::LibBookRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_libbook(&cache.cache, query)
                .await
                .map_err(offline_read_error)
        })
        .await
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookLibrariesRecord {
    pub data: Vec<BridgeLibBookLibrary>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookLibrariesRefresh {
    pub data: Vec<BridgeLibBookLibrary>,
    pub route: BridgeRouteDecision,
    pub state: BridgeLibBookRefreshState,
}
impl BridgeOfflineCache {
    /// 本地读取不获取网络锁，也不授予学校操作资格。
    ///
    /// # Errors
    /// 账号关闭、损坏或参数无效返回稳定错误，缺记录返回 None。
    pub async fn read_libbook_libraries(
        &self,
        route: BridgeConnectionMode,
        day: String,
    ) -> Result<Option<BridgeCachedLibBookLibrariesRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_libbook(route.into(), &core::LibBookCacheQuery::Libraries { day })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::LibBookLibraries(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedLibBookLibrariesRecord {
                        data: map_libbook_libraries(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 沿原协议读取并保存只读投影，待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务分类、账号与退出屏障保持。
    pub async fn libbook_libraries_cached(
        &self,
        cache: &BridgeOfflineCache,
        day: String,
    ) -> Result<BridgeLibBookLibrariesRefresh, BridgeError> {
        let value = self
            .refresh_libbook_record(cache, core::LibBookCacheQuery::Libraries { day })
            .await?;
        let state = refresh_state(&value);
        let core::LibBookReadData::Libraries(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeLibBookLibrariesRefresh {
            data: map_libbook_libraries(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookAreasRecord {
    pub data: Vec<BridgeLibBookArea>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookAreasRefresh {
    pub data: Vec<BridgeLibBookArea>,
    pub route: BridgeRouteDecision,
    pub state: BridgeLibBookRefreshState,
}
impl BridgeOfflineCache {
    /// 本地读取不获取网络锁，也不授予学校操作资格。
    ///
    /// # Errors
    /// 账号关闭、损坏或参数无效返回稳定错误，缺记录返回 None。
    pub async fn read_libbook_areas(
        &self,
        route: BridgeConnectionMode,
        premises_id: String,
        storey_id: Option<String>,
        day: String,
    ) -> Result<Option<BridgeCachedLibBookAreasRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_libbook(
                    route.into(),
                    &core::LibBookCacheQuery::Areas {
                        premises_id,
                        storey_id,
                        day,
                    },
                )
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::LibBookAreas(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedLibBookAreasRecord {
                        data: map_libbook_areas(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 沿原协议读取并保存只读投影，待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务分类、账号与退出屏障保持。
    pub async fn libbook_areas_cached(
        &self,
        cache: &BridgeOfflineCache,
        premises_id: String,
        storey_id: Option<String>,
        day: String,
    ) -> Result<BridgeLibBookAreasRefresh, BridgeError> {
        let value = self
            .refresh_libbook_record(
                cache,
                core::LibBookCacheQuery::Areas {
                    premises_id,
                    storey_id,
                    day,
                },
            )
            .await?;
        let state = refresh_state(&value);
        let core::LibBookReadData::Areas(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeLibBookAreasRefresh {
            data: map_libbook_areas(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookAreaDetailRecord {
    pub data: BridgeLibBookAreaDetail,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookAreaDetailRefresh {
    pub data: BridgeLibBookAreaDetail,
    pub route: BridgeRouteDecision,
    pub state: BridgeLibBookRefreshState,
}
impl BridgeOfflineCache {
    /// 本地读取不获取网络锁，也不授予学校操作资格。
    ///
    /// # Errors
    /// 账号关闭、损坏或参数无效返回稳定错误，缺记录返回 None。
    pub async fn read_libbook_area_detail(
        &self,
        route: BridgeConnectionMode,
        area_id: String,
    ) -> Result<Option<BridgeCachedLibBookAreaDetailRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_libbook(
                    route.into(),
                    &core::LibBookCacheQuery::AreaDetail { area_id },
                )
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::LibBookAreaDetail(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedLibBookAreaDetailRecord {
                        data: map_libbook_area_detail(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 沿原协议读取并保存只读投影，待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务分类、账号与退出屏障保持。
    pub async fn libbook_area_detail_cached(
        &self,
        cache: &BridgeOfflineCache,
        area_id: String,
    ) -> Result<BridgeLibBookAreaDetailRefresh, BridgeError> {
        let value = self
            .refresh_libbook_record(cache, core::LibBookCacheQuery::AreaDetail { area_id })
            .await?;
        let state = refresh_state(&value);
        let core::LibBookReadData::AreaDetail(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeLibBookAreaDetailRefresh {
            data: map_libbook_area_detail(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookSeatsRecord {
    pub data: Vec<BridgeCachedLibBookSeat>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookSeatsRefresh {
    pub data: Vec<BridgeLibBookSeat>,
    pub route: BridgeRouteDecision,
    pub state: BridgeLibBookRefreshState,
}
impl BridgeOfflineCache {
    /// 本地读取不获取网络锁，也不授予学校操作资格。
    ///
    /// # Errors
    /// 账号关闭、损坏或参数无效返回稳定错误，缺记录返回 None。
    pub async fn read_libbook_seats(
        &self,
        route: BridgeConnectionMode,
        area_id: String,
        day: String,
        start_time: String,
        end_time: String,
    ) -> Result<Option<BridgeCachedLibBookSeatsRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_libbook(
                    route.into(),
                    &core::LibBookCacheQuery::Seats {
                        area_id,
                        day,
                        start_time,
                        end_time,
                    },
                )
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::LibBookSeats(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedLibBookSeatsRecord {
                        data: data.into_iter().map(map_cached_libbook_seat).collect(),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 沿原协议读取并保存只读投影，待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务分类、账号与退出屏障保持。
    pub async fn libbook_seats_cached(
        &self,
        cache: &BridgeOfflineCache,
        area_id: String,
        day: String,
        start_time: String,
        end_time: String,
    ) -> Result<BridgeLibBookSeatsRefresh, BridgeError> {
        let value = self
            .refresh_libbook_record(
                cache,
                core::LibBookCacheQuery::Seats {
                    area_id,
                    day,
                    start_time,
                    end_time,
                },
            )
            .await?;
        let state = refresh_state(&value);
        let core::LibBookReadData::Seats(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeLibBookSeatsRefresh {
            data: map_libbook_seats(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedLibBookBookingsRecord {
    pub data: BridgeCachedLibBookBookingsPage,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeLibBookBookingsRefresh {
    pub data: BridgeLibBookBookingsPage,
    pub route: BridgeRouteDecision,
    pub state: BridgeLibBookRefreshState,
}
impl BridgeOfflineCache {
    /// 本地读取不获取网络锁，也不授予学校操作资格。
    ///
    /// # Errors
    /// 账号关闭、损坏或参数无效返回稳定错误，缺记录返回 None。
    pub async fn read_libbook_bookings(
        &self,
        route: BridgeConnectionMode,
        page: i32,
        limit: i32,
    ) -> Result<Option<BridgeCachedLibBookBookingsRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_libbook(
                    route.into(),
                    &core::LibBookCacheQuery::Bookings { page, limit },
                )
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::LibBookBookings(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedLibBookBookingsRecord {
                        data: map_cached_libbook_bookings_page(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 沿原协议读取并保存只读投影，待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务分类、账号与退出屏障保持。
    pub async fn libbook_bookings_cached(
        &self,
        cache: &BridgeOfflineCache,
        page: i32,
        limit: i32,
    ) -> Result<BridgeLibBookBookingsRefresh, BridgeError> {
        let value = self
            .refresh_libbook_record(cache, core::LibBookCacheQuery::Bookings { page, limit })
            .await?;
        let state = refresh_state(&value);
        let core::LibBookReadData::Bookings(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeLibBookBookingsRefresh {
            data: map_libbook_bookings(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}
#[cfg(test)]
mod tests {
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    use crate::api::{client::*, offline::BridgeOfflineCache};
    use ubaa_core::facade as core;
    #[tokio::test]
    async fn 图书馆本地记录不等待网络且分页路线隔离() {
        let root = std::env::temp_dir().join(format!("ubaa-libbook-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repo = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([8; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repo
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::LibBookBookings { page: 1, limit: 20 },
            })
            .unwrap();
        repo.publish(
            &ticket,
            core::CachePayload::LibBookBookings(core::CachedLibBookBookingsPage {
                bookings: vec![core::CachedLibBookBooking {
                    id: "b9".into(),
                    name_merge: "合成预约".into(),
                    ..Default::default()
                }],
                page: 1,
                limit: 20,
                total: 21,
            }),
            123,
            core::CacheCompleteness::Complete,
        )
        .unwrap();
        drop(repo);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![8; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let record = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_libbook_bookings(BridgeConnectionMode::Direct, 1, 20),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.data.bookings[0].id, "b9");
        assert_eq!(record.data.total, 21);
        assert!(
            cache
                .read_libbook_bookings(BridgeConnectionMode::Direct, 2, 20)
                .await
                .unwrap()
                .is_none()
        );
        assert!(
            cache
                .read_libbook_bookings(BridgeConnectionMode::WebVpn, 1, 20)
                .await
                .unwrap()
                .is_none()
        );
        drop(guard);
        check_pending(&client, &cache).await;
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_libbook_bookings(BridgeConnectionMode::Direct, 1, 20)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(cache);
        drop(client);
        let _ = std::fs::remove_dir_all(root);
    }
    async fn check_pending(client: &BridgeClient, cache: &BridgeOfflineCache) {
        client.write_intents.lock().await.insert(
            "synthetic".into(),
            PendingEntry {
                request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 42 }),
                expires_at: i64::MAX,
                resolved_route: BridgeConnectionMode::Direct,
                conflict_key: "synthetic".into(),
            },
        );
        assert_eq!(
            client
                .libbook_bookings_cached(cache, 1, 20)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
    }
}
