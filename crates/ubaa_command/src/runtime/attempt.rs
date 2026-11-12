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
#[derive(Clone)]
pub struct PreparedCommand {
    pub(crate) plan: CommandPlan,
    pub(crate) input: Vec<u8>,
    bhpan_input: Option<crate::bhpan::BhpanPreparedInput>,
    ygdk_request: Option<ubaa_core::facade::YgdkClockinSubmitRequest>,
}
/// 保留 typed 执行结果，调用者不能构造成功正文。
pub struct ResultHandle {
    json: bool,
    feature: CliFeature,
    result: RoutedResult<CommandOutput>,
    fixed: Option<(ConnectionMode, ReadonlyRouteContext)>,
    stop: Option<StopReason>,
    extra: Option<ExtraResult>,
    school_write: bool,
}
enum ExtraResult {
    Auth(Box<crate::execute::aggregate::AggregateResult>),
}
/// 只有明确路线的只读认证过期才允许上层安排一次恢复。
pub enum AttemptOutcome {
    Completed(ResultHandle),
    AuthExpired {
        target: RecoveryTarget,
        route: ConnectionMode,
        result: ResultHandle,
    },
    SharedStateChanged {
        target: RecoveryTarget,
        result: ResultHandle,
    },
}
impl AttemptOutcome {
    #[must_use]
    pub fn into_result(self) -> ResultHandle {
        match self {
            Self::Completed(r)
            | Self::AuthExpired { result: r, .. }
            | Self::SharedStateChanged { result: r, .. } => r,
        }
    }
}
impl ResultHandle {
    #[must_use]
    pub fn authentication_succeeded(&self) -> bool {
        matches!(&self.extra,Some(ExtraResult::Auth(value)) if matches!(value.as_ref(),crate::execute::aggregate::AggregateResult::Auth{outcome,..} if outcome.readiness!=ubaa_core::facade::LoginReadiness::NoneReady))
    }
    /// 只有完整交付的确定结果才清除本次学校写入的核对提示。
    #[must_use]
    pub fn write_result_known(&self) -> bool {
        self.stop.is_none()
            && match &self.result {
                Err(error) => error.error.code != ErrorCode::OutcomeUnknown,
                Ok(value) => {
                    !matches!(&value.data,CommandOutput::EvaluationBatch{data,..} if data.items.iter().any(|v|v.outcome==ubaa_core::facade::EvaluationCourseOutcome::OutcomeUnknown))
                }
            }
    }
    #[must_use]
    pub fn registration_succeeded(mut self) -> Self {
        if let Some(ExtraResult::Auth(value)) = &mut self.extra
            && let crate::execute::aggregate::AggregateResult::Auth { registration, .. } =
                value.as_mut()
        {
            *registration = Some(Ok(()));
        }
        self
    }
    /// 恢复失败保留原命令与已知路线，只替换错误结果，不交付原正文。
    #[must_use]
    pub fn replace_error(mut self, error: UbaaError) -> Self {
        let resolution = match &self.result {
            Ok(value) => Some(value.resolution),
            Err(error) => error.resolution,
        };
        self.result = Err(RoutedError { error, resolution });
        self.extra = None;
        self
    }
    #[must_use]
    pub fn registration_failed(mut self) -> Self {
        if let Some(ExtraResult::Auth(value)) = &mut self.extra
            && let crate::execute::aggregate::AggregateResult::Auth { registration, .. } =
                value.as_mut()
        {
            *registration = Some(Err(crate::agenda::LocalError::MaterialUnavailable));
        }
        self
    }
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
        if let Some(reason) = stop {
            if self.school_write
                && let Err(error) = &self.result
                && error.error.code == ErrorCode::OutcomeUnknown
            {
                return crate::render_operation_error(
                    self.json,
                    self.feature,
                    error.clone(),
                    stdout,
                    stderr,
                );
            }
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
            Err(StopReason::Deadline) => 5,
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
/// 按计划消费所需 stdin。help 与只读计划不读取输入，本机写入按具体操作读取快照。
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
    plan.validate_local_arguments()?;
    if let crate::Command::Auth(crate::AuthArgs {
        command: crate::AuthCommand::Login(args),
    }) = &plan.cli.command
    {
        let lines = usize::from(args.username_stdin || args.username.is_none()) + 1;
        for line in 0..lines {
            if line == 0 && args.username_stdin {
                let username = crate::io::input::read_username_stdin(input)?;
                bytes.extend_from_slice(username.as_bytes());
                bytes.push(b'\n');
            } else {
                input
                    .read_until(b'\n', &mut bytes)
                    .map_err(|_| crate::io::input::invalid_input("无法读取登录输入"))?;
            }
            control.check().map_err(stop_error)?;
        }
    } else if let crate::Command::Agenda(arguments) = &plan.cli.command {
        if !crate::agenda::confirmed(&arguments.command)
            && !matches!(arguments.command, crate::AgendaCommand::Clear { .. })
        {
            return Err(crate::io::input::invalid_input(
                "修改本机日程需要 --confirm-local-write",
            ));
        }
        if let Some(path) = crate::agenda::input_path(&arguments.command) {
            use std::io::Read;
            if path == std::path::Path::new("-") {
                input.take(1_048_577).read_to_end(&mut bytes)
            } else {
                std::fs::File::open(path)
                    .and_then(|file| file.take(1_048_577).read_to_end(&mut bytes))
            }
            .map_err(|_| crate::io::input::invalid_input("无法读取本机日程输入"))?;
            if bytes.len() > 1_048_576 {
                return Err(crate::io::input::invalid_input("本机日程输入过大"));
            }
        }
    } else if matches!(&plan.cli.command, crate::Command::Bhpan(args) if args.command.password_stdin())
    {
        use std::io::Read;
        input
            .take(4097)
            .read_to_end(&mut bytes)
            .map_err(|_| crate::io::input::invalid_input("无法读取分享密码"))?;
    } else if plan.requirements().stdin {
        input
            .read_to_end(&mut bytes)
            .map_err(|_| crate::io::input::invalid_input("无法读取命令输入"))?;
    }
    let ygdk_request = validate_prepared_input(&plan, &bytes)?;
    control.check().map_err(stop_error)?;
    let bhpan_input = if let crate::Command::Bhpan(args) = &plan.cli.command {
        Some(crate::bhpan::BhpanPreparedInput::capture(args, &bytes)?)
    } else {
        None
    };
    Ok(PreparedCommand {
        plan,
        input: bytes,
        bhpan_input,
        ygdk_request,
    })
}
fn validate_prepared_input(
    plan: &CommandPlan,
    bytes: &[u8],
) -> ubaa_core::facade::Result<Option<ubaa_core::facade::YgdkClockinSubmitRequest>> {
    match &plan.cli.command {
        crate::Command::Auth(crate::AuthArgs {
            command: crate::AuthCommand::Login(args),
        }) => {
            crate::execute::aggregate::read_dual_credentials(
                plan.cli.json,
                args,
                &mut Cursor::new(bytes),
                &mut std::io::sink(),
            )?;
        }
        crate::Command::Cgyy(crate::CgyyArgs {
            command: crate::CgyyCommand::Submit { .. },
        }) => {
            crate::io::input::read_cgyy_request_stdin(&mut Cursor::new(bytes))?;
        }
        crate::Command::Agenda(args) => {
            crate::agenda::validate_input(&args.command, bytes)
                .map_err(|error| crate::io::input::invalid_input(error.message()))?;
        }
        crate::Command::Ygdk(crate::YgdkArgs {
            command:
                crate::YgdkCommand::Submit {
                    classify_id,
                    item_id,
                    start_time,
                    end_time,
                    place,
                    photo,
                    share_to_square,
                    ..
                },
        }) => {
            return crate::io::input::build_ygdk_request(
                *classify_id,
                *item_id,
                start_time.clone(),
                end_time.clone(),
                place.clone(),
                photo,
                *share_to_square,
            )
            .map(Some);
        }
        _ => {}
    }
    Ok(None)
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
            prepared.ygdk_request.clone(),
            prepared.bhpan_input.clone(),
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
            prepared.ygdk_request.clone(),
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
    let shared_changed = requirements.class == CommandClass::Readonly
        && result
            .as_ref()
            .err()
            .is_some_and(|e| e.error.is_session_conflict() || e.error.is_shared_account_conflict());
    let handle = ResultHandle {
        json: prepared.plan.cli.json,
        feature: prepared.plan.cli.feature(),
        result,
        fixed,
        stop,
        extra: None,
        school_write: requirements.class == CommandClass::SchoolWrite,
    };
    if shared_changed && let Some(target) = requirements.recovery_target {
        AttemptOutcome::SharedStateChanged {
            target,
            result: handle,
        }
    } else if let (Some(route), Some(target)) = (retry, requirements.recovery_target) {
        AttemptOutcome::AuthExpired {
            target,
            route,
            result: handle,
        }
    } else {
        AttemptOutcome::Completed(handle)
    }
}
/// 本机已核实账号的会话检查失败沿用相同命令元数据和恢复分类。
#[must_use]
pub fn preflight_failure(prepared: &PreparedCommand, error: RoutedError) -> AttemptOutcome {
    outcome(prepared, Ok(Err(error)), None)
}

/// 显式聚合认证沿自身语义执行，不进入认证过期重跑器。
pub async fn execute_auth_attempt(
    prepared: &PreparedCommand,
    backend: &mut ubaa_core::facade::UbaaClient,
    control: &CommandControl,
) -> AttemptOutcome {
    if let crate::Command::Auth(crate::AuthArgs {
        command: crate::AuthCommand::Login(arguments),
    }) = &prepared.plan.cli.command
        && let Some(mode) = arguments.mode
    {
        let mode = mode.into();
        let context = ReadonlyRouteContext::explicit(mode);
        let credentials = crate::execute::aggregate::read_dual_credentials(
            prepared.plan.cli.json,
            arguments,
            &mut Cursor::new(&prepared.input),
            &mut std::io::sink(),
        );
        let result = control
            .run(async {
                let (username, password) = credentials?;
                backend
                    .login_required_route(
                        mode,
                        ubaa_core::facade::LoginInput {
                            username,
                            password: ubaa_core::facade::SecretValue::new(password),
                        },
                    )
                    .await
                    .map(|v| CommandOutput::Profile(crate::io::human::redacted_profile(v.data)))
            })
            .await;
        return outcome(
            prepared,
            result.map(|v| {
                v.map(|data| ubaa_core::facade::Routed {
                    data,
                    resolution: context.resolution(mode),
                })
                .map_err(|error| RoutedError {
                    error,
                    resolution: Some(context.resolution(mode)),
                })
            }),
            Some((mode, context)),
        );
    }
    let result = control
        .run(crate::execute::aggregate::execute_auth(
            prepared.plan.cli.clone(),
            backend,
            &mut Cursor::new(&prepared.input),
        ))
        .await;
    extra_outcome(prepared, result.map(|r| ExtraResult::Auth(Box::new(r))))
}
fn extra_outcome(
    prepared: &PreparedCommand,
    result: Result<ExtraResult, StopReason>,
) -> AttemptOutcome {
    let stop = result.as_ref().err().copied();
    let extra = result.ok();
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

#[cfg(test)]
mod delivery_tests {
    use super::*;
    fn assert_unknown(control: &CommandControl) {
        let prepared = prepare_input(
            crate::parse([
                "ubaa-cli",
                "--json",
                "bykc",
                "select",
                "--course-id",
                "42",
                "--confirm-write",
            ])
            .unwrap(),
            &mut Cursor::new([]),
            &CommandControl::default(),
        )
        .unwrap();
        let result = preflight_failure(
            &prepared,
            RoutedError {
                error: UbaaError::new(
                    ErrorCode::OutcomeUnknown,
                    ErrorKind::Network,
                    false,
                    "学校写入结果未知，请先只读核对",
                ),
                resolution: Some(
                    ReadonlyRouteContext::explicit(ConnectionMode::WebVpn)
                        .resolution(ConnectionMode::WebVpn),
                ),
            },
        )
        .into_result();
        let (mut out, mut err) = (vec![], vec![]);
        assert_eq!(result.render(control, &mut out, &mut err), 5);
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["error"]["code"], "outcome_unknown");
        assert_eq!(value["meta"]["resolvedRoute"], "webvpn");
    }
    #[test]
    fn 未知写结果在交付前取消仍保留原错误与路线() {
        let control = CommandControl::default();
        control.cancel();
        assert_unknown(&control);
    }
    #[test]
    fn 未知写结果在交付前到期仍保留原错误与路线() {
        assert_unknown(&CommandControl::new(
            std::time::Instant::now(),
            std::time::Duration::ZERO,
        ));
    }
}
