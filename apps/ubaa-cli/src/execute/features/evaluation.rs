//! 教学评教 handler。

use ubaa_core::error::Result;
use ubaa_core::facade::{Routed, RoutedError, RoutedResult};
use ubaa_core::output::CliFeature;

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{EvaluationArgs, EvaluationCommand};
use crate::execute::routed_readonly;
use crate::io::input::{internal_error, invalid_input, read_evaluation_payload};
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_evaluation<B: CliBackend + Send>(
    arguments: EvaluationArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        EvaluationCommand::All => backend
            .evaluation_all()
            .await
            .and_then(|result| readonly(result, CliFeature::Evaluation)),
        EvaluationCommand::Pending => backend.evaluation_all().await.and_then(|result| {
            let pending: Vec<_> = result
                .data
                .courses
                .into_iter()
                .filter(|course| !course.is_evaluated)
                .collect();
            Ok(CommandOutput::Readonly {
                data: serde_json::to_value(pending)
                    .map_err(|_| internal_error("无法序列化评教输出"))?,
                route: result.resolved_route,
                feature: CliFeature::Evaluation,
            })
        }),
        EvaluationCommand::Submit {
            payload,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("评教是写操作，必须显式指定 --confirm-write"));
            }
            let payload = read_evaluation_payload(&payload)?;
            backend
                .evaluation_submit(payload)
                .await
                .and_then(|result| readonly(result, CliFeature::Evaluation))
        }
        EvaluationCommand::SubmitPending { confirm_write } => {
            if !confirm_write {
                return Err(invalid_input("评教是写操作，必须显式指定 --confirm-write"));
            }
            let result = backend.evaluation_all().await?;
            let courses = result
                .data
                .courses
                .into_iter()
                .filter(|course| !course.is_evaluated)
                .collect();
            backend
                .evaluation_submit_courses(courses)
                .await
                .and_then(|result| readonly(result, CliFeature::Evaluation))
        }
    }
}

pub(in crate::execute) async fn run_routed_evaluation<B: RoutedCliBackend + Send>(
    arguments: EvaluationArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        EvaluationCommand::All => {
            routed_readonly(backend.evaluation_all().await, CliFeature::Evaluation)
        }
        EvaluationCommand::Pending => match backend.evaluation_all().await {
            Ok(value) => {
                let data = value
                    .data
                    .courses
                    .into_iter()
                    .filter(|course| !course.is_evaluated)
                    .collect::<Vec<_>>();
                Ok(Routed {
                    data: CommandOutput::Readonly {
                        data: serde_json::to_value(data).unwrap_or(serde_json::Value::Null),
                        route: value.resolution.mode,
                        feature: CliFeature::Evaluation,
                    },
                    resolution: value.resolution,
                })
            }
            Err(error) => Err(error),
        },
        EvaluationCommand::Submit {
            payload,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("评教是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            let payload = read_evaluation_payload(&payload).map_err(|error| RoutedError {
                error,
                resolution: None,
            })?;
            routed_readonly(
                backend.evaluation_submit(payload).await,
                CliFeature::Evaluation,
            )
        }
        EvaluationCommand::SubmitPending { confirm_write } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("评教是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            let value = backend.evaluation_all().await?;
            let courses = value
                .data
                .courses
                .into_iter()
                .filter(|course| !course.is_evaluated)
                .collect();
            routed_readonly(
                backend.evaluation_submit_courses(courses).await,
                CliFeature::Evaluation,
            )
        }
    }
}
