//! 场馆预约 handler。

use crate::io::schema::CliFeature;
use ubaa_core::facade::Result;
use ubaa_core::facade::{Routed, RoutedError, RoutedResult};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{CgyyArgs, CgyyCommand};
use crate::execute::routed_readonly;
use crate::io::human::safe_lock_code_value;
use crate::io::input::{invalid_input, read_cgyy_request_stdin};
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_cgyy<B: CliBackend + Send>(
    arguments: CgyyArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        CgyyCommand::Sites => backend
            .cgyy_sites()
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Purposes => backend
            .cgyy_purposes()
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Day { site_id, date } => backend
            .cgyy_day(site_id, &date)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Orders { page, size } => backend
            .cgyy_orders(page, size)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Detail { id } => backend
            .cgyy_order_detail(id)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::LockCode => {
            backend
                .cgyy_lock_code()
                .await
                .map(|result| CommandOutput::Readonly {
                    data: safe_lock_code_value(&result.data),
                    route: result.resolved_route,
                    feature: CliFeature::Cgyy,
                })
        }
        CgyyCommand::Cancel { id, confirm_write } => {
            if !confirm_write {
                return Err(invalid_input(
                    "取消预约是写操作，必须显式指定 --confirm-write",
                ));
            }
            backend
                .cgyy_cancel_order(id)
                .await
                .and_then(|result| readonly(result, CliFeature::Cgyy))
        }
        CgyyCommand::Submit {
            request_stdin,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("预约是写操作，必须显式指定 --confirm-write"));
            }
            if !request_stdin {
                return Err(invalid_input(
                    "预约请求含敏感字段，必须显式指定 --request-stdin",
                ));
            }
            let request = read_cgyy_request_stdin()?;
            backend
                .cgyy_submit_reservation(request)
                .await
                .and_then(|result| readonly(result, CliFeature::Cgyy))
        }
    }
}

pub(in crate::execute) async fn run_routed_cgyy<B: RoutedCliBackend + Send>(
    arguments: CgyyArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        CgyyCommand::Sites => routed_readonly(backend.cgyy_sites().await, CliFeature::Cgyy),
        CgyyCommand::Purposes => routed_readonly(backend.cgyy_purposes().await, CliFeature::Cgyy),
        CgyyCommand::Day { site_id, date } => {
            routed_readonly(backend.cgyy_day(site_id, &date).await, CliFeature::Cgyy)
        }
        CgyyCommand::Orders { page, size } => {
            routed_readonly(backend.cgyy_orders(page, size).await, CliFeature::Cgyy)
        }
        CgyyCommand::Detail { id } => {
            routed_readonly(backend.cgyy_order_detail(id).await, CliFeature::Cgyy)
        }
        CgyyCommand::LockCode => {
            backend
                .cgyy_lock_code()
                .await
                .map(|Routed { data, resolution }| Routed {
                    data: CommandOutput::Readonly {
                        data: safe_lock_code_value(&data),
                        route: resolution.mode,
                        feature: CliFeature::Cgyy,
                    },
                    resolution,
                })
        }
        CgyyCommand::Cancel { id, confirm_write } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("取消预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(backend.cgyy_cancel_order(id).await, CliFeature::Cgyy)
        }
        CgyyCommand::Submit {
            request_stdin,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            if !request_stdin {
                return Err(RoutedError {
                    error: invalid_input("预约请求含敏感字段，必须显式指定 --request-stdin"),
                    resolution: None,
                });
            }
            let request = read_cgyy_request_stdin().map_err(|error| RoutedError {
                error,
                resolution: None,
            })?;
            routed_readonly(
                backend.cgyy_submit_reservation(request).await,
                CliFeature::Cgyy,
            )
        }
    }
}
