//! 成绩变化基线的本机加密通道，不使用网络客户端或学校写意图。
use crate::api::client::{BridgeConnectionMode, BridgeError};
use crate::api::offline::{BridgeOfflineCache, cache_error, local_task};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeGradeScoreEntry {
    pub key: String,
    pub course_name: Option<String>,
    pub course_code: Option<String>,
    pub score: Option<String>,
}

#[derive(Clone, Debug)]
pub struct BridgeGradeScoreBaseline {
    pub term_code: String,
    pub term_name: String,
    pub scores: Vec<BridgeGradeScoreEntry>,
}

impl From<BridgeGradeScoreBaseline> for core::CachedGradeScoreBaseline {
    fn from(value: BridgeGradeScoreBaseline) -> Self {
        Self {
            term_code: value.term_code,
            term_name: value.term_name,
            scores: value
                .scores
                .into_iter()
                .map(|entry| core::CachedGradeScoreEntry {
                    key: entry.key,
                    course_name: entry.course_name,
                    course_code: entry.course_code,
                    score: entry.score,
                })
                .collect(),
        }
    }
}
impl From<core::CachedGradeScoreBaseline> for BridgeGradeScoreBaseline {
    fn from(value: core::CachedGradeScoreBaseline) -> Self {
        Self {
            term_code: value.term_code,
            term_name: value.term_name,
            scores: value
                .scores
                .into_iter()
                .map(|entry| BridgeGradeScoreEntry {
                    key: entry.key,
                    course_name: entry.course_name,
                    course_code: entry.course_code,
                    score: entry.score,
                })
                .collect(),
        }
    }
}

impl BridgeOfflineCache {
    /// 本地精确学期读取，不获取学校客户端锁。
    ///
    /// # Errors
    /// 返回本地缓存类别，未保存不伪装成学校查询失败。
    pub async fn read_grade_score_baseline(
        &self,
        route: BridgeConnectionMode,
        term: String,
    ) -> Result<Option<BridgeGradeScoreBaseline>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_grade_score_baseline(route.into(), &term)
                .map(|value| value.map(Into::into))
                .map_err(cache_error)
        })
        .await
    }

    /// 原基线读取与新观察保存共享本地锁；旧文件基线仅在缺失时迁入。
    ///
    /// # Errors
    /// 空集合、容量、密钥、清理或退出错误不回退明文。
    pub async fn update_grade_score_baseline(
        &self,
        route: BridgeConnectionMode,
        latest: BridgeGradeScoreBaseline,
        legacy: Option<BridgeGradeScoreBaseline>,
    ) -> Result<Option<BridgeGradeScoreBaseline>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .update_grade_score_baseline(route.into(), latest.into(), legacy.map(Into::into))
                .map(|value| value.map(Into::into))
                .map_err(cache_error)
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::client::{BridgeClient, BridgeErrorCode};
    #[tokio::test]
    async fn 成绩基线不等待网络锁且退出后明确拒绝保存() {
        let root =
            std::env::temp_dir().join(format!("ubaa-grade-baseline-bridge-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let path = root.to_string_lossy().into_owned();
        let client = BridgeClient::open(path.clone()).unwrap();
        let cache = BridgeOfflineCache::open(
            path,
            "0123456789abcdef0123456789abcdef".into(),
            "synthetic".into(),
            vec![19; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let value = BridgeGradeScoreBaseline {
            term_code: "2026-2027-1".into(),
            term_name: "合成学期".into(),
            scores: vec![BridgeGradeScoreEntry {
                key: "code:synthetic".into(),
                course_name: None,
                course_code: Some("synthetic".into()),
                score: Some("89".into()),
            }],
        };
        let previous = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.update_grade_score_baseline(BridgeConnectionMode::Direct, value.clone(), None),
        )
        .await
        .unwrap()
        .unwrap();
        assert!(previous.is_none());
        let saved = cache
            .read_grade_score_baseline(BridgeConnectionMode::Direct, value.term_code.clone())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(saved.scores[0].score.as_deref(), Some("89"));
        cache.deactivate().await.unwrap();
        let error = cache
            .update_grade_score_baseline(BridgeConnectionMode::Direct, value, None)
            .await
            .unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::AuthenticationRequired);
        assert!(error.cache_failure.is_some());
        drop(guard);
        drop(cache);
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    }
}
