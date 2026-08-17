use std::io::{self, BufReader};
use std::path::PathBuf;

use clap::Parser;
use directories::ProjectDirs;
use ubaa_cli::{
    Cli, authentication_required, render_empty_logout, render_startup_error, run_with_backend,
};
use ubaa_core::facade::UbaaClient;
use ubaa_core::session::{FileSessionStore, SessionStore};

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
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
            ubaa_core::error::UbaaError::new(
                ubaa_core::error::ErrorCode::InternalError,
                ubaa_core::error::ErrorKind::Internal,
                false,
                "could not determine the configuration directory",
            ),
            &mut stdout,
            &mut stderr,
        );
    };
    let store = match FileSessionStore::new(&config_dir) {
        Ok(store) => store,
        Err(error) => {
            return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
        }
    };
    let snapshot = match store.load() {
        Ok(snapshot) => snapshot,
        Err(error) => {
            return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
        }
    };
    if snapshot.is_none() && cli.requires_session() {
        return render_startup_error(
            json_mode,
            authentication_required(),
            &mut stdout,
            &mut stderr,
        );
    }
    if snapshot.is_none() && cli.is_logout() {
        return render_empty_logout(json_mode, &mut stdout);
    }
    let mode = match cli.resolve_mode(snapshot.as_ref().map(|session| session.mode)) {
        Ok(mode) => mode,
        Err(error) => {
            return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
        }
    };
    let mut backend = match UbaaClient::new(mode, &config_dir) {
        Ok(client) => client,
        Err(error) => {
            return render_startup_error(json_mode, error, &mut stdout, &mut stderr);
        }
    };
    let stdin = io::stdin();
    let mut input = BufReader::new(stdin.lock());
    run_with_backend(cli, &mut backend, &mut input, &mut stdout, &mut stderr).await
}

fn default_config_dir() -> Option<PathBuf> {
    ProjectDirs::from("org", "BUAASubnet", "UBAA")
        .map(|directories| directories.config_dir().to_path_buf())
}
