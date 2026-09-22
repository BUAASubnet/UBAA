//! 评教缓存只含公开展示字段；学校写资格始终来自新鲜读取。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{BridgeEvaluationCoursesResponse, BridgeEvaluationProgress, map_evaluation};
use ubaa_core::facade as core;
#[derive(Clone, Debug)]
pub struct BridgeCachedEvaluationCourse {
    pub id: String,
    pub kcmc: String,
    pub bpmc: String,
    pub is_evaluated: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedEvaluationCourses {
    pub courses: Vec<BridgeCachedEvaluationCourse>,
    pub progress: BridgeEvaluationProgress,
}
#[derive(Clone, Debug)]
pub struct BridgeCachedEvaluationRecord {
    pub data: BridgeCachedEvaluationCourses,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeEvaluationRefresh {
    pub data: BridgeEvaluationCoursesResponse,
    pub route: BridgeRouteDecision,
    pub fetched_at: i64,
    pub complete: bool,
    pub saved_for_offline: bool,
    pub preserved_previous: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 当前固定任务范围的本地快照，不等待网络锁。
    ///
    /// # Errors
    /// 账号关闭或存储损坏返回稳定错误，缺少记录返回 None。
    pub async fn read_evaluation(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedEvaluationRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_evaluation(route.into())
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::EvaluationCurrent(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedEvaluationRecord {
                        data: BridgeCachedEvaluationCourses {
                            courses: data
                                .courses
                                .into_iter()
                                .map(|v| BridgeCachedEvaluationCourse {
                                    id: v.id,
                                    kcmc: v.kcmc,
                                    bpmc: v.bpmc,
                                    is_evaluated: v.is_evaluated,
                                })
                                .collect(),
                            progress: BridgeEvaluationProgress {
                                total_courses: data.progress.total_courses,
                                evaluated_courses: data.progress.evaluated_courses,
                                pending_courses: data.progress.pending_courses,
                            },
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
    /// 沿原读取保存只读副本；待确认写意图禁止隐式恢复。
    ///
    /// # Errors
    /// 原认证/业务与账号/退出屏障保持。
    pub async fn evaluation_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeEvaluationRefresh, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let value = client
                .refresh_cached_evaluation(&cache.cache)
                .await
                .map_err(offline_read_error)?;
            Ok(BridgeEvaluationRefresh {
                data: map_evaluation(value.result.data),
                route: map_route(value.result.resolution),
                fetched_at: value.result.fetched_at,
                complete: value.complete,
                saved_for_offline: value.publication == Some(core::CachePublication::Stored),
                preserved_previous: value.publication == Some(core::CachePublication::Preserved),
                save_error: value.result.save_error.map(Into::into),
            })
        })
        .await
    }
}
#[cfg(test)]
mod tests {
    use crate::api::{client::*, offline::BridgeOfflineCache};
    use ubaa_core::facade as core;
    #[tokio::test]
    async fn 评教本地缓存独立网络锁且路线和退出隔离() {
        let root =
            std::env::temp_dir().join(format!("ubaa-evaluation-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repo = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([8; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repo
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::EvaluationCurrent,
            })
            .unwrap();
        repo.publish(
            &ticket,
            core::CachePayload::EvaluationCurrent(core::CachedEvaluationCourses {
                courses: vec![core::CachedEvaluationCourse {
                    id: "synthetic".into(),
                    kcmc: "合成课程".into(),
                    bpmc: "合成教师".into(),
                    is_evaluated: false,
                }],
                progress: core::EvaluationProgress {
                    total_courses: 1,
                    evaluated_courses: 0,
                    pending_courses: 1,
                },
            }),
            123,
            core::CacheCompleteness::Complete,
        )
        .unwrap();
        drop(repo);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![8; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let record = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_evaluation(BridgeConnectionMode::Direct),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.data.courses[0].kcmc, "合成课程");
        assert_eq!(record.data.progress.pending_courses, 1);
        assert!(
            cache
                .read_evaluation(BridgeConnectionMode::WebVpn)
                .await
                .unwrap()
                .is_none()
        );
        drop(guard);
        client.write_intents.lock().await.insert(
            "synthetic".into(),
            crate::api::write::PendingEntry {
                request: crate::api::write::PendingWrite::BykcSelect(
                    crate::api::write::BridgeBykcCourseRequest { course_id: 42 },
                ),
                expires_at: i64::MAX,
                resolved_route: BridgeConnectionMode::Direct,
                conflict_key: "synthetic".into(),
            },
        );
        assert_eq!(
            client.evaluation_cached(&cache).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_evaluation(BridgeConnectionMode::Direct)
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

pub mod scan;
