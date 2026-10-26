//! 缓存管理只处理本地数值与句柄，不获取学校客户端锁。
use super::client::BridgeError;
use super::offline::{BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task};
use ubaa_core::facade as core;
#[derive(Clone, Debug)]
pub struct BridgeCacheUsage {
    pub entry_count: u64,
    pub content_bytes: u64,
    pub database_bytes: u64,
    pub reusable_bytes: u64,
    pub soft_limit_bytes: u64,
    pub hard_limit_bytes: u64,
}
#[derive(Clone, Debug)]
pub struct BridgeCacheClearReport {
    pub usage: Option<BridgeCacheUsage>,
    pub compacted: bool,
    pub maintenance_error: Option<BridgeCacheFailure>,
}
#[flutter_rust_bridge::frb(non_opaque)]
pub struct BridgeCacheReset {
    pub cache: BridgeOfflineCache,
    pub report: BridgeCacheClearReport,
}
#[flutter_rust_bridge::frb(non_opaque)]
pub struct BridgeCacheRecovery {
    pub cache: Option<BridgeOfflineCache>,
    pub report: BridgeCacheClearReport,
}
fn map_report(report: &core::CacheClearReport) -> BridgeCacheClearReport {
    BridgeCacheClearReport {
        usage: report.usage.map(map_usage),
        compacted: report.compacted,
        maintenance_error: report.maintenance_error.map(Into::into),
    }
}
fn map_usage(value: core::CacheUsage) -> BridgeCacheUsage {
    BridgeCacheUsage {
        entry_count: value.entry_count,
        content_bytes: value.content_bytes,
        database_bytes: value.database_bytes,
        reusable_bytes: value.reusable_bytes,
        soft_limit_bytes: value.soft_limit_bytes,
        hard_limit_bytes: value.hard_limit_bytes,
    }
}
impl BridgeOfflineCache {
    /// 仅供设置确认后的本机业务缓存清理，不自动调用、不获取网络锁。
    ///
    /// # Errors
    /// 清空前返回稳定错误；清空后的失败由空cache和report表达。
    pub async fn clear_or_rebuild(
        config_dir: String,
        account_id: String,
        expected_identity: String,
        mut key: Vec<u8>,
    ) -> Result<BridgeCacheRecovery, BridgeError> {
        local_task(move || {
            let bytes = <[u8; 32]>::try_from(key.as_slice());
            key.fill(0);
            let bytes = bytes.map_err(|_| cache_error(core::CacheError::InvalidInput))?;
            let (cache, report) = core::OfflineCache::clear_or_rebuild(
                std::path::Path::new(&config_dir),
                &account_id,
                &expected_identity,
                core::CacheKey::new(bytes),
                core::CacheLimits::default(),
            )
            .map_err(cache_error)?;
            Ok(BridgeCacheRecovery {
                cache: cache.map(|cache| BridgeOfflineCache { cache }),
                report: map_report(&report),
            })
        })
        .await
    }
    /// 仅返回当前账号的数值用量。
    ///
    /// # Errors
    /// 已退出、旧句柄和存储故障保持稳定错误。
    pub async fn usage(&self) -> Result<BridgeCacheUsage, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || cache.usage().map(map_usage).map_err(cache_error)).await
    }
    /// 清除事务成功后移交新句柄；旧句柄永久失效。
    ///
    /// # Errors
    /// 事务失败返回错误；提交后空间维护失败在 report 中单独报告。
    pub async fn clear_and_reopen(&self) -> Result<BridgeCacheReset, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            let (cache, report) = cache.clear_and_reopen().map_err(cache_error)?;
            Ok(BridgeCacheReset {
                cache: BridgeOfflineCache { cache },
                report: map_report(&report),
            })
        })
        .await
    }
}
#[cfg(test)]
mod tests {
    use crate::api::{client::*, offline::BridgeOfflineCache};
    #[tokio::test]
    async fn 显式重建使用本地通道且坏密钥长度不能触碰文件() {
        let root = std::env::temp_dir().join(format!("ubaa-cache-rebuild-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let old = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![8; 32],
        )
        .await
        .unwrap();
        let path = root
            .join("business-cache")
            .join(format!("{account}.sqlite"));
        std::fs::write(&path, b"synthetic-corrupt").unwrap();
        assert!(
            BridgeOfflineCache::clear_or_rebuild(
                root.to_string_lossy().into(),
                account.into(),
                "synthetic".into(),
                vec![8; 31]
            )
            .await
            .is_err()
        );
        assert_eq!(std::fs::read(&path).unwrap(), b"synthetic-corrupt");
        let guard = client.inner.lock().await;
        let value = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            BridgeOfflineCache::clear_or_rebuild(
                root.to_string_lossy().into(),
                account.into(),
                "synthetic".into(),
                vec![8; 32],
            ),
        )
        .await
        .unwrap()
        .unwrap();
        let recovered = value.cache.unwrap();
        assert!(value.report.maintenance_error.is_none());
        assert_eq!(recovered.usage().await.unwrap().entry_count, 0);
        assert!(old.usage().await.is_err());
        drop(guard);
        drop((client, old, recovered));
        std::fs::remove_dir_all(root).unwrap();
    }
    #[tokio::test]
    async fn 本地清理独立于网络锁并交付新句柄() {
        let root = std::env::temp_dir().join(format!("ubaa-cache-admin-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let old = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            "0123456789abcdef0123456789abcdef".into(),
            "synthetic".into(),
            vec![8; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let value = tokio::time::timeout(std::time::Duration::from_secs(1), old.clear_and_reopen())
            .await
            .unwrap()
            .unwrap();
        assert!(value.report.compacted);
        assert!(value.report.maintenance_error.is_none());
        assert_eq!(value.report.usage.unwrap().entry_count, 0);
        assert_eq!(
            old.usage().await.err().unwrap().code,
            BridgeErrorCode::OperationConflict
        );
        let usage = value.cache.usage().await.unwrap();
        assert_eq!(usage.content_bytes, 0);
        assert_eq!(usage.soft_limit_bytes, 50 * 1024 * 1024);
        assert_eq!(usage.hard_limit_bytes, 100 * 1024 * 1024);
        value.cache.deactivate().await.unwrap();
        assert_eq!(
            value.cache.clear_and_reopen().await.err().unwrap().code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(guard);
        drop(value.cache);
        drop(old);
        drop(client);
        let _ = std::fs::remove_dir_all(root);
    }
}
