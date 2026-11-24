use super::{BridgeWriteIntent, BridgeWriteOperation, PendingWrite};
use crate::api::{
    bhpan::BridgeBhpanTransfer,
    client::{BridgeClient, BridgeError, catch_panic, disposed_error},
    read::spoc_files::BridgeSpocSubmitAction,
};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeSpocSubmitSummary {
    pub title: String,
    pub course_name: String,
    pub file_name: String,
    pub byte_len: u64,
    pub due_time: Option<String>,
    pub past_due: Option<bool>,
    pub late_submission_deadline: Option<String>,
    pub submission_count: Option<u32>,
}
#[derive(Clone, Debug)]
pub struct BridgeSpocSubmitReceipt {
    pub submitted_at: Option<String>,
    pub file_name: String,
    pub file_id: String,
}

impl BridgeClient {
    pub async fn prepare_spoc_submit_assignment(
        &self,
        action: BridgeSpocSubmitAction,
        path: String,
        transfer: &BridgeBhpanTransfer,
    ) -> Result<BridgeWriteIntent, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let target = core::SpocSubmitAction {
                assignment_id: action.assignment_id,
                course_id: action.course_id,
                allowed_extensions: action.allowed_extensions,
                max_submissions: action.max_submissions,
                due_time: action.due_time,
                late_submission_deadline: action.late_submission_deadline,
            };
            let prepared = client
                .prepare_spoc_submit_assignment(
                    &target,
                    std::path::Path::new(&path),
                    transfer.control.clone(),
                )
                .await
                .map_err(BridgeError::from_routed)?;
            let summary = prepared.data.summary();
            let label = format!(
                "{} · {} · {}（{} 字节）",
                summary.course_name, summary.title, summary.file_name, summary.byte_len
            );
            let dto = BridgeSpocSubmitSummary {
                title: summary.title.clone(),
                course_name: summary.course_name.clone(),
                file_name: summary.file_name.clone(),
                byte_len: summary.byte_len,
                due_time: summary.due_time.clone(),
                past_due: summary.past_due,
                late_submission_deadline: summary.late_submission_deadline.clone(),
                submission_count: summary.submission_count,
            };
            let warnings = if summary.past_due == Some(true) {
                vec!["已过作业截止时间，是否接受提交以学校结果为准".into()]
            } else {
                vec![]
            };
            let mut intent = self
                .store_write_intent(
                    BridgeWriteOperation::SpocSubmitAssignment,
                    format!("{}:{}:{}", target.course_id, target.assignment_id, label),
                    label,
                    warnings,
                    PendingWrite::Spoc(prepared.data),
                    prepared.resolution,
                )
                .await?;
            intent.spoc_summary = Some(dto);
            Ok(intent)
        })
        .await
    }
}
