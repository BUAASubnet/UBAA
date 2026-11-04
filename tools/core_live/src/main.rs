//! Core-live 真实只读验证入口。
//!
//! 该二进制在一个 `RouteClient` 生命周期内完成一条路线的登录和逐操作读取，
//! 只向 stdout 输出安全摘要；凭据仅从 stdin 读取并只在内存中使用。

mod args;
mod evidence;
mod steps;

#[tokio::main]
async fn main() {
    init_logging();
    std::process::exit(steps::process().await);
}

fn init_logging() {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn"));
    let _ = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .with_target(true)
        .with_ansi(false)
        .try_init();
}
