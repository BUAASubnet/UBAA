//! RFC 5545 范围快照，不输出完整重复系列。
use super::AgendaStore;
use crate::{
    cache::{CacheError, CacheResult},
    domain::agenda::{AgendaTime, SchoolAgendaItem},
};
use chrono::{Datelike, NaiveDate};
mod content_lines;
mod serialize;
use serialize::{serialize, valid_time};

#[derive(Clone, Debug)]
pub struct AgendaExportOptions {
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub generated_at: AgendaTime,
    pub include_hidden: bool,
    pub include_completed: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AgendaExportResult {
    pub ics: String,
    pub exported_count: usize,
    pub skipped_unknown_time_count: usize,
}

impl AgendaStore {
    /// 导出本机日程的范围快照。
    ///
    /// # Errors
    /// 输入无效、账号已关闭、内容非法或展开超限时返回稳定本地错误。
    pub fn export_local_ics(
        &self,
        options: &AgendaExportOptions,
    ) -> CacheResult<AgendaExportResult> {
        self.export_with_school(options, Vec::new())
    }

    pub(crate) fn export_with_school(
        &self,
        options: &AgendaExportOptions,
        school: Vec<SchoolAgendaItem>,
    ) -> CacheResult<AgendaExportResult> {
        if options.from >= options.to
            || (options.to - options.from).num_days() > 3660
            || !valid_time(options.generated_at)
            || [options.from, options.to]
                .iter()
                .any(|d| !(1..=9999).contains(&d.year()))
        {
            return Err(CacheError::InvalidInput);
        }
        self.access(true, false, |data| {
            // 展开、覆盖、完成与修改时间取自同一次日程读取事务。
            let entries = super::query::merge_entries(
                data,
                options.from,
                options.to,
                school,
                options.include_hidden,
            )?;
            serialize(data, &entries, options, self.account_alias())
        })
    }
}

#[cfg(test)]
mod tests;
