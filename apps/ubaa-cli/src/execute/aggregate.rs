//! 双路线聚合认证 dispatcher。

use std::io::{BufRead, Write};

use ubaa_core::facade::UbaaClient;
use ubaa_core::facade::{DualLoginInput, LoginReadiness, RoutePolicy, SafeError, SecretValue};
use ubaa_core::facade::{Result, UbaaError};

use crate::command::{AuthArgs, AuthCommand, Cli, Command, LoginArgs};
use crate::io::exit_code::{ExitCode, safe_error_exit_code};
use crate::io::human::{redacted_profile, write_profile};
use crate::io::input::{internal_error, invalid_input, prompt_line, read_secret_line, write_json};
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
    let json_mode = cli.json;
    let route_policy = backend.default_route_policy();
    let Command::Auth(AuthArgs {
        command: AuthCommand::Login(arguments),
    }) = cli.command
    else {
        return render_aggregate_input_error(
            json_mode,
            invalid_input("聚合登录必须先执行 auth login"),
            stdout,
            stderr,
        );
    };
    let (username, password) = match read_dual_credentials(json_mode, &arguments, input, stderr) {
        Ok(credentials) => credentials,
        Err(error) => {
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
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
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
        }
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(json_mode, outcome, route_policy, stdout, stderr)
}

/// 执行普通聚合认证状态流程。
pub async fn run_dual_status<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let route_policy = backend.default_route_policy();
    let mut outcome = match backend.auth_status().await {
        Ok(outcome) => outcome,
        Err(error) => return render_aggregate_input_error(cli.json, error, stdout, stderr),
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(cli.json, outcome, route_policy, stdout, stderr)
}

/// 使用固定的聚合路由元数据退出两个路由槽位。
pub async fn run_dual_logout<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let route_policy = backend.default_route_policy();
    let result = backend.logout().await;
    match result {
        Ok(()) => {
            if cli.json {
                let envelope = AggregateJsonEnvelope::logout_success(route_policy);
                if write_json(stdout, &envelope).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if writeln!(stdout, "已退出登录。").is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_startup_error(cli.json, CliFeature::Auth, error, stdout, stderr),
    }
}

fn read_dual_credentials<R: BufRead, E: Write>(
    json_mode: bool,
    arguments: &LoginArgs,
    input: &mut R,
    stderr: &mut E,
) -> Result<(String, String)> {
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
        rpassword::prompt_password("密码：").map_err(|_| internal_error("无法安全读取密码"))?
    };
    Ok((username, password))
}

fn render_dual_outcome<O: Write, E: Write>(
    json_mode: bool,
    outcome: ubaa_core::facade::LoginOutcome,
    route_policy: RoutePolicy,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let error = aggregate_error(&outcome);
    let exit_code = aggregate_exit_code(&outcome, error.as_ref());
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
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else {
        for route in &outcome.routes {
            let _ = writeln!(stdout, "{:?}: {:?}", route.route, route.state);
        }
        if outcome
            .profile
            .as_ref()
            .is_some_and(|profile| write_profile(stdout, profile).is_err())
        {
            return ExitCode::Internal as i32;
        }
        if let Some(error) = error {
            let _ = writeln!(stderr, "错误：{}", error.message);
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
