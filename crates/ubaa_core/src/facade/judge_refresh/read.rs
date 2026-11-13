//! 每次返回一个索引或详情；持久复用不伪装新网络读取。
use super::{
    CacheError, CachePayload, CacheQuery, CacheReadTicket, CacheScope, JudgeRefresh, JudgeScan,
    JudgeScanBatch, JudgeScanKind, OfflineReadError, UbaaClient, history, policy, remember_save,
};
use crate::cache::CacheRecord;

pub(super) struct Step {
    pub(super) batch: JudgeScanBatch,
    pub(super) reused: bool,
    pub(super) source_at: i64,
    pub(super) child: Option<CacheReadTicket>,
    pub(super) index_revision: Option<i64>,
}
impl UbaaClient {
    pub(super) async fn read_judge_refresh_batch(
        &mut self,
        refresh: &mut JudgeRefresh,
    ) -> Result<Step, OfflineReadError> {
        let now = chrono::Utc::now().timestamp();
        let assignment = refresh.scan.cursor.current_assignment().cloned();
        let course = refresh.scan.cursor.current_course().cloned();
        let query = assignment
            .as_ref()
            .map(|item| CacheQuery::JudgeDetail {
                course_id: item.course_id.clone(),
                assignment_id: item.assignment_id.clone(),
            })
            .or_else(|| {
                course.as_ref().map(|item| CacheQuery::JudgeAssignments {
                    course_id: item.course_id.clone(),
                })
            });
        let scope = query.map(|query| CacheScope {
            route: refresh.scan.resolution.mode,
            query,
        });
        let cached = if let (Some(assignment), Some(scope)) = (&assignment, &scope) {
            match refresh.scan.cache.read(scope, now) {
                Ok(Some(record))
                    if policy::reusable(&record, assignment, &refresh.options, now) =>
                {
                    Some(record)
                }
                Ok(_) => None,
                Err(error) => {
                    remember_save(&mut refresh.save_error, Err::<(), _>(error))?;
                    None
                }
            }
        } else if let Some(course) = &course {
            history::prepare(refresh, &course.course_id)?;
            history::cached_index(refresh, &course.course_id, now)?
        } else {
            None
        };
        if let Some(record) = cached {
            self.validate_judge_scan(&refresh.scan)?;
            refresh.parallel.forget(&record.scope.query);
            return reuse(&mut refresh.scan, record);
        }
        Box::pin(self.read_judge_network_batch(refresh, scope, assignment, course)).await
    }
    async fn read_judge_network_batch(
        &mut self,
        refresh: &mut JudgeRefresh,
        scope: Option<CacheScope>,
        assignment: Option<crate::domain::Assignment>,
        course: Option<crate::domain::Course>,
    ) -> Result<Step, OfflineReadError> {
        let prefetched = self.prepare_judge_details(refresh).await?;
        let mut child = if let Some((child, _)) = &prefetched {
            Some(child.clone())
        } else {
            scope
                .map(|scope| refresh.scan.cache.begin(scope))
                .transpose()
                .map_err(OfflineReadError::Cache)?
        };
        let prepared_route = refresh.scan.resolution.mode;
        let prefetched_at = prefetched.as_ref().map(|(_, detail)| detail.source_at);
        let force_fresh = refresh.scan.force_fresh;
        refresh.scan.force_fresh = true;
        let result = self
            .next_judge_scan_prepared(&mut refresh.scan, prefetched.map(|(_, detail)| detail))
            .await;
        refresh.scan.force_fresh = force_fresh;
        let batch = match result {
            Ok(result) => result.data,
            Err(error) => {
                refresh
                    .parallel
                    .discard(&refresh.scan.cache, &refresh.scan.ticket);
                if let Some(child) = &child {
                    let _ = refresh.scan.cache.repository(|repository| {
                        repository.record_failure_guarded(
                            child,
                            &refresh.scan.ticket,
                            chrono::Utc::now().timestamp(),
                        )
                    });
                }
                return Err(error);
            }
        };
        if batch.kind == JudgeScanKind::CourseFailure
            || refresh.scan.resolution.mode != prepared_route
        {
            refresh
                .parallel
                .discard(&refresh.scan.cache, &refresh.scan.ticket);
        }
        if batch.kind == JudgeScanKind::Assignments {
            for prepared in refresh.scan.cursor.drain_prepared() {
                let scope = CacheScope {
                    route: refresh.scan.resolution.mode,
                    query: CacheQuery::JudgeDetail {
                        course_id: prepared.key.0.clone(),
                        assignment_id: prepared.key.1.clone(),
                    },
                };
                let ticket = refresh
                    .scan
                    .cache
                    .repository(|repo| repo.begin_read_guarded(scope, &refresh.scan.ticket))
                    .map_err(OfflineReadError::Cache)?;
                refresh.parallel.pending.push_back((ticket, prepared));
            }
        }
        let index_revision = (batch.kind == JudgeScanKind::Assignments)
            .then(|| child.as_ref().map(CacheReadTicket::revision))
            .flatten();
        if let Some(child) = &mut child {
            child.set_source_route(refresh.scan.resolution.mode);
        }
        let source_at = prefetched_at
            .filter(|_| refresh.scan.resolution.mode == prepared_route)
            .or_else(|| {
                course.as_ref().and_then(|course| {
                    self.runtime_for(refresh.scan.resolution.mode)
                        .feature_state()
                        .judge
                        .source_time(
                            Some(&course.course_id),
                            assignment.as_ref().map(|item| item.assignment_id.as_str()),
                        )
                })
            })
            .unwrap_or_else(|| chrono::Utc::now().timestamp());
        Ok(Step {
            batch,
            reused: false,
            source_at,
            child,
            index_revision,
        })
    }
}
fn reuse(scan: &mut JudgeScan, record: CacheRecord) -> Result<Step, OfflineReadError> {
    let mut batch = JudgeScanBatch {
        kind: JudgeScanKind::Finished,
        course_id: None,
        assignments: Vec::new(),
        detail: None,
        error: None,
        finished: false,
        complete: false,
        failed_courses: scan.cursor.failed_courses(),
    };
    let mut index_revision = None;
    match record.payload {
        CachePayload::JudgeDetail(detail) => {
            batch.kind = JudgeScanKind::Detail;
            batch.course_id = Some(detail.course_id.clone());
            batch.detail = Some(*detail);
            scan.cursor.finish_detail();
        }
        CachePayload::JudgeAssignments(assignments) => {
            batch.kind = JudgeScanKind::Assignments;
            batch.course_id = scan
                .cursor
                .current_course()
                .map(|item| item.course_id.clone());
            batch.assignments.clone_from(&assignments);
            index_revision = Some(record.revision);
            scan.cursor.accept_assignments(assignments);
        }
        _ => return Err(OfflineReadError::Cache(CacheError::Corrupt)),
    }
    batch.finished = scan.cursor.finished();
    batch.complete = scan.cursor.complete();
    Ok(Step {
        batch,
        reused: true,
        source_at: record.fetched_at,
        child: None,
        index_revision,
    })
}

pub(super) fn next_reused_detail(
    refresh: &mut JudgeRefresh,
) -> Result<Option<Step>, OfflineReadError> {
    let Some(assignment) = refresh.scan.cursor.current_assignment() else {
        return Ok(None);
    };
    let now = chrono::Utc::now().timestamp();
    let scope = CacheScope {
        route: refresh.scan.resolution.mode,
        query: CacheQuery::JudgeDetail {
            course_id: assignment.course_id.clone(),
            assignment_id: assignment.assignment_id.clone(),
        },
    };
    match refresh.scan.cache.read(&scope, now) {
        Ok(Some(record)) if policy::reusable(&record, assignment, &refresh.options, now) => {
            refresh.parallel.forget(&scope.query);
            reuse(&mut refresh.scan, record).map(Some)
        }
        Ok(_) => Ok(None),
        Err(error) => {
            remember_save(&mut refresh.save_error, Err::<(), _>(error))?;
            Ok(None)
        }
    }
}
