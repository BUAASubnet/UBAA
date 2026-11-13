//! Direct 详情读取使用独立业务 Cookie，整组收尾后才交还宿主。
use crate::{
    domain::{Assignment, JudgeAssignmentDetail},
    error::Result,
    runtime::ClientRuntime,
};

pub(crate) struct DetailWorker {
    runtime: ClientRuntime,
    activated: bool,
}
impl DetailWorker {
    pub(crate) fn new(parent: &mut ClientRuntime) -> Self {
        Self {
            runtime: super::batch::fork_judge_worker(parent),
            activated: false,
        }
    }
    pub(crate) async fn read(&mut self, assignment: &Assignment) -> PreparedDetail {
        self.runtime.reset_network_observation();
        let state = self.runtime.feature_state();
        let result = super::service::get_detail_cached(
            &mut self.runtime,
            &state,
            state.judge.generation(),
            assignment,
            &mut self.activated,
            true,
        )
        .await;
        PreparedDetail {
            result,
            source_at: chrono::Utc::now().timestamp(),
            failure_domain: self.runtime.network_failure_domain.clone(),
            reached_domains: self.runtime.reached_domains.clone(),
        }
    }
}
pub(crate) struct PreparedDetail {
    result: Result<JudgeAssignmentDetail>,
    pub(crate) source_at: i64,
    failure_domain: Option<String>,
    reached_domains: std::collections::BTreeSet<String>,
}
impl PreparedDetail {
    pub(crate) async fn finish(
        self,
        runtime: &mut ClientRuntime,
    ) -> super::scan::ScanRead<JudgeAssignmentDetail> {
        runtime.network_failure_domain = self.failure_domain;
        runtime.reached_domains = self.reached_domains;
        super::scan::finish(runtime, self.result).await
    }
}
