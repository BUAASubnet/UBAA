//! CLI 结果、路线错误与启动错误渲染。

use std::io::Write;

use serde_json::Value;
use ubaa_core::domain::ConnectionMode;
use ubaa_core::error::{Result, UbaaError};
use ubaa_core::facade::{RouteResolution, Routed, RoutedError, RoutedResult};

use crate::io::error::CliJsonError;
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
        Ok(output) => {
            let resolved_route = match &output {
                CommandOutput::Readonly { route, .. } => *route,
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
        let error = project_cli_error(error, feature, resolution.mode);
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

fn project_cli_error(
    error: UbaaError,
    _feature: CliFeature,
    _route: ConnectionMode,
) -> CliJsonError {
    CliJsonError::from_core(error)
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
