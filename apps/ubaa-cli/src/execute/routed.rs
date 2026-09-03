//! Core 聚合路由 dispatcher。

use std::io::Write;

use ubaa_core::facade::RoutedError;
use ubaa_core::output::CliFeature;

use crate::backend::RoutedCliBackend;
use crate::command::{Cli, Command, UserArgs, UserCommand};
use crate::io::error::render_routed_result;
use crate::io::human::redacted_profile;
use crate::io::input::invalid_input;
use crate::io::schema::CommandOutput;

use super::features::academic::{
    run_routed_classroom, run_routed_exam, run_routed_grades, run_routed_schedule,
};
use super::features::assignments::{run_routed_judge, run_routed_signin, run_routed_spoc};
use super::features::bykc::run_routed_bykc;
use super::features::cgyy::run_routed_cgyy;
use super::features::evaluation::run_routed_evaluation;
use super::features::libbook::run_routed_libbook;
use super::features::ygdk::run_routed_ygdk;
use super::routed_map;

/// 使用 Core 所有的路由解析执行普通用户命令或只读命令。
pub async fn run_with_routed_backend<B, O, E>(
    cli: Cli,
    backend: &mut B,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    B: RoutedCliBackend + Send,
    O: Write,
    E: Write,
{
    let json_mode = cli.json;
    let (feature, result) = match cli.command {
        Command::User(UserArgs {
            command: UserCommand::Show,
        }) => (
            CliFeature::User,
            routed_map(backend.get_user_info().await, |profile| {
                CommandOutput::Profile(redacted_profile(profile))
            }),
        ),
        Command::Schedule(arguments) => (
            CliFeature::Schedule,
            run_routed_schedule(arguments, backend).await,
        ),
        Command::Exam(arguments) => (CliFeature::Exam, run_routed_exam(arguments, backend).await),
        Command::Grades(arguments) => (
            CliFeature::Grades,
            run_routed_grades(arguments, backend).await,
        ),
        Command::Classroom(arguments) => (
            CliFeature::Classroom,
            run_routed_classroom(arguments, backend).await,
        ),
        Command::Spoc(arguments) => (CliFeature::Spoc, run_routed_spoc(arguments, backend).await),
        Command::Judge(arguments) => (
            CliFeature::Judge,
            run_routed_judge(arguments, backend).await,
        ),
        Command::Signin(arguments) => (
            CliFeature::Signin,
            run_routed_signin(arguments, backend).await,
        ),
        Command::Libbook(arguments) => (
            CliFeature::LibBook,
            run_routed_libbook(arguments, backend).await,
        ),
        Command::Bykc(arguments) => (CliFeature::Bykc, run_routed_bykc(arguments, backend).await),
        Command::Cgyy(arguments) => (CliFeature::Cgyy, run_routed_cgyy(arguments, backend).await),
        Command::Ygdk(arguments) => (CliFeature::Ygdk, run_routed_ygdk(arguments, backend).await),
        Command::Evaluation(arguments) => (
            CliFeature::Evaluation,
            run_routed_evaluation(arguments, backend).await,
        ),
        Command::Auth(_) => (
            CliFeature::Auth,
            Err(RoutedError {
                error: invalid_input("普通路由执行不接受认证命令"),
                resolution: None,
            }),
        ),
    };

    render_routed_result(json_mode, feature, result, stdout, stderr)
}
