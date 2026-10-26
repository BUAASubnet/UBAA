//! 场馆预约 handler。

use crate::io::schema::CliFeature;
use ubaa_core::facade::{
    CgyyCancelOrderRequest, CgyyCancelOrderResult, ErrorCode, ErrorKind, Result, Routed,
    RoutedError, RoutedResult, UbaaError,
};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{CgyyArgs, CgyyCommand};
use crate::execute::routed_readonly;
use crate::io::error::{
    CGYY_CANCEL_OUTCOME_UNKNOWN_MESSAGE, CGYY_RESERVATION_OUTCOME_UNKNOWN_MESSAGE,
};
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
            let request = normalize_cancel_request(id)?;
            backend
                .cgyy_cancel_order(request)
                .await
                .map_err(sanitize_cancel_error)
                .and_then(|mut result| {
                    result.data = safe_cancel_result(&result.data)?;
                    Ok(result)
                })
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
                .map_err(sanitize_reservation_error)
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
            let request = normalize_cancel_request(id).map_err(|error| RoutedError {
                error,
                resolution: None,
            })?;
            let result = backend
                .cgyy_cancel_order(request)
                .await
                .and_then(|mut routed| {
                    routed.data =
                        safe_cancel_result(&routed.data).map_err(|error| RoutedError {
                            error,
                            resolution: Some(routed.resolution),
                        })?;
                    Ok(routed)
                })
                .map_err(sanitize_routed_cancel_error);
            routed_readonly(result, CliFeature::Cgyy)
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
            let result = backend
                .cgyy_submit_reservation(request)
                .await
                .map_err(sanitize_routed_reservation_error);
            routed_readonly(result, CliFeature::Cgyy)
        }
    }
}

fn normalize_cancel_request(order_id: i32) -> Result<CgyyCancelOrderRequest> {
    if order_id <= 0 {
        return Err(invalid_input("场馆订单编号必须为正整数"));
    }
    Ok(CgyyCancelOrderRequest { order_id })
}

fn safe_cancel_result(result: &CgyyCancelOrderResult) -> Result<CgyyCancelOrderResult> {
    if !result.success {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "场馆订单取消资格核对响应无效",
        ));
    }
    Ok(CgyyCancelOrderResult {
        success: true,
        message: "场馆订单已取消".to_owned(),
    })
}

fn sanitize_cancel_error(error: UbaaError) -> UbaaError {
    match error.code {
        ErrorCode::UpstreamChanged => UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "场馆订单取消资格核对响应无效",
        ),
        ErrorCode::OutcomeUnknown => UbaaError::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            CGYY_CANCEL_OUTCOME_UNKNOWN_MESSAGE,
        ),
        _ => error,
    }
}

fn sanitize_routed_cancel_error(mut error: RoutedError) -> RoutedError {
    error.error = sanitize_cancel_error(error.error);
    error
}

fn sanitize_reservation_error(error: UbaaError) -> UbaaError {
    if error.code == ErrorCode::OutcomeUnknown {
        return UbaaError::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            CGYY_RESERVATION_OUTCOME_UNKNOWN_MESSAGE,
        );
    }
    error
}

fn sanitize_routed_reservation_error(mut error: RoutedError) -> RoutedError {
    error.error = sanitize_reservation_error(error.error);
    error
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::{sanitize_cancel_error, sanitize_reservation_error};
    use crate::io::render::render_result;
    use crate::io::schema::{CliFeature, CommandOutput};
    use crate::routing::ReadonlyRouteContext;
    use ubaa_core::facade::{ConnectionMode, ErrorCode, ErrorKind, Result, UbaaError};

    fn render_error(error: UbaaError) -> Value {
        let result: Result<CommandOutput> = Err(error);
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let exit = render_result(
            true,
            ConnectionMode::Direct,
            CliFeature::Cgyy,
            ReadonlyRouteContext::explicit(ConnectionMode::Direct),
            result,
            &mut stdout,
            &mut stderr,
        );

        assert_eq!(exit, 5);
        assert!(stderr.is_empty());
        serde_json::from_slice(&stdout).expect("解析场馆写入错误 JSON")
    }

    #[test]
    fn 场馆未知结果由typed命令分支投影且最终渲染不猜消息() {
        let cancel = render_error(sanitize_cancel_error(UbaaError::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            "RAW-CANCEL token=PRIVATE",
        )));
        let reservation = render_error(sanitize_reservation_error(UbaaError::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            "场馆订单取消结果未知，请刷新订单列表与详情核对后再操作",
        )));

        assert_eq!(
            cancel["error"]["message"],
            "场馆订单取消结果未知，请刷新订单列表与详情核对后再操作"
        );
        assert_eq!(
            reservation["error"]["message"],
            "场馆写入结果未知，请稍后查询预约记录确认"
        );
        assert!(!cancel.to_string().contains("RAW-CANCEL"));
        assert!(!cancel.to_string().contains("PRIVATE"));

        let renderer = include_str!("../../io/render.rs");
        assert!(!renderer.contains("CGYY_CANCEL_OUTCOME_UNKNOWN_MESSAGE"));
    }
}
