//! 个人文件作业的预检、单次提交与原路线核对。
mod file;
mod upload;

use super::{
    SpocCredential, detail::fetch_submission, files::business_post, get_assignment_detail,
};
use crate::{
    domain::{
        ConnectionMode, SpocSubmitAction, SpocSubmitReceipt, SpocSubmitSummary,
        bhpan::{BhpanTransferPhase as Phase, transfer::BhpanTransfer},
    },
    error::{ErrorCode, ErrorKind, Result, UbaaError},
    runtime::ClientRuntime,
};
use file::Source;
use std::path::Path;

const CHUNK: u64 = 2_048_000;
const SUBMIT: &str = "https://spoc.buaa.edu.cn/spocnewht/kczy/submitKcz2";
pub(super) fn chunk_count(size: u64) -> u64 {
    (size / CHUNK).max(1)
}
pub(super) fn chunk_len(size: u64, number: u64) -> u64 {
    if number == chunk_count(size) {
        size - (number - 1) * CHUNK
    } else {
        CHUNK
    }
}

/// 仅能消费一次的本机文件意图，路径和摘要不投影到日志或持久缓存。
pub struct SpocPreparedSubmission {
    action: SpocSubmitAction,
    source: Source,
    summary: SpocSubmitSummary,
    route: ConnectionMode,
    generation: uuid::Uuid,
    transfer: BhpanTransfer,
}
impl SpocPreparedSubmission {
    #[must_use]
    pub fn assignment_id(&self) -> &str {
        &self.action.assignment_id
    }
    #[must_use]
    pub const fn summary(&self) -> &SpocSubmitSummary {
        &self.summary
    }
    pub(crate) const fn route(&self) -> ConnectionMode {
        self.route
    }
}

pub(crate) async fn prepare(
    runtime: &mut ClientRuntime,
    action: &SpocSubmitAction,
    path: &Path,
    transfer: BhpanTransfer,
) -> Result<SpocPreparedSubmission> {
    transfer.claim()?;
    let result = async {
        let detail = get_assignment_detail(runtime, &action.assignment_id).await?;
        let current = detail.submit_action.ok_or_else(|| {
            UbaaError::invalid_input(
                detail
                    .submit_unavailable_reason
                    .unwrap_or_else(|| "请刷新作业详情".into()),
            )
        })?;
        if action.course_id != current.course_id || action.assignment_id != current.assignment_id {
            return Err(UbaaError::invalid_input("作业目标已变化，请重新准备"));
        }
        let source = Source::open(path, &current.allowed_extensions, &transfer).await?;
        let now = chrono::DateTime::<chrono::Utc>::from(runtime.now())
            .with_timezone(&chrono_tz::Asia::Shanghai)
            .naive_local();
        let past_due = detail
            .due_time
            .as_deref()
            .and_then(|value| {
                chrono::NaiveDateTime::parse_from_str(value, "%Y-%m-%d %H:%M:%S").ok()
            })
            .map(|deadline| now > deadline);
        let summary = SpocSubmitSummary {
            title: detail.title,
            course_name: detail.course_name,
            file_name: source.name.clone(),
            byte_len: source.size,
            due_time: detail.due_time,
            past_due,
            late_submission_deadline: detail.late_submission_deadline,
            submission_count: detail.submission_count.or_else(|| {
                (detail.submission_status == crate::domain::SpocSubmissionStatus::Unsubmitted)
                    .then_some(0)
            }),
        };
        transfer.set(Phase::AwaitingConfirmation, 0, source.size);
        Ok(SpocPreparedSubmission {
            action: current,
            source,
            summary,
            route: runtime.mode(),
            generation: runtime.authentication_generation(),
            transfer: transfer.clone(),
        })
    }
    .await;
    if result.is_err() {
        transfer.set(Phase::Failed, 0, 0);
    }
    result
}

pub(crate) async fn confirm(
    runtime: &mut ClientRuntime,
    prepared: SpocPreparedSubmission,
) -> Result<SpocSubmitReceipt> {
    let progress = &prepared.transfer;
    let result = async {
        if prepared.generation != runtime.authentication_generation() {
            return Err(UbaaError::invalid_input("作业会话已变化，请重新准备"));
        }
        let mut file = prepared.source.verify(progress).await?;
        let (id, credential) =
            upload::upload(runtime, &prepared.source, &mut file, progress).await?;
        progress.ensure_active()?;
        progress.set(
            Phase::Submitting,
            prepared.source.size,
            prepared.source.size,
        );
        submit_and_verify(
            runtime,
            &prepared.action,
            &prepared.source,
            &id,
            &credential,
            progress,
        )
        .await
    }
    .await;
    let phase = match &result {
        Ok(_) => Phase::Completed,
        Err(error) if error.code == ErrorCode::OutcomeUnknown => Phase::OutcomeUnknown,
        Err(_) => Phase::Failed,
    };
    progress.set(phase, progress.progress().bytes, prepared.source.size);
    result
}

async fn submit_and_verify(
    runtime: &mut ClientRuntime,
    action: &SpocSubmitAction,
    source: &Source,
    id: &str,
    credential: &SpocCredential,
    progress: &BhpanTransfer,
) -> Result<SpocSubmitReceipt> {
    let url = runtime.url(SUBMIT)?;
    let mut request = business_post(url.clone(), credential)
        .with_header("Content-Type", "application/x-www-form-urlencoded");
    // ytjcs=2 是官方提交页的固定值，与学生实际已提交次数无关。
    request.body = encode(&[
        ("kczyid", &action.assignment_id),
        ("tjfs", "5"),
        ("scwjid", id),
        ("scwjid_name", &source.name),
        ("tjlx", "5"),
        ("ytjcs", "2"),
        ("sskcid", &action.course_id),
    ])
    .into_bytes();
    match runtime
        .request_non_idempotent_with_pre_send_check(request, |_| progress.ensure_active())
        .await
    {
        Err(error) if error.code != ErrorCode::OutcomeUnknown => return Err(error),
        Ok(response) if response.status == 200 && response.final_url == url => {
            if let Ok(envelope) =
                serde_json::from_slice::<super::Envelope<serde_json::Value>>(&response.body)
                && envelope.code != 200
                && let Some(message) = envelope.msg.filter(|msg| !msg.trim().is_empty())
            {
                return Err(UbaaError::new(
                    ErrorCode::BusinessRejected,
                    ErrorKind::Upstream,
                    false,
                    "学校未接受本次作业提交",
                )
                .with_private_display_message(message));
            }
        }
        _ => {}
    }
    progress.set(Phase::Checking, source.size, source.size);
    let record = fetch_submission(runtime, action.assignment_id.clone(), credential)
        .await
        .ok()
        .flatten()
        .filter(|record| {
            record.scwjid.as_deref() == Some(id)
                && record
                    .tjzt
                    .as_deref()
                    .is_some_and(|status| !status.trim().is_empty())
        })
        .ok_or_else(|| {
            UbaaError::outcome_unknown("作业提交结果未知，请刷新详情核对，不要重复提交")
        })?;
    Ok(SpocSubmitReceipt {
        file_name: source.name.clone(),
        file_id: id.into(),
        submitted_at: super::calendar::normalize_datetime(record.tjsj.as_deref()),
    })
}

fn encode(pairs: &[(&str, &str)]) -> String {
    url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(pairs.iter().copied())
        .finish()
}
