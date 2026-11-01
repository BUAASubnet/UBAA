use std::io::{self, BufReader};
use std::path::PathBuf;

use directories::ProjectDirs;
use ubaa_cli::{
    Cli, render_startup_error, run_dual_login_with_agenda, run_dual_logout, run_dual_status,
    run_with_backend,
};
use ubaa_core::facade::{ErrorCode, ErrorKind, UbaaError};
use ubaa_core::facade::{RouteClient, UbaaClient};

fn main() {
    if let Some(code) = ubaa_cli::local_agenda::keychain_worker() {
        std::process::exit(code);
    }
    async_main();
}
#[tokio::main]
async fn async_main() {
    init_logging();
    let control = ubaa_cli::CommandControl::default();
    let cli = match ubaa_cli::parse(std::env::args_os()) {
        Ok(plan) => plan.into_cli(),
        Err(error) => {
            let code = error.render(&mut io::stdout().lock(), &mut io::stderr().lock());
            std::process::exit(code);
        }
    };
    let code = run(cli, &control).await;
    std::process::exit(code);
}

fn init_logging() {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));
    let _ = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .with_ansi(false)
        .try_init();
}

async fn run(mut cli: Cli, control: &ubaa_cli::CommandControl) -> i32 {
    let json_mode = cli.json;
    let feature = cli.feature();
    let mut stdout = io::stdout().lock();
    let mut stderr = io::stderr().lock();
    let Some(config_dir) = cli.config_dir.clone().or_else(default_config_dir) else {
        return render_startup_error(
            json_mode,
            feature,
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "无法确定配置目录",
            ),
            &mut stdout,
            &mut stderr,
        );
    };
    if matches!(cli.command, ubaa_cli::Command::Agenda(_)) {
        let prepared = ubaa_cli::prepare_input(cli.into(), &mut io::empty(), control)
            .expect("本机计划不读取 stdin");
        return ubaa_cli::execute_local_attempt(&prepared, &config_dir, control)
            .into_result()
            .render(control, &mut stdout, &mut stderr);
    }
    let mut agenda = match open_agenda(&cli, &config_dir) {
        Ok(agenda) => agenda,
        Err(error) => {
            return render_startup_error(json_mode, feature, error, &mut stdout, &mut stderr);
        }
    };
    let config_dir = agenda
        .as_ref()
        .map_or(config_dir.clone(), |a| a.config_dir().to_path_buf());
    if cli.is_login() && cli.login_mode().is_some() {
        return run_fixed_login(cli, &config_dir, &mut stdout, &mut stderr).await;
    }

    let mut client = match UbaaClient::open(&config_dir) {
        Ok(client) => client,
        Err(error) => {
            return render_startup_error(json_mode, feature, error, &mut stdout, &mut stderr);
        }
    };

    if cli.is_login() {
        let terminal_password = match prepare_terminal_password(&mut cli, &mut stderr) {
            Ok(password) => password,
            Err(error) => {
                return render_startup_error(json_mode, feature, error, &mut stdout, &mut stderr);
            }
        };
        let stdin = io::stdin();
        let mut input = BufReader::new(std::io::Read::chain(
            std::io::Cursor::new(terminal_password),
            stdin.lock(),
        ));
        run_dual_login_with_agenda(
            cli,
            &mut client,
            &mut input,
            &mut stdout,
            &mut stderr,
            agenda.as_mut().expect("登录持有配置作用域锁"),
        )
        .await
    } else if cli.is_auth_status() {
        run_dual_status(cli, &mut client, &mut stdout, &mut stderr).await
    } else if cli.is_logout() {
        run_dual_logout(cli, &mut client, &mut stdout, &mut stderr).await
    } else {
        let mut input = BufReader::new(io::stdin().lock());
        let prepared = match ubaa_cli::prepare_input(cli.into(), &mut input, control) {
            Ok(prepared) => prepared,
            Err(error) => {
                return render_startup_error(json_mode, feature, error, &mut stdout, &mut stderr);
            }
        };
        ubaa_cli::execute_attempt(&prepared, &mut client, control)
            .await
            .into_result()
            .render(control, &mut stdout, &mut stderr)
    }
}

fn default_config_dir() -> Option<PathBuf> {
    ProjectDirs::from("org", "BUAASubnet", "UBAA")
        .map(|directories| directories.config_dir().to_path_buf())
}

// 隐藏密码只由终端宿主读取，公共命令库始终消费注入的输入。
fn prepare_terminal_password(
    cli: &mut Cli,
    stderr: &mut impl std::io::Write,
) -> ubaa_core::facade::Result<Vec<u8>> {
    let ubaa_cli::Command::Auth(ubaa_cli::AuthArgs {
        command: ubaa_cli::AuthCommand::Login(args),
    }) = &mut cli.command
    else {
        return Ok(Vec::new());
    };
    if cli.json || args.password_stdin || (args.username_stdin && args.username.is_some()) {
        return Ok(Vec::new());
    }
    prepare_username(args, &mut io::stdin().lock(), stderr)?;
    let password = rpassword::prompt_password("密码：").map_err(|_| {
        UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "无法安全读取密码",
        )
    })?;
    args.password_stdin = true;
    Ok(format!("{password}\n").into_bytes())
}

async fn run_fixed_login(
    mut cli: Cli,
    config_dir: &std::path::Path,
    stdout: &mut impl std::io::Write,
    stderr: &mut impl std::io::Write,
) -> i32 {
    let json_mode = cli.json;
    let feature = cli.feature();
    let client = match RouteClient::open(cli.login_mode(), config_dir) {
        Ok(client) => client,
        Err(error) => {
            return render_startup_error(json_mode, feature, error, stdout, stderr);
        }
    };
    let Some(mut client) = client else {
        return render_startup_error(
            json_mode,
            feature,
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "无法打开诊断路线",
            ),
            stdout,
            stderr,
        );
    };
    let terminal_password = match prepare_terminal_password(&mut cli, stderr) {
        Ok(password) => password,
        Err(error) => {
            return render_startup_error(json_mode, feature, error, stdout, stderr);
        }
    };
    let stdin = io::stdin();
    let mut input = BufReader::new(std::io::Read::chain(
        std::io::Cursor::new(terminal_password),
        stdin.lock(),
    ));
    run_with_backend(cli, &mut client, &mut input, stdout, stderr).await
}

fn open_agenda(
    cli: &Cli,
    root: &std::path::Path,
) -> ubaa_core::facade::Result<Option<ubaa_cli::local_agenda::AgendaAccess>> {
    if !cli.is_login() && !cli.is_logout() {
        return Ok(None);
    }
    ubaa_cli::local_agenda::AgendaAccess::open(root)
        .and_then(|mut access| {
            access.revoke()?;
            Ok(Some(access))
        })
        .map_err(|_| {
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "本机日程账号无法安全撤销，认证操作已停止",
            )
        })
}
fn prepare_username(
    args: &mut ubaa_cli::LoginArgs,
    input: &mut impl std::io::BufRead,
    stderr: &mut impl std::io::Write,
) -> ubaa_core::facade::Result<()> {
    let invalid =
        |message| UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message);
    let internal = |message| {
        UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            message,
        )
    };
    if args.username_stdin {
        let mut name = String::new();
        input
            .read_line(&mut name)
            .map_err(|_| invalid("标准输入中缺少用户名"))?;
        let name = name.trim_end_matches(['\r', '\n']);
        if name.is_empty() {
            return Err(invalid("标准输入中缺少用户名"));
        }
        if name.trim().is_empty() {
            return Err(invalid("用户名不能为空"));
        }
        args.username = Some(name.to_owned());
        args.username_stdin = false;
        return Ok(());
    }
    if let Some(name) = &args.username {
        if !name.trim().is_empty() {
            return Ok(());
        }
        if args.mode.is_none() {
            return Err(invalid("用户名不能为空"));
        }
    }
    loop {
        write!(stderr, "用户名：").map_err(|_| internal("无法写入提示"))?;
        stderr.flush().map_err(|_| internal("无法刷新提示"))?;
        let mut name = String::new();
        let count = input
            .read_line(&mut name)
            .map_err(|_| invalid("无法读取必填输入"))?;
        if count == 0 {
            return Err(invalid("缺少必填输入"));
        }
        let name = name.trim_end_matches(['\r', '\n']);
        if !name.is_empty() {
            args.username = Some(name.to_owned());
            return Ok(());
        }
        writeln!(stderr, "必须提供一个值。").map_err(|_| internal("无法写入提示"))?;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 用户名标准输入保持单行失败语义且不提前读取密码() {
        for (bytes, message) in [
            ("\n后续输入\n", "标准输入中缺少用户名"),
            ("  \n后续输入\n", "用户名不能为空"),
        ] {
            let mut args = ubaa_cli::LoginArgs {
                mode: None,
                username: None,
                username_stdin: true,
                password_stdin: false,
            };
            let mut input = io::Cursor::new(bytes.as_bytes());
            let mut stderr = Vec::new();
            let error = prepare_username(&mut args, &mut input, &mut stderr).unwrap_err();
            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(error.message, message);
            assert!(input.position() < u64::try_from(bytes.len()).unwrap());
            assert!(stderr.is_empty());
        }
    }
    #[test]
    fn 聚合登录的显式空用户名立即失败() {
        let mut args = ubaa_cli::LoginArgs {
            mode: None,
            username: Some(" ".into()),
            username_stdin: false,
            password_stdin: false,
        };
        let mut input = io::Cursor::new("不得消费\n".as_bytes());
        assert_eq!(
            prepare_username(&mut args, &mut input, &mut Vec::new())
                .unwrap_err()
                .message,
            "用户名不能为空"
        );
        assert_eq!(input.position(), 0);
    }
}
