//! 阳光记录按实际分类分页；上次分类索引不能携带认证材料或写资格。
use super::{
    CacheCompleteness, CacheError, CachePayload, CachePublication, CacheQuery, CacheReadTicket,
    CacheScope, CachedYgdkRecordsPage, CachedYgdkRecordsSelection, ConnectionMode, OfflineCache,
    OfflineReadError, OfflineRefresh, ReadonlyFeature, UbaaClient, YgdkRecordsPage,
};
#[derive(Debug)]
pub struct YgdkRecordsRefresh {
    pub result: OfflineRefresh<YgdkRecordsPage>,
    pub selection: CachedYgdkRecordsSelection,
    pub complete: bool,
    pub publication: Option<CachePublication>,
    pub selection_saved: bool,
}
impl OfflineCache {
    /// 只读上次观察分类；数据页必须另按该分类的精确参数读取。
    ///
    /// # Errors
    /// 退出和本地损坏保持稳定错误。
    pub fn read_ygdk_records_selection(
        &self,
        route: ConnectionMode,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: CacheQuery::YgdkRecordsSelection,
            },
            chrono::Utc::now().timestamp(),
        )
    }
    /// 分类、页码和大小不能被当前默认值替换。
    ///
    /// # Errors
    /// 无效范围、退出或存储失败返回稳定错误。
    pub fn read_ygdk_records(
        &self,
        route: ConnectionMode,
        classify_id: i32,
        page: i32,
        size: i32,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &records_scope(route, classify_id, page, size),
            chrono::Utc::now().timestamp(),
        )
    }
}
impl UbaaClient {
    /// 原上下文确定真实分类后，先建立该页票据再读记录；不持本地锁等待学校网络。
    ///
    /// # Errors
    /// 原学校错误和账号/退出/替代屏障保持；仅存储失败可降级在线。
    pub async fn refresh_cached_ygdk_records(
        &mut self,
        cache: &OfflineCache,
        page: i32,
        size: i32,
    ) -> Result<YgdkRecordsRefresh, OfflineReadError> {
        self.refresh_ygdk_records_scoped(cache, page, size, None)
            .await
    }

    /// 组合概览与记录时要求本次所需路线、实际分类均与已显示概览一致。
    ///
    /// # Errors
    /// 不匹配在对应业务读取前返回 Superseded；不改路由配置或旧固定路线接口。
    pub async fn refresh_cached_ygdk_records_for_overview(
        &mut self,
        cache: &OfflineCache,
        route: ConnectionMode,
        classify_id: i32,
        page: i32,
        size: i32,
    ) -> Result<YgdkRecordsRefresh, OfflineReadError> {
        if classify_id <= 0 {
            return Err(OfflineReadError::Cache(CacheError::InvalidInput));
        }
        self.refresh_ygdk_records_scoped(cache, page, size, Some((route, classify_id)))
            .await
    }

    async fn ygdk_records_session(
        &mut self,
        expected: Option<ConnectionMode>,
    ) -> Result<super::Routed<super::AuthStatus>, OfflineReadError> {
        let resolution = self
            .resolve_operation(super::types::Operation::Feature(ReadonlyFeature::Ygdk))
            .map_err(OfflineReadError::Read)?;
        if expected.is_some_and(|route| route != resolution.mode) {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        self.recover_resolved_session(resolution)
            .await
            .map_err(OfflineReadError::Read)
    }

    async fn refresh_ygdk_records_scoped(
        &mut self,
        cache: &OfflineCache,
        page: i32,
        size: i32,
        expected: Option<(ConnectionMode, i32)>,
    ) -> Result<YgdkRecordsRefresh, OfflineReadError> {
        cache
            .check_read_generation()
            .map_err(OfflineReadError::Cache)?;
        if page <= 0 || size <= 0 {
            return Err(OfflineReadError::Cache(CacheError::InvalidInput));
        }
        let authenticated = self
            .ygdk_records_session(expected.map(|value| value.0))
            .await?;
        let resolution = authenticated.resolution;
        if !cache.matches(&authenticated.data.user) {
            return Err(OfflineReadError::IdentityMismatch {
                resolution,
                cache_error: cache.deactivate().err(),
            });
        }
        let (selection_ticket, mut save_error) = super::begin_refresh(
            cache,
            CacheScope {
                route: resolution.mode,
                query: CacheQuery::YgdkRecordsSelection,
            },
        )?;
        let context =
            crate::features::ygdk::get_overview_context(self.runtime_for(resolution.mode)).await;
        let context = match self.finish_routed(resolution, context) {
            Ok(context) => context.data,
            Err(error) => {
                if let Some(ticket) = &selection_ticket {
                    cache.failure(ticket, chrono::Utc::now().timestamp());
                }
                return Err(OfflineReadError::Read(error));
            }
        };
        let selection = CachedYgdkRecordsSelection {
            classify_id: context.overview.classify_id,
            classify_name: context.overview.classify_name.clone(),
        };
        if expected.is_some_and(|(_, classify_id)| classify_id != selection.classify_id) {
            return Err(OfflineReadError::Cache(CacheError::Superseded));
        }
        let scope = records_scope(resolution.mode, selection.classify_id, page, size);
        scope.validate().map_err(OfflineReadError::Cache)?;
        let (ticket, page_error) = super::begin_refresh(cache, scope.clone())?;
        save_error = page_error.or(save_error);
        let result = crate::features::ygdk::get_records_in_context(
            self.runtime_for(resolution.mode),
            &context,
            page,
            size,
        )
        .await;
        let fetched_at = chrono::Utc::now().timestamp();
        let (data, complete) = match self.finish_routed(resolution, result) {
            Ok(result) => result.data,
            Err(error) => {
                if let (Some(ticket), Some(parent)) = (&ticket, &selection_ticket) {
                    fail_page(cache, ticket, parent, fetched_at);
                }
                if let Some(ticket) = &selection_ticket {
                    cache.failure(ticket, fetched_at);
                }
                return Err(OfflineReadError::Read(error));
            }
        };
        let mut publication = None;
        let mut selection_saved = false;
        if let (Some(ticket), Some(parent)) = (&ticket, &selection_ticket) {
            let result = publish(
                cache, ticket, parent, &data, &selection, complete, fetched_at,
            );
            match result {
                Ok(value) => {
                    publication = Some(value);
                    selection_saved = selection_ticket.is_some();
                }
                Err(error @ (CacheError::Inactive | CacheError::Superseded)) => {
                    return Err(OfflineReadError::Cache(error));
                }
                Err(error) => {
                    save_error = Some(error);
                    fail_page(cache, ticket, parent, fetched_at);
                }
            }
        }
        Ok(YgdkRecordsRefresh {
            result: OfflineRefresh {
                data,
                resolution,
                scope,
                fetched_at,
                save_error,
            },
            selection,
            complete,
            publication,
            selection_saved,
        })
    }
}

/// 数据页与分类票据在同一事务内核对；索引只在已有合法数据页后更新。
fn publish(
    cache: &OfflineCache,
    ticket: &CacheReadTicket,
    parent: &CacheReadTicket,
    data: &YgdkRecordsPage,
    selection: &CachedYgdkRecordsSelection,
    complete: bool,
    fetched_at: i64,
) -> super::CacheResult<CachePublication> {
    cache.repository(|repository| {
        let result = repository.publish_guarded(
            ticket,
            parent,
            CachePayload::YgdkRecords(CachedYgdkRecordsPage::from_page(
                selection.classify_id,
                data.clone(),
            )),
            fetched_at,
            if complete {
                CacheCompleteness::Complete
            } else {
                CacheCompleteness::Partial
            },
        )?;
        repository.publish(
            parent,
            CachePayload::YgdkRecordsSelection(selection.clone()),
            fetched_at,
            CacheCompleteness::Complete,
        )?;
        Ok(result)
    })
}

fn records_scope(route: ConnectionMode, classify_id: i32, page: i32, size: i32) -> CacheScope {
    CacheScope {
        route,
        query: CacheQuery::YgdkRecords {
            classify_id,
            page,
            size,
        },
    }
}

fn fail_page(cache: &OfflineCache, ticket: &CacheReadTicket, parent: &CacheReadTicket, now: i64) {
    let _ = cache.repository(|repository| repository.record_failure_guarded(ticket, parent, now));
}
