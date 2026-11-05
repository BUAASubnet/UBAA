//! 同步输出保留操作状态和待同步数量，未验证及未知结果不输出成功。
use crate::{CLI_JSON_SCHEMA_VERSION, CommandControl, StopReason};
use serde_json::{Value, json};
use std::io::Write;
use ubaa_core::facade::{
    AgendaSyncError, AgendaSyncReport, AgendaSyncStatus, CacheError, ErrorCode, ErrorKind,
    UbaaError,
};

pub struct AgendaSyncCommandResult(pub Result<AgendaSyncReport, AgendaSyncError>);
impl AgendaSyncCommandResult {
    pub fn render(
        self,
        json_mode: bool,
        control: &CommandControl,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        let mut result = self.0;
        // 宿主确认总期限后也会发出取消通知。写入结果未知时仍需提示只读核对。
        let keep_result = match &result {
            Ok(report) => report.status == AgendaSyncStatus::OutcomeUnknown,
            Err(AgendaSyncError::Remote(error)) => {
                matches!(error.code, ErrorCode::Timeout | ErrorCode::OutcomeUnknown)
            }
            Err(AgendaSyncError::Local(_)) => false,
        };
        if !keep_result && let Err(reason) = control.check() {
            result = Err(AgendaSyncError::Remote(UbaaError::new(
                if reason == StopReason::Deadline {
                    ErrorCode::Timeout
                } else {
                    ErrorCode::InternalError
                },
                ErrorKind::Internal,
                false,
                reason.message(),
            )));
        }
        let (exit, data, error) = match result {
            Ok(report) => {
                let data = json!({"status":status(report.status),"pendingCount":report.pending_count,"changedCount":report.changed_count});
                let (exit, code, message) = outcome(report.status);
                (
                    exit,
                    data,
                    (exit != 0).then(
                        || json!({"code":code,"kind":"local","retryable":false,"message":message}),
                    ),
                )
            }
            Err(AgendaSyncError::Remote(error)) => (
                crate::io::exit_code::exit_code(error.code) as i32,
                Value::Null,
                Some(
                    json!({"code":error.code,"kind":error.kind,"retryable":error.retryable,"message":error.message}),
                ),
            ),
            Err(AgendaSyncError::Local(error)) => {
                let (code, exit) = match error {
                    CacheError::Inactive => ("registration_required", 3),
                    CacheError::Superseded => ("stale_identity", 3),
                    CacheError::InvalidInput => ("invalid_input", 2),
                    CacheError::Corrupt | CacheError::UnsupportedVersion => ("agenda_corrupt", 7),
                    _ => ("storage", 7),
                };
                (
                    exit,
                    Value::Null,
                    Some(
                        json!({"code":code,"kind":"local","retryable":false,"message":"本机日程同步未完成，原数据已保留"}),
                    ),
                )
            }
        };
        if json_mode {
            let mut envelope = json!({"schemaVersion":CLI_JSON_SCHEMA_VERSION,"ok":exit==0,"data":data,"meta":{"feature":"agenda","operation":"sync"}});
            if let Some(error) = error {
                envelope["error"] = error;
            }
            if serde_json::to_writer(&mut *stdout, &envelope).is_err() || writeln!(stdout).is_err()
            {
                return 7;
            }
        } else if let Some(error) = error {
            if writeln!(
                stderr,
                "错误：{}",
                error["message"].as_str().unwrap_or("日程同步未完成")
            )
            .is_err()
            {
                return 7;
            }
            if let Some(count) = data.get("pendingCount").and_then(Value::as_u64)
                && writeln!(stdout, "本机待同步记录：{count}").is_err()
            {
                return 7;
            }
        } else if writeln!(
            stdout,
            "日程同步状态：{}；待同步记录：{}",
            data["status"].as_str().unwrap_or(""),
            data["pendingCount"]
        )
        .is_err()
        {
            return 7;
        }
        crate::runtime::finish_output(exit, stdout, stderr)
    }
}
fn status(value: AgendaSyncStatus) -> &'static str {
    match value {
        AgendaSyncStatus::UpToDate => "up_to_date",
        AgendaSyncStatus::Pending => "pending",
        AgendaSyncStatus::NeedsCreation => "needs_creation",
        AgendaSyncStatus::LocationUnknown => "location_unknown",
        AgendaSyncStatus::Unverified => "unverified",
        AgendaSyncStatus::Failed => "failed",
        AgendaSyncStatus::Conflict => "conflict",
        AgendaSyncStatus::OutcomeUnknown => "outcome_unknown",
    }
}

fn outcome(value: AgendaSyncStatus) -> (i32, &'static str, &'static str) {
    match value {
        AgendaSyncStatus::UpToDate | AgendaSyncStatus::Pending => (0, "", ""),
        AgendaSyncStatus::NeedsCreation => {
            (2, "sync_needs_creation", "尚未创建云端日程，修改保存在本机")
        }
        AgendaSyncStatus::LocationUnknown => (
            2,
            "sync_location_unknown",
            "尚未找到可确认的云端日程，修改保存在本机",
        ),
        AgendaSyncStatus::Unverified => {
            (6, "sync_unverified", "云端同步能力尚未验证，修改保存在本机")
        }
        AgendaSyncStatus::Failed => (5, "sync_failed", "同步未完成，修改保存在本机"),
        AgendaSyncStatus::Conflict => (6, "sync_conflict", "云端日程已更新，请重新合并"),
        AgendaSyncStatus::OutcomeUnknown => {
            (5, "outcome_unknown", "云端操作结果未知，请先只读核对")
        }
    }
}
