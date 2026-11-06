//! 分段读取切换路线时重新建立该路线的业务激活和选课上下文。
use super::{
    Assignment, Course, JudgeAssignmentDetail, JudgeScanBatch, JudgeScanKind, RouteResolution,
    UbaaClient, scan,
};

pub(super) enum BatchData {
    Assignments(Vec<Assignment>),
    Detail(Box<JudgeAssignmentDetail>),
}
impl BatchData {
    pub(super) fn apply(self, batch: &mut JudgeScanBatch) {
        match self {
            Self::Assignments(value) => {
                batch.kind = JudgeScanKind::Assignments;
                batch.assignments = value;
            }
            Self::Detail(value) => {
                batch.kind = JudgeScanKind::Detail;
                batch.detail = Some(*value);
            }
        }
    }
}
impl UbaaClient {
    pub(super) async fn read_judge_batch(
        &mut self,
        resolution: RouteResolution,
        course: &Course,
        assignment: Option<&Assignment>,
        was_activated: bool,
        force_fresh: bool,
    ) -> (RouteResolution, scan::ScanRead<BatchData>, bool) {
        let initial_route = resolution.mode;
        let mut fatal;
        let (resolution, result) = crate::facade::routing::read_with_fallback!(self, resolution, {
            let mut activated = resolution.mode == initial_route && was_activated;
            let read = if let Some(assignment) = assignment {
                let read = scan::detail(
                    self.runtime_for(resolution.mode),
                    assignment,
                    &mut activated,
                    force_fresh,
                )
                .await;
                scan::ScanRead {
                    result: read
                        .result
                        .map(|detail| BatchData::Detail(Box::new(detail))),
                    fatal: read.fatal,
                }
            } else {
                let read = scan::assignments(
                    self.runtime_for(resolution.mode),
                    course,
                    &mut activated,
                    force_fresh,
                )
                .await;
                scan::ScanRead {
                    result: read.result.map(BatchData::Assignments),
                    fatal: read.fatal,
                }
            };
            fatal = read.fatal;
            read.result.map(|data| (data, activated))
        });
        let activated = result.as_ref().map_or(was_activated, |(_, active)| *active);
        (
            resolution,
            scan::ScanRead {
                result: result.map(|(data, _)| data),
                fatal,
            },
            activated,
        )
    }
}
