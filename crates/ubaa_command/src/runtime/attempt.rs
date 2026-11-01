use super::{CommandClass, CommandControl, CommandPlan, RecoveryTarget, StopReason};
use crate::io::{
    render::{render_result, render_routed_result},
    schema::CommandOutput,
};
use crate::{CliBackend, CliFeature, ReadonlyRouteContext, RoutedCliBackend};
use std::io::{BufRead, Cursor, Write};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, RoutedError, RoutedResult, UbaaError,
};

/// 输入快照在尝试之间保持不变，不包含可重放的写资格。
pub struct PreparedCommand {
    plan: CommandPlan,
    input: Vec<u8>,
}
/// 保留 typed 执行结果，调用者不能构造成功正文。
pub struct ResultHandle {
    json: bool,
    feature: CliFeature,
    result: RoutedResult<CommandOutput>,
    fixed: Option<(ConnectionMode, ReadonlyRouteContext)>,
    stop: Option<StopReason>,
    extra: Option<ExtraResult>,
    local: Option<crate::Cli>,
    school_write: bool,
}
enum ExtraResult {
    Auth(Box<crate::execute::aggregate::AggregateResult>),
    Local(crate::local_agenda::read::LocalAttempt),
    LocalStop,
}
/// 只有明确路线的只读认证过期才允许上层安排一次恢复。
pub enum AttemptOutcome {
    Completed(ResultHandle),
    AuthExpired {
        target: RecoveryTarget,
        route: ConnectionMode,
        result: ResultHandle,
    },
}
impl AttemptOutcome {
    #[must_use]
    pub fn into_result(self) -> ResultHandle {
        match self {
            Self::Completed(r) | Self::AuthExpired { result: r, .. } => r,
        }
    }
}
impl ResultHandle {
    /// 交付开始后失败仅停止后续输出，不追加第二个 JSON 或重跑业务。
    pub fn render_bounded(
        self,
        control: &CommandControl,
        stdout: &mut super::OutputWriter,
        stderr: &mut super::OutputWriter,
    ) -> i32 {
        let stop = self.stop.or_else(|| control.check().err());
        let cleanup = control.cleanup();
        if stop.is_some()
            && (stdout.begin_cleanup(&cleanup).is_err() || stderr.begin_cleanup(&cleanup).is_err())
        {
            return 7;
        }
        self.render_with_stop(control, stop, stdout, stderr)
    }
    pub fn render(
        self,
        control: &CommandControl,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        let stop = self.stop.or_else(|| control.check().err());
        self.render_with_stop(control, stop, stdout, stderr)
    }
    fn render_with_stop(
        self,
        control: &CommandControl,
        stop: Option<StopReason>,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        if let (Some(cli), Some(reason)) = (&self.local, stop) {
            return crate::local_agenda::read::render_stop(cli, reason, stdout, stderr);
        }
        if let Some(reason) = stop {
            if writeln!(stderr, "{}", reason.message()).is_err() {
                return 7;
            }
            let mut error = stop_error(reason);
            if self.school_write {
                error.message = format!(
                    "{}，学校写入可能已经发送，请先只读核对，禁止自动重试",
                    reason.message()
                );
            }

            return crate::render_startup_error(self.json, self.feature, error, stdout, stderr);
        }
        let local = self.local.is_some();
        let mut guarded_stdout = GuardedWriter {
            writer: stdout,
            control,
        };
        let mut guarded_stderr = GuardedWriter {
            writer: stderr,
            control,
        };
        let stdout = &mut guarded_stdout;
        let stderr = &mut guarded_stderr;
        let code = if let Some(extra) = self.extra {
            match extra {
                ExtraResult::Auth(result) => result.render(self.json, stdout, stderr),
                ExtraResult::Local(result) => result.render(self.json, stdout, stderr),
                ExtraResult::LocalStop => 7,
            }
        } else if let Some((mode, context)) = self.fixed {
            render_result(
                self.json,
                mode,
                self.feature,
                context,
                self.result.map(|r| r.data).map_err(|e| e.error),
                stdout,
                stderr,
            )
        } else {
            render_routed_result(self.json, self.feature, self.result, stdout, stderr)
        };
        let code = super::finish_output(code, stdout, stderr);
        match control.check() {
            Err(StopReason::Deadline) => {
                if local {
                    7
                } else {
                    5
                }
            }
            Err(StopReason::Cancelled) => 7,
            Ok(()) => code,
        }
    }
}
fn stop_error(reason: StopReason) -> UbaaError {
    UbaaError::new(
        if reason == StopReason::Deadline {
            ErrorCode::Timeout
        } else {
            ErrorCode::InternalError
        },
        if reason == StopReason::Deadline {
            ErrorKind::Network
        } else {
            ErrorKind::Internal
        },
        false,
        reason.message(),
    )
}
/// 按计划消费所需 stdin，help、只读和本机计划均不读取输入。
/// 宿主必须提供受同一 control 约束的读取适配器，不能传无限阻塞的全局输入。
/// # Errors
/// 输入读取失败或命令停止。
pub fn prepare_input(
    plan: CommandPlan,
    input: &mut impl BufRead,
    control: &CommandControl,
) -> ubaa_core::facade::Result<PreparedCommand> {
    control.check().map_err(stop_error)?;
    let mut bytes = Vec::new();
    if let crate::Command::Auth(crate::AuthArgs {
        command: crate::AuthCommand::Login(args),
    }) = &plan.cli.command
    {
        let invalid = (args.username_stdin && args.username.is_some())
            || (plan.cli.json
                && (!args.password_stdin || (args.username.is_none() && !args.username_stdin)))
            || args
                .username
                .as_ref()
                .is_some_and(|name| name.trim().is_empty());
        let lines = if invalid {
            0
        } else {
            usize::from(args.username_stdin || args.username.is_none()) + 1
        };
        for _ in 0..lines {
            input
                .read_until(b'\n', &mut bytes)
                .map_err(|_| crate::io::input::invalid_input("无法读取登录输入"))?;
            control.check().map_err(stop_error)?;
        }
    } else if plan.requirements().stdin {
        input
            .read_to_end(&mut bytes)
            .map_err(|_| crate::io::input::invalid_input("无法读取命令输入"))?;
    }
    control.check().map_err(stop_error)?;
    Ok(PreparedCommand { plan, input: bytes })
}
/// 执行一次完整聚合路由尝试；本函数不接触任何输出通道。
pub async fn execute_attempt<B: RoutedCliBackend + Send>(
    prepared: &PreparedCommand,
    backend: &mut B,
    control: &CommandControl,
) -> AttemptOutcome {
    let cli = prepared.plan.cli.clone();
    let result = control
        .run(crate::execute::routed::execute_routed(
            cli,
            backend,
            &mut Cursor::new(&prepared.input),
        ))
        .await;
    outcome(prepared, result, None)
}
/// 固定路线和显式诊断登录复用相同的结果、期限与交付接口。
/// 交互输入由宿主提前安全准备，执行阶段不访问全局终端。
pub async fn execute_fixed_attempt<B: CliBackend + Send>(
    prepared: &PreparedCommand,
    backend: &mut B,
    control: &CommandControl,
) -> AttemptOutcome {
    let mode = backend.mode();
    let context = ReadonlyRouteContext::explicit(mode);
    let result = control
        .run(crate::execute::fixed::execute_fixed(
            prepared.plan.cli.clone(),
            backend,
            &mut Cursor::new(&prepared.input),
            &mut std::io::sink(),
        ))
        .await;
    outcome(
        prepared,
        result.map(|r| {
            r.map(|data| ubaa_core::facade::Routed {
                data,
                resolution: context.resolution(mode),
            })
            .map_err(|error| RoutedError {
                error,
                resolution: Some(context.resolution(mode)),
            })
        }),
        Some((mode, context)),
    )
}
fn outcome(
    prepared: &PreparedCommand,
    result: Result<RoutedResult<CommandOutput>, StopReason>,
    fixed: Option<(ConnectionMode, ReadonlyRouteContext)>,
) -> AttemptOutcome {
    let stop = result.as_ref().err().copied();
    let result = result.unwrap_or_else(|reason| {
        Err(RoutedError {
            error: stop_error(reason),
            resolution: None,
        })
    });
    let requirements = prepared.plan.requirements();
    let retry = if requirements.class == CommandClass::Readonly {
        result
            .as_ref()
            .err()
            .filter(|e| e.error.code == ErrorCode::AuthenticationRequired)
            .and_then(|e| e.resolution)
            .map(|r| r.mode)
    } else {
        None
    };
    let handle = ResultHandle {
        json: prepared.plan.cli.json,
        feature: prepared.plan.cli.feature(),
        result,
        fixed,
        stop,
        extra: None,
        local: None,
        school_write: requirements.class == CommandClass::SchoolWrite,
    };
    if let (Some(route), Some(target)) = (retry, requirements.recovery_target) {
        AttemptOutcome::AuthExpired {
            target,
            route,
            result: handle,
        }
    } else {
        AttemptOutcome::Completed(handle)
    }
}

/// 显式聚合认证沿自身语义执行，不进入认证过期重跑器。
pub async fn execute_auth_attempt(
    prepared: &PreparedCommand,
    backend: &mut ubaa_core::facade::UbaaClient,
    control: &CommandControl,
) -> AttemptOutcome {
    let result = control
        .run(crate::execute::aggregate::execute_auth(
            prepared.plan.cli.clone(),
            backend,
            &mut Cursor::new(&prepared.input),
        ))
        .await;
    extra_outcome(prepared, result.map(|r| ExtraResult::Auth(Box::new(r))))
}
/// 旧本机账号适配的独立执行入口，不创建网络客户端。
/// 任意同步存储调用的中断由宿主工作线程与进程收尾上限负责。
#[must_use]
pub fn execute_local_attempt(
    prepared: &PreparedCommand,
    root: &std::path::Path,
    control: &CommandControl,
) -> AttemptOutcome {
    let result = control.check().map(|()| {
        ExtraResult::Local(crate::local_agenda::read::execute_local(
            &prepared.plan.cli,
            root,
        ))
    });
    let result = result.and_then(|r| control.check().map(|()| r));
    extra_outcome(prepared, result)
}
fn extra_outcome(
    prepared: &PreparedCommand,
    result: Result<ExtraResult, StopReason>,
) -> AttemptOutcome {
    let stop = result.as_ref().err().copied();
    let extra = result.ok().or_else(|| {
        (prepared.plan.requirements().class == CommandClass::Local).then(|| ExtraResult::LocalStop)
    });
    AttemptOutcome::Completed(ResultHandle {
        json: prepared.plan.cli.json,
        feature: prepared.plan.cli.feature(),
        result: Err(RoutedError {
            error: crate::io::input::invalid_input("命令执行未完成"),
            resolution: None,
        }),
        fixed: None,
        stop,
        extra,
        local: (prepared.plan.requirements().class == CommandClass::Local)
            .then(|| prepared.plan.cli.clone()),
        school_write: false,
    })
}

struct GuardedWriter<'a, W> {
    writer: &'a mut W,
    control: &'a CommandControl,
}
impl<W: Write> Write for GuardedWriter<'_, W> {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.control
            .check()
            .map_err(|_| std::io::Error::other("命令交付已停止"))?;
        self.writer.write(bytes)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.control
            .check()
            .map_err(|_| std::io::Error::other("命令交付已停止"))?;
        self.writer.flush()
    }
}
