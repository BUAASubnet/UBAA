//! 平台安全索引捕获的撤销版本，不含凭据或学校身份。
use super::{
    agenda::BridgeAgendaStore,
    client::{BridgeClient, BridgeError},
    offline::BridgeOfflineCache,
};
use std::path::Path;
use ubaa_core::facade as core;

pub(crate) struct LogoutRestore<'a> {
    pub(crate) client: &'a mut core::UbaaClient,
    pub(crate) previous: Option<core::SharedAccountGuard>,
}
impl Drop for LogoutRestore<'_> {
    fn drop(&mut self) {
        self.client.bind_shared_account(self.previous.take());
    }
}

pub struct BridgeSharedAccount {
    pub(crate) guard: core::SharedAccountGuard,
}
impl BridgeSharedAccount {
    /// 只绑定固定本机版本，任何后续检查失败后永久失效。
    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub fn capture(directory: String, generation: u64) -> Result<Self, BridgeError> {
        Ok(Self {
            guard: core::SharedAccountGuard::new(&std::path::PathBuf::from(directory), generation)
                .map_err(|error| BridgeError::from_core(error, None))?,
        })
    }
}
impl BridgeClient {
    /// 仅在此退出调用内使用条件撤销票据，结束后恢复旧归属，不能继承为普通写资格。
    ///
    /// # Errors
    /// 票据已被另一登录取代、客户端已关闭或本地退出失败时返回稳定错误。
    pub async fn logout_with_shared_account(
        &self,
        scope: &BridgeSharedAccount,
    ) -> Result<(), BridgeError> {
        use futures_util::FutureExt;
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(super::client::disposed_error());
        }
        let mut inner = self.inner.lock().await;
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(super::client::disposed_error());
        }
        self.inner.clear_readers().await;
        self.write_intents.lock().await.clear();
        let client = inner.as_mut().ok_or_else(super::client::disposed_error)?;
        let previous = client.shared_account_guard();
        client.bind_shared_account(Some(scope.guard.clone()));
        let restore = LogoutRestore { client, previous };
        let result = std::panic::AssertUnwindSafe(restore.client.logout())
            .catch_unwind()
            .await;
        match result {
            Ok(result) => result.map_err(|error| BridgeError::from_core(error, None)),
            Err(_) => Err(super::client::panic_error()),
        }
    }

    /// 仅供显式登录开始使用，先丢弃旧写意图与派生读取。
    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub async fn release_shared_account_for_login(&self) -> Result<(), BridgeError> {
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(super::client::disposed_error());
        }
        let mut inner = self.inner.lock().await;
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(super::client::disposed_error());
        }
        inner
            .as_mut()
            .ok_or_else(super::client::disposed_error)?
            .bind_shared_account(None);
        self.inner.clear_readers().await;
        self.write_intents.lock().await.clear();
        Ok(())
    }

    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub async fn bind_shared_account(
        &self,
        scope: &BridgeSharedAccount,
    ) -> Result<(), BridgeError> {
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(super::client::disposed_error());
        }
        let mut inner = self.inner.lock().await;
        if self.is_disposed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(super::client::disposed_error());
        }
        inner
            .as_mut()
            .ok_or_else(super::client::disposed_error)?
            .bind_shared_account(Some(scope.guard.clone()));
        self.inner.clear_readers().await;
        self.write_intents.lock().await.clear();
        Ok(())
    }
}
impl BridgeAgendaStore {
    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub async fn open_shared(
        config_dir: String,
        account_id: String,
        scope: &BridgeSharedAccount,
    ) -> Result<Self, super::agenda::models::BridgeAgendaError> {
        let guard = scope.guard.clone();
        tokio::task::spawn_blocking(move || {
            core::AgendaStore::open_shared(Path::new(&config_dir), &account_id, guard)
                .map(|store| Self { store })
                .map_err(super::agenda::convert::error)
        })
        .await
        .map_err(|_| super::agenda::convert::error(core::CacheError::Unavailable))?
    }

    #[must_use]
    pub fn with_shared_account(&self, scope: &BridgeSharedAccount) -> Self {
        Self {
            store: self.store.clone().with_shared_account(scope.guard.clone()),
        }
    }
}
impl BridgeOfflineCache {
    /// 仅释放本进程仓库，等待已交付事务收尾，不停用共享库。
    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub async fn close(&self) -> Result<(), BridgeError> {
        let cache = self.cache.clone();
        super::offline::local_task(move || cache.close().map_err(super::offline::cache_error)).await
    }

    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub async fn open_shared(
        config_dir: String,
        account_id: String,
        expected_identity: String,
        mut key: Vec<u8>,
        scope: &BridgeSharedAccount,
    ) -> Result<Self, BridgeError> {
        let guard = scope.guard.clone();
        super::offline::local_task(move || {
            let bytes = <[u8; 32]>::try_from(key.as_slice());
            key.fill(0);
            let bytes =
                bytes.map_err(|_| super::offline::cache_error(core::CacheError::InvalidInput))?;
            core::OfflineCache::open_shared(
                Path::new(&config_dir),
                &account_id,
                &expected_identity,
                core::CacheKey::new(bytes),
                core::CacheLimits::default(),
                guard,
            )
            .map(|cache| Self { cache })
            .map_err(super::offline::cache_error)
        })
        .await
    }
    ///
    /// # Errors
    /// 身份版本已撤销、输入非法或本地存储不可用时返回稳定错误。
    pub async fn clear_or_rebuild_shared(
        config_dir: String,
        account_id: String,
        expected_identity: String,
        mut key: Vec<u8>,
        scope: &BridgeSharedAccount,
    ) -> Result<super::cache_management::BridgeCacheRecovery, BridgeError> {
        let guard = scope.guard.clone();
        super::offline::local_task(move || {
            let bytes = <[u8; 32]>::try_from(key.as_slice());
            key.fill(0);
            let bytes =
                bytes.map_err(|_| super::offline::cache_error(core::CacheError::InvalidInput))?;
            let (cache, report) = core::OfflineCache::clear_or_rebuild_shared(
                Path::new(&config_dir),
                &account_id,
                &expected_identity,
                core::CacheKey::new(bytes),
                core::CacheLimits::default(),
                guard,
            )
            .map_err(super::offline::cache_error)?;
            Ok(super::cache_management::BridgeCacheRecovery {
                cache: cache.map(|cache| Self { cache }),
                report: super::cache_management::map_report(&report),
            })
        })
        .await
    }

    #[must_use]
    pub fn with_shared_account(&self, scope: &BridgeSharedAccount) -> Self {
        Self {
            cache: self.cache.clone().with_shared_account(scope.guard.clone()),
        }
    }
}

#[cfg(test)]
mod tests;
