//! 资料在线与离线使用相同展示字段，缓存不提供认证资格。
use super::{
    CacheError, CachePayload, CacheQuery, CacheScope, CachedDisplayProfile, ConnectionMode,
    OfflineCache, OfflineReadError, OfflineRefresh, UbaaClient, UserProfile,
};
impl OfflineCache {
    /// 优先读取展示资料；旧账号缓存保留遮罩资料直至在线更新。
    ///
    /// # Errors
    /// 本地损坏、账号关闭或存储失败按缓存错误返回。
    pub fn read_profile(
        &self,
        route: ConnectionMode,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        let current = self.read(
            &CacheScope {
                route,
                query: CacheQuery::DisplayProfile,
            },
            chrono::Utc::now().timestamp(),
        )?;
        if current.is_some() {
            return Ok(current);
        }
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
    /// 按默认 User 路线核对身份后取资料，将展示字段写入账号加密缓存。
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
        let mut scope = CacheScope {
            route: resolution.mode,
            query: CacheQuery::DisplayProfile,
        };
        let (mut ticket, mut save_error) = super::begin_refresh(cache, scope.clone())?;
        let (resolution, read) = crate::facade::routing::read_with_fallback!(self, resolution, {
            let (runtime, auth) = self.route_parts_for(resolution.mode);
            let mut clear_workflow = || auth.clear();
            crate::features::user::get_user_info(runtime, &mut clear_workflow).await
        });
        scope.route = resolution.mode;
        if let Some(ticket) = &mut ticket {
            ticket.set_source_route(resolution.mode);
        }
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
                CachePayload::DisplayProfile(CachedDisplayProfile::from_profile(&read.data));
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
