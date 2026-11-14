//! 在线扫描的同课程预取，返回前收尾整组请求。
use super::{JudgeOnlineScan, OfflineReadError, RoutedError, UbaaClient};
use crate::features::judge::parallel::PreparedDetail;

impl UbaaClient {
    pub(super) async fn prepare_online_judge_details(
        &mut self,
        plan: &mut JudgeOnlineScan,
    ) -> Result<Option<PreparedDetail>, OfflineReadError> {
        let mut prepared = plan.cursor.take_prepared();
        if prepared.is_none() {
            let network = self.network_control();
            let runtime = self.runtime_for(plan.resolution.mode);
            let state = runtime.feature_state();
            let force = plan.options.full_refresh
                || plan.options.detail_refresh == crate::facade::JudgeDetailRefresh::RefreshActive
                || plan.options.keys.is_some();
            let assignments: Vec<_> = plan
                .cursor
                .pending_assignments()
                .iter()
                .take(4)
                .take_while(|a| {
                    !plan.cursor.has_prepared(a)
                        && (force
                            || state
                                .judge
                                .detail(
                                    state.judge.generation(),
                                    &a.course_id,
                                    &a.assignment_id,
                                    std::time::Instant::now(),
                                    std::time::Duration::from_mins(2),
                                )
                                .is_none())
                })
                .cloned()
                .collect();
            if assignments.len() >= 2 {
                let results = network
                    .run_read(
                        plan.resolution.mode,
                        plan.resolution.mode == crate::domain::ConnectionMode::Direct
                            && plan.resolution.policy == crate::domain::RoutePolicy::Auto
                            && plan.resolution.diagnostic.network
                                == crate::connection::NetworkState::OffCampus,
                        Box::pin(crate::features::judge::parallel::read_same_course_details(
                            runtime,
                            &assignments,
                        )),
                    )
                    .await
                    .map_err(|error| {
                        OfflineReadError::Read(RoutedError {
                            error,
                            resolution: Some(plan.resolution),
                        })
                    })?;
                self.validate_judge_online(plan)?;
                for result in results {
                    plan.cursor.push_prepared(result);
                }
                prepared = plan.cursor.take_prepared();
            }
        }
        Ok(prepared)
    }
}
