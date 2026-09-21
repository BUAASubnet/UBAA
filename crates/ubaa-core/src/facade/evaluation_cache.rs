//! 评教当前任务范围的只读快照；部分容错不覆盖旧完整结果。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheScope,
    ConnectionMode, EvaluationCoursesResponse, OfflineCache, OfflineReadError, OfflineRefresh,
    ReadonlyFeature, UbaaClient,
};
#[derive(Debug)]
pub struct EvaluationRefresh {
    pub result: OfflineRefresh<EvaluationCoursesResponse>,
    pub complete: bool,
    /// 本次 Stored 与保留此前记录的 Preserved 分开报告。
    pub publication: Option<CachePublication>,
}
impl OfflineCache {
    /// 读取明确查询范围的缓存，不获取网络锁或恢复学校写资格。
    ///
    /// # Errors
    /// 参数、账号栅栏或存储错误按本地缓存分类返回。
    pub fn read_evaluation(
        &self,
        route: ConnectionMode,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: CacheQuery::EvaluationCurrent,
            },
            chrono::Utc::now().timestamp(),
        )
    }
}
impl UbaaClient {
    /// 身份核对后沿原协议读取，保留当前固定任务范围，部分结果不替换旧完整集合。
    ///
    /// # Errors
    /// 原认证/业务失败保持分类；账号不符、退出和请求被替代不可降级。
    pub async fn refresh_cached_evaluation(
        &mut self,
        cache: &OfflineCache,
    ) -> Result<EvaluationRefresh, OfflineReadError> {
        let cache_query = CacheQuery::EvaluationCurrent;
        CacheScope {
            route: ConnectionMode::Direct,
            query: cache_query.clone(),
        }
        .validate()
        .map_err(OfflineReadError::Cache)?;
        let authenticated = self
            .recover_required_session(ReadonlyFeature::Evaluation)
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
            query: cache_query,
        };
        let (ticket, mut save_error) = match cache.begin(scope.clone()) {
            Ok(ticket) => (Some(ticket), None),
            Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                return Err(OfflineReadError::Cache(error));
            }
            Err(error) => (None, Some(error)),
        };
        let runtime = self.runtime_for(resolution.mode);
        let read = crate::features::evaluation::get_all_observed(runtime).await;
        let fetched_at = chrono::Utc::now().timestamp();
        let read = match self.finish_routed(resolution, read) {
            Ok(read) => read,
            Err(error) => {
                if let Some(ticket) = &ticket {
                    cache.failure(ticket, fetched_at);
                }
                return Err(OfflineReadError::Read(error));
            }
        };
        let (data, complete) = read.data;
        let mut publication = None;
        if let Some(ticket) = &ticket {
            let saved = cache.repository(|repository| {
                repository.publish(
                    ticket,
                    CachePayload::EvaluationCurrent(data.clone().into()),
                    fetched_at,
                    if complete {
                        CacheCompleteness::Complete
                    } else {
                        CacheCompleteness::Partial
                    },
                )
            });
            match saved {
                Ok(value) => publication = Some(value),
                Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                    return Err(OfflineReadError::Cache(error));
                }
                Err(error) => {
                    save_error = Some(error);
                    cache.failure(ticket, fetched_at);
                }
            }
        }
        Ok(EvaluationRefresh {
            result: OfflineRefresh {
                data,
                resolution,
                scope,
                fetched_at,
                save_error,
            },
            complete,
            publication,
        })
    }
}
