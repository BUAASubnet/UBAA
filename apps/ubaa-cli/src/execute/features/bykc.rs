//! 博雅课程 handler。

use crate::io::schema::CliFeature;
use ubaa_core::facade::BykcSignRequest;
use ubaa_core::facade::Result;
use ubaa_core::facade::{RoutedError, RoutedResult};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{BykcArgs, BykcCommand};
use crate::execute::routed_readonly;
use crate::io::input::invalid_input;
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_bykc<B: CliBackend + Send>(
    arguments: BykcArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        BykcCommand::Profile => backend
            .bykc_profile()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Courses { page, size, all } => backend
            .bykc_courses(page, size, all)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Course { id } => backend
            .bykc_course_detail(id)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Chosen => backend
            .bykc_chosen_courses()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Statistics => backend
            .bykc_statistics()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Select {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("选课是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .bykc_select_course(course_id)
                .await
                .and_then(|r| readonly(r, CliFeature::Bykc))
        }
        BykcCommand::Deselect {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("退选是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .bykc_deselect_course(course_id)
                .await
                .and_then(|r| readonly(r, CliFeature::Bykc))
        }
        BykcCommand::Sign {
            course_id,
            sign_type,
            lat,
            lng,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(invalid_input("签到是写操作，必须显式指定 --confirm-write"));
            }
            backend
                .bykc_sign_course(BykcSignRequest {
                    course_id,
                    sign_type,
                    lat,
                    lng,
                })
                .await
                .and_then(|r| readonly(r, CliFeature::Bykc))
        }
    }
}

pub(in crate::execute) async fn run_routed_bykc<B: RoutedCliBackend + Send>(
    arguments: BykcArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        BykcCommand::Profile => routed_readonly(backend.bykc_profile().await, CliFeature::Bykc),
        BykcCommand::Courses { page, size, all } => routed_readonly(
            backend.bykc_courses(page, size, all).await,
            CliFeature::Bykc,
        ),
        BykcCommand::Course { id } => {
            routed_readonly(backend.bykc_course_detail(id).await, CliFeature::Bykc)
        }
        BykcCommand::Chosen => {
            routed_readonly(backend.bykc_chosen_courses().await, CliFeature::Bykc)
        }
        BykcCommand::Statistics => {
            routed_readonly(backend.bykc_statistics().await, CliFeature::Bykc)
        }
        BykcCommand::Select {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("选课是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend.bykc_select_course(course_id).await,
                CliFeature::Bykc,
            )
        }
        BykcCommand::Deselect {
            course_id,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("退选是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend.bykc_deselect_course(course_id).await,
                CliFeature::Bykc,
            )
        }
        BykcCommand::Sign {
            course_id,
            sign_type,
            lat,
            lng,
            confirm_write,
        } => {
            if !confirm_write {
                return Err(RoutedError {
                    error: invalid_input("签到是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                });
            }
            routed_readonly(
                backend
                    .bykc_sign_course(BykcSignRequest {
                        course_id,
                        sign_type,
                        lat,
                        lng,
                    })
                    .await,
                CliFeature::Bykc,
            )
        }
    }
}
