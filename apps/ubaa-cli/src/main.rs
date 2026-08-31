use std::io::{self, BufReader};
use std::path::PathBuf;

use clap::Parser;
use directories::ProjectDirs;
use ubaa_cli::{
    Cli, render_startup_error, run_dual_login, run_dual_logout, run_dual_status, run_with_backend,
    run_with_routed_backend,
};
use ubaa_core::error::{ErrorCode, ErrorKind, UbaaError};
use ubaa_core::facade::{RouteClient, UbaaClient};
use ubaa_core::output::CliFeature;

#[tokio::main]
async fn main() {
    init_logging();
    let json_requested = std::env::args_os().any(|argument| argument == "--json");
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) if error.exit_code() == 0 => {
            let _ = error.print();
            return;
        }
        Err(_error) if json_requested => {
            let mut stdout = io::stdout().lock();
            let mut stderr = io::stderr().lock();
            let code = render_startup_error(
                true,
                CliFeature::Cli,
                UbaaError::new(
                    ErrorCode::InvalidInput,
                    ErrorKind::Input,
                    false,
                    "命令行参数无效",
                ),
                &mut stdout,
                &mut stderr,
            );
            std::process::exit(code);
        }
        Err(error) => {
            let code = error.exit_code();
            let _ = error.print();
            std::process::exit(code);
        }
    };
    let code = run(cli).await;
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

async fn run(cli: Cli) -> i32 {
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
    if cli.is_login() && cli.login_mode().is_some() {
        let client = match RouteClient::open(cli.login_mode(), &config_dir) {
            Ok(client) => client,
            Err(error) => {
                return render_startup_error(json_mode, feature, error, &mut stdout, &mut stderr);
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
                &mut stdout,
                &mut stderr,
            );
        };
        let stdin = io::stdin();
        let mut input = BufReader::new(stdin.lock());
        return run_with_backend(cli, &mut client, &mut input, &mut stdout, &mut stderr).await;
    }

    let mut client = match UbaaClient::open(&config_dir) {
        Ok(client) => client,
        Err(error) => {
            return render_startup_error(json_mode, feature, error, &mut stdout, &mut stderr);
        }
    };

    if cli.is_login() {
        let stdin = io::stdin();
        let mut input = BufReader::new(stdin.lock());
        run_dual_login(cli, &mut client, &mut input, &mut stdout, &mut stderr).await
    } else if cli.is_auth_status() {
        run_dual_status(cli, &mut client, &mut stdout, &mut stderr).await
    } else if cli.is_logout() {
        run_dual_logout(cli, &mut client, &mut stdout, &mut stderr).await
    } else {
        run_with_routed_backend(cli, &mut client, &mut stdout, &mut stderr).await
    }
}

fn default_config_dir() -> Option<PathBuf> {
    ProjectDirs::from("org", "BUAASubnet", "UBAA")
        .map(|directories| directories.config_dir().to_path_buf())
}
