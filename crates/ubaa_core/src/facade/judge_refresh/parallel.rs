//! 同课程最多四份待更新详情并行读取，账号与路线栅栏仍由父扫描负责。
use super::{
    CachePayload, CacheQuery, CacheReadTicket, CacheScope, JudgeRefresh, OfflineReadError,
    UbaaClient, policy, remember_save,
};
use crate::features::judge::parallel::PreparedDetail;
use std::collections::VecDeque;

#[derive(Default)]
pub(super) struct DetailReads {
    pub(super) pending: VecDeque<(CacheReadTicket, PreparedDetail)>,
}
impl DetailReads {
    pub(super) fn forget(&mut self, query: &CacheQuery) {
        self.pending
            .retain(|(ticket, _)| &ticket.scope().query != query);
    }
    pub(super) fn discard(&mut self, cache: &super::OfflineCache, parent: &CacheReadTicket) {
        for (ticket, _) in self.pending.drain(..) {
            let _ = cache.repository(|repo| {
                repo.record_failure_guarded(&ticket, parent, chrono::Utc::now().timestamp())
            });
        }
    }
}
impl UbaaClient {
    pub(super) async fn prepare_judge_details(
        &mut self,
        refresh: &mut JudgeRefresh,
    ) -> Result<Option<(CacheReadTicket, PreparedDetail)>, OfflineReadError> {
        if refresh.scan.cursor.current_assignment().is_none() {
            return Ok(None);
        }
        let assignment = refresh
            .scan
            .cursor
            .current_assignment()
            .expect("已确认当前详情");
        let query = CacheQuery::JudgeDetail {
            course_id: assignment.course_id.clone(),
            assignment_id: assignment.assignment_id.clone(),
        };
        if let Some(index) = refresh
            .parallel
            .pending
            .iter()
            .position(|(ticket, _)| ticket.scope().query == query)
        {
            return Ok(refresh.parallel.pending.remove(index));
        }
        if refresh.options.current_assignment.is_some() {
            return Ok(None);
        }
        let assignments = pending_requests(refresh)?;
        if assignments.len() < 2 {
            return Ok(None);
        }
        let tickets = assignments
            .iter()
            .map(|(_, scope)| refresh.scan.cache.begin(scope.clone()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(OfflineReadError::Cache)?;
        let requested: Vec<_> = assignments.iter().map(|(a, _)| a.clone()).collect();
        let route = refresh.scan.resolution.mode;
        let results = self
            .network_control()
            .run_read(
                route,
                refresh.scan.resolution.mode == crate::domain::ConnectionMode::Direct
                    && refresh.scan.resolution.policy == crate::domain::RoutePolicy::Auto
                    && refresh.scan.resolution.diagnostic.network
                        == crate::connection::NetworkState::OffCampus,
                Box::pin(crate::features::judge::parallel::read_same_course_details(
                    self.runtime_for(route),
                    &requested,
                )),
            )
            .await
            .map_err(|error| {
                OfflineReadError::Read(crate::facade::RoutedError {
                    error,
                    resolution: Some(refresh.scan.resolution),
                })
            })?;
        self.validate_judge_scan(&refresh.scan)?;
        refresh
            .parallel
            .pending
            .extend(tickets.into_iter().zip(results));
        Ok(refresh.parallel.pending.pop_front())
    }
}

fn pending_requests(
    refresh: &mut JudgeRefresh,
) -> Result<Vec<(crate::domain::Assignment, CacheScope)>, OfflineReadError> {
    let now = chrono::Utc::now().timestamp();
    let mut assignments = Vec::new();
    for assignment in refresh.scan.cursor.pending_assignments().iter().take(4) {
        if refresh.scan.cursor.has_prepared(assignment) {
            break;
        }
        let scope = CacheScope {
            route: refresh.scan.resolution.mode,
            query: CacheQuery::JudgeDetail {
                course_id: assignment.course_id.clone(),
                assignment_id: assignment.assignment_id.clone(),
            },
        };
        if refresh
            .parallel
            .pending
            .iter()
            .any(|(ticket, _)| ticket.scope().query == scope.query)
        {
            break;
        }
        // 首项已经过缓存判定，后续遇到可复用项便结束本组。
        if !assignments.is_empty() {
            match refresh.scan.cache.read(&scope, now) {
                Ok(Some(record))
                    if matches!(&record.payload, CachePayload::JudgeDetail(_))
                        && policy::reusable(
                            &record,
                            assignment,
                            &refresh.options,
                            refresh.semester.is_some(),
                            now,
                        ) =>
                {
                    break;
                }
                Err(error) => remember_save(&mut refresh.save_error, Err::<(), _>(error))?,
                _ => {}
            }
        }
        assignments.push((assignment.clone(), scope));
    }
    Ok(assignments)
}
