//! 首页待办的只读缓存与在线资格使用分开的绑定类型。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, catch_panic, disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{
    BridgeRoutedSigninClasses, BridgeRoutedSpocAssignmentDetail, BridgeRoutedSpocAssignments,
    BridgeRoutedYgdkOverview, BridgeSpocAssignmentDetail, BridgeSpocAssignments,
    BridgeYgdkTermSummary, map_signin_classes, map_spoc_assignments, map_spoc_detail,
    map_ygdk_overview, map_ygdk_summary,
};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeCachedSigninClass {
    pub course_id: String,
    pub course_name: String,
    pub class_begin_time: String,
    pub class_end_time: String,
    pub sign_status: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedYgdkItem {
    pub item_id: i32,
    pub name: String,
    pub kind: Option<i32>,
    pub sort: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedYgdkOverview {
    pub summary: BridgeYgdkTermSummary,
    pub classify_id: i32,
    pub classify_name: String,
    pub default_item_id: i32,
    pub default_item_name: String,
    pub items: Vec<BridgeCachedYgdkItem>,
}
fn cached_signin(values: Vec<core::CachedSigninClass>) -> Vec<BridgeCachedSigninClass> {
    values
        .into_iter()
        .map(|v| BridgeCachedSigninClass {
            course_id: v.course_id,
            course_name: v.course_name,
            class_begin_time: v.class_begin_time,
            class_end_time: v.class_end_time,
            sign_status: v.sign_status,
        })
        .collect()
}
fn cached_ygdk(v: core::CachedYgdkOverview) -> BridgeCachedYgdkOverview {
    BridgeCachedYgdkOverview {
        summary: map_ygdk_summary(v.summary),
        classify_id: v.classify_id,
        classify_name: v.classify_name,
        default_item_id: v.default_item_id,
        default_item_name: v.default_item_name,
        items: v
            .items
            .into_iter()
            .map(|item| BridgeCachedYgdkItem {
                item_id: item.item_id,
                name: item.name,
                kind: item.kind,
                sort: item.sort,
            })
            .collect(),
    }
}
/// 本次同步完整度和实际保存结果不等于学校写资格。
#[derive(Clone, Debug)]
pub struct BridgeHomeRefreshState {
    pub fetched_at: i64,
    pub complete: bool,
    pub saved_for_offline: bool,
    pub preserved_previous: bool,
    pub save_error: Option<BridgeCacheFailure>,
    pub scope_date: Option<String>,
}
fn home_state(value: &core::HomeRefresh) -> BridgeHomeRefreshState {
    BridgeHomeRefreshState {
        fetched_at: value.result.fetched_at,
        complete: value.complete,
        saved_for_offline: value.publication == Some(core::CachePublication::Stored),
        preserved_previous: value.publication == Some(core::CachePublication::Preserved),
        save_error: value.result.save_error.map(Into::into),
        scope_date: match &value.result.scope.query {
            core::CacheQuery::SigninToday { date } => Some(date.clone()),
            _ => None,
        },
    }
}
impl BridgeClient {
    async fn refresh_home_record(
        &self,
        cache: &BridgeOfflineCache,
        query: core::HomeQuery,
    ) -> Result<core::HomeRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_home(&cache.cache, query)
                .await
                .map_err(offline_read_error)
        })
        .await
    }
}

/// 精确来源的旧内容；没有学校写资格。
#[derive(Clone, Debug)]
pub struct BridgeCachedHomeSignin {
    pub data: Vec<BridgeCachedSigninClass>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
    pub date: String,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeSigninRefresh {
    pub result: BridgeRoutedSigninClasses,
    pub state: BridgeHomeRefreshState,
}
impl BridgeOfflineCache {
    /// 独立本地读取不等待网络锁，不进行认证。
    ///
    /// # Errors
    /// 缺少记录返回 None，账号关闭/损坏/非法范围返回稳定错误。
    pub async fn read_home_signin(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedHomeSignin>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_home(route.into(), &core::HomeQuery::SigninToday)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::SigninToday(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    let core::CacheQuery::SigninToday { date } = record.scope.query else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedHomeSignin {
                        data: cached_signin(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                        date,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 读取在线内容并持久化只读投影；既有学校写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务错误与账号/退出栅栏不降级为缓存保存错误。
    pub async fn home_signin_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeHomeSigninRefresh, BridgeError> {
        let value = self
            .refresh_home_record(cache, core::HomeQuery::SigninToday)
            .await?;
        let state = home_state(&value);
        let core::HomeReadData::Signin(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeHomeSigninRefresh {
            result: BridgeRoutedSigninClasses {
                data: map_signin_classes(data),
                route: map_route(value.result.resolution),
            },
            state,
        })
    }
}

/// 精确来源的旧内容；没有学校写资格。
#[derive(Clone, Debug)]
pub struct BridgeCachedHomeSpoc {
    pub data: BridgeSpocAssignments,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeSpocRefresh {
    pub result: BridgeRoutedSpocAssignments,
    pub state: BridgeHomeRefreshState,
}
impl BridgeOfflineCache {
    /// 独立本地读取不等待网络锁，不进行认证。
    ///
    /// # Errors
    /// 缺少记录返回 None，账号关闭/损坏/非法范围返回稳定错误。
    pub async fn read_home_spoc(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedHomeSpoc>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_home(route.into(), &core::HomeQuery::SpocAssignments)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::SpocAssignments(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };

                    Ok(BridgeCachedHomeSpoc {
                        data: map_spoc_assignments(data),
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
    /// 读取在线内容并持久化只读投影；既有学校写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务错误与账号/退出栅栏不降级为缓存保存错误。
    pub async fn home_spoc_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeHomeSpocRefresh, BridgeError> {
        let value = self
            .refresh_home_record(cache, core::HomeQuery::SpocAssignments)
            .await?;
        let state = home_state(&value);
        let core::HomeReadData::SpocAssignments(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeHomeSpocRefresh {
            result: BridgeRoutedSpocAssignments {
                data: map_spoc_assignments(data),
                route: map_route(value.result.resolution),
            },
            state,
        })
    }
}

/// 精确来源的旧内容；没有学校写资格。
#[derive(Clone, Debug)]
pub struct BridgeCachedHomeSpocDetail {
    pub data: BridgeSpocAssignmentDetail,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeSpocDetailRefresh {
    pub result: BridgeRoutedSpocAssignmentDetail,
    pub state: BridgeHomeRefreshState,
}
impl BridgeOfflineCache {
    /// 独立本地读取不等待网络锁，不进行认证。
    ///
    /// # Errors
    /// 缺少记录返回 None，账号关闭/损坏/非法范围返回稳定错误。
    pub async fn read_home_spoc_detail(
        &self,
        route: BridgeConnectionMode,
        assignment_id: String,
    ) -> Result<Option<BridgeCachedHomeSpocDetail>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_home(route.into(), &core::HomeQuery::SpocDetail { assignment_id })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::SpocDetail(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };

                    Ok(BridgeCachedHomeSpocDetail {
                        data: map_spoc_detail(*data),
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
    /// 读取在线内容并持久化只读投影；既有学校写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务错误与账号/退出栅栏不降级为缓存保存错误。
    pub async fn home_spoc_detail_cached(
        &self,
        cache: &BridgeOfflineCache,
        assignment_id: String,
    ) -> Result<BridgeHomeSpocDetailRefresh, BridgeError> {
        let value = self
            .refresh_home_record(cache, core::HomeQuery::SpocDetail { assignment_id })
            .await?;
        let state = home_state(&value);
        let core::HomeReadData::SpocDetail(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeHomeSpocDetailRefresh {
            result: BridgeRoutedSpocAssignmentDetail {
                data: map_spoc_detail(data),
                route: map_route(value.result.resolution),
            },
            state,
        })
    }
}

/// 精确来源的旧内容；没有学校写资格。
#[derive(Clone, Debug)]
pub struct BridgeCachedHomeYgdk {
    pub data: BridgeCachedYgdkOverview,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeYgdkRefresh {
    pub result: BridgeRoutedYgdkOverview,
    pub state: BridgeHomeRefreshState,
}
impl BridgeOfflineCache {
    /// 独立本地读取不等待网络锁，不进行认证。
    ///
    /// # Errors
    /// 缺少记录返回 None，账号关闭/损坏/非法范围返回稳定错误。
    pub async fn read_home_ygdk(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedHomeYgdk>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_home(route.into(), &core::HomeQuery::YgdkOverview)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::YgdkOverview(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };

                    Ok(BridgeCachedHomeYgdk {
                        data: cached_ygdk(data),
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
    /// 读取在线内容并持久化只读投影；既有学校写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 原业务错误与账号/退出栅栏不降级为缓存保存错误。
    pub async fn home_ygdk_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeHomeYgdkRefresh, BridgeError> {
        let value = self
            .refresh_home_record(cache, core::HomeQuery::YgdkOverview)
            .await?;
        let state = home_state(&value);
        let core::HomeReadData::YgdkOverview(data) = value.result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeHomeYgdkRefresh {
            result: BridgeRoutedYgdkOverview {
                data: map_ygdk_overview(data),
                route: map_route(value.result.resolution),
            },
            state,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::super::{client::*, offline::BridgeOfflineCache};
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    use ubaa_core::facade as core;
    fn store_spoc_selection(repository: &mut core::OfflineRepository) {
        let selection = repository
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::SpocSelection,
            })
            .unwrap();
        repository
            .publish(
                &selection,
                core::CachePayload::SpocSelection {
                    term: "synthetic-term".into(),
                },
                123,
                core::CacheCompleteness::Complete,
            )
            .unwrap();
    }
    #[tokio::test]
    async fn 首页缓存读取保留旧状态但不恢复操作资格() {
        let root = std::env::temp_dir().join(format!("ubaa-home-bridge-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repository = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([5; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repository
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::SpocTerm {
                    term: "synthetic-term".into(),
                },
            })
            .unwrap();
        repository
            .publish(
                &ticket,
                core::CachePayload::SpocAssignments(core::SpocAssignments {
                    term_code: "synthetic-term".into(),
                    ..Default::default()
                }),
                123,
                core::CacheCompleteness::Complete,
            )
            .unwrap();
        store_spoc_selection(&mut repository);
        drop(repository);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![5; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let record = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_home_spoc(BridgeConnectionMode::Direct),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.data.term_code, "synthetic-term");
        assert_eq!(record.fetched_at, 123);
        assert!(
            cache
                .read_home_spoc(BridgeConnectionMode::WebVpn)
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
            client.home_signin_cached(&cache).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_home_spoc(BridgeConnectionMode::Direct)
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

pub mod spoc_scan;
