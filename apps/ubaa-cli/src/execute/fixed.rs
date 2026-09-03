//! 固定路线 dispatcher。

use std::io::{BufRead, Write};

use crate::backend::CliBackend;
use crate::command::{AuthArgs, AuthCommand, Cli, Command, LoginArgs, UserArgs, UserCommand};
use crate::io::human::{redacted_profile, redacted_status};
use crate::io::input::{internal_error, invalid_input, prompt_line, read_secret_line};
use crate::io::render::render_result;
use crate::io::schema::CommandOutput;
use crate::routing::ReadonlyRouteContext;
use serde_json::json;
use ubaa_core::facade::Result;
use ubaa_core::facade::{LoginInput, SecretValue};

use super::command_feature;
use super::features::academic::{run_classroom, run_exam, run_grades, run_schedule};
use super::features::assignments::{run_judge, run_signin, run_spoc};
use super::features::bykc::run_bykc;
use super::features::cgyy::run_cgyy;
use super::features::evaluation::run_evaluation;
use super::features::libbook::run_libbook;
use super::features::ygdk::run_ygdk;

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

/// 使用宿主已验证的只读路由决策执行已解析命令。
pub async fn run_with_backend_with_route<B, R, O, E>(
    cli: Cli,
    backend: &mut B,
    route_context: ReadonlyRouteContext,
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
    let feature = command_feature(&cli.command);
    let result = match cli.command {
        Command::Auth(AuthArgs {
            command: AuthCommand::Login(arguments),
        }) => run_login(cli.json, arguments, backend, input, stderr).await,
        Command::Auth(AuthArgs {
            command: AuthCommand::Status,
        }) => backend
            .auth_status()
            .await
            .map(|status| CommandOutput::Status(redacted_status(status))),
        Command::Auth(AuthArgs {
            command: AuthCommand::Logout,
        }) => backend
            .logout()
            .await
            .map(|()| CommandOutput::Logout(json!({ "loggedOut": true }))),
        Command::User(UserArgs {
            command: UserCommand::Show,
        }) => backend
            .get_user_info()
            .await
            .map(|profile| CommandOutput::Profile(redacted_profile(profile))),
        Command::Schedule(arguments) => run_schedule(arguments, backend).await,
        Command::Exam(arguments) => run_exam(arguments, backend).await,
        Command::Grades(arguments) => run_grades(arguments, backend).await,
        Command::Classroom(arguments) => run_classroom(arguments, backend).await,
        Command::Spoc(arguments) => run_spoc(arguments, backend).await,
        Command::Judge(arguments) => run_judge(arguments, backend).await,
        Command::Signin(arguments) => run_signin(arguments, backend).await,
        Command::Libbook(arguments) => run_libbook(arguments, backend).await,
        Command::Bykc(arguments) => run_bykc(arguments, backend).await,
        Command::Cgyy(arguments) => run_cgyy(arguments, backend).await,
        Command::Ygdk(arguments) => run_ygdk(arguments, backend).await,
        Command::Evaluation(arguments) => run_evaluation(arguments, backend).await,
    };

    render_result(
        cli.json,
        mode,
        feature,
        route_context,
        result,
        stdout,
        stderr,
    )
}

async fn run_login<B, R, E>(
    json_mode: bool,
    arguments: LoginArgs,
    backend: &mut B,
    input: &mut R,
    stderr: &mut E,
) -> Result<CommandOutput>
where
    B: CliBackend + Send,
    R: BufRead,
    E: Write,
{
    let username = if arguments.username_stdin {
        if arguments.username.is_some() {
            return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
        }
        let username = read_secret_line(input, "标准输入中缺少用户名")?;
        if username.trim().is_empty() {
            return Err(invalid_input("用户名不能为空"));
        }
        username
    } else {
        match arguments.username {
            Some(username) if !username.trim().is_empty() => username,
            Some(_) if json_mode => return Err(invalid_input("用户名不能为空")),
            None if json_mode => return Err(invalid_input("JSON 模式必须提供 --username")),
            _ => prompt_line(input, stderr, "用户名：")?,
        }
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "标准输入中缺少密码")?
    } else if json_mode {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    } else {
        rpassword::prompt_password("密码：").map_err(|_| internal_error("无法安全读取密码"))?
    };

    backend
        .login(LoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
        .map(|profile| CommandOutput::Profile(redacted_profile(profile)))
}
