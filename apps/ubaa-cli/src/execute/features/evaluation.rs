//! 教学评教 handler。

use std::collections::HashSet;

use ubaa_core::facade::{
    ActionEligibility, EvaluationCoursesResponse, EvaluationSubmitCoursesRequest,
    EvaluationSubmitTarget, Result, Routed, RoutedError, RoutedResult,
};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{EvaluationArgs, EvaluationCommand};
use crate::execute::routed_readonly;
use crate::io::input::{internal_error, invalid_input, upstream_changed};
use crate::io::schema::{CliFeature, CommandOutput, readonly};

const CONFIRM_WRITE_MESSAGE: &str = "评教是写操作，必须显式指定 --confirm-write";
const NO_PENDING_MESSAGE: &str = "没有可提交的待评课程";
const UNSAFE_PENDING_MESSAGE: &str = "待评课程资格或提交目标无法安全确认，请刷新后重试";

pub(in crate::execute) async fn run_evaluation<B: CliBackend + Send>(
    arguments: EvaluationArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        EvaluationCommand::All => backend
            .evaluation_all()
            .await
            .and_then(|result| readonly(result, CliFeature::Evaluation)),
        EvaluationCommand::Pending => backend.evaluation_all().await.and_then(pending_output),
        EvaluationCommand::SubmitPending { confirm_write } => {
            if !confirm_write {
                return Err(invalid_input(CONFIRM_WRITE_MESSAGE));
            }
            let authority = backend.evaluation_all().await?;
            let route = authority.resolved_route;
            if backend.mode() != route {
                return Err(upstream_changed("评教 fresh authority 偏离固定后端路线"));
            }
            let request = pending_request(authority.data)?;
            let batch = match backend.evaluation_submit_courses(request).await {
                Ok(batch) => batch,
                Err(error) => {
                    let _ = backend.evaluation_all_on_route(route).await;
                    return Err(error);
                }
            };
            if batch.resolved_route != route {
                return Err(internal_error("评教提交结果偏离固定路线"));
            }
            let _ = backend.evaluation_all_on_route(route).await;
            Ok(CommandOutput::EvaluationBatch {
                data: batch.data,
                route,
            })
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
        EvaluationCommand::Pending => backend.evaluation_all().await.and_then(|value| {
            let output = pending_output(ubaa_core::facade::FeatureResult {
                data: value.data,
                resolved_route: value.resolution.mode,
            })
            .map_err(|error| RoutedError {
                error,
                resolution: Some(value.resolution),
            })?;
            Ok(Routed {
                data: output,
                resolution: value.resolution,
            })
        }),
        EvaluationCommand::SubmitPending { confirm_write } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input(CONFIRM_WRITE_MESSAGE),
                    resolution: None,
                });
            }
            let authority = backend.evaluation_all().await?;
            let route = authority.resolution.mode;
            let request = pending_request(authority.data).map_err(|error| RoutedError {
                error,
                resolution: Some(authority.resolution),
            })?;
            let batch = match backend
                .evaluation_submit_courses_if_route_matches(request, route)
                .await
            {
                Ok(batch) => batch,
                Err(error) => {
                    if error.resolution.is_some() {
                        let _ = backend.evaluation_all_on_route(route).await;
                    }
                    return Err(error);
                }
            };
            let _ = backend.evaluation_all_on_route(route).await;
            Ok(Routed {
                data: CommandOutput::EvaluationBatch {
                    data: batch.data,
                    route,
                },
                resolution: batch.resolution,
            })
        }
    }
}

fn pending_output(
    result: ubaa_core::facade::FeatureResult<EvaluationCoursesResponse>,
) -> Result<CommandOutput> {
    let pending = result
        .data
        .courses
        .into_iter()
        .filter(|course| !course.is_evaluated)
        .collect::<Vec<_>>();
    Ok(CommandOutput::Readonly {
        data: serde_json::to_value(pending).map_err(|_| internal_error("无法序列化评教输出"))?,
        route: result.resolved_route,
        feature: CliFeature::Evaluation,
    })
}

fn pending_request(response: EvaluationCoursesResponse) -> Result<EvaluationSubmitCoursesRequest> {
    let mut targets = Vec::new();
    let mut unique = HashSet::new();
    for course in response
        .courses
        .into_iter()
        .filter(|course| !course.is_evaluated)
    {
        if course.submit_eligibility != ActionEligibility::Allowed {
            return Err(upstream_changed(UNSAFE_PENDING_MESSAGE));
        }
        let target = course
            .submit_target
            .and_then(normalize_target)
            .ok_or_else(|| upstream_changed(UNSAFE_PENDING_MESSAGE))?;
        if !unique.insert(target.clone()) {
            return Err(upstream_changed(UNSAFE_PENDING_MESSAGE));
        }
        targets.push(target);
    }
    if targets.is_empty() {
        return Err(invalid_input(NO_PENDING_MESSAGE));
    }
    Ok(EvaluationSubmitCoursesRequest { targets })
}

fn normalize_target(target: EvaluationSubmitTarget) -> Option<EvaluationSubmitTarget> {
    let rwid = canonical_required(target.rwid)?;
    let wjid = canonical_required(target.wjid)?;
    let kcdm = canonical_required(target.kcdm)?;
    let bpdm = match target.bpdm {
        None => None,
        Some(value) if value.is_empty() => None,
        Some(value) if value == value.trim() => Some(value),
        Some(_) => return None,
    };
    Some(EvaluationSubmitTarget {
        rwid,
        wjid,
        kcdm,
        bpdm,
    })
}

fn canonical_required(value: String) -> Option<String> {
    (!value.is_empty() && value == value.trim()).then_some(value)
}
