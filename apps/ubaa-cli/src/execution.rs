use std::io::{BufRead, Write};

use super::{Cli, CliBackend, Command, ReadonlyRouteContext, run_with_backend_with_route};
use ubaa_core::output::CliFeature;

/// 使用注入的后端执行已解析命令。
pub async fn run_with_backend<B, R, O, E>(
    cli: Cli,
    backend: &mut B,
    input: &mut R,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    B: CliBackend + Send,
    R: BufRead,
    O: Write,
    E: Write,
{
    let mode = backend.mode();
    run_with_backend_with_route(
        cli,
        backend,
        ReadonlyRouteContext::explicit(mode),
        input,
        stdout,
        stderr,
    )
    .await
}

pub(crate) const fn command_feature(command: &Command) -> CliFeature {
    match command {
        Command::Auth(_) => CliFeature::Auth,
        Command::User(_) => CliFeature::User,
        Command::Schedule(_) => CliFeature::Schedule,
        Command::Exam(_) => CliFeature::Exam,
        Command::Grades(_) => CliFeature::Grades,
        Command::Classroom(_) => CliFeature::Classroom,
        Command::Spoc(_) => CliFeature::Spoc,
        Command::Judge(_) => CliFeature::Judge,
        Command::Signin(_) => CliFeature::Signin,
        Command::Libbook(_) => CliFeature::LibBook,
        Command::Bykc(_) => CliFeature::Bykc,
        Command::Cgyy(_) => CliFeature::Cgyy,
        Command::Ygdk(_) => CliFeature::Ygdk,
        Command::Evaluation(_) => CliFeature::Evaluation,
    }
}
