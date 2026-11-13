//! 同课程最多四份待更新详情并行读取，账号与路线栅栏仍由父扫描负责。
use super::{
    CachePayload, CacheQuery, CacheReadTicket, CacheScope, JudgeRefresh, OfflineReadError,
    UbaaClient, policy, remember_save,
};
use crate::{
    domain::ConnectionMode,
    features::judge::parallel::{DetailWorker, PreparedDetail},
};
use std::collections::VecDeque;

#[derive(Default)]
pub(super) struct DetailReads {
    workers: Vec<DetailWorker>,
    pending: VecDeque<(CacheReadTicket, PreparedDetail)>,
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
        self.workers.clear();
    }
}
impl UbaaClient {
    pub(super) async fn prepare_judge_details(
        &mut self,
        refresh: &mut JudgeRefresh,
    ) -> Result<Option<(CacheReadTicket, PreparedDetail)>, OfflineReadError> {
        if refresh.scan.resolution.mode != ConnectionMode::Direct
            || refresh.options.current_assignment.is_some()
            || refresh.scan.cursor.current_assignment().is_none()
        {
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
        // 新 worker 需要激活和选课；短课程沿原客户端读取，避免准备成本超过收益。
        if refresh.parallel.workers.is_empty()
            && refresh.scan.cursor.pending_assignments().len() < 8
        {
            return Ok(None);
        }
        let assignments = pending_requests(refresh)?;
        if assignments.len() < 2 || (refresh.parallel.workers.is_empty() && assignments.len() < 4) {
            return Ok(None);
        }
        let tickets = assignments
            .iter()
            .map(|(_, scope)| refresh.scan.cache.begin(scope.clone()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(OfflineReadError::Cache)?;
        while refresh.parallel.workers.len() < assignments.len() {
            refresh
                .parallel
                .workers
                .push(DetailWorker::new(self.runtime_for(ConnectionMode::Direct)));
        }
        let resolution = refresh.scan.resolution;
        let network = self.network_control();
        let fast_connect = resolution.policy == crate::domain::RoutePolicy::Auto
            && resolution.diagnostic.network == crate::connection::NetworkState::OffCampus;
        let results = network
            .run_read(
                ConnectionMode::Direct,
                fast_connect,
                Box::pin(async {
                    Ok(futures_util::future::join_all(
                        refresh
                            .parallel
                            .workers
                            .iter_mut()
                            .zip(&assignments)
                            .map(|(worker, (assignment, _))| worker.read(assignment)),
                    )
                    .await)
                }),
            )
            .await
            .map_err(|error| {
                OfflineReadError::Read(crate::facade::RoutedError {
                    error,
                    resolution: Some(resolution),
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
        let scope = CacheScope {
            route: ConnectionMode::Direct,
            query: CacheQuery::JudgeDetail {
                course_id: assignment.course_id.clone(),
                assignment_id: assignment.assignment_id.clone(),
            },
        };
        // 首项已经过缓存判定，后续遇到可复用项便结束本组。
        if !assignments.is_empty() {
            match refresh.scan.cache.read(&scope, now) {
                Ok(Some(record))
                    if matches!(&record.payload, CachePayload::JudgeDetail(_))
                        && policy::reusable(&record, assignment, &refresh.options, now) =>
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
