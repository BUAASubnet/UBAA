//! 阳光打卡 handler。

use crate::io::schema::CliFeature;
use ubaa_core::error::Result;
use ubaa_core::facade::{RoutedError, RoutedResult};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{YgdkArgs, YgdkCommand};
use crate::execute::routed_readonly;
use crate::io::input::{build_ygdk_request, invalid_input};
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_ygdk<B: CliBackend + Send>(
    arguments: YgdkArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        YgdkCommand::Overview => backend
            .ygdk_overview()
            .await
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        YgdkCommand::Records { page, size } => backend
            .ygdk_records(page, size)
            .await
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        YgdkCommand::Submit {
            item_id,
            start_time,
            end_time,
            place,
            photo,
            share_to_square,
            confirm_write,
        } => {
            if confirm_write {
                match build_ygdk_request(
                    item_id,
                    start_time,
                    end_time,
                    place,
                    &photo,
                    share_to_square,
                ) {
                    Ok(request) => backend
                        .ygdk_submit(request)
                        .await
                        .and_then(|data| readonly(data, CliFeature::Ygdk)),
                    Err(error) => Err(error),
                }
            } else {
                Err(invalid_input("打卡是写操作，必须显式指定 --confirm-write"))
            }
        }
    }
}

pub(in crate::execute) async fn run_routed_ygdk<B: RoutedCliBackend + Send>(
    arguments: YgdkArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        YgdkCommand::Overview => routed_readonly(backend.ygdk_overview().await, CliFeature::Ygdk),
        YgdkCommand::Records { page, size } => {
            routed_readonly(backend.ygdk_records(page, size).await, CliFeature::Ygdk)
        }
        YgdkCommand::Submit {
            item_id,
            start_time,
            end_time,
            place,
            photo,
            share_to_square,
            confirm_write,
        } => {
            let result = if confirm_write {
                match build_ygdk_request(
                    item_id,
                    start_time,
                    end_time,
                    place,
                    &photo,
                    share_to_square,
                ) {
                    Ok(request) => backend.ygdk_submit(request).await,
                    Err(error) => Err(RoutedError {
                        error,
                        resolution: None,
                    }),
                }
            } else {
                Err(RoutedError {
                    error: invalid_input("打卡是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                })
            };
            routed_readonly(result, CliFeature::Ygdk)
        }
    }
}
