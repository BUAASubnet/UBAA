use std::io::{self, BufReader};
use std::path::PathBuf;

use clap::Parser;
use directories::ProjectDirs;
use ubaa_cli::{
    Cli, authentication_required, render_empty_logout, render_startup_error, run_dual_login,
    run_dual_logout, run_dual_status, run_with_backend,
};
use ubaa_core::config::RouteConfig;
use ubaa_core::connection::{SystemDnsProbe, resolve_feature_route};
use ubaa_core::domain::ReadonlyFeature;
use ubaa_core::error::{ErrorCode, ErrorKind, UbaaError};
use ubaa_core::facade::{DualUbaaClient, UbaaClient};

#[tokio::main]
async fn main() {
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
                UbaaError::new(
                    ErrorCode::InvalidInput,
                    ErrorKind::Input,
                    false,
                    "command-line arguments are invalid",
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

async fn run(cli: Cli) -> i32 {
    let json_mode = cli.json;
    let mut stdout = io::stdout().lock();
    let mut stderr = io::stderr().lock();
    let Some(config_dir) = cli.config_dir.clone().or_else(default_config_dir) else {
        return render_startup_error(
            json_mode,
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "could not determine the configuration directory",
            ),
            &mut stdout,
            &mut stderr,
        );
    };
    let has_route_config = config_dir.join("config.toml").is_file();
    if cli.is_login() && cli.login_mode().is_none() && (!json_mode || has_route_config) {
        let mut client = match DualUbaaClient::open(&config_dir) {
            Ok(client) => client,
            Err(error) => {
                return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
            }
        };
        let stdin = io::stdin();
        let mut input = BufReader::new(stdin.lock());
        return run_dual_login(cli, &mut client, &mut input, &mut stdout, &mut stderr).await;
    }
    if cli.is_auth_status() && cli.login_mode().is_none() {
        let mut client = match DualUbaaClient::open(&config_dir) {
            Ok(client) => client,
            Err(error) => {
                return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
            }
        };
        return run_dual_status(cli, &mut client, &mut stdout, &mut stderr).await;
    }
    if cli.is_logout() && cli.login_mode().is_none() {
        let mut client = match DualUbaaClient::open(&config_dir) {
            Ok(client) => client,
            Err(error) => {
                return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
            }
        };
        return run_dual_logout(cli, &mut client, &mut stdout, &mut stderr).await;
    }

    let selected_mode = if let Some(feature) = route_feature(&cli) {
        let config = match RouteConfig::load(&config_dir) {
            Ok(config) => config,
            Err(error) => {
                return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
            }
        };
        match resolve_feature_route(feature, config.feature(feature), &config, &SystemDnsProbe) {
            Ok(route) => Some(route.mode),
            Err(error) => {
                return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
            }
        }
    } else {
        cli.login_mode()
    };
    let client = match UbaaClient::open(selected_mode, &config_dir) {
        Ok(client) => client,
        Err(error) => {
            return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
        }
    };
    if client.is_none() && cli.requires_session() {
        return render_startup_error(
            json_mode,
            authentication_required(),
            &mut stdout,
            &mut stderr,
        );
    }
    if client.is_none() && cli.is_logout() {
        return render_empty_logout(json_mode, &mut stdout);
    }
    let Some(mut backend) = client else {
        let error = cli.resolve_mode(None).err().unwrap_or_else(|| {
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "client mode could not be resolved",
            )
        });
        return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
    };
    let stdin = io::stdin();
    let mut input = BufReader::new(stdin.lock());
    run_with_backend(cli, &mut backend, &mut input, &mut stdout, &mut stderr).await
}

fn command_feature(cli: &Cli) -> Option<ReadonlyFeature> {
    match &cli.command {
        ubaa_cli::Command::Schedule(_) => Some(ReadonlyFeature::Schedule),
        ubaa_cli::Command::Exam(_) => Some(ReadonlyFeature::Exam),
        ubaa_cli::Command::Grades(_) => Some(ReadonlyFeature::Grades),
        ubaa_cli::Command::Classroom(_) => Some(ReadonlyFeature::Classroom),
        ubaa_cli::Command::Spoc(_) => Some(ReadonlyFeature::Spoc),
        ubaa_cli::Command::Judge(_) => Some(ReadonlyFeature::Judge),
        _ => None,
    }
}

fn route_feature(cli: &Cli) -> Option<ReadonlyFeature> {
    command_feature(cli).or_else(|| {
        matches!(
            &cli.command,
            ubaa_cli::Command::User(ubaa_cli::UserArgs {
                command: ubaa_cli::UserCommand::Show
            })
        )
        .then_some(ReadonlyFeature::Schedule)
    })
}

fn default_config_dir() -> Option<PathBuf> {
    ProjectDirs::from("org", "BUAASubnet", "UBAA")
        .map(|directories| directories.config_dir().to_path_buf())
}
