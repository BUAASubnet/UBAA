//! 日程范围快照只读取本机数据，不借用网络客户端。
use super::models::BridgeAgendaError;
use super::school::BridgeAgendaQuery;
use super::{BridgeAgendaStore, date, error, task};
use crate::api::offline::BridgeOfflineCache;
use ubaa_core::facade as core;

#[derive(Debug)]
pub struct BridgeAgendaExport {
    pub ics: String,
    pub exported_count: u32,
    pub skipped_unknown_time_count: u32,
}
fn result(value: core::AgendaExportResult) -> Result<BridgeAgendaExport, BridgeAgendaError> {
    Ok(BridgeAgendaExport {
        ics: value.ics,
        exported_count: u32::try_from(value.exported_count)
            .map_err(|_| error(core::CacheError::Capacity))?,
        skipped_unknown_time_count: u32::try_from(value.skipped_unknown_time_count)
            .map_err(|_| error(core::CacheError::Capacity))?,
    })
}
impl BridgeAgendaStore {
    /// 导出选定日期范围的本机快照。
    ///
    /// # Errors
    /// 日期、内容或存储无效及账号关闭时返回稳定日程错误。
    pub async fn export_ics(
        &self,
        query: BridgeAgendaQuery,
        include_completed: bool,
    ) -> Result<BridgeAgendaExport, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || {
            result(
                store
                    .export_local_ics(&core::AgendaExportOptions {
                        from: date(&query.from)?,
                        to: date(&query.to)?,
                        generated_at: query.now.try_into()?,
                        include_hidden: query.include_hidden,
                        include_completed,
                    })
                    .map_err(error)?,
            )
        })
        .await
    }
    /// 导出同账号、指定路线的学校缓存及本机日程，缓存错误明确失败。
    ///
    /// # Errors
    /// 身份、范围、缓存或日程无效时返回稳定日程错误，不生成残缺成功文件。
    pub async fn export_with_cache(
        &self,
        cache: &BridgeOfflineCache,
        query: BridgeAgendaQuery,
        include_completed: bool,
    ) -> Result<BridgeAgendaExport, BridgeAgendaError> {
        let store = self.store.clone();
        let cache = cache.cache.clone();
        task(move || {
            result(
                cache
                    .export_agenda_ics(&store, &query.try_into()?, include_completed)
                    .map_err(error)?
                    .snapshot,
            )
        })
        .await
    }
}
