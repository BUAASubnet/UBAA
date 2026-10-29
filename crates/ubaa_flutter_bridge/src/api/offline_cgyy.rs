//! 研讨室只读缓存沿公开字段白名单；在线资格与缓存分离。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{
    BridgeCgyyDayInfo, BridgeCgyyOrder, BridgeCgyyOrdersPage, BridgeCgyyPurposeTypes,
    BridgeCgyyTimeSlot, BridgeCgyyVenueSite, map_cgyy_day_info, map_cgyy_order, map_cgyy_orders,
    map_cgyy_purpose_types, map_cgyy_sites, map_cgyy_time_slot,
};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyySlotStatus {
    pub time_id: i32,
    pub reservation_status: Option<i32>,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
}
fn map_cached_cgyy_slot_status(v: core::CachedCgyySlotStatus) -> BridgeCachedCgyySlotStatus {
    BridgeCachedCgyySlotStatus {
        time_id: v.time_id,
        reservation_status: v.reservation_status,
        start_date: v.start_date,
        end_date: v.end_date,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyySpaceAvailability {
    pub space_id: i32,
    pub space_name: String,
    pub venue_site_id: i32,
    pub venue_space_group_id: Option<i32>,
    pub slots: Vec<BridgeCachedCgyySlotStatus>,
}
fn map_cached_cgyy_space_availability(
    v: core::CachedCgyySpaceAvailability,
) -> BridgeCachedCgyySpaceAvailability {
    BridgeCachedCgyySpaceAvailability {
        space_id: v.space_id,
        space_name: v.space_name,
        venue_site_id: v.venue_site_id,
        venue_space_group_id: v.venue_space_group_id,
        slots: v
            .slots
            .into_iter()
            .map(map_cached_cgyy_slot_status)
            .collect(),
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyDayInfo {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<BridgeCgyyTimeSlot>,
    pub spaces: Vec<BridgeCachedCgyySpaceAvailability>,
    pub reservation_total_num: Option<i32>,
}
fn map_cached_cgyy_day_info(v: core::CachedCgyyDayInfo) -> BridgeCachedCgyyDayInfo {
    BridgeCachedCgyyDayInfo {
        venue_site_id: v.venue_site_id,
        reservation_date: v.reservation_date,
        available_dates: v.available_dates,
        time_slots: v.time_slots.into_iter().map(map_cgyy_time_slot).collect(),
        spaces: v
            .spaces
            .into_iter()
            .map(map_cached_cgyy_space_availability)
            .collect(),
        reservation_total_num: v.reservation_total_num,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyOrder {
    pub id: i32,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub venue_space_name: Option<String>,
    pub campus_name: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
    pub order_status: Option<i32>,
    pub check_status: Option<i32>,
    pub theme: Option<String>,
    pub purpose_type_name: Option<String>,
    pub joiner_num: Option<i32>,
}
fn map_cached_cgyy_order(v: core::CachedCgyyOrder) -> BridgeCachedCgyyOrder {
    BridgeCachedCgyyOrder {
        id: v.id,
        venue_site_id: v.venue_site_id,
        reservation_date: v.reservation_date,
        reservation_date_detail: v.reservation_date_detail,
        venue_space_name: v.venue_space_name,
        campus_name: v.campus_name,
        venue_name: v.venue_name,
        site_name: v.site_name,
        reservation_start_date: v.reservation_start_date,
        reservation_end_date: v.reservation_end_date,
        order_status: v.order_status,
        check_status: v.check_status,
        theme: v.theme,
        purpose_type_name: v.purpose_type_name,
        joiner_num: v.joiner_num,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyOrdersPage {
    pub content: Vec<BridgeCachedCgyyOrder>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}
fn map_cached_cgyy_orders_page(v: core::CachedCgyyOrdersPage) -> BridgeCachedCgyyOrdersPage {
    BridgeCachedCgyyOrdersPage {
        content: v.content.into_iter().map(map_cached_cgyy_order).collect(),
        total_elements: v.total_elements,
        total_pages: v.total_pages,
        size: v.size,
        number: v.number,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCgyyRefreshState {
    pub fetched_at: i64,
    pub complete: bool,
    pub saved_for_offline: bool,
    pub preserved_previous: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
fn refresh_state(v: &core::CgyyRefresh) -> BridgeCgyyRefreshState {
    BridgeCgyyRefreshState {
        fetched_at: v.result.fetched_at,
        complete: v.complete,
        saved_for_offline: v.publication == Some(core::CachePublication::Stored),
        preserved_previous: v.publication == Some(core::CachePublication::Preserved),
        save_error: v.result.save_error.map(Into::into),
    }
}
impl BridgeClient {
    async fn refresh_cgyy_record(
        &self,
        cache: &BridgeOfflineCache,
        query: core::CgyyCacheQuery,
    ) -> Result<core::CgyyRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Cgyy))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_cgyy(&cache.cache, query)
                .await
                .map_err(offline_read_error)
        })
        .await
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyySitesRecord {
    pub data: Vec<BridgeCgyyVenueSite>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyySitesRefresh {
    pub data: Vec<BridgeCgyyVenueSite>,
    pub route: BridgeRouteDecision,
    pub state: BridgeCgyyRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络读取精确本地范围。
    ///
    /// # Errors
    /// 账号关闭、范围无效或损坏返回稳定错误；缺记录返回 None。
    pub async fn read_cgyy_sites(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedCgyySitesRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_cgyy(route.into(), &core::CgyyCacheQuery::Sites)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::CgyySites(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedCgyySitesRecord {
                        data: map_cgyy_sites(data),
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
    /// 原查询与只读保存；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误及账号/退出栅栏。
    pub async fn cgyy_sites_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeCgyySitesRefresh, BridgeError> {
        let value = self
            .refresh_cgyy_record(cache, core::CgyyCacheQuery::Sites)
            .await?;
        let state = refresh_state(&value);
        let core::CgyyReadData::Sites(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeCgyySitesRefresh {
            data: map_cgyy_sites(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyPurposesRecord {
    pub data: BridgeCgyyPurposeTypes,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyPurposesRefresh {
    pub data: BridgeCgyyPurposeTypes,
    pub route: BridgeRouteDecision,
    pub state: BridgeCgyyRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络读取精确本地范围。
    ///
    /// # Errors
    /// 账号关闭、范围无效或损坏返回稳定错误；缺记录返回 None。
    pub async fn read_cgyy_purposes(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedCgyyPurposesRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_cgyy(route.into(), &core::CgyyCacheQuery::Purposes)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::CgyyPurposes(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedCgyyPurposesRecord {
                        data: map_cgyy_purpose_types(data),
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
    /// 原查询与只读保存；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误及账号/退出栅栏。
    pub async fn cgyy_purposes_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeCgyyPurposesRefresh, BridgeError> {
        let value = self
            .refresh_cgyy_record(cache, core::CgyyCacheQuery::Purposes)
            .await?;
        let state = refresh_state(&value);
        let core::CgyyReadData::Purposes(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeCgyyPurposesRefresh {
            data: map_cgyy_purpose_types(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyDayRecord {
    pub data: BridgeCachedCgyyDayInfo,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyDayRefresh {
    pub data: BridgeCgyyDayInfo,
    pub route: BridgeRouteDecision,
    pub state: BridgeCgyyRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络读取精确本地范围。
    ///
    /// # Errors
    /// 账号关闭、范围无效或损坏返回稳定错误；缺记录返回 None。
    pub async fn read_cgyy_day(
        &self,
        route: BridgeConnectionMode,
        site_id: i32,
        date: String,
    ) -> Result<Option<BridgeCachedCgyyDayRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_cgyy(route.into(), &core::CgyyCacheQuery::Day { site_id, date })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::CgyyDay(payload) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedCgyyDayRecord {
                        data: map_cached_cgyy_day_info(payload),
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
    /// 原查询与只读保存；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误及账号/退出栅栏。
    pub async fn cgyy_day_cached(
        &self,
        cache: &BridgeOfflineCache,
        site_id: i32,
        date: String,
    ) -> Result<BridgeCgyyDayRefresh, BridgeError> {
        let value = self
            .refresh_cgyy_record(cache, core::CgyyCacheQuery::Day { site_id, date })
            .await?;
        let state = refresh_state(&value);
        let core::CgyyReadData::Day(payload) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeCgyyDayRefresh {
            data: map_cgyy_day_info(payload),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyOrdersRecord {
    pub data: BridgeCachedCgyyOrdersPage,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyOrdersRefresh {
    pub data: BridgeCgyyOrdersPage,
    pub route: BridgeRouteDecision,
    pub state: BridgeCgyyRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络读取精确本地范围。
    ///
    /// # Errors
    /// 账号关闭、范围无效或损坏返回稳定错误；缺记录返回 None。
    pub async fn read_cgyy_orders(
        &self,
        route: BridgeConnectionMode,
        page: i32,
        size: i32,
    ) -> Result<Option<BridgeCachedCgyyOrdersRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_cgyy(route.into(), &core::CgyyCacheQuery::Orders { page, size })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::CgyyOrders(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedCgyyOrdersRecord {
                        data: map_cached_cgyy_orders_page(data),
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
    /// 原查询与只读保存；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误及账号/退出栅栏。
    pub async fn cgyy_orders_cached(
        &self,
        cache: &BridgeOfflineCache,
        page: i32,
        size: i32,
    ) -> Result<BridgeCgyyOrdersRefresh, BridgeError> {
        let value = self
            .refresh_cgyy_record(cache, core::CgyyCacheQuery::Orders { page, size })
            .await?;
        let state = refresh_state(&value);
        let core::CgyyReadData::Orders(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeCgyyOrdersRefresh {
            data: map_cgyy_orders(data),
            route: map_route(value.result.resolution),
            state,
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCgyyDetailRecord {
    pub data: BridgeCachedCgyyOrder,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCgyyDetailRefresh {
    pub data: BridgeCgyyOrder,
    pub route: BridgeRouteDecision,
    pub state: BridgeCgyyRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络读取精确本地范围。
    ///
    /// # Errors
    /// 账号关闭、范围无效或损坏返回稳定错误；缺记录返回 None。
    pub async fn read_cgyy_detail(
        &self,
        route: BridgeConnectionMode,
        order_id: i32,
    ) -> Result<Option<BridgeCachedCgyyDetailRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_cgyy(route.into(), &core::CgyyCacheQuery::Detail { order_id })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::CgyyDetail(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedCgyyDetailRecord {
                        data: map_cached_cgyy_order(data),
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
    /// 原查询与只读保存；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误及账号/退出栅栏。
    pub async fn cgyy_detail_cached(
        &self,
        cache: &BridgeOfflineCache,
        order_id: i32,
    ) -> Result<BridgeCgyyDetailRefresh, BridgeError> {
        let value = self
            .refresh_cgyy_record(cache, core::CgyyCacheQuery::Detail { order_id })
            .await?;
        let state = refresh_state(&value);
        let core::CgyyReadData::Detail(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeCgyyDetailRefresh {
            data: map_cgyy_order(*data),
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
    async fn 研讨室本地订单读取不等待网络且分页路线隔离() {
        let root = std::env::temp_dir().join(format!("ubaa-cgyy-cache-{}", std::process::id()));
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
                query: core::CacheQuery::CgyyOrders { page: 0, size: 20 },
            })
            .unwrap();
        repo.publish(
            &ticket,
            core::CachePayload::CgyyOrders(core::CachedCgyyOrdersPage {
                content: vec![core::CachedCgyyOrder {
                    id: 9,
                    theme: Some("合成预约".into()),
                    ..Default::default()
                }],
                number: 0,
                size: 20,
                total_pages: 2,
                total_elements: 21,
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
            cache.read_cgyy_orders(BridgeConnectionMode::Direct, 0, 20),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.data.content[0].id, 9);
        assert_eq!(record.data.total_pages, 2);
        assert!(
            cache
                .read_cgyy_orders(BridgeConnectionMode::Direct, 1, 20)
                .await
                .unwrap()
                .is_none()
        );
        assert!(
            cache
                .read_cgyy_orders(BridgeConnectionMode::WebVpn, 0, 20)
                .await
                .unwrap()
                .is_none()
        );
        drop(guard);
        check_pending(&client, &cache).await;
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_cgyy_orders(BridgeConnectionMode::Direct, 0, 20)
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
                .cgyy_orders_cached(cache, 0, 20)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
    }
}
