//! 双路线聚合认证 dispatcher。

use std::io::{BufRead, Write};

use ubaa_core::facade::UbaaClient;
use ubaa_core::facade::{DualLoginInput, LoginReadiness, RoutePolicy, SafeError, SecretValue};
use ubaa_core::facade::{Result, UbaaError};

use crate::command::{AuthArgs, AuthCommand, Cli, Command, LoginArgs};
use crate::io::exit_code::{ExitCode, safe_error_exit_code};
use crate::io::human::{redacted_profile, write_profile};
use crate::io::input::{
    invalid_input, prompt_line, read_secret_line, read_username_stdin, write_json,
};
use crate::io::render::render_startup_error;
use crate::io::schema::{AggregateJsonEnvelope, CliFeature};

/// 通过双路门面执行普通聚合登录流程。
pub async fn run_dual_login<R, O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    input: &mut R,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    R: BufRead,
    O: Write,
    E: Write,
{
    let code = run_dual_login_impl(cli, backend, input, stdout, stderr).await;
    crate::runtime::finish_output(code, stdout, stderr)
}

async fn run_dual_login_impl<R: BufRead, O: Write, E: Write>(
    cli: Cli,
    backend: &mut UbaaClient,
    input: &mut R,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let cli_json = cli.json;
    execute_login(cli, backend, input, stderr)
        .await
        .render(cli_json, stdout, stderr)
}

pub(crate) async fn execute_login<R: BufRead, E: Write>(
    cli: Cli,
    backend: &mut UbaaClient,
    input: &mut R,
    stderr: &mut E,
) -> AggregateResult {
    let json_mode = cli.json;
    let route_policy = backend.default_route_policy();
    let Command::Auth(AuthArgs {
        command: AuthCommand::Login(arguments),
    }) = cli.command
    else {
        return AggregateResult::Error(invalid_input("聚合登录必须先执行 auth login"));
    };
    let (username, password) = match read_dual_credentials(json_mode, &arguments, input, stderr) {
        Ok(credentials) => credentials,
        Err(error) => {
            return AggregateResult::Error(error);
        }
    };
    let mut outcome = match backend
        .login(DualLoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
    {
        Ok(outcome) => outcome,
        Err(error) => {
            return AggregateResult::Error(error);
        }
    };
    let registration = None;
    outcome.profile = outcome.profile.map(redacted_profile);
    AggregateResult::Auth {
        outcome: Box::new(outcome),
        route_policy,
        registration,
    }
}

/// 执行普通聚合认证状态流程。
async fn run_dual_status_unflushed<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let json = cli.json;
    execute_auth(cli, backend, &mut std::io::empty())
        .await
        .render(json, stdout, stderr)
}

/// 使用固定的聚合路由元数据退出两个路由槽位。
async fn run_dual_logout_unflushed<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let json = cli.json;
    execute_auth(cli, backend, &mut std::io::empty())
        .await
        .render(json, stdout, stderr)
}

pub(crate) fn validate_login_arguments(json: bool, args: &LoginArgs) -> Result<()> {
    if args.username_stdin && args.username.is_some() {
        return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
    }
    if args
        .username
        .as_ref()
        .is_some_and(|name| name.trim().is_empty())
    {
        return Err(invalid_input("用户名不能为空"));
    }
    if json && args.username.is_none() && !args.username_stdin {
        return Err(invalid_input("JSON 模式必须提供 --username"));
    }
    if json && !args.password_stdin {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    }
    Ok(())
}

pub(crate) fn read_dual_credentials<R: BufRead, E: Write>(
    json_mode: bool,
    arguments: &LoginArgs,
    input: &mut R,
    stderr: &mut E,
) -> Result<(String, String)> {
    validate_login_arguments(json_mode, arguments)?;
    let username = if arguments.username_stdin {
        if arguments.username.is_some() {
            return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
        }
        read_username_stdin(input)?
    } else {
        match arguments.username.as_deref() {
            Some(username) if !username.trim().is_empty() => username.to_owned(),
            Some(_) => return Err(invalid_input("用户名不能为空")),
            None if json_mode => return Err(invalid_input("JSON 模式必须提供 --username")),
            None => prompt_line(input, stderr, "用户名：")?,
        }
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "标准输入中缺少密码")?
    } else if json_mode {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    } else {
        prompt_line(input, stderr, "密码：")?
    };
    Ok((username, password))
}

fn render_dual_outcome<O: Write, E: Write>(
    json_mode: bool,
    outcome: ubaa_core::facade::LoginOutcome,
    route_policy: RoutePolicy,
    stdout: &mut O,
    stderr: &mut E,
    registration: Option<std::result::Result<(), crate::agenda::LocalError>>,
) -> i32 {
    let error = aggregate_error(&outcome);
    let exit_code = registration
        .as_ref()
        .and_then(|r| r.as_ref().err())
        .map_or_else(
            || aggregate_exit_code(&outcome, error.as_ref()),
            |error| error.exit(),
        );
    if json_mode {
        let envelope = match error {
            Some(error) => AggregateJsonEnvelope::auth_failure(outcome, error, route_policy),
            None => AggregateJsonEnvelope::auth_success(outcome, route_policy),
        };
        let envelope = match envelope {
            Ok(envelope) => envelope,
            Err(error) => {
                return render_startup_error(true, CliFeature::Auth, error, stdout, stderr);
            }
        };
        let Ok(mut value) = serde_json::to_value(&envelope) else {
            return 7;
        };
        if let Some(result) = registration {
            value["agendaRegistration"] = match result {
                Ok(()) => serde_json::json!({"state":"ready"}),
                Err(error) => {
                    serde_json::json!({"state":"failed","error":{"code":error,"message":error.message(),"retryable":false}})
                }
            };
        }
        if write_json(stdout, &value).is_err() {
            return 7;
        }
    } else {
        for route in &outcome.routes {
            if writeln!(stdout, "{:?}: {:?}", route.route, route.state).is_err() {
                return 7;
            }
        }
        if outcome
            .profile
            .as_ref()
            .is_some_and(|profile| write_profile(stdout, profile).is_err())
        {
            return ExitCode::Internal as i32;
        }
        if let Some(error) = error
            && writeln!(stderr, "错误：{}", error.message).is_err()
        {
            return 7;
        }
        if let Some(result) = registration {
            match result {
                Ok(()) => {
                    if writeln!(stdout, "本机日程账号已登记。").is_err() {
                        return 7;
                    }
                }
                Err(error) => {
                    if writeln!(
                        stderr,
                        "学校认证已完成，本机日程登记失败：{}",
                        error.message()
                    )
                    .is_err()
                    {
                        return 7;
                    }
                }
            }
        }
    }
    exit_code
}

fn aggregate_error(outcome: &ubaa_core::facade::LoginOutcome) -> Option<SafeError> {
    if outcome.readiness == LoginReadiness::NoneReady {
        Some(
            outcome
                .routes
                .iter()
                .find_map(|route| route.error.clone())
                .unwrap_or_else(|| SafeError {
                    diagnostic: None,
                    code: "internal_error".into(),
                    kind: "internal".into(),
                    retryable: false,
                    message: "没有认证路线成功建立会话".into(),
                }),
        )
    } else {
        None
    }
}

fn aggregate_exit_code(
    outcome: &ubaa_core::facade::LoginOutcome,
    error: Option<&SafeError>,
) -> i32 {
    if outcome.readiness == LoginReadiness::NoneReady {
        error.map_or(ExitCode::Internal as i32, safe_error_exit_code)
    } else {
        ExitCode::Success as i32
    }
}

fn render_aggregate_input_error<O: Write, E: Write>(
    json_mode: bool,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    render_startup_error(json_mode, CliFeature::Auth, error, stdout, stderr)
}

/// 聚合认证状态复用原结果，交付前刷新两条流。
pub async fn run_dual_status<O: Write, E: Write>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let code = run_dual_status_unflushed(cli, backend, stdout, stderr).await;
    crate::runtime::finish_output(code, stdout, stderr)
}
/// 聚合退出不重放，交付前刷新两条流。
pub async fn run_dual_logout<O: Write, E: Write>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let code = run_dual_logout_unflushed(cli, backend, stdout, stderr).await;
    crate::runtime::finish_output(code, stdout, stderr)
}

pub(crate) enum AggregateResult {
    Auth {
        outcome: Box<ubaa_core::facade::LoginOutcome>,
        route_policy: RoutePolicy,
        registration: Option<std::result::Result<(), crate::agenda::LocalError>>,
    },
    Logout {
        result: Result<()>,
        route_policy: RoutePolicy,
    },
    Error(UbaaError),
}
impl AggregateResult {
    pub(crate) fn render(
        self,
        json: bool,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        match self {
            Self::Auth {
                outcome,
                route_policy,
                registration,
            } => render_dual_outcome(json, *outcome, route_policy, stdout, stderr, registration),
            Self::Error(error) => render_aggregate_input_error(json, error, stdout, stderr),
            Self::Logout {
                result,
                route_policy,
            } => match result {
                Ok(()) => {
                    let result = if json {
                        write_json(stdout, &AggregateJsonEnvelope::logout_success(route_policy))
                    } else {
                        writeln!(stdout, "已退出登录。")
                    };
                    if result.is_err() { 7 } else { 0 }
                }
                Err(error) => render_aggregate_input_error(json, error, stdout, stderr),
            },
        }
    }
}
pub(crate) async fn execute_auth(
    cli: Cli,
    backend: &mut UbaaClient,
    input: &mut impl BufRead,
) -> AggregateResult {
    match cli.command {
        Command::Auth(AuthArgs {
            command: AuthCommand::Login(_),
        }) => execute_login(cli, backend, input, &mut std::io::sink()).await,
        Command::Auth(AuthArgs {
            command: AuthCommand::Status,
        }) => {
            let route_policy = backend.default_route_policy();
            match backend.auth_status().await {
                Ok(mut outcome) => {
                    outcome.profile = outcome.profile.map(redacted_profile);
                    AggregateResult::Auth {
                        outcome: Box::new(outcome),
                        route_policy,
                        registration: None,
                    }
                }
                Err(error) => AggregateResult::Error(error),
            }
        }
        Command::Auth(AuthArgs {
            command: AuthCommand::Logout,
        }) => {
            let route_policy = backend.default_route_policy();
            AggregateResult::Logout {
                result: backend.logout().await,
                route_policy,
            }
        }
        _ => AggregateResult::Error(invalid_input("聚合认证入口只接受 auth 命令")),
    }
}
