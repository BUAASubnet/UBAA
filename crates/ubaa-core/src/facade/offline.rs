//! 独立本地缓存出口与明确绑定账号的在线读取，不持本地事务等待网络。
use super::{RoutedError, UbaaClient};
use crate::cache::{
    CacheCompleteness, CacheError, CacheKey, CacheLimits, CachePayload, CacheQuery,
    CacheReadTicket, CacheRecord, CacheResult, CacheScope, OfflineRepository,
};
use crate::connection::RouteResolution;
use crate::domain::{ConnectionMode, ReadonlyFeature, TodayClass, UserProfile};
use std::{
    path::Path,
    sync::{Arc, Mutex},
};

/// 与网络客户端锁独立的账号缓存句柄。格式化不会泄露账号或材料。
#[derive(Clone)]
pub struct OfflineCache {
    repository: Arc<Mutex<OfflineRepository>>,
    expected_identity: Arc<str>,
}
impl OfflineCache {
    /// 打开已由安全账号索引确认归属的私有缓存。
    ///
    /// # Errors
    /// 账号、私有存储或密钥无效时返回稳定缓存错误。
    pub fn open(
        root: &Path,
        account_id: &str,
        expected_identity: &str,
        key: CacheKey,
        limits: CacheLimits,
    ) -> CacheResult<Self> {
        if expected_identity.trim().is_empty() || expected_identity.len() > 128 {
            return Err(CacheError::InvalidInput);
        }
        Ok(Self {
            repository: Arc::new(Mutex::new(OfflineRepository::open(
                root, account_id, key, limits,
            )?)),
            expected_identity: Arc::from(expected_identity.trim()),
        })
    }
    /// 本地精确范围读取，不校验网络认证也不获取客户端锁。
    ///
    /// # Errors
    /// 账号已关闭、记录损坏或存储不可用时返回错误。
    pub fn read(&self, scope: &CacheScope, now: i64) -> CacheResult<Option<CacheRecord>> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .read(scope, now)
    }
    /// 只读取当前上海日历日期的已保存课表。
    ///
    /// # Errors
    /// 继承本地仓库的稳定错误，不回退到昨日内容。
    pub fn read_today(&self, route: ConnectionMode) -> CacheResult<Option<CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: CacheQuery::ScheduleToday {
                    date: crate::features::schedule::shanghai_date(),
                },
            },
            chrono::Utc::now().timestamp(),
        )
    }
    /// 精确读取希冀摘要范围，不获取网络客户端锁。
    ///
    /// # Errors
    /// 账号关闭、记录损坏或存储不可用时返回稳定错误。
    pub fn read_judge(
        &self,
        route: ConnectionMode,
        include_expired: bool,
    ) -> CacheResult<Option<CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: CacheQuery::JudgeSummaries { include_expired },
            },
            chrono::Utc::now().timestamp(),
        )
    }
    /// 先关闭缓存，再执行学校注销；阻止已发送读取回写。
    ///
    /// # Errors
    /// 持久栅栏失败时不能宣称退出成功。
    pub fn deactivate(&self) -> CacheResult<()> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .deactivate()
    }
    /// 显式重新登录且确认身份后重新开放内容，不恢复旧 ticket。
    ///
    /// # Errors
    /// 存储不可用时返回错误。
    pub fn activate(&self) -> CacheResult<()> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .activate()
    }
    /// 清理内容与在途 ticket，保持账号是否已关闭的状态。
    ///
    /// # Errors
    /// 存储失败时返回错误，原事务回滚。
    pub fn clear(&self) -> CacheResult<()> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .clear()
    }
    pub(super) fn repository<T>(
        &self,
        operation: impl FnOnce(&mut OfflineRepository) -> CacheResult<T>,
    ) -> CacheResult<T> {
        let mut repository = self
            .repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?;
        operation(&mut repository)
    }
    pub(super) fn fail_scan(&self, parent: &CacheReadTicket, child: Option<&CacheReadTicket>) {
        let now = chrono::Utc::now().timestamp();
        let _ = self.repository(|repository| {
            if let Some(child) = child {
                let _ = repository.record_failure_guarded(child, parent, now);
            }
            repository.record_failure(parent, now)
        });
    }
    pub(super) fn matches(&self, profile: &UserProfile) -> bool {
        [profile.username.as_deref(), profile.school_id.as_deref()]
            .into_iter()
            .flatten()
            .any(|value| value.trim() == self.expected_identity.as_ref())
    }
    pub(super) fn validate_read(&self, ticket: &CacheReadTicket) -> CacheResult<()> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .validate_read(ticket)
    }
    pub(super) fn begin(&self, scope: CacheScope) -> CacheResult<CacheReadTicket> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .begin_read(scope)
    }
    fn publish(
        &self,
        ticket: &CacheReadTicket,
        payload: CachePayload,
        now: i64,
    ) -> CacheResult<()> {
        self.repository
            .lock()
            .map_err(|_| CacheError::Unavailable)?
            .publish(ticket, payload, now, CacheCompleteness::Complete)
            .map(|_| ())
    }
    fn failure(&self, ticket: &CacheReadTicket, now: i64) {
        if let Ok(mut repository) = self.repository.lock() {
            let _ = repository.record_failure(ticket, now);
        }
    }
}

/// 在线内容与本地保存状态独立，保存失败不伪装成学校查询失败。
#[derive(Debug)]
pub struct OfflineRefresh<T> {
    pub data: T,
    pub resolution: RouteResolution,
    pub scope: CacheScope,
    pub fetched_at: i64,
    pub save_error: Option<CacheError>,
}

/// 缓存身份和磁盘错误不混入原学校错误分类，旧 CLI 合同保持不变。
#[derive(Debug)]
pub enum OfflineReadError {
    Read(RoutedError),
    Cache(CacheError),
    IdentityMismatch {
        resolution: RouteResolution,
        cache_error: Option<CacheError>,
    },
}

impl UbaaClient {
    /// 保存希冀聚合摘要；包含过期项与默认筛选使用不同的持久范围。
    ///
    /// # Errors
    /// 原聚合错误、身份不符或已关闭的本机账号会阻止本次替换。
    pub async fn refresh_cached_judge(
        &mut self,
        cache: &OfflineCache,
        include_expired: bool,
    ) -> Result<OfflineRefresh<Vec<crate::domain::JudgeAssignmentSummary>>, OfflineReadError> {
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Judge)
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = authenticated.resolution;
        if !cache.matches(&authenticated.data.user) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.deactivate().err(),
            });
        }
        let scope = CacheScope {
            route: resolution.mode,
            query: CacheQuery::JudgeSummaries { include_expired },
        };
        let (ticket, mut save_error) = match cache.begin(scope.clone()) {
            Ok(ticket) => (Some(ticket), None),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                return Err(OfflineReadError::Cache(error));
            }
            Err(error) => (None, Some(error)),
        };
        let read = crate::features::judge::get_assignments(
            self.runtime_for(resolution.mode),
            include_expired,
        )
        .await;
        let fetched_at = chrono::Utc::now().timestamp();
        match self.finish_routed(resolution, read) {
            Ok(result) => {
                if let Some(ticket) = &ticket {
                    save_error = cache
                        .publish(
                            ticket,
                            CachePayload::JudgeSummaries(result.data.clone()),
                            fetched_at,
                        )
                        .err();
                }
                Ok(OfflineRefresh {
                    data: result.data,
                    resolution,
                    scope,
                    fetched_at,
                    save_error,
                })
            }
            Err(error) => {
                if let Some(ticket) = &ticket {
                    cache.failure(ticket, fetched_at);
                }
                Err(OfflineReadError::Read(error))
            }
        }
    }

    /// 保存今日课表；同一次捕获的日期同时用于精确请求和缓存键。
    ///
    /// # Errors
    /// 原读取错误、账号不匹配或本机账号已关闭时返回明确分类。
    pub async fn refresh_cached_today(
        &mut self,
        cache: &OfflineCache,
    ) -> Result<OfflineRefresh<Vec<TodayClass>>, OfflineReadError> {
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Schedule)
            .await
            .map_err(OfflineReadError::Read)?;
        let resolution = authenticated.resolution;
        if !cache.matches(&authenticated.data.user) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.deactivate().err(),
            });
        }
        let date = crate::features::schedule::shanghai_date();
        let scope = CacheScope {
            route: resolution.mode,
            query: CacheQuery::ScheduleToday { date: date.clone() },
        };
        let (ticket, mut save_error) = match cache.begin(scope.clone()) {
            Ok(ticket) => (Some(ticket), None),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                return Err(OfflineReadError::Cache(error));
            }
            Err(error) => (None, Some(error)),
        };
        let read =
            crate::features::schedule::get_today_for_date(self.runtime_for(resolution.mode), &date)
                .await;
        let fetched_at = chrono::Utc::now().timestamp();
        let result = self.finish_routed(resolution, read);
        match result {
            Ok(result) => {
                if let Some(ticket) = &ticket {
                    save_error = cache
                        .publish(ticket, CachePayload::Today(result.data.clone()), fetched_at)
                        .err();
                }
                Ok(OfflineRefresh {
                    data: result.data,
                    resolution,
                    scope,
                    fetched_at,
                    save_error,
                })
            }
            Err(error) => {
                if let Some(ticket) = &ticket {
                    cache.failure(ticket, fetched_at);
                }
                Err(OfflineReadError::Read(error))
            }
        }
    }
}
