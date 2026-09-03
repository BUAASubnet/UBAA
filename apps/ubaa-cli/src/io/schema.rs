//! CLI 命令结果模型与 Core 结果投影。

use serde::Serialize;
use serde_json::Value;
use ubaa_core::domain::{AuthStatus, ConnectionMode, FeatureResult, UserProfile};
use ubaa_core::error::Result;
use ubaa_core::output::CliFeature;

use crate::io::input::internal_error;

pub(crate) fn readonly<T: Serialize>(
    result: FeatureResult<T>,
    feature: CliFeature,
) -> Result<CommandOutput> {
    let data =
        serde_json::to_value(result.data).map_err(|_| internal_error("无法序列化命令输出"))?;
    Ok(CommandOutput::Readonly {
        data,
        route: result.resolved_route,
        feature,
    })
}

pub(crate) enum CommandOutput {
    Profile(UserProfile),
    Status(AuthStatus),
    Logout(Value),
    Readonly {
        data: Value,
        route: ConnectionMode,
        feature: CliFeature,
    },
}

pub(crate) fn command_output_value(output: CommandOutput) -> Result<Value> {
    match output {
        CommandOutput::Profile(profile) => serde_json::to_value(profile),
        CommandOutput::Status(status) => serde_json::to_value(status),
        CommandOutput::Logout(value) | CommandOutput::Readonly { data: value, .. } => Ok(value),
    }
    .map_err(|_| internal_error("无法序列化命令输出"))
}
