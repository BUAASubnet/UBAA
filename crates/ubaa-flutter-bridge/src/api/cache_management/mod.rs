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
                report: BridgeCacheClearReport {
                    usage: report.usage.map(map_usage),
                    compacted: report.compacted,
                    maintenance_error: report.maintenance_error.map(Into::into),
                },
            })
        })
        .await
    }
}
#[cfg(test)]
mod tests {
    use crate::api::{client::*, offline::BridgeOfflineCache};
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
