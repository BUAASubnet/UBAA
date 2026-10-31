//! 仅消费同账号、指定路线的现有缓存，不刷新学校内容。
use super::{AgendaQuery, AgendaSourceAvailability};
use crate::facade::{
    AgendaExportOptions, AgendaExportResult, AgendaStore, CacheError, CacheResult, OfflineCache,
};

#[derive(Clone, Debug, PartialEq)]
pub struct AgendaCachedExportResult {
    pub snapshot: AgendaExportResult,
    pub sources: Vec<AgendaSourceAvailability>,
}
impl OfflineCache {
    /// 导出统一日程的范围快照，并保留逐来源缓存缺口与时间。
    ///
    /// # Errors
    /// 账号不符、日程/缓存失效、输入非法、内容损坏或资源超限时返回稳定本地错误。
    pub fn export_agenda_ics(
        &self,
        agenda: &AgendaStore,
        query: &AgendaQuery,
        include_completed: bool,
    ) -> CacheResult<AgendaCachedExportResult> {
        if !self.matches_agenda_account(agenda) {
            return Err(CacheError::InvalidInput);
        }
        let (school, sources) = self.school_agenda(query)?;
        let snapshot = agenda.export_with_school(
            &AgendaExportOptions {
                from: query.from,
                to: query.to,
                generated_at: query.now,
                include_hidden: query.include_hidden,
                include_completed,
            },
            school,
        )?;
        Ok(AgendaCachedExportResult { snapshot, sources })
    }
}
