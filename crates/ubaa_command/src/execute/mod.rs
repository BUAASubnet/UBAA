//! CLI dispatcher 与共享结果投影。

use serde::Serialize;
use ubaa_core::facade::{Routed, RoutedError, RoutedResult};

use crate::io::input::internal_error;
use crate::io::schema::{CliFeature, CommandOutput};

pub(crate) mod aggregate;
mod features;
pub(crate) mod routed;

pub(in crate::execute) fn routed_map<T>(
    result: RoutedResult<T>,
    map: impl FnOnce(T) -> CommandOutput,
) -> RoutedResult<CommandOutput> {
    result.map(|Routed { data, resolution }| Routed {
        data: map(data),
        resolution,
    })
}

pub(in crate::execute) fn routed_readonly<T: Serialize>(
    result: RoutedResult<T>,
    feature: CliFeature,
) -> RoutedResult<CommandOutput> {
    result.and_then(|Routed { data, resolution }| {
        let data = serde_json::to_value(data).map_err(|_| RoutedError {
            error: internal_error("无法序列化命令输出"),
            resolution: Some(resolution),
        })?;
        Ok(Routed {
            data: CommandOutput::Readonly {
                data,
                route: resolution.mode,
                feature,
            },
            resolution,
        })
    })
}
