//! 资料在线结果保持原合同，离线只保存遮罩后的最小投影。
use super::{
    CacheError, CachePayload, CacheQuery, CacheScope, CachedMaskedProfile, ConnectionMode,
    OfflineCache, OfflineReadError, OfflineRefresh, UbaaClient, UserProfile,
};
impl OfflineCache {
    /// 读取已保存的遮罩资料，不恢复会话或授予身份。
    ///
    /// # Errors
    /// 本地损坏、账号关闭或存储失败按缓存错误返回。
    pub fn read_profile(
        &self,
        route: ConnectionMode,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: CacheQuery::MaskedProfile,
            },
            chrono::Utc::now().timestamp(),
        )
    }
}
impl UbaaClient {
    /// 按默认User路线核对身份后取资料，只将遮罩投影写入账号缓存。
    ///
    /// # Errors
    /// 原认证与业务错误保留；资料身份不符、退出或票据被替代不降级。
    pub async fn refresh_cached_profile(
        &mut self,
        cache: &OfflineCache,
    ) -> Result<OfflineRefresh<UserProfile>, OfflineReadError> {
        cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        let resolution = self
            .resolve_operation(super::types::Operation::User)
            .map_err(OfflineReadError::Read)?;
        let authenticated = self
            .recover_resolved_session(resolution)
            .await
            .map_err(OfflineReadError::Read)?;
        verify_identity(cache, &authenticated.data.user, resolution)?;
        let scope = CacheScope {
            route: resolution.mode,
            query: CacheQuery::MaskedProfile,
        };
        let (ticket, mut save_error) = match cache.begin(scope.clone()) {
            Ok(ticket) => (Some(ticket), None),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                return Err(OfflineReadError::Cache(error));
            }
            Err(error) => (None, Some(error)),
        };
        let read = {
            let (runtime, auth) = self.route_parts_for(resolution.mode);
            let mut clear_workflow = || auth.clear();
            crate::features::user::get_user_info(runtime, &mut clear_workflow).await
        };
        let fetched_at = chrono::Utc::now().timestamp();
        let read = match self.finish_routed(resolution, read) {
            Ok(value) => value,
            Err(error) => {
                if let Some(ticket) = &ticket {
                    cache.failure(ticket, fetched_at);
                }
                return Err(OfflineReadError::Read(error));
            }
        };
        if let Err(error) = verify_identity(cache, &read.data, resolution) {
            if let Some(ticket) = &ticket {
                cache.failure(ticket, fetched_at);
            }
            return Err(error);
        }
        if let Some(ticket) = &ticket {
            let payload =
                CachePayload::MaskedProfile(CachedMaskedProfile::from_profile(&read.data));
            match cache.publish(ticket, payload, fetched_at) {
                Ok(()) => {}
                Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                    return Err(OfflineReadError::Cache(error));
                }
                Err(error) => {
                    save_error = Some(error);
                    cache.failure(ticket, fetched_at);
                }
            }
        }
        Ok(OfflineRefresh {
            data: read.data,
            resolution,
            scope,
            fetched_at,
            save_error,
        })
    }
}

fn verify_identity(
    cache: &OfflineCache,
    profile: &UserProfile,
    resolution: super::RouteResolution,
) -> Result<(), OfflineReadError> {
    let known = [profile.username.as_deref(), profile.school_id.as_deref()]
        .into_iter()
        .flatten()
        .any(|value| !value.trim().is_empty());
    if !known {
        return Err(OfflineReadError::Read(super::RoutedError {
            error: super::UbaaError::new(
                super::ErrorCode::UpstreamChanged,
                super::ErrorKind::Upstream,
                false,
                "用户资料缺少可核对的身份",
            ),
            resolution: Some(resolution),
        }));
    }
    if !cache.matches(profile) {
        return Err(OfflineReadError::IdentityMismatch {
            resolution,
            cache_error: cache.deactivate().err(),
        });
    }
    Ok(())
}
