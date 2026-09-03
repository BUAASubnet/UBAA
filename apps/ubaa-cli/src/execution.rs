use std::io::{BufRead, Write};

use super::{Cli, CliBackend, ReadonlyRouteContext, run_with_backend_with_route};

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
