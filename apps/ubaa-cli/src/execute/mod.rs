//! CLI dispatcher 与共享结果投影。

use serde::Serialize;
use ubaa_core::facade::{Routed, RoutedError, RoutedResult};
use ubaa_core::output::CliFeature;

use crate::command::command_feature;
use crate::io::input::internal_error;
use crate::io::schema::CommandOutput;

mod aggregate;
mod features;
mod fixed;
mod routed;

pub use aggregate::{run_dual_login, run_dual_logout, run_dual_status};
pub use fixed::{run_with_backend, run_with_backend_with_route};
pub use routed::run_with_routed_backend;

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
