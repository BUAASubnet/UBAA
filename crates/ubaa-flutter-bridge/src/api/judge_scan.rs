//! 每次调用仅持网络锁完成一批；计划与取消标记不包含学校会话。
use super::client::{
    BridgeClient, BridgeError, BridgeRouteDecision, catch_panic, disposed_error, map_route,
};
use super::offline::{BridgeOfflineCache, offline_read_error};
use super::read::{BridgeJudgeAssignmentDetail, map_judge_detail};
use ubaa_core::facade as core;

pub struct BridgeJudgeScan {
    plan: tokio::sync::Mutex<core::JudgeScan>,
    cancellation: core::JudgeScanCancellation,
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeCourse {
    pub course_id: String,
    pub course_name: String,
}
#[derive(Clone, Debug)]
pub struct BridgeJudgeAssignmentIndex {
    pub assignment_id: String,
    pub course_id: String,
    pub course_name: String,
    pub title: String,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeJudgeScanKind {
    Assignments,
    Detail,
    CourseFailure,
    Finished,
}
/// 逐批内容与扫描完整度；未声明持久保存成功或刚完成网络刷新。
#[derive(Clone, Debug)]
pub struct BridgeJudgeScanBatch {
    pub kind: BridgeJudgeScanKind,
    pub route: BridgeRouteDecision,
    pub course_id: Option<String>,
    pub assignments: Vec<BridgeJudgeAssignmentIndex>,
    pub detail: Option<BridgeJudgeAssignmentDetail>,
    pub error: Option<BridgeError>,
    pub finished: bool,
    pub complete: bool,
    pub failed_courses: u32,
}
impl BridgeJudgeScan {
    /// 仅设置取消标记，不等待客户端锁，不中断在途 HTTP。
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }
    /// 返回已读取索引；不发学校请求。
    pub async fn courses(&self) -> Vec<BridgeJudgeCourse> {
        self.plan
            .lock()
            .await
            .courses()
            .iter()
            .map(|course| BridgeJudgeCourse {
                course_id: course.course_id.clone(),
                course_name: course.course_name.clone(),
            })
            .collect()
    }
}
impl BridgeClient {
    /// 开始有界扫描。索引成功返回后释放客户端共享锁。
    ///
    /// # Errors
    /// 身份、会话、存储或学校索引失败时保留稳定错误。
    pub async fn begin_judge_scan(
        &self,
        cache: &BridgeOfflineCache,
        include_expired: bool,
        preferred_course: Option<String>,
    ) -> Result<BridgeJudgeScan, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let plan = client
                .begin_judge_scan(&cache.cache, include_expired, preferred_course.as_deref())
                .await
                .map_err(offline_read_error)?;
            let cancellation = plan.cancellation();
            Ok(BridgeJudgeScan {
                plan: tokio::sync::Mutex::new(plan),
                cancellation,
            })
        })
        .await
    }
    /// 完成一次完整选课及索引或详情读取，然后归还共享锁。
    ///
    /// # Errors
    /// 取消、较新请求、账号/路线失效或写操作冲突时拒绝旧批次。
    pub async fn next_judge_scan(
        &self,
        scan: &BridgeJudgeScan,
    ) -> Result<BridgeJudgeScanBatch, BridgeError> {
        catch_panic(async {
            // 固定先获取计划锁，避免同计划并发调用排队占用客户端锁。
            let mut plan = scan.plan.lock().await;
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let result = client
                .next_judge_scan(&mut plan)
                .await
                .map_err(offline_read_error)?;
            Ok(map_scan_batch(result))
        })
        .await
    }
}

#[cfg(test)]
#[path = "judge_scan/tests.rs"]
mod tests;

pub(super) fn map_scan_batch(result: core::Routed<core::JudgeScanBatch>) -> BridgeJudgeScanBatch {
    let data = result.data;
    BridgeJudgeScanBatch {
        kind: match data.kind {
            core::JudgeScanKind::Assignments => BridgeJudgeScanKind::Assignments,
            core::JudgeScanKind::Detail => BridgeJudgeScanKind::Detail,
            core::JudgeScanKind::CourseFailure => BridgeJudgeScanKind::CourseFailure,
            core::JudgeScanKind::Finished => BridgeJudgeScanKind::Finished,
        },
        route: map_route(result.resolution),
        course_id: data.course_id,
        assignments: data
            .assignments
            .into_iter()
            .map(|item| BridgeJudgeAssignmentIndex {
                assignment_id: item.assignment_id,
                course_id: item.course_id,
                course_name: item.course_name,
                title: item.title,
            })
            .collect(),
        detail: data.detail.map(map_judge_detail),
        error: data
            .error
            .map(|error| BridgeError::from_core(error, Some(result.resolution.mode.into()))),
        finished: data.finished,
        complete: data.complete,
        failed_courses: u32::try_from(data.failed_courses).unwrap_or(u32::MAX),
    }
}

pub mod online;
