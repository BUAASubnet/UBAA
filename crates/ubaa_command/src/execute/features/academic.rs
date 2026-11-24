//! 课表、考试、成绩与空闲教室 handler。

use crate::io::schema::CliFeature;
use ubaa_core::facade::RoutedResult;

use crate::backend::RoutedCliBackend;
use crate::command::{
    ClassroomArgs, ClassroomCommand, ExamArgs, ExamCommand, GradesArgs, GradesCommand,
    ScheduleArgs, ScheduleCommand,
};
use crate::execute::routed_readonly;
use crate::io::schema::CommandOutput;

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
        ExamCommand::Terms => routed_readonly(backend.exam_terms().await, CliFeature::Exam),
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
        GradesCommand::Overview => {
            routed_readonly(backend.grades_overview().await, CliFeature::Grades)
        }
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
