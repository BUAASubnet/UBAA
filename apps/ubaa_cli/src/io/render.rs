//! CLI 结果、路线错误与启动错误渲染。

use std::io::Write;

use serde_json::Value;
use ubaa_core::facade::ConnectionMode;
use ubaa_core::facade::{ErrorCode, ErrorKind, EvaluationBatchResult, Result, UbaaError};
use ubaa_core::facade::{RouteResolution, Routed, RoutedError, RoutedResult};

use crate::io::error::{CliJsonError, EVALUATION_OUTCOME_UNKNOWN_MESSAGE};
use crate::io::exit_code::{ExitCode, exit_code};
use crate::io::human::render_human;
use crate::io::input::write_json;
use crate::io::schema::{
    CliFeature, CommandOutput, ResolvedRoutedJsonMeta, RoutedJsonEnvelope,
    UnresolvedRoutedJsonMeta, command_output_value,
};
use crate::routing::ReadonlyRouteContext;

pub(crate) fn render_routed_result<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    result: RoutedResult<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(Routed {
            data: CommandOutput::EvaluationBatch { data, route },
            resolution,
        }) if data.outcome_unknown => {
            render_evaluation_outcome_unknown(json_mode, data, route, resolution, stdout, stderr)
        }
        Ok(Routed { data, resolution }) => {
            if json_mode {
                let value = match command_output_value(data) {
                    Ok(value) => value,
                    Err(error) => {
                        return render_resolved_error(
                            true, feature, resolution, error, stdout, stderr,
                        );
                    }
                };
                let meta = ResolvedRoutedJsonMeta::from_resolution(feature, resolution);
                if write_json(stdout, &RoutedJsonEnvelope::success(value, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else {
                match data {
                    CommandOutput::Readonly {
                        data,
                        route,
                        feature,
                    } => {
                        if writeln!(stdout, "{} ({route:?}): {data}", feature.as_str()).is_err() {
                            return ExitCode::Internal as i32;
                        }
                    }
                    output => {
                        if render_human(output, stdout).is_err() {
                            return ExitCode::Internal as i32;
                        }
                    }
                }
            }
            ExitCode::Success as i32
        }
        Err(RoutedError {
            error,
            resolution: Some(resolution),
        }) => render_resolved_error(json_mode, feature, resolution, error, stdout, stderr),
        Err(RoutedError {
            error,
            resolution: None,
        }) => render_startup_error(json_mode, feature, error, stdout, stderr),
    }
}

pub(crate) fn render_result<O: Write, E: Write>(
    json_mode: bool,
    mode: ConnectionMode,
    feature: CliFeature,
    route_context: ReadonlyRouteContext,
    result: Result<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(CommandOutput::EvaluationBatch { data, route }) if data.outcome_unknown => {
            render_evaluation_outcome_unknown(
                json_mode,
                data,
                route,
                route_context.resolution(route),
                stdout,
                stderr,
            )
        }
        Ok(output) => {
            let resolved_route = match &output {
                CommandOutput::Readonly { route, .. }
                | CommandOutput::EvaluationBatch { route, .. } => *route,
                _ => mode,
            };
            if json_mode {
                let value = match command_output_value(output) {
                    Ok(value) => value,
                    Err(error) => {
                        return render_resolved_error(
                            true,
                            feature,
                            route_context.resolution(resolved_route),
                            error,
                            stdout,
                            stderr,
                        );
                    }
                };
                let meta = route_context.meta(feature, resolved_route);
                if write_json(stdout, &RoutedJsonEnvelope::success(value, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if let CommandOutput::Readonly {
                data,
                route,
                feature,
            } = output
            {
                if writeln!(stdout, "{}（{route:?}）：{data}", feature.as_str()).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if render_human(output, stdout).is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_resolved_error(
            json_mode,
            feature,
            route_context.resolution(mode),
            error,
            stdout,
            stderr,
        ),
    }
}

fn render_evaluation_outcome_unknown<O: Write, E: Write>(
    json_mode: bool,
    data: EvaluationBatchResult,
    route: ConnectionMode,
    resolution: RouteResolution,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let error = UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        EVALUATION_OUTCOME_UNKNOWN_MESSAGE,
    );
    if json_mode {
        let Ok(data) = serde_json::to_value(data) else {
            return ExitCode::Internal as i32;
        };
        let meta = ResolvedRoutedJsonMeta::from_resolution(CliFeature::Evaluation, resolution);
        let envelope = RoutedJsonEnvelope::evaluation_outcome_unknown(
            data,
            CliJsonError::from_core(error),
            meta,
        );
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else {
        if render_human(CommandOutput::EvaluationBatch { data, route }, stdout).is_err() {
            return ExitCode::Internal as i32;
        }
        if writeln!(stderr, "错误：{error}").is_err() {
            return ExitCode::Internal as i32;
        }
    }
    ExitCode::Network as i32
}

fn render_resolved_error<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    resolution: RouteResolution,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit_code = exit_code(error.code) as i32;
    if json_mode {
        let error = CliJsonError::from_core(error);
        let meta = ResolvedRoutedJsonMeta::from_resolution(feature, resolution);
        let envelope = RoutedJsonEnvelope::<Value>::resolved_failure(error, meta);
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "错误：{error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

/// 在后端构造前展示错误，并保持 JSON 标准输出约束。
pub fn render_startup_error<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit_code = exit_code(error.code) as i32;
    if json_mode {
        let envelope = RoutedJsonEnvelope::<Value>::unresolved_failure(
            CliJsonError::from_core(error),
            UnresolvedRoutedJsonMeta::new(feature),
        );
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "错误：{error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}
