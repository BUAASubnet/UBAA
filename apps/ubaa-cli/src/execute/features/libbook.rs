//! 图书馆 handler。

use ubaa_core::domain::LibBookReserveRequest;
use ubaa_core::error::Result;
use ubaa_core::facade::{RoutedError, RoutedResult};
use ubaa_core::output::CliFeature;

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{LibBookArgs, LibBookCommand};
use crate::execute::routed_readonly;
use crate::io::input::invalid_input;
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_libbook<B: CliBackend + Send>(
    arguments: LibBookArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        LibBookCommand::Libraries { day } => backend
            .libbook_libraries(&day)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Areas {
            premises_id,
            storey_id,
            day,
        } => backend
            .libbook_areas(&premises_id, storey_id.as_deref(), &day)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::AreaDetail { area_id } => backend
            .libbook_area_detail(&area_id)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Seats {
            area_id,
            day,
            start_time,
            end_time,
        } => backend
            .libbook_seats(&area_id, &day, &start_time, &end_time)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Bookings { page, limit } => backend
            .libbook_bookings(page, limit)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Reserve {
            area_id,
            seat_id,
            day,
            segment,
            start_time,
            end_time,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("预约是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .libbook_reserve(LibBookReserveRequest {
                    area_id,
                    seat_id,
                    day,
                    segment,
                    start_time,
                    end_time,
                })
                .await
                .and_then(|result| readonly(result, CliFeature::LibBook))
        }
        LibBookCommand::Cancel {
            booking_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input(
                    "取消预约是写操作，必须显式指定 --confirm-write",
                ));
            }
            backend
                .libbook_cancel_booking(&booking_id)
                .await
                .and_then(|result| readonly(result, CliFeature::LibBook))
        }
    }
}

pub(in crate::execute) async fn run_routed_libbook<B: RoutedCliBackend + Send>(
    arguments: LibBookArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        LibBookCommand::Libraries { day } => {
            routed_readonly(backend.libbook_libraries(&day).await, CliFeature::LibBook)
        }
        LibBookCommand::Areas {
            premises_id,
            storey_id,
            day,
        } => routed_readonly(
            backend
                .libbook_areas(&premises_id, storey_id.as_deref(), &day)
                .await,
            CliFeature::LibBook,
        ),
        LibBookCommand::AreaDetail { area_id } => routed_readonly(
            backend.libbook_area_detail(&area_id).await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Seats {
            area_id,
            day,
            start_time,
            end_time,
        } => routed_readonly(
            backend
                .libbook_seats(&area_id, &day, &start_time, &end_time)
                .await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Bookings { page, limit } => routed_readonly(
            backend.libbook_bookings(page, limit).await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Reserve {
            area_id,
            seat_id,
            day,
            segment,
            start_time,
            end_time,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend
                    .libbook_reserve(LibBookReserveRequest {
                        area_id,
                        seat_id,
                        day,
                        segment,
                        start_time,
                        end_time,
                    })
                    .await,
                CliFeature::LibBook,
            )
        }
        LibBookCommand::Cancel {
            booking_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("取消预约是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend.libbook_cancel_booking(&booking_id).await,
                CliFeature::LibBook,
            )
        }
    }
}
