//! SPOC、希冀与课堂签到 handler。

use crate::io::schema::CliFeature;
use ubaa_core::facade::JudgeAssignmentKey;
use ubaa_core::facade::Result;
use ubaa_core::facade::{RoutedError, RoutedResult};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{
    JudgeArgs, JudgeAssignmentCommand, JudgeCommand, SigninArgs, SigninCommand, SpocArgs,
    SpocAssignmentCommand, SpocCommand,
};
use crate::execute::routed_readonly;
use crate::io::input::invalid_input;
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_spoc<B: CliBackend + Send>(
    arguments: SpocArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        SpocCommand::Assignments => backend
            .spoc_assignments()
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
        SpocCommand::Diagnostics => backend
            .spoc_assignments_diagnostics()
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => backend
            .spoc_assignment(&id)
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
    }
}

pub(in crate::execute) async fn run_judge<B: CliBackend + Send>(
    arguments: JudgeArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        JudgeCommand::Assignments { include_expired } => backend
            .judge_assignments(include_expired)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Diagnostics { include_expired } => backend
            .judge_assignments_diagnostics(include_expired)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => backend
            .judge_assignment(&course_id, &id)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("希冀详情键必须使用 course-id:assignment-id 格式")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "希冀详情键必须使用 course-id:assignment-id 格式",
                        ));
                    }
                    Ok(JudgeAssignmentKey {
                        course_id: course_id.into(),
                        assignment_id: assignment_id.into(),
                    })
                })
                .collect::<Result<Vec<_>>>()?;
            backend
                .judge_assignment_details(&parsed)
                .await
                .and_then(|result| readonly(result, CliFeature::Judge))
        }
    }
}

pub(in crate::execute) async fn run_signin<B: CliBackend + Send>(
    arguments: SigninArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        SigninCommand::Today => backend
            .signin_today()
            .await
            .and_then(|data| readonly(data, CliFeature::Signin)),
        SigninCommand::Perform {
            course_id,
            confirm_write,
        } => {
            if confirm_write {
                backend
                    .signin_perform(&course_id)
                    .await
                    .and_then(|data| readonly(data, CliFeature::Signin))
            } else {
                Err(invalid_input("签到是写操作，必须显式指定 --confirm-write"))
            }
        }
    }
}

pub(in crate::execute) async fn run_routed_spoc<B: RoutedCliBackend + Send>(
    arguments: SpocArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        SpocCommand::Assignments => {
            routed_readonly(backend.spoc_assignments().await, CliFeature::Spoc)
        }
        SpocCommand::Diagnostics => routed_readonly(
            backend.spoc_assignments_diagnostics().await,
            CliFeature::Spoc,
        ),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => routed_readonly(backend.spoc_assignment(&id).await, CliFeature::Spoc),
    }
}

pub(in crate::execute) async fn run_routed_judge<B: RoutedCliBackend + Send>(
    arguments: JudgeArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        JudgeCommand::Assignments { include_expired } => routed_readonly(
            backend.judge_assignments(include_expired).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Diagnostics { include_expired } => routed_readonly(
            backend.judge_assignments_diagnostics(include_expired).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => routed_readonly(
            backend.judge_assignment(&course_id, &id).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("希冀详情键必须使用 course-id:assignment-id 格式")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "希冀详情键必须使用 course-id:assignment-id 格式",
                        ));
                    }
                    Ok(JudgeAssignmentKey {
                        course_id: course_id.into(),
                        assignment_id: assignment_id.into(),
                    })
                })
                .collect::<Result<Vec<_>>>()
                .map_err(|error| RoutedError {
                    error,
                    resolution: None,
                })?;
            routed_readonly(
                backend.judge_assignment_details(&parsed).await,
                CliFeature::Judge,
            )
        }
    }
}

pub(in crate::execute) async fn run_routed_signin<B: RoutedCliBackend + Send>(
    arguments: SigninArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        SigninCommand::Today => routed_readonly(backend.signin_today().await, CliFeature::Signin),
        SigninCommand::Perform {
            course_id,
            confirm_write,
        } => {
            let result = if confirm_write {
                backend.signin_perform(&course_id).await
            } else {
                Err(RoutedError {
                    error: invalid_input("签到是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                })
            };
            routed_readonly(result, CliFeature::Signin)
        }
    }
}
