use super::school::{
    BridgeAgendaCacheKind, BridgeAgendaCacheScope, BridgeAgendaCompleteness,
    BridgeAgendaObservation, BridgeAgendaSource,
};
use ubaa_core::facade as core;
impl From<core::CacheScope> for BridgeAgendaCacheScope {
    fn from(v: core::CacheScope) -> Self {
        let mut r = Self {
            route: v.route.into(),
            kind: BridgeAgendaCacheKind::Unknown,
            term: None,
            week: None,
            date: None,
            page: None,
            size: None,
            include_expired: None,
            classify_id: None,
            term_id: None,
            week_start: None,
        };
        r.kind = match v.query {
            core::CacheQuery::BykcChosen => BridgeAgendaCacheKind::BykcChosen,
            core::CacheQuery::SpocSelection => BridgeAgendaCacheKind::SpocSelection,
            core::CacheQuery::SpocTerm { term } => {
                r.term = Some(term);
                BridgeAgendaCacheKind::SpocTerm
            }
            core::CacheQuery::JudgeSummaries { include_expired } => {
                r.include_expired = Some(include_expired);
                BridgeAgendaCacheKind::JudgeSummaries
            }
            core::CacheQuery::CgyyOrders { page, size } => {
                r.page = Some(page);
                r.size = Some(size);
                BridgeAgendaCacheKind::CgyyOrders
            }
            core::CacheQuery::SigninToday { date } => {
                r.date = Some(date);
                BridgeAgendaCacheKind::SigninToday
            }
            core::CacheQuery::Exams { term } => {
                r.term = Some(term);
                BridgeAgendaCacheKind::Exams
            }
            core::CacheQuery::YgdkOverviewSelection { week_start } => {
                r.week_start = Some(week_start);
                BridgeAgendaCacheKind::YgdkOverviewSelection
            }
            core::CacheQuery::YgdkOverviewPeriod {
                classify_id,
                term_id,
                week_start,
            } => {
                r.classify_id = Some(classify_id);
                r.term_id = term_id;
                r.week_start = Some(week_start);
                BridgeAgendaCacheKind::YgdkOverviewPeriod
            }
            core::CacheQuery::ScheduleWeeks { term } => {
                r.term = Some(term);
                BridgeAgendaCacheKind::ScheduleWeeks
            }
            core::CacheQuery::ScheduleWeek { term, week } => {
                r.term = Some(term);
                r.week = Some(week);
                BridgeAgendaCacheKind::ScheduleWeek
            }
            core::CacheQuery::ImportedSchedules => BridgeAgendaCacheKind::ImportedSchedules,
            _ => BridgeAgendaCacheKind::Unknown,
        };
        r
    }
}
impl From<core::AgendaSourceAvailability> for BridgeAgendaSource {
    fn from(v: core::AgendaSourceAvailability) -> Self {
        Self {
            feature: v.feature.into(),
            observations: v
                .observations
                .into_iter()
                .map(|v| BridgeAgendaObservation {
                    scope: v.scope.into(),
                    fetched_at: v.fetched_at,
                    last_verified_at: v.last_verified_at,
                    last_attempt_at: v.last_attempt_at,
                    last_attempt_succeeded: v.last_attempt_succeeded,
                    completeness: match v.completeness {
                        core::CacheCompleteness::Complete => BridgeAgendaCompleteness::Complete,
                        core::CacheCompleteness::Partial => BridgeAgendaCompleteness::Partial,
                    },
                })
                .collect(),
            missing_scopes: v.missing_scopes.into_iter().map(Into::into).collect(),
            semester_imported: v.semester_imported,
            unprojectable_count: u32::try_from(v.unprojectable_count).unwrap_or(u32::MAX),
        }
    }
}
