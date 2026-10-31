//! 门户资料、校园账户指标与网费流量的类型化只读绑定。
#![allow(clippy::missing_errors_doc)]
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeRouteDecision,
    catch_panic, disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use ubaa_core::facade as domain;

/// 门户身份与学院，仅用于资料展示。
#[derive(Clone, Debug)]
pub struct BridgePortalProfile {
    pub identity: String,
    pub department: String,
    pub fetched_at: i64,
}
impl From<domain::PortalProfile> for BridgePortalProfile {
    fn from(v: domain::PortalProfile) -> Self {
        Self {
            identity: v.identity,
            department: v.department,
            fetched_at: v.fetched_at,
        }
    }
}

/// 上游十进制字符串与原始单位，不换算。
#[derive(Clone, Debug)]
pub struct BridgeCampusAmount {
    pub value: String,
    pub unit: String,
}
impl From<domain::CampusAmount> for BridgeCampusAmount {
    fn from(v: domain::CampusAmount) -> Self {
        Self {
            value: v.value,
            unit: v.unit,
        }
    }
}

/// 单项失败只公开安全分类与消息，不含原始上游响应。
#[derive(Clone, Debug)]
pub struct BridgeCampusMetricFailure {
    pub code: BridgeErrorCode,
    pub message: String,
}
impl From<domain::UbaaError> for BridgeCampusMetricFailure {
    fn from(v: domain::UbaaError) -> Self {
        Self {
            code: v.code.into(),
            message: v.message,
        }
    }
}

/// 金额或容量指标；`value` 与 `failure` 恰有一个存在。
#[derive(Clone, Debug)]
pub struct BridgeCampusAmountMetric {
    pub value: Option<BridgeCampusAmount>,
    pub failure: Option<BridgeCampusMetricFailure>,
    pub fetched_at: i64,
}
impl From<domain::CampusMetric<domain::CampusAmount>> for BridgeCampusAmountMetric {
    fn from(v: domain::CampusMetric<domain::CampusAmount>) -> Self {
        match v {
            domain::CampusMetric::Success { value, fetched_at } => Self {
                value: Some(value.into()),
                failure: None,
                fetched_at,
            },
            domain::CampusMetric::Failure { error, fetched_at } => Self {
                value: None,
                failure: Some(error.into()),
                fetched_at,
            },
        }
    }
}

/// 计数指标；`value` 与 `failure` 恰有一个存在。
#[derive(Clone, Debug)]
pub struct BridgeCampusCountMetric {
    pub value: Option<i64>,
    pub failure: Option<BridgeCampusMetricFailure>,
    pub fetched_at: i64,
}
impl From<domain::CampusMetric<u64>> for BridgeCampusCountMetric {
    fn from(v: domain::CampusMetric<u64>) -> Self {
        match v {
            domain::CampusMetric::Success { value, fetched_at } => match i64::try_from(value) {
                Ok(count) => Self {
                    value: Some(count),
                    failure: None,
                    fetched_at,
                },
                // 超出 Dart 整数范围的计数视为协议异常，不截断显示。
                Err(_) => Self {
                    value: None,
                    failure: Some(BridgeCampusMetricFailure {
                        code: BridgeErrorCode::ParseError,
                        message: "数值超出可显示范围".to_owned(),
                    }),
                    fetched_at,
                },
            },
            domain::CampusMetric::Failure { error, fetched_at } => Self {
                value: None,
                failure: Some(error.into()),
                fetched_at,
            },
        }
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCampusMetrics {
    pub network_balance: BridgeCampusAmountMetric,
    pub card_balance: BridgeCampusAmountMetric,
    pub unread_mail: BridgeCampusCountMetric,
    pub borrowed_books: BridgeCampusCountMetric,
    pub cloud_storage_remaining: BridgeCampusAmountMetric,
}
impl From<domain::CampusMetrics> for BridgeCampusMetrics {
    fn from(v: domain::CampusMetrics) -> Self {
        Self {
            network_balance: v.network_balance.into(),
            card_balance: v.card_balance.into(),
            unread_mail: v.unread_mail.into(),
            borrowed_books: v.borrowed_books.into(),
            cloud_storage_remaining: v.cloud_storage_remaining.into(),
        }
    }
}

/// 一个网络产品的流量；两项剩余均不含套餐。
#[derive(Clone, Debug)]
pub struct BridgeNetworkProductUsage {
    pub product_name: String,
    pub used: BridgeCampusAmount,
    pub free_remaining: BridgeCampusAmount,
    pub billable_remaining: BridgeCampusAmount,
}
impl From<domain::NetworkProductUsage> for BridgeNetworkProductUsage {
    fn from(v: domain::NetworkProductUsage) -> Self {
        Self {
            product_name: v.product_name,
            used: v.used.into(),
            free_remaining: v.free_remaining.into(),
            billable_remaining: v.billable_remaining.into(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct BridgeNetworkUsage {
    pub products: Vec<BridgeNetworkProductUsage>,
    pub remaining_excludes_packages: bool,
    pub fetched_at: i64,
}
impl From<domain::NetworkUsage> for BridgeNetworkUsage {
    fn from(v: domain::NetworkUsage) -> Self {
        Self {
            products: v.products.into_iter().map(Into::into).collect(),
            remaining_excludes_packages: v.remaining_excludes_packages,
            fetched_at: v.fetched_at,
        }
    }
}

#[derive(Clone, Debug)]
pub struct BridgePortalProfileResult {
    pub data: BridgePortalProfile,
    pub route: BridgeRouteDecision,
}
#[derive(Clone, Debug)]
pub struct BridgeCampusMetricsResult {
    pub data: BridgeCampusMetrics,
    pub route: BridgeRouteDecision,
}
#[derive(Clone, Debug)]
pub struct BridgeNetworkUsageResult {
    pub data: BridgeNetworkUsage,
    pub route: BridgeRouteDecision,
}

impl BridgeClient {
    /// 在线读取门户身份与学院，不写业务缓存。
    pub async fn portal_profile(&self) -> Result<BridgePortalProfileResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .portal_profile()
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgePortalProfileResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }

    /// 在线读取五项校园账户指标；单项失败保留在对应项中。
    pub async fn campus_metrics(&self) -> Result<BridgeCampusMetricsResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .campus_metrics()
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeCampusMetricsResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }

    /// 在线读取网络产品流量，保留原始单位。
    pub async fn network_usage(&self) -> Result<BridgeNetworkUsageResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .network_usage()
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeNetworkUsageResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
}

/// 本地快照的一项：快照中缺失的项既无值也无失败，表示尚未取得。
fn cached_amount(
    item: Option<domain::CachedCampusItem<domain::CampusAmount>>,
) -> BridgeCampusAmountMetric {
    match item {
        Some(item) => BridgeCampusAmountMetric {
            value: Some(item.value.into()),
            failure: None,
            fetched_at: item.fetched_at,
        },
        None => BridgeCampusAmountMetric {
            value: None,
            failure: None,
            fetched_at: 0,
        },
    }
}

fn cached_count(item: Option<domain::CachedCampusItem<u64>>) -> BridgeCampusCountMetric {
    match item {
        Some(item) => BridgeCampusCountMetric::from(domain::CampusMetric::Success {
            value: item.value,
            fetched_at: item.fetched_at,
        }),
        None => BridgeCampusCountMetric {
            value: None,
            failure: None,
            fetched_at: 0,
        },
    }
}

impl From<domain::CachedCampusMetrics> for BridgeCampusMetrics {
    fn from(v: domain::CachedCampusMetrics) -> Self {
        Self {
            network_balance: cached_amount(v.network_balance),
            card_balance: cached_amount(v.card_balance),
            unread_mail: cached_count(v.unread_mail),
            borrowed_books: cached_count(v.borrowed_books),
            cloud_storage_remaining: cached_amount(v.cloud_storage_remaining),
        }
    }
}

/// 在线指标与合并快照的展示投影：本次成功取在线值，本次失败但有旧值时显示旧值。
fn merged_metrics(
    online: domain::CampusMetrics,
    snapshot: domain::CachedCampusMetrics,
) -> BridgeCampusMetrics {
    fn amount(
        online: domain::CampusMetric<domain::CampusAmount>,
        cached: Option<domain::CachedCampusItem<domain::CampusAmount>>,
    ) -> BridgeCampusAmountMetric {
        match (&online, cached) {
            (domain::CampusMetric::Failure { .. }, Some(item)) => cached_amount(Some(item)),
            _ => online.into(),
        }
    }
    fn count(
        online: domain::CampusMetric<u64>,
        cached: Option<domain::CachedCampusItem<u64>>,
    ) -> BridgeCampusCountMetric {
        match (&online, cached) {
            (domain::CampusMetric::Failure { .. }, Some(item)) => cached_count(Some(item)),
            _ => online.into(),
        }
    }
    BridgeCampusMetrics {
        network_balance: amount(online.network_balance, snapshot.network_balance),
        card_balance: amount(online.card_balance, snapshot.card_balance),
        unread_mail: count(online.unread_mail, snapshot.unread_mail),
        borrowed_books: count(online.borrowed_books, snapshot.borrowed_books),
        cloud_storage_remaining: amount(
            online.cloud_storage_remaining,
            snapshot.cloud_storage_remaining,
        ),
    }
}

/// “我的”页三组数据之一的本地快照或在线刷新结果；恰有一个字段存在，与查询范围对应。
#[derive(Clone, Debug)]
pub struct BridgeCampusSection {
    pub profile: Option<BridgePortalProfile>,
    pub metrics: Option<BridgeCampusMetrics>,
    pub network_usage: Option<BridgeNetworkUsage>,
}
impl BridgeCampusSection {
    fn profile(v: BridgePortalProfile) -> Self {
        Self {
            profile: Some(v),
            metrics: None,
            network_usage: None,
        }
    }
    fn metrics(v: BridgeCampusMetrics) -> Self {
        Self {
            profile: None,
            metrics: Some(v),
            network_usage: None,
        }
    }
    fn network_usage(v: BridgeNetworkUsage) -> Self {
        Self {
            profile: None,
            metrics: None,
            network_usage: Some(v),
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub enum BridgeCampusCacheQuery {
    Profile,
    Metrics,
    NetworkUsage,
}
impl From<BridgeCampusCacheQuery> for domain::CampusCacheQuery {
    fn from(v: BridgeCampusCacheQuery) -> Self {
        match v {
            BridgeCampusCacheQuery::Profile => Self::Profile,
            BridgeCampusCacheQuery::Metrics => Self::Metrics,
            BridgeCampusCacheQuery::NetworkUsage => Self::NetworkUsage,
        }
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedCampusSection {
    pub data: BridgeCampusSection,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
}

#[derive(Clone, Debug)]
pub struct BridgeCampusRefresh {
    pub data: BridgeCampusSection,
    pub route: BridgeRouteDecision,
    pub fetched_at: i64,
    pub saved_for_offline: bool,
    pub save_error: Option<BridgeCacheFailure>,
}

impl BridgeOfflineCache {
    /// 读取本地快照，不等待网络锁；没有记录时返回 None。
    ///
    /// # Errors
    /// 账号关闭或存储损坏返回稳定错误。
    pub async fn read_campus(
        &self,
        route: BridgeConnectionMode,
        query: BridgeCampusCacheQuery,
    ) -> Result<Option<BridgeCachedCampusSection>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_campus(route.into(), query.into())
                .map_err(cache_error)?
                .map(|record| {
                    let data = match (query, record.payload) {
                        (
                            BridgeCampusCacheQuery::Profile,
                            domain::CachePayload::CampusProfile(v),
                        ) => BridgeCampusSection::profile(v.into()),
                        (
                            BridgeCampusCacheQuery::Metrics,
                            domain::CachePayload::CampusMetrics(v),
                        ) => BridgeCampusSection::metrics(v.into()),
                        (
                            BridgeCampusCacheQuery::NetworkUsage,
                            domain::CachePayload::NetworkUsage(v),
                        ) => BridgeCampusSection::network_usage(v.into()),
                        _ => return Err(cache_error(domain::CacheError::Corrupt)),
                    };
                    Ok(BridgeCachedCampusSection {
                        data,
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                    })
                })
                .transpose()
        })
        .await
    }
}

impl BridgeClient {
    /// 在线读取并保存快照；保存失败只在结果中报告，不影响在线数据。
    ///
    /// # Errors
    /// 原认证/业务与账号/退出屏障保持。
    pub async fn campus_cached(
        &self,
        cache: &BridgeOfflineCache,
        query: BridgeCampusCacheQuery,
    ) -> Result<BridgeCampusRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .refresh_cached_campus(&cache.cache, query.into())
                .await
                .map_err(offline_read_error)?;
            let data = match value.result.data {
                domain::CampusReadData::Profile(v) => BridgeCampusSection::profile(v.into()),
                domain::CampusReadData::Metrics(read) => {
                    let read = *read;
                    BridgeCampusSection::metrics(merged_metrics(read.online, read.snapshot))
                }
                domain::CampusReadData::NetworkUsage(v) => {
                    BridgeCampusSection::network_usage(v.into())
                }
            };
            Ok(BridgeCampusRefresh {
                data,
                route: map_route(value.result.resolution),
                fetched_at: value.result.fetched_at,
                saved_for_offline: value.result.save_error.is_none() && value.publication.is_some(),
                save_error: value.result.save_error.map(Into::into),
            })
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn amount(value: &str) -> domain::CampusAmount {
        domain::CampusAmount {
            value: value.to_owned(),
            unit: "元".to_owned(),
        }
    }

    #[test]
    fn metrics_keep_success_and_failure_per_item() {
        let failure = domain::UbaaError::new(
            domain::ErrorCode::UpstreamUnavailable,
            domain::ErrorKind::Upstream,
            true,
            "网费余额暂不可用",
        );
        let metrics = BridgeCampusMetrics::from(domain::CampusMetrics {
            network_balance: domain::CampusMetric::Failure {
                error: failure,
                fetched_at: 2,
            },
            card_balance: domain::CampusMetric::Success {
                value: amount("0"),
                fetched_at: 1,
            },
            unread_mail: domain::CampusMetric::Success {
                value: 3,
                fetched_at: 3,
            },
            borrowed_books: domain::CampusMetric::Success {
                value: u64::MAX,
                fetched_at: 4,
            },
            cloud_storage_remaining: domain::CampusMetric::Success {
                value: amount("48.6"),
                fetched_at: 5,
            },
        });

        assert!(metrics.network_balance.value.is_none());
        let network = metrics.network_balance.failure.expect("网费余额应失败");
        assert_eq!(network.code, BridgeErrorCode::UpstreamUnavailable);
        assert_eq!(network.message, "网费余额暂不可用");
        assert_eq!(metrics.network_balance.fetched_at, 2);
        // 有效零值不能被当成缺失。
        assert_eq!(
            metrics.card_balance.value.expect("校园卡余额应成功").value,
            "0"
        );
        assert_eq!(metrics.unread_mail.value, Some(3));
        // 超出 Dart 范围的计数转为失败，不截断。
        assert!(metrics.borrowed_books.value.is_none());
        assert_eq!(
            metrics.borrowed_books.failure.expect("越界计数应失败").code,
            BridgeErrorCode::ParseError
        );
    }

    #[test]
    fn network_usage_keeps_products_and_units() {
        let usage = BridgeNetworkUsage::from(domain::NetworkUsage {
            products: vec![domain::NetworkProductUsage {
                product_name: "学生校园网".to_owned(),
                used: domain::CampusAmount {
                    value: "36.42".to_owned(),
                    unit: "G".to_owned(),
                },
                free_remaining: domain::CampusAmount {
                    value: "13.58".to_owned(),
                    unit: "G".to_owned(),
                },
                billable_remaining: domain::CampusAmount {
                    value: "0".to_owned(),
                    unit: "M".to_owned(),
                },
            }],
            remaining_excludes_packages: true,
            fetched_at: 7,
        });
        assert_eq!(usage.products.len(), 1);
        assert_eq!(usage.products[0].billable_remaining.unit, "M");
        assert!(usage.remaining_excludes_packages);
        assert_eq!(usage.fetched_at, 7);
    }

    #[test]
    fn 本次失败的项显示上次成功值且没有旧值时保留失败() {
        fn failure<T>() -> domain::CampusMetric<T> {
            domain::CampusMetric::Failure {
                error: domain::UbaaError::new(
                    domain::ErrorCode::UpstreamUnavailable,
                    domain::ErrorKind::Upstream,
                    true,
                    "合成失败",
                ),
                fetched_at: 20,
            }
        }
        let online = domain::CampusMetrics {
            network_balance: failure(),
            card_balance: domain::CampusMetric::Success {
                value: amount("6.17"),
                fetched_at: 20,
            },
            unread_mail: failure(),
            borrowed_books: domain::CampusMetric::Success {
                value: 0,
                fetched_at: 20,
            },
            cloud_storage_remaining: failure(),
        };
        let snapshot = domain::CachedCampusMetrics {
            network_balance: Some(domain::CachedCampusItem {
                value: amount("10.66"),
                fetched_at: 10,
            }),
            unread_mail: Some(domain::CachedCampusItem {
                value: 11,
                fetched_at: 10,
            }),
            ..Default::default()
        };
        let merged = merged_metrics(online, snapshot);
        let fee = merged.network_balance.value.expect("网费显示旧值");
        assert_eq!(fee.value, "10.66");
        assert_eq!(merged.network_balance.fetched_at, 10);
        assert!(merged.network_balance.failure.is_none());
        assert_eq!(merged.unread_mail.value, Some(11));
        assert_eq!(merged.card_balance.fetched_at, 20);
        assert!(merged.cloud_storage_remaining.value.is_none());
        assert!(merged.cloud_storage_remaining.failure.is_some());
    }

    #[tokio::test]
    async fn 本地快照独立网络锁且范围类型隔离() {
        let root = std::env::temp_dir().join(format!("ubaa-campus-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repo = domain::OfflineRepository::open(
            &root,
            account,
            domain::CacheKey::new([9; 32]),
            domain::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repo
            .begin_read(domain::CacheScope {
                route: domain::ConnectionMode::Direct,
                query: domain::CacheQuery::CampusMetrics,
            })
            .unwrap();
        repo.publish(
            &ticket,
            domain::CachePayload::CampusMetrics(domain::CachedCampusMetrics {
                unread_mail: Some(domain::CachedCampusItem {
                    value: 0,
                    fetched_at: 100,
                }),
                ..Default::default()
            }),
            100,
            domain::CacheCompleteness::Partial,
        )
        .unwrap();
        drop(repo);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic-user".into(),
            vec![9; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let value = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_campus(
                BridgeConnectionMode::Direct,
                BridgeCampusCacheQuery::Metrics,
            ),
        )
        .await
        .unwrap()
        .unwrap()
        .expect("应读到指标快照");
        drop(guard);
        let metrics = value.data.metrics.expect("类型不符");
        // 有效零值保留；缺失项既无值也无失败。
        assert_eq!(metrics.unread_mail.value, Some(0));
        assert!(metrics.card_balance.value.is_none());
        assert!(metrics.card_balance.failure.is_none());
        assert_eq!(value.fetched_at, 100);
        for (route, query) in [
            (
                BridgeConnectionMode::WebVpn,
                BridgeCampusCacheQuery::Metrics,
            ),
            (
                BridgeConnectionMode::Direct,
                BridgeCampusCacheQuery::Profile,
            ),
        ] {
            assert!(cache.read_campus(route, query).await.unwrap().is_none());
        }
        let _ = std::fs::remove_dir_all(root);
    }
}
