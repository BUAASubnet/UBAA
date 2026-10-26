//! 资料缓存与在线身份使用不同类型，遮罩值不能恢复认证。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, BridgeUserProfile,
    catch_panic, disposed_error, map_profile, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use ubaa_core::facade as core;
#[derive(Clone, Debug)]
pub struct BridgeMaskedProfile {
    pub masked_username: Option<String>,
    pub masked_name: Option<String>,
    pub masked_school_id: Option<String>,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedProfile {
    pub data: BridgeMaskedProfile,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeProfileRefresh {
    pub data: BridgeUserProfile,
    pub route: BridgeRouteDecision,
    pub fetched_at: i64,
    pub saved_for_offline: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 仅本地遮罩资料，不等待网络锁。
    ///
    /// # Errors
    /// 损坏、退出或本地存储失败保持稳定错误。
    pub async fn read_profile(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedProfile>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_profile(route.into())
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::MaskedProfile(value) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedProfile {
                        data: BridgeMaskedProfile {
                            masked_username: value.masked_username().map(str::to_owned),
                            masked_name: value.masked_name().map(str::to_owned),
                            masked_school_id: value.masked_school_id().map(str::to_owned),
                        },
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
    /// 在线资料保持完整映射，仅持久化遮罩投影；待确认写入禁止隐式恢复。
    ///
    /// # Errors
    /// 保留原读取、身份及退出错误。
    pub async fn user_info_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeProfileRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .refresh_cached_profile(&cache.cache)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeProfileRefresh {
                data: map_profile(value.data),
                route: map_route(value.resolution),
                fetched_at: value.fetched_at,
                saved_for_offline: value.save_error.is_none(),
                save_error: value.save_error.map(Into::into),
            })
        })
        .await
    }
}
#[cfg(test)]
mod tests {
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    use crate::api::{client::*, offline::BridgeOfflineCache};
    use ubaa_core::facade as core;
    #[tokio::test]
    async fn 遮罩资料独立本地锁且不能绕过待确认写入() {
        let root = std::env::temp_dir().join(format!("ubaa-profile-bridge-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repo = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([7; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repo
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::MaskedProfile,
            })
            .unwrap();
        repo.publish(
            &ticket,
            core::CachePayload::MaskedProfile(core::CachedMaskedProfile::from_profile(
                &core::UserProfile {
                    username: Some("synthetic-user".into()),
                    name: Some("合成名字".into()),
                    phone: Some("不应跨缓存边界".into()),
                    ..Default::default()
                },
            )),
            100,
            core::CacheCompleteness::Complete,
        )
        .unwrap();
        drop(repo);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic-user".into(),
            vec![7; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let value = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_profile(BridgeConnectionMode::Direct),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(value.data.masked_username.as_deref(), Some("s***r"));
        assert_eq!(value.data.masked_name.as_deref(), Some("合***字"));
        assert_eq!(value.fetched_at, 100);
        assert!(
            cache
                .read_profile(BridgeConnectionMode::WebVpn)
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
            client.user_info_cached(&cache).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_profile(BridgeConnectionMode::Direct)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(client);
        drop(cache);
        let _ = std::fs::remove_dir_all(root);
    }
}
