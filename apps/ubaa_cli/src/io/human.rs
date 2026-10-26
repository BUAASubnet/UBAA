//! CLI 输出层的安全投影与脱敏辅助。

use std::io::{self, Write};

use serde_json::{Value, json};
use ubaa_core::facade::{
    AuthStatus, CgyyLockCode, EvaluationBatchResult, EvaluationCourseOutcome, UserProfile,
};

use super::schema::CommandOutput;

pub(crate) fn safe_lock_code_value(data: &CgyyLockCode) -> Value {
    json!({"available": data.available})
}

pub(crate) fn write_profile<W: Write>(stdout: &mut W, profile: &UserProfile) -> io::Result<()> {
    write_optional(stdout, "姓名", profile.name.as_deref())?;
    write_optional(stdout, "学号", profile.school_id.as_deref())?;
    write_optional(stdout, "用户名", profile.username.as_deref())?;
    write_optional(stdout, "手机号", profile.phone.as_deref())?;
    write_optional(stdout, "身份证号", profile.id_card_number.as_deref())?;
    write_optional(stdout, "邮箱", profile.email.as_deref())
}

pub(crate) fn render_human<O: Write>(output: CommandOutput, stdout: &mut O) -> io::Result<()> {
    match output {
        CommandOutput::Profile(profile) => write_profile(stdout, &profile),
        CommandOutput::Status(status) => {
            writeln!(stdout, "已认证：是")?;
            writeln!(stdout, "连接检查时间：{}", status.last_activity)?;
            write_profile(stdout, &status.user)
        }
        CommandOutput::Logout(_) => writeln!(stdout, "已退出登录。"),
        CommandOutput::Readonly { .. } => unreachable!("readonly output handled above"),
        CommandOutput::EvaluationBatch { data, .. } => write_evaluation_batch(stdout, &data),
    }
}

fn write_evaluation_batch<W: Write>(
    stdout: &mut W,
    batch: &EvaluationBatchResult,
) -> io::Result<()> {
    let summary = if batch.outcome_unknown {
        "结果未知"
    } else if batch.success {
        "全部成功"
    } else {
        "部分失败"
    };
    writeln!(stdout, "评教批量提交：{summary}")?;
    for item in &batch.items {
        let outcome = match item.outcome {
            EvaluationCourseOutcome::Success => "成功",
            EvaluationCourseOutcome::Failure => "失败",
            EvaluationCourseOutcome::OutcomeUnknown => "结果未知",
            EvaluationCourseOutcome::Unattempted => "未尝试",
        };
        writeln!(
            stdout,
            "- {}：{}（{}）",
            item.course_name, outcome, item.message
        )?;
    }
    Ok(())
}

fn write_optional<W: Write>(stdout: &mut W, label: &str, value: Option<&str>) -> io::Result<()> {
    if let Some(value) = value {
        writeln!(stdout, "{label}: {value}")?;
    }
    Ok(())
}

pub(crate) fn redacted_status(mut status: AuthStatus) -> AuthStatus {
    status.user = redacted_profile(status.user);
    status
}

pub(crate) fn redacted_profile(mut profile: UserProfile) -> UserProfile {
    profile.phone = profile.phone.as_deref().map(mask_sensitive);
    profile.id_card_number = profile.id_card_number.as_deref().map(mask_sensitive);
    profile
}

pub(crate) fn mask_sensitive(value: &str) -> String {
    let characters: Vec<char> = value.chars().collect();
    match characters.len() {
        0 => String::new(),
        1..=4 => "*".repeat(characters.len()),
        length => format!(
            "{}{}{}",
            characters[..2].iter().collect::<String>(),
            "*".repeat(length - 4),
            characters[length - 2..].iter().collect::<String>()
        ),
    }
}
