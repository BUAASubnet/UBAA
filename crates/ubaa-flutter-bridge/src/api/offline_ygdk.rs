//! 阳光记录缓存以分类与分页定位，照片只跨边界传递数量。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{BridgeYgdkRecord, BridgeYgdkRecordsPage, map_ygdk_records};
use ubaa_core::facade as core;
#[derive(Clone, Debug)]
pub struct BridgeYgdkRecordsSelection {
    pub classify_id: i32,
    pub classify_name: String,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedYgdkSelection {
    pub data: BridgeYgdkRecordsSelection,
    pub source_route: BridgeConnectionMode,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedYgdkRecords {
    pub data: BridgeYgdkRecordsPage,
    pub classify_id: i32,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeYgdkRecordsRefresh {
    pub data: BridgeYgdkRecordsPage,
    pub selection: BridgeYgdkRecordsSelection,
    pub route: BridgeRouteDecision,
    pub fetched_at: i64,
    pub complete: bool,
    pub saved_for_offline: bool,
    pub preserved_previous: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
fn map_selection(v: core::CachedYgdkRecordsSelection) -> BridgeYgdkRecordsSelection {
    BridgeYgdkRecordsSelection {
        classify_id: v.classify_id,
        classify_name: v.classify_name,
    }
}
fn map_cached_records(v: core::CachedYgdkRecordsPage) -> BridgeYgdkRecordsPage {
    BridgeYgdkRecordsPage {
        content: v
            .content
            .into_iter()
            .map(|r| BridgeYgdkRecord {
                record_id: r.record_id,
                item_id: r.item_id,
                item_name: r.item_name,
                start_time: r.start_time,
                end_time: r.end_time,
                place: r.place,
                image_count: r.image_count,
                is_open: r.is_open,
                state: r.state,
                created_at: r.created_at,
                created_at_label: r.created_at_label,
            })
            .collect(),
        total: v.total,
        page: v.page,
        size: v.size,
        has_more: v.has_more,
    }
}
fn map_refresh(v: core::YgdkRecordsRefresh) -> BridgeYgdkRecordsRefresh {
    BridgeYgdkRecordsRefresh {
        data: map_ygdk_records(v.result.data),
        selection: map_selection(v.selection),
        route: map_route(v.result.resolution),
        fetched_at: v.result.fetched_at,
        complete: v.complete,
        saved_for_offline: v.publication == Some(core::CachePublication::Stored)
            && v.selection_saved,
        preserved_previous: v.publication == Some(core::CachePublication::Preserved),
        save_error: v.result.save_error.map(Into::into),
    }
}
impl BridgeOfflineCache {
    /// 上次分类索引不代表数据页取得时间，宿主须另外读取精确页。
    ///
    /// # Errors
    /// 缺值返回 None，退出或损坏保持稳定错误。
    pub async fn read_ygdk_records_selection(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedYgdkSelection>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_ygdk_records_selection(route.into())
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::YgdkRecordsSelection(value) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedYgdkSelection {
                        data: map_selection(value),
                        source_route: record.scope.route.into(),
                    })
                })
                .transpose()
        })
        .await
    }
    /// 独立本地读取精确分类页，不请求学校服务或授予写资格。
    ///
    /// # Errors
    /// 无效范围、退出或损坏返回稳定错误。
    pub async fn read_ygdk_records(
        &self,
        route: BridgeConnectionMode,
        classify_id: i32,
        page: i32,
        size: i32,
    ) -> Result<Option<BridgeCachedYgdkRecords>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_ygdk_records(route.into(), classify_id, page, size)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::YgdkRecords(value) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedYgdkRecords {
                        classify_id: value.classify_id,
                        data: map_cached_records(value),
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
    /// 普通记录查询按实际分类保存；待确认写意图禁止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务及账号/代次错误。
    pub async fn ygdk_records_cached(
        &self,
        cache: &BridgeOfflineCache,
        page: i32,
        size: i32,
    ) -> Result<BridgeYgdkRecordsRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_ygdk_records(&cache.cache, page, size)
                .await
                .map(map_refresh)
                .map_err(offline_read_error)
        })
        .await
    }
    /// 概览组合读取要求路线和分类仍匹配，不替代原caller-pinned写后回读。
    ///
    /// # Errors
    /// 上下文变化返回冲突，其他错误沿原读取分类。
    pub async fn ygdk_records_for_overview_cached(
        &self,
        cache: &BridgeOfflineCache,
        route: BridgeConnectionMode,
        classify_id: i32,
        page: i32,
        size: i32,
    ) -> Result<BridgeYgdkRecordsRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_ygdk_records_for_overview(
                    &cache.cache,
                    route.into(),
                    classify_id,
                    page,
                    size,
                )
                .await
                .map(map_refresh)
                .map_err(offline_read_error)
        })
        .await
    }
}
#[cfg(test)]
mod tests {
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    use crate::api::{client::*, offline::BridgeOfflineCache};
    use ubaa_core::facade as core;
    fn seed(root: &std::path::Path, account: &str) {
        let mut repo = core::OfflineRepository::open(
            root,
            account,
            core::CacheKey::new([8; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let selected = repo
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::YgdkRecordsSelection,
            })
            .unwrap();
        repo.publish(
            &selected,
            core::CachePayload::YgdkRecordsSelection(core::CachedYgdkRecordsSelection {
                classify_id: 2,
                classify_name: "合成体育".into(),
            }),
            200,
            core::CacheCompleteness::Complete,
        )
        .unwrap();
        let ticket = repo
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::YgdkRecords {
                    classify_id: 2,
                    page: 2,
                    size: 5,
                },
            })
            .unwrap();
        repo.publish(
            &ticket,
            core::CachePayload::YgdkRecords(core::CachedYgdkRecordsPage {
                classify_id: 2,
                page: 2,
                size: 5,
                total: 21,
                has_more: true,
                content: vec![core::CachedYgdkRecord {
                    record_id: 3,
                    image_count: 2,
                    ..Default::default()
                }],
            }),
            100,
            core::CacheCompleteness::Complete,
        )
        .unwrap();
        drop(repo);
    }
    #[tokio::test]
    async fn 阳光分类索引与记录页独立网络锁且精确隔离() {
        let root = std::env::temp_dir().join(format!("ubaa-ygdk-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        seed(&root, account);
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
            cache.read_ygdk_records(BridgeConnectionMode::Direct, 2, 2, 5),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.fetched_at, 100);
        assert_eq!(record.data.content[0].image_count, 2);
        assert_eq!(
            cache
                .read_ygdk_records_selection(BridgeConnectionMode::Direct)
                .await
                .unwrap()
                .unwrap()
                .data
                .classify_id,
            2
        );
        assert!(
            cache
                .read_ygdk_records(BridgeConnectionMode::Direct, 1, 2, 5)
                .await
                .unwrap()
                .is_none()
        );
        assert!(
            cache
                .read_ygdk_records(BridgeConnectionMode::WebVpn, 2, 2, 5)
                .await
                .unwrap()
                .is_none()
        );
        drop(guard);
        client.write_intents.lock().await.insert(
            "synthetic".into(),
            PendingEntry {
                request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
                expires_at: i64::MAX,
                resolved_route: BridgeConnectionMode::Direct,
                conflict_key: "synthetic".into(),
            },
        );
        assert_eq!(
            client
                .ygdk_records_cached(&cache, 1, 20)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(
            client
                .ygdk_records_for_overview_cached(&cache, BridgeConnectionMode::Direct, 2, 1, 20)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_ygdk_records_selection(BridgeConnectionMode::Direct)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(cache);
        drop(client);
        let _ = std::fs::remove_dir_all(root);
    }
}
