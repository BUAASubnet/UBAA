//! 本地缓存通道不获取网络客户端锁；在线保存仍由 Core facade 管理。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind, catch_panic,
    disposed_error, map_route,
};
use super::read::{
    BridgeJudgeAssignmentDetail, BridgeJudgeAssignmentSummary, BridgeRoutedJudgeSummaries,
    BridgeRoutedTodayClasses, BridgeTodayClass, map_judge_detail, map_judge_summaries,
};
use std::path::Path;
use ubaa_core::facade::{self as core, CachePayload, CacheQuery};

/// 不携带 Cookie、学校写意图或网络客户端的本地句柄。
pub struct BridgeOfflineCache {
    pub(super) cache: core::OfflineCache,
}

/// 本地缓存故障不表示学校读取失败。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeCacheFailure {
    Unavailable,
    InvalidInput,
    Corrupt,
    UnsupportedVersion,
    Inactive,
    Superseded,
    Capacity,
}

/// 磁盘中取得的不可写今日内容及原日期/来源。
#[derive(Clone, Debug)]
pub struct BridgeCachedToday {
    pub data: Vec<BridgeTodayClass>,
    pub source_route: BridgeConnectionMode,
    pub date: String,
    pub fetched_at: i64,
    pub complete: bool,
}

/// 在线查询和保存结果分别表达；未保存不能称为已可离线使用。
#[derive(Clone, Debug)]
pub struct BridgeTodayRefresh {
    pub result: BridgeRoutedTodayClasses,
    pub date: String,
    pub fetched_at: i64,
    pub save_error: Option<BridgeCacheFailure>,
}

/// 已保存的希冀待办摘要，筛选范围与取得时间均保留。
#[derive(Clone, Debug)]
pub struct BridgeCachedJudge {
    pub data: Vec<BridgeJudgeAssignmentSummary>,
    pub source_route: BridgeConnectionMode,
    pub include_expired: bool,
    pub fetched_at: i64,
    pub complete: bool,
}

/// 精确目标的离线详情，不带在线操作资格。
#[derive(Clone, Debug)]
pub struct BridgeCachedJudgeDetail {
    pub data: BridgeJudgeAssignmentDetail,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}

/// 在线希冀读取和本地保存分别记录。
#[derive(Clone, Debug)]
pub struct BridgeJudgeRefresh {
    pub result: BridgeRoutedJudgeSummaries,
    pub include_expired: bool,
    pub fetched_at: i64,
    pub save_error: Option<BridgeCacheFailure>,
}

impl BridgeOfflineCache {
    /// 从安全材料打开独立本地仓库，不创建第二个持久会话客户端。
    ///
    /// # Errors
    /// 密钥、账号或私有存储不可用时返回稳定错误。
    pub async fn open(
        config_dir: String,
        account_id: String,
        expected_identity: String,
        mut key: Vec<u8>,
    ) -> Result<Self, BridgeError> {
        local_task(move || {
            let bytes = <[u8; 32]>::try_from(key.as_slice());
            key.fill(0);
            let bytes = bytes.map_err(|_| cache_error(core::CacheError::InvalidInput))?;
            let cache = core::OfflineCache::open(
                Path::new(&config_dir),
                &account_id,
                &expected_identity,
                core::CacheKey::new(bytes),
                core::CacheLimits::default(),
            )
            .map_err(cache_error)?;
            Ok(Self { cache })
        })
        .await
    }
    /// 仅按指定来源读取校园今日缓存，不获取网络客户端锁。
    ///
    /// # Errors
    /// 已退出、损坏或存储不可用时返回稳定错误。
    pub async fn read_today(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedToday>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            let record = cache.read_today(route.into()).map_err(cache_error)?;
            record
                .map(|record| {
                    let CachePayload::Today(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    let CacheQuery::ScheduleToday { date } = record.scope.query else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedToday {
                        data: map_today(data),
                        source_route: record.scope.route.into(),
                        date,
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
    /// 读取精确路线与过期筛选范围内的希冀缓存。
    ///
    /// # Errors
    /// 账号关闭、载荷损坏或存储不可用时返回稳定错误。
    pub async fn read_judge(
        &self,
        route: BridgeConnectionMode,
        include_expired: bool,
    ) -> Result<Option<BridgeCachedJudge>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            let record = cache
                .read_judge(route.into(), include_expired)
                .map_err(cache_error)?;
            record
                .map(|record| {
                    let CachePayload::JudgeSummaries(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedJudge {
                        data: map_judge_summaries(data),
                        source_route: record.scope.route.into(),
                        include_expired,
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }

    /// 只读取明确课程和作业的已保存详情，不获取网络锁。
    ///
    /// # Errors
    /// 账号关闭、范围无效或损坏时返回稳定本地错误。
    pub async fn read_judge_detail(
        &self,
        route: BridgeConnectionMode,
        course_id: String,
        assignment_id: String,
    ) -> Result<Option<BridgeCachedJudgeDetail>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_judge_detail(route.into(), course_id, assignment_id)
                .map_err(cache_error)?
                .map(|record| {
                    let CachePayload::JudgeDetail(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedJudgeDetail {
                        data: map_judge_detail(*data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }

    /// 关闭本地账号的在途回写资格。
    ///
    /// # Errors
    /// 无法持久化退出栅栏时返回稳定错误。
    pub async fn deactivate(&self) -> Result<(), BridgeError> {
        let cache = self.cache.clone();
        local_task(move || cache.deactivate().map_err(cache_error)).await
    }
    /// 重新启用已由宿主核实的本机账号。
    ///
    /// # Errors
    /// 存储不可用时返回稳定错误。
    pub async fn activate(&self) -> Result<(), BridgeError> {
        let cache = self.cache.clone();
        local_task(move || cache.activate().map_err(cache_error)).await
    }
    /// 清空本地记录，不恢复已关闭账号的写入资格。
    ///
    /// # Errors
    /// 无法完成清理事务时返回稳定错误。
    pub async fn clear(&self) -> Result<(), BridgeError> {
        let cache = self.cache.clone();
        local_task(move || cache.clear().map_err(cache_error)).await
    }
}

impl BridgeClient {
    /// 沿既有聚合接口读取并保存希冀摘要；尚不表示可分段抢占。
    ///
    /// # Errors
    /// 学校读取、身份、缓存栅栏或客户端状态失败时返回稳定错误。
    pub async fn judge_assignments_cached(
        &self,
        cache: &BridgeOfflineCache,
        include_expired: bool,
    ) -> Result<BridgeJudgeRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Judge))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            if !self.write_intents.lock().await.is_empty() {
                return Err(BridgeError::local(
                    BridgeErrorCode::OperationConflict,
                    BridgeErrorKind::Input,
                    true,
                    "请先完成当前操作",
                ));
            }
            let value = client
                .refresh_cached_judge(&cache.cache, include_expired)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeJudgeRefresh {
                result: BridgeRoutedJudgeSummaries {
                    data: map_judge_summaries(value.data),
                    route: map_route(value.resolution),
                },
                include_expired,
                fetched_at: value.fetched_at,
                save_error: value.save_error.map(Into::into),
            })
        })
        .await
    }

    /// 受网络锁保护的在线读取；已有待确认学校写意图时禁止隐式会话校验。
    ///
    /// # Errors
    /// 返回原学校读取错误、身份冲突、持久栅栏或客户端生命周期错误。
    pub async fn schedule_today_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeTodayRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Academic))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            if !self.write_intents.lock().await.is_empty() {
                return Err(BridgeError::local(
                    BridgeErrorCode::OperationConflict,
                    BridgeErrorKind::Input,
                    true,
                    "请先完成当前操作",
                ));
            }
            let value = client
                .refresh_cached_today(&cache.cache)
                .await
                .map_err(offline_read_error)?;
            let CacheQuery::ScheduleToday { date } = value.scope.query else {
                return Err(cache_error(core::CacheError::Corrupt));
            };
            Ok(BridgeTodayRefresh {
                result: BridgeRoutedTodayClasses {
                    data: map_today(value.data),
                    route: map_route(value.resolution),
                },
                date,
                fetched_at: value.fetched_at,
                save_error: value.save_error.map(Into::into),
            })
        })
        .await
    }
}

pub(super) fn offline_read_error(error: core::OfflineReadError) -> BridgeError {
    match error {
        core::OfflineReadError::Read(error) => BridgeError::from_routed(error),
        core::OfflineReadError::Cache(error) => cache_error(error),
        core::OfflineReadError::IdentityMismatch { resolution, .. } => BridgeError {
            cache_failure: None,
            code: BridgeErrorCode::CacheIdentityMismatch,
            kind: BridgeErrorKind::Authentication,
            retryable: false,
            message: "当前账号与本机内容不一致，请重新登录".into(),
            resolved_route: Some(resolution.mode.into()),
        },
    }
}

// SQLite 工作交给阻塞池，避免文件系统延迟占用网络运行时工作线程。
pub(super) async fn local_task<T: Send + 'static>(
    operation: impl FnOnce() -> Result<T, BridgeError> + Send + 'static,
) -> Result<T, BridgeError> {
    tokio::task::spawn_blocking(operation)
        .await
        .map_err(|_| cache_error(core::CacheError::Unavailable))?
}

fn map_today(data: Vec<core::TodayClass>) -> Vec<BridgeTodayClass> {
    data.into_iter()
        .map(|item| BridgeTodayClass {
            biz_name: item.biz_name,
            place: item.place,
            time: item.time,
            short_name: item.short_name,
        })
        .collect()
}
pub(super) fn cache_error(error: core::CacheError) -> BridgeError {
    let code = match error {
        core::CacheError::InvalidInput => BridgeErrorCode::InvalidInput,
        core::CacheError::Inactive => BridgeErrorCode::AuthenticationRequired,
        core::CacheError::Superseded => BridgeErrorCode::OperationConflict,
        _ => BridgeErrorCode::InternalError,
    };
    let kind = match error {
        core::CacheError::InvalidInput | core::CacheError::Superseded => BridgeErrorKind::Input,
        core::CacheError::Inactive => BridgeErrorKind::Authentication,
        _ => BridgeErrorKind::Internal,
    };
    let mut mapped = BridgeError::local(code, kind, false, error.to_string());
    mapped.cache_failure = Some(error.into());
    mapped
}
impl From<core::CacheError> for BridgeCacheFailure {
    fn from(error: core::CacheError) -> Self {
        match error {
            core::CacheError::Unavailable => Self::Unavailable,
            core::CacheError::InvalidInput => Self::InvalidInput,
            core::CacheError::Corrupt => Self::Corrupt,
            core::CacheError::UnsupportedVersion => Self::UnsupportedVersion,
            core::CacheError::Inactive => Self::Inactive,
            core::CacheError::Superseded => Self::Superseded,
            core::CacheError::Capacity => Self::Capacity,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    #[test]
    fn 缓存错误保留独立分类而学校错误不冒充存储失败() {
        for failure in [
            core::CacheError::Corrupt,
            core::CacheError::Unavailable,
            core::CacheError::UnsupportedVersion,
            core::CacheError::Capacity,
            core::CacheError::InvalidInput,
            core::CacheError::Inactive,
            core::CacheError::Superseded,
        ] {
            assert_eq!(cache_error(failure).cache_failure, Some(failure.into()));
        }
        assert_eq!(super::super::client::disposed_error().cache_failure, None);
        let school = BridgeError::from_core(
            core::UbaaError::new(
                core::ErrorCode::NetworkError,
                core::ErrorKind::Network,
                true,
                "合成学校网络故障",
            ),
            Some(BridgeConnectionMode::Direct),
        );
        assert_eq!(school.cache_failure, None);
        assert_eq!(school.resolved_route, Some(BridgeConnectionMode::Direct));
    }
    static NEXT: AtomicU64 = AtomicU64::new(0);

    #[tokio::test]
    async fn local_cache_and_logout_fence_do_not_wait_for_the_network_client_lock() {
        let root = std::env::temp_dir().join(format!(
            "ubaa-bridge-offline-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            "0123456789abcdef0123456789abcdef".into(),
            "fixture-user".into(),
            vec![8; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let local = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_today(BridgeConnectionMode::Direct),
        )
        .await
        .unwrap()
        .unwrap();
        assert!(local.is_none());
        tokio::time::timeout(std::time::Duration::from_secs(1), cache.deactivate())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            cache
                .read_today(BridgeConnectionMode::Direct)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(guard);
        drop(cache);
        drop(client);
        let _ = std::fs::remove_dir_all(root);
    }
}

#[cfg(test)]
mod judge_tests {
    use super::*;
    #[tokio::test]
    async fn 详情缓存同时隔离路线课程作业且不等待网络锁() {
        let root = std::env::temp_dir().join(format!("ubaa-detail-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repository = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([6; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repository
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: CacheQuery::JudgeDetail {
                    course_id: "12".into(),
                    assignment_id: "101".into(),
                },
            })
            .unwrap();
        repository
            .publish(
                &ticket,
                CachePayload::JudgeDetail(Box::new(core::JudgeAssignmentDetail {
                    course_id: "12".into(),
                    assignment_id: "101".into(),
                    title: "合成详情".into(),
                    ..Default::default()
                })),
                100,
                core::CacheCompleteness::Complete,
            )
            .unwrap();
        drop(repository);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![6; 32],
        )
        .await
        .unwrap();
        let _guard = client.inner.lock().await;
        let record = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_judge_detail(BridgeConnectionMode::Direct, "12".into(), "101".into()),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.data.title, "合成详情");
        assert_eq!(record.fetched_at, 100);
        for (route, course, assignment) in [
            (BridgeConnectionMode::WebVpn, "12", "101"),
            (BridgeConnectionMode::Direct, "13", "101"),
            (BridgeConnectionMode::Direct, "12", "102"),
        ] {
            assert!(
                cache
                    .read_judge_detail(route, course.into(), assignment.into())
                    .await
                    .unwrap()
                    .is_none()
            );
        }
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_judge_detail(BridgeConnectionMode::Direct, "12".into(), "101".into())
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(cache);
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn saved_judge_summary_projects_original_fields_without_network() {
        let root =
            std::env::temp_dir().join(format!("ubaa-bridge-judge-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repository = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([6; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let scope = core::CacheScope {
            route: core::ConnectionMode::Direct,
            query: core::CacheQuery::JudgeSummaries {
                include_expired: false,
            },
        };
        let ticket = repository.begin_read(scope).unwrap();
        repository
            .publish(
                &ticket,
                core::CachePayload::JudgeSummaries(vec![core::JudgeAssignmentSummary {
                    course_id: "12".into(),
                    assignment_id: "101".into(),
                    title: "合成作业".into(),
                    submitted_count: 2,
                    total_problems: 3,
                    submission_status: core::JudgeSubmissionStatus::Partial,
                    ..Default::default()
                }]),
                100,
                core::CacheCompleteness::Complete,
            )
            .unwrap();
        drop(repository);
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![6; 32],
        )
        .await
        .unwrap();
        let record = cache
            .read_judge(BridgeConnectionMode::Direct, false)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(record.fetched_at, 100);
        assert_eq!(record.data[0].submitted_count, 2);
        assert_eq!(record.data[0].title, "合成作业");
        assert!(
            cache
                .read_judge(BridgeConnectionMode::Direct, true)
                .await
                .unwrap()
                .is_none()
        );
        drop(cache);
        let _ = std::fs::remove_dir_all(root);
    }
}
