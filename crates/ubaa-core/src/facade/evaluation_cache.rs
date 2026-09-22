//! 评教当前任务范围的只读快照；部分容错不覆盖旧完整结果。
use super::{
    CachePublication, CacheQuery, CacheScope, ConnectionMode, EvaluationCoursesResponse,
    OfflineCache, OfflineReadError, OfflineRefresh, UbaaClient,
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
        let mut plan = self.begin_evaluation_scan(Some(cache), None).await?;
        loop {
            let batch = self.next_evaluation_scan(&mut plan).await?;
            if batch.finished {
                return Ok(EvaluationRefresh {
                    result: OfflineRefresh {
                        data: batch.data,
                        resolution: batch.resolution,
                        scope: CacheScope {
                            route: batch.resolution.mode,
                            query: CacheQuery::EvaluationCurrent,
                        },
                        fetched_at: batch.fetched_at,
                        save_error: batch.save_error,
                    },
                    complete: batch.complete,
                    publication: batch.publication,
                });
            }
        }
    }
}
mod scan;
pub use scan::{EvaluationScan, EvaluationScanBatch, EvaluationScanCancellation};
