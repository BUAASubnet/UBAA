//! 课表、考试、成绩与空闲教室 handler。

use ubaa_core::error::Result;
use ubaa_core::facade::RoutedResult;
use ubaa_core::output::CliFeature;

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{
    ClassroomArgs, ClassroomCommand, ExamArgs, ExamCommand, GradesArgs, GradesCommand,
    ScheduleArgs, ScheduleCommand,
};
use crate::execute::routed_readonly;
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_schedule<B: CliBackend + Send>(
    arguments: ScheduleArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ScheduleCommand::Terms => backend
            .schedule_terms()
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Weeks { term } => backend
            .schedule_weeks(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Current { term, week } => backend
            .schedule_week(&term, week)
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Today => backend
            .schedule_today()
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
    }
}

pub(in crate::execute) async fn run_exam<B: CliBackend + Send>(
    arguments: ExamArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ExamCommand::List { term } => backend
            .exam_arrangement(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Exam)),
    }
}

pub(in crate::execute) async fn run_grades<B: CliBackend + Send>(
    arguments: GradesArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        GradesCommand::List { term } => backend
            .grades(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Grades)),
    }
}

pub(in crate::execute) async fn run_classroom<B: CliBackend + Send>(
    arguments: ClassroomArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ClassroomCommand::Search { campus, date } => backend
            .classroom_search(campus, &date)
            .await
            .and_then(|result| readonly(result, CliFeature::Classroom)),
    }
}

pub(in crate::execute) async fn run_routed_schedule<B: RoutedCliBackend + Send>(
    arguments: ScheduleArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ScheduleCommand::Terms => {
            routed_readonly(backend.schedule_terms().await, CliFeature::Schedule)
        }
        ScheduleCommand::Weeks { term } => {
            routed_readonly(backend.schedule_weeks(&term).await, CliFeature::Schedule)
        }
        ScheduleCommand::Current { term, week } => routed_readonly(
            backend.schedule_week(&term, week).await,
            CliFeature::Schedule,
        ),
        ScheduleCommand::Today => {
            routed_readonly(backend.schedule_today().await, CliFeature::Schedule)
        }
    }
}

pub(in crate::execute) async fn run_routed_exam<B: RoutedCliBackend + Send>(
    arguments: ExamArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ExamCommand::List { term } => {
            routed_readonly(backend.exam_arrangement(&term).await, CliFeature::Exam)
        }
    }
}

pub(in crate::execute) async fn run_routed_grades<B: RoutedCliBackend + Send>(
    arguments: GradesArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        GradesCommand::List { term } => {
            routed_readonly(backend.grades(&term).await, CliFeature::Grades)
        }
    }
}

pub(in crate::execute) async fn run_routed_classroom<B: RoutedCliBackend + Send>(
    arguments: ClassroomArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ClassroomCommand::Search { campus, date } => routed_readonly(
            backend.classroom_search(campus, &date).await,
            CliFeature::Classroom,
        ),
    }
}
