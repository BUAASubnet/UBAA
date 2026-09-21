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
        let assignment = refresh
            .scan
            .assignments
            .as_ref()
            .and_then(|items| items.get(refresh.scan.detail_index))
            .cloned();
        let course = refresh.scan.courses.get(refresh.scan.course_index).cloned();
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
            return reuse(&mut refresh.scan, record);
        }
        let child = scope
            .map(|scope| refresh.scan.cache.begin(scope))
            .transpose()
            .map_err(OfflineReadError::Cache)?;
        let batch = match self.next_judge_scan(&mut refresh.scan).await {
            Ok(result) => result.data,
            Err(error) => {
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
        let index_revision = (batch.kind == JudgeScanKind::Assignments)
            .then(|| child.as_ref().map(CacheReadTicket::revision))
            .flatten();
        Ok(Step {
            batch,
            reused: false,
            source_at: chrono::Utc::now().timestamp(),
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
        failed_courses: scan.failed_courses,
    };
    let mut index_revision = None;
    match record.payload {
        CachePayload::JudgeDetail(detail) => {
            batch.kind = JudgeScanKind::Detail;
            batch.course_id = Some(detail.course_id.clone());
            batch.detail = Some(*detail);
            scan.detail_index += 1;
            if scan
                .assignments
                .as_ref()
                .is_some_and(|items| scan.detail_index == items.len())
            {
                scan.advance_course();
            }
        }
        CachePayload::JudgeAssignments(assignments) => {
            batch.kind = JudgeScanKind::Assignments;
            batch.course_id = scan
                .courses
                .get(scan.course_index)
                .map(|item| item.course_id.clone());
            batch.assignments.clone_from(&assignments);
            index_revision = Some(record.revision);
            if assignments.is_empty() {
                scan.advance_course();
            } else {
                scan.assignments = Some(assignments);
            }
        }
        _ => return Err(OfflineReadError::Cache(CacheError::Corrupt)),
    }
    batch.finished = scan.course_index >= scan.courses.len();
    batch.complete = batch.finished && scan.failed_courses == 0;
    Ok(Step {
        batch,
        reused: true,
        source_at: record.fetched_at,
        child: None,
        index_revision,
    })
}
