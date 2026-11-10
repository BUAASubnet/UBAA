//! 命令只借用当前 Core 与本机句柄，解析和输出始终由公共命令库负责。
pub(crate) mod backend;
mod cache;
pub mod output;
use super::client::{BridgeClient, BridgeConnectionMode, BridgeError, disposed_error};
pub use output::BridgeCommandDelivery;
use std::{
    io::Cursor,
    sync::{
        Arc, Mutex, RwLock,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};
use ubaa_command::{self as command, CommandClass};
use ubaa_core::facade::{self as core, ErrorCode, ErrorKind, UbaaError};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeCommandClass {
    Early,
    Local,
    Readonly,
    ExplicitAuth,
    SchoolWrite,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeCommandAuth {
    Login,
    Status,
    Logout,
}
#[derive(Clone, Debug)]
pub struct BridgeCommandRequirements {
    pub class: BridgeCommandClass,
    pub auth: Option<BridgeCommandAuth>,
    pub config_directory: Option<String>,
    pub school_cache: bool,
    pub agenda_sync: bool,
    pub has_transfer: bool,
    pub recovery_target: Option<super::recovery::BridgeRecoveryFeature>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeCommandInputKind {
    Ready,
    Line,
    Secret,
    Body,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeCommandFailure {
    Authentication,
    InvalidCredentials,
    PermissionDenied,
    Network,
    Timeout,
    UpstreamChanged,
    Cancelled,
    MaterialUnavailable,
    Storage,
    CacheKeyMissing,
    CacheMissing,
    CacheCorrupt,
    AgendaCorrupt,
    UpdateRequired,
}
#[derive(Clone, Debug)]
pub struct BridgeCommandInput {
    pub kind: BridgeCommandInputKind,
    pub prompt: String,
}
pub struct BridgeCommand {
    plan: Option<command::CommandPlan>,
    early: Mutex<Option<Body>>,
    prepared: tokio::sync::Mutex<Option<command::PreparedCommand>>,
    pub(crate) control: command::CommandControl,
    attempts: AtomicUsize,
    pub(crate) transfer: Mutex<Option<core::bhpan::BhpanTransfer>>,
    close: RwLock<Option<core::ClientCloseControl>>,
    pub(crate) sent: Mutex<Option<(Arc<core::WriteBoundaryObservation>, core::RouteResolution)>>,
}
pub(super) enum Body {
    AgendaSync {
        json: bool,
        result: command::agenda::sync::AgendaSyncCommandResult,
    },
    Result(command::ResultHandle),
    Parse(command::runtime::ParseFailure),
    Error {
        json: bool,
        feature: command::CliFeature,
        error: UbaaError,
        resolution: Option<core::RouteResolution>,
    },
    Agenda {
        json: bool,
        result: command::agenda::SharedAgendaResult,
    },
    LocalError {
        json: bool,
        operation: String,
        error: command::agenda::LocalError,
    },
}
#[derive(Clone)]
pub struct BridgeCommandResult {
    pub(super) body: Arc<Mutex<Option<Body>>>,
    control: command::CommandControl,
    pub(super) scope: Option<core::SharedAccountGuard>,
    pub(super) hints: Arc<Mutex<Vec<super::write::command::CommandHint>>>,
}
pub struct BridgeCommandAttempt {
    pub result: BridgeCommandResult,
    pub recovery_target: Option<super::recovery::BridgeRecoveryFeature>,
    pub route: Option<BridgeConnectionMode>,
}
impl BridgeCommand {
    /// argv 包含程序名；剩余预算由原生入口扣除 Engine 启动时间后传入。
    #[flutter_rust_bridge::frb(sync)]
    pub fn parse(argv: Vec<String>, remaining_millis: u32) -> Self {
        let control = command::CommandControl::new(
            Instant::now(),
            Duration::from_millis(u64::from(remaining_millis)),
        );
        let (plan, early) = match command::parse(argv) {
            Ok(plan) => (Some(plan), None),
            Err(error) => (None, Some(Body::Parse(error))),
        };
        let command = Self {
            plan,
            early: Mutex::new(early),
            prepared: tokio::sync::Mutex::new(None),
            control,
            attempts: AtomicUsize::new(0),
            transfer: Mutex::new(None),
            close: RwLock::new(None),
            sent: Mutex::new(None),
        };
        if let Some(error) = command
            .plan
            .as_ref()
            .and_then(|plan| plan.validate_configuration().err())
        {
            command.set_error(error);
        }
        command
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn requirements(&self) -> BridgeCommandRequirements {
        let Some(plan) = &self.plan else {
            return BridgeCommandRequirements {
                class: BridgeCommandClass::Early,
                auth: None,
                config_directory: None,
                school_cache: false,
                agenda_sync: false,
                has_transfer: false,
                recovery_target: None,
            };
        };
        let req = plan.requirements();
        let auth = match &plan.cli().command {
            command::Command::Auth(command::AuthArgs { command }) => Some(match command {
                command::AuthCommand::Login(_) => BridgeCommandAuth::Login,
                command::AuthCommand::Status => BridgeCommandAuth::Status,
                command::AuthCommand::Logout => BridgeCommandAuth::Logout,
            }),
            _ => None,
        };
        let school_cache = matches!(
            &plan.cli().command,
            command::Command::Agenda(command::AgendaArgs {
                command: command::AgendaCommand::List {
                    school_cache: true,
                    ..
                } | command::AgendaCommand::Export {
                    school_cache: true,
                    ..
                }
            })
        );
        BridgeCommandRequirements {
            class: match req.class {
                CommandClass::Local => BridgeCommandClass::Local,
                CommandClass::Readonly => BridgeCommandClass::Readonly,
                CommandClass::ExplicitAuth => BridgeCommandClass::ExplicitAuth,
                CommandClass::SchoolWrite => BridgeCommandClass::SchoolWrite,
            },
            auth,
            config_directory: req.config_dir.map(|p| p.to_string_lossy().into()),
            school_cache,
            agenda_sync: matches!(
                &plan.cli().command,
                command::Command::Agenda(command::AgendaArgs {
                    command: command::AgendaCommand::Sync { .. }
                })
            ),
            recovery_target: req.recovery_target.map(target_to_bridge),
            has_transfer: req.has_transfer,
        }
    }
    /// 原生每次只读取所请求的输入；无效用户名不能提前消耗密码。
    /// # Errors
    /// 输入流或命令状态不能继续时返回错误。
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    #[allow(clippy::needless_pass_by_value)]
    pub fn input_request(
        &self,
        input: Vec<u8>,
        eof: bool,
    ) -> Result<BridgeCommandInput, BridgeError> {
        let ready = || BridgeCommandInput {
            kind: BridgeCommandInputKind::Ready,
            prompt: String::new(),
        };
        let Some(plan) = &self.plan else {
            return Ok(ready());
        };
        if self.early.lock().unwrap().is_some() {
            return Ok(ready());
        }
        self.control.check().map_err(|_| stopped())?;
        if let Err(error) = plan.validate_local_arguments() {
            self.set_error(error);
            return Ok(ready());
        }
        if let command::Command::Auth(command::AuthArgs {
            command: command::AuthCommand::Login(args),
        }) = &plan.cli().command
        {
            let username_line = args.username_stdin || args.username.is_none();
            let mut lines = input.split_inclusive(|c| *c == b'\n');
            if username_line {
                let Some(name) = lines.next().filter(|s| eof || s.ends_with(b"\n")) else {
                    if eof {
                        return Ok(ready());
                    }
                    return Ok(BridgeCommandInput {
                        kind: BridgeCommandInputKind::Line,
                        prompt: if args.username_stdin {
                            String::new()
                        } else {
                            "用户名：".into()
                        },
                    });
                };
                if std::str::from_utf8(name).map_or(true, |s| s.trim().is_empty()) {
                    self.set_error(UbaaError::new(
                        ErrorCode::InvalidInput,
                        ErrorKind::Input,
                        false,
                        "用户名不能为空且必须为 UTF-8",
                    ));
                    return Ok(ready());
                }
            }
            if lines.next().is_none() && !eof {
                return Ok(BridgeCommandInput {
                    kind: if args.password_stdin {
                        BridgeCommandInputKind::Line
                    } else {
                        BridgeCommandInputKind::Secret
                    },
                    prompt: if args.password_stdin {
                        String::new()
                    } else {
                        "密码：".into()
                    },
                });
            }
        } else if matches!(&plan.cli().command, command::Command::Bhpan(args) if args.command.password_stdin())
            && !eof
            && !input.ends_with(b"\n")
        {
            return Ok(BridgeCommandInput {
                kind: BridgeCommandInputKind::Secret,
                prompt: String::new(),
            });
        } else if plan.requirements().stdin
            && !eof
            && !matches!(&plan.cli().command, command::Command::Bhpan(_))
        {
            return Ok(BridgeCommandInput {
                kind: BridgeCommandInputKind::Body,
                prompt: String::new(),
            });
        }
        Ok(ready())
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub async fn prepare(&self, input: Vec<u8>) {
        let Some(plan) = &self.plan else { return };
        if self.early.lock().unwrap().is_some() {
            return;
        }
        match command::prepare_input(plan.clone(), &mut Cursor::new(input), &self.control) {
            Ok(value) => *self.prepared.lock().await = Some(value),
            Err(error) => self.set_error(error),
        }
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub fn early_result(&self) -> Option<BridgeCommandResult> {
        self.early
            .lock()
            .unwrap()
            .take()
            .map(|body| self.result(body))
    }
    pub(super) fn result(&self, body: Body) -> BridgeCommandResult {
        BridgeCommandResult {
            body: Arc::new(Mutex::new(Some(body))),
            control: self.control.clone(),
            scope: None,
            hints: Arc::new(Mutex::new(Vec::new())),
        }
    }
    fn set_error(&self, error: UbaaError) {
        if let Some(plan) = &self.plan {
            if self.requirements().agenda_sync {
                *self.early.lock().unwrap() = Some(Body::AgendaSync {
                    json: plan.cli().json,
                    result: command::agenda::sync::AgendaSyncCommandResult(Err(
                        core::AgendaSyncError::Remote(error),
                    )),
                });
                return;
            }
            let body = if let command::Command::Agenda(args) = &plan.cli().command {
                Body::LocalError {
                    json: plan.cli().json,
                    operation: args.command.operation().into(),
                    error: if error.code == ErrorCode::InvalidInput {
                        command::agenda::LocalError::InvalidInput
                    } else {
                        command::agenda::LocalError::Storage
                    },
                }
            } else {
                Body::Error {
                    json: plan.cli().json,
                    feature: plan.cli().feature(),
                    error,
                    resolution: None,
                }
            };
            *self.early.lock().unwrap() = Some(body);
        }
    }
    pub fn fail(&self, authentication: bool) -> BridgeCommandResult {
        self.failure(if authentication {
            BridgeCommandFailure::Authentication
        } else {
            BridgeCommandFailure::MaterialUnavailable
        })
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub fn failure(&self, failure: BridgeCommandFailure) -> BridgeCommandResult {
        if !self.requirements().agenda_sync
            && let Some(plan) = &self.plan
            && let command::Command::Agenda(args) = &plan.cli().command
        {
            use command::agenda::LocalError as E;
            let error = match failure {
                BridgeCommandFailure::Authentication => E::RegistrationRequired,
                BridgeCommandFailure::CacheKeyMissing => E::CacheKeyMissing,
                BridgeCommandFailure::CacheMissing => E::CacheMissing,
                BridgeCommandFailure::CacheCorrupt => E::CacheCorrupt,
                BridgeCommandFailure::AgendaCorrupt => E::AgendaCorrupt,
                BridgeCommandFailure::MaterialUnavailable => E::MaterialUnavailable,
                _ => E::Storage,
            };
            return self.result(Body::LocalError {
                json: plan.cli().json,
                operation: args.command.operation().into(),
                error,
            });
        }
        let mut error = failure_error(failure);
        let mut resolution = None;
        if let Some((observation, known)) = self.sent.lock().unwrap().as_ref()
            && observation.may_have_been_sent()
        {
            error = UbaaError::new(
                ErrorCode::OutcomeUnknown,
                ErrorKind::Network,
                false,
                "学校写入可能已经发送，结果未知，请先只读核对，禁止自动重试",
            );
            resolution = Some(*known);
        }
        let plan = self.plan.as_ref();
        if self.requirements().agenda_sync {
            return self.result(Body::AgendaSync {
                json: plan.is_some_and(|p| p.cli().json),
                result: command::agenda::sync::AgendaSyncCommandResult(Err(
                    core::AgendaSyncError::Remote(error),
                )),
            });
        }
        self.result(Body::Error {
            json: plan.is_some_and(|p| p.cli().json),
            feature: plan.map_or(command::CliFeature::Cli, |p| p.cli().feature()),
            error,
            resolution,
        })
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.control.cancel();
        if let Some(transfer) = self.transfer.lock().unwrap().as_ref() {
            transfer.cancel();
        }
        if let Some(close) = self.close.read().unwrap().as_ref() {
            close.close();
        }
    }
    /// 安全进度仅包含阶段与字节数，供有界终端通道写入 stderr。
    #[flutter_rust_bridge::frb(sync)]
    pub fn transfer_progress_line(&self) -> Option<String> {
        self.transfer
            .lock()
            .unwrap()
            .as_ref()
            .map(|transfer| ubaa_command::bhpan::progress_line(&transfer.progress()))
    }
    /// 本机命令独立于学校客户端，使用同账号的现有日程与可选加密缓存。
    /// # Errors
    /// 计划已消费、句柄不可用或执行任务失败时返回错误。
    pub async fn execute_agenda(
        &self,
        agenda: &super::agenda::BridgeAgendaStore,
        scope: &super::shared_account::BridgeSharedAccount,
    ) -> Result<BridgeCommandResult, BridgeError> {
        self.execute_agenda_scoped(agenda, None, scope).await
    }
    /// # Errors
    /// 计划已消费、缓存或日程句柄不可用时返回错误。
    pub async fn execute_cached_agenda(
        &self,
        agenda: &super::agenda::BridgeAgendaStore,
        cache: &super::offline::BridgeOfflineCache,
        scope: &super::shared_account::BridgeSharedAccount,
    ) -> Result<BridgeCommandResult, BridgeError> {
        self.execute_agenda_scoped(agenda, Some(cache), scope).await
    }
    async fn execute_agenda_scoped(
        &self,
        agenda: &super::agenda::BridgeAgendaStore,
        cache: Option<&super::offline::BridgeOfflineCache>,
        scope: &super::shared_account::BridgeSharedAccount,
    ) -> Result<BridgeCommandResult, BridgeError> {
        if self.requirements().class != BridgeCommandClass::Local
            || self.attempts.fetch_add(1, Ordering::SeqCst) != 0
        {
            return Err(stopped());
        }
        let prepared = self
            .prepared
            .lock()
            .await
            .as_ref()
            .ok_or_else(stopped)?
            .clone();
        let json = self.plan.as_ref().is_some_and(|p| p.cli().json);
        let store = agenda.store.clone();
        let cache = cache.map(|value| value.cache.clone());
        let delivery_scope = scope.guard.clone();
        let scope = delivery_scope.clone();
        let control = self.control.clone();
        let result = tokio::task::spawn_blocking(move || {
            command::agenda::execute_shared_agenda(
                &prepared,
                &store,
                cache.as_ref(),
                scope,
                &control,
            )
        })
        .await
        .map_err(|_| stopped())?;
        let mut result = self.result(Body::Agenda { json, result });
        result.scope = Some(delivery_scope);
        Ok(result)
    }
}
mod agenda_sync;
impl BridgeCommandResult {
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    #[must_use]
    pub fn authentication_succeeded(&self) -> bool {
        matches!(self.body.lock().unwrap().as_ref(),Some(Body::Result(result)) if result.authentication_succeeded())
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    #[must_use]
    pub fn recovery_failed(&self, failure: BridgeCommandFailure) -> Self {
        let body = self.body.lock().unwrap().take().map(|body| match body {
            Body::Result(result) => Body::Result(result.replace_error(failure_error(failure))),
            other => other,
        });
        Self {
            body: Arc::new(Mutex::new(body)),
            control: self.control.clone(),
            scope: None,
            hints: self.hints.clone(),
        }
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    #[must_use]
    pub fn registration_succeeded(&self) -> Self {
        let body = self.body.lock().unwrap().take().map(|body| match body {
            Body::Result(result) => Body::Result(result.registration_succeeded()),
            other => other,
        });
        Self {
            body: Arc::new(Mutex::new(body)),
            control: self.control.clone(),
            scope: None,
            hints: self.hints.clone(),
        }
    }
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    #[must_use]
    pub fn registration_failed(&self) -> Self {
        let body = self.body.lock().unwrap().take().map(|body| match body {
            Body::Result(result) => Body::Result(result.registration_failed()),
            other => other,
        });
        Self {
            body: Arc::new(Mutex::new(body)),
            control: self.control.clone(),
            scope: None,
            hints: self.hints.clone(),
        }
    }
}
fn failure_error(failure: BridgeCommandFailure) -> UbaaError {
    use BridgeCommandFailure as F;
    let (code, kind, message) = match failure {
        F::Authentication => (
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            "当前账号不能执行此命令，请登录后重试",
        ),
        F::InvalidCredentials => (
            ErrorCode::InvalidCredentials,
            ErrorKind::Authentication,
            "保存的凭据已被拒绝，请重新登录",
        ),
        F::PermissionDenied => (
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            "当前账号没有操作权限",
        ),
        F::Network => (
            ErrorCode::NetworkError,
            ErrorKind::Network,
            "恢复会话时网络不可用",
        ),
        F::Timeout => (ErrorCode::Timeout, ErrorKind::Network, "命令总期限已到达"),
        F::UpstreamChanged => (
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            "服务响应已变化",
        ),
        F::UpdateRequired => return UbaaError::update_required(),
        F::Cancelled => (ErrorCode::InternalError, ErrorKind::Internal, "命令已取消"),
        _ => (
            ErrorCode::InternalError,
            ErrorKind::Internal,
            "本机材料或命令运行资源不可用",
        ),
    };
    UbaaError::new(code, kind, false, message)
}
fn stopped() -> BridgeError {
    BridgeError::from_core(
        UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "命令已停止",
        ),
        None,
    )
}
impl BridgeClient {
    /// 每次读取借用当前 Core；学校写入使用共享的一次性意图，最多重跑一次只读命令。
    /// # Errors
    /// 客户端已关闭、次数已用尽或命令已停止时返回错误。
    pub async fn execute_command(
        &self,
        command: &BridgeCommand,
        expected_identity: Option<String>,
    ) -> Result<BridgeCommandAttempt, BridgeError> {
        self.execute_command_scoped(command, expected_identity, None, None)
            .await
    }
    /// # Errors
    /// 客户端或缓存不可用、次数已用尽或命令已停止时返回错误。
    pub async fn execute_cached_command(
        &self,
        command: &BridgeCommand,
        expected_identity: String,
        cache: &super::offline::BridgeOfflineCache,
    ) -> Result<BridgeCommandAttempt, BridgeError> {
        self.execute_command_scoped(command, Some(expected_identity), None, Some(cache))
            .await
    }
    /// 条件撤销票据只供本次显式退出，结束后恢复原固定归属。
    /// # Errors
    /// 计划不是退出、撤销票据不可用或客户端已关闭时返回错误。
    pub async fn execute_command_logout(
        &self,
        command: &BridgeCommand,
        scope: &super::shared_account::BridgeSharedAccount,
    ) -> Result<BridgeCommandAttempt, BridgeError> {
        if command.requirements().auth != Some(BridgeCommandAuth::Logout) {
            return Err(stopped());
        }
        self.execute_command_scoped(command, None, Some(scope), None)
            .await
    }
    async fn execute_command_scoped(
        &self,
        command: &BridgeCommand,
        expected_identity: Option<String>,
        logout: Option<&super::shared_account::BridgeSharedAccount>,
        cache: Option<&super::offline::BridgeOfflineCache>,
    ) -> Result<BridgeCommandAttempt, BridgeError> {
        let requirements = command.requirements();
        let max = if requirements.class == BridgeCommandClass::Readonly {
            2
        } else {
            1
        };
        if command.attempts.fetch_add(1, Ordering::SeqCst) >= max {
            return Err(stopped());
        }
        let prepared = command.prepared.lock().await;
        let prepared = prepared.as_ref().ok_or_else(stopped)?;
        let (outcome, scope, hints) = command
            .control
            .run(Box::pin(async {
                let mut inner = self.inner.lock().await;
                let client = inner.as_mut().ok_or_else(disposed_error)?;
                *command.close.write().unwrap() = Some(client.close_control());
                if let Some(logout) = logout {
                    let previous = client.shared_account_guard();
                    client.bind_shared_account(Some(logout.guard.clone()));
                    let restore = super::shared_account::LogoutRestore { client, previous };
                    let outcome =
                        command::execute_auth_attempt(prepared, restore.client, &command.control)
                            .await;
                    return Ok((outcome, Some(logout.guard.clone()), Vec::new()));
                }
                let scope = client.shared_account_guard();
                if matches!(
                    requirements.class,
                    BridgeCommandClass::Readonly | BridgeCommandClass::SchoolWrite
                ) {
                    let target = command
                        .plan
                        .as_ref()
                        .and_then(|p| p.requirements().recovery_target)
                        .ok_or_else(stopped)?;
                    let verification = verify_identity(
                        client,
                        target,
                        expected_identity.as_deref(),
                        command.control.remaining(),
                    )
                    .await;
                    if let Err(error) = verification {
                        return Ok((
                            command::runtime::preflight_failure(prepared, error),
                            scope,
                            Vec::new(),
                        ));
                    }
                }
                if requirements.class == BridgeCommandClass::ExplicitAuth {
                    let outcome =
                        command::execute_auth_attempt(prepared, client, &command.control).await;
                    return Ok((outcome, scope, Vec::new()));
                }
                drop(inner);
                let mut backend = backend::CommandBackend {
                    client: self,
                    cache,
                    command: Some(command),
                    hints: Vec::new(),
                };
                let outcome =
                    command::execute_attempt(prepared, &mut backend, &command.control).await;
                Ok::<_, BridgeError>((outcome, scope, backend.hints))
            }))
            .await
            .map_err(|_| stopped())??;
        let (target, route, result) = match outcome {
            command::AttemptOutcome::Completed(result) => (None, None, result),
            command::AttemptOutcome::AuthExpired {
                target,
                route,
                result,
            } => (Some(target_to_bridge(target)), Some(route.into()), result),
            command::AttemptOutcome::SharedStateChanged { target, result } => {
                (Some(target_to_bridge(target)), None, result)
            }
        };
        let mut result = command.result(Body::Result(result));
        result.scope = scope;
        *result.hints.lock().unwrap() = hints;
        Ok(BridgeCommandAttempt {
            result,
            recovery_target: target,
            route,
        })
    }
}
async fn verify_identity(
    client: &mut core::UbaaClient,
    target: command::RecoveryTarget,
    expected: Option<&str>,
    remaining: Duration,
) -> core::RoutedResult<()> {
    let Some(expected) = expected.filter(|s| !s.trim().is_empty()) else {
        return Err(core::RoutedError {
            error: failure_error(BridgeCommandFailure::Authentication),
            resolution: None,
        });
    };
    let control =
        core::RequiredRecoveryControl::new(remaining).map_err(|error| core::RoutedError {
            error,
            resolution: None,
        })?;
    let operation = control.claim().map_err(|error| core::RoutedError {
        error,
        resolution: None,
    })?;
    let recovered = match target {
        command::RecoveryTarget::Bhpan => {
            client.recover_bhpan_session_controlled(operation).await?
        }
        _ => match target_to_bridge(target).feature() {
            Some(feature) => {
                client
                    .recover_required_session_controlled(feature, operation)
                    .await?
            }
            None => client.recover_user_session_controlled(operation).await?,
        },
    };
    let profile = &recovered.data.user;
    if ![profile.username.as_deref(), profile.school_id.as_deref()]
        .into_iter()
        .flatten()
        .any(|s| s.trim() == expected.trim())
    {
        return Err(core::RoutedError {
            error: core::UbaaError::new(
                ErrorCode::PermissionDenied,
                ErrorKind::Authentication,
                false,
                "本机会话与已核实账号不一致",
            ),
            resolution: Some(recovered.resolution),
        });
    }
    Ok(core::Routed {
        data: (),
        resolution: recovered.resolution,
    })
}

/// 显式登录能力由 Core 签发，宿主在共享材料事务内核实并消费。
pub struct BridgeCommandLoginIdentity {
    identity: Mutex<Option<core::VerifiedLoginIdentity>>,
}
impl BridgeClient {
    /// # Errors
    /// 本次认证没有可交付的身份凭证时返回错误。
    pub async fn take_command_login_identity(
        &self,
    ) -> Result<BridgeCommandLoginIdentity, BridgeError> {
        let mut inner = self.inner.lock().await;
        let identity = inner
            .as_mut()
            .ok_or_else(disposed_error)?
            .take_verified_login_identity()
            .map_err(|e| BridgeError::from_core(e, None))?;
        Ok(BridgeCommandLoginIdentity {
            identity: Mutex::new(Some(identity)),
        })
    }
    /// # Errors
    /// 身份凭证已消费或不属于当前认证代次时返回错误。
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub async fn command_login_username(
        &self,
        identity: &BridgeCommandLoginIdentity,
    ) -> Result<String, BridgeError> {
        let mut inner = self.inner.lock().await;
        let identity = identity.identity.lock().unwrap();
        inner
            .as_mut()
            .ok_or_else(disposed_error)?
            .validate_login_identity(identity.as_ref().ok_or_else(stopped)?)
            .map(str::to_owned)
            .map_err(|e| BridgeError::from_core(e, None))
    }
    /// # Errors
    /// 身份凭证已消费或认证代次已变化时返回错误。
    /// # Panics
    /// 命令状态锁被其他线程的 panic 污染时终止。
    pub async fn consume_command_login_identity(
        &self,
        identity: &BridgeCommandLoginIdentity,
    ) -> Result<(), BridgeError> {
        let mut inner = self.inner.lock().await;
        let mut identity = identity.identity.lock().unwrap();
        inner
            .as_mut()
            .ok_or_else(disposed_error)?
            .consume_login_identity(identity.as_ref().ok_or_else(stopped)?)
            .map_err(|e| BridgeError::from_core(e, None))?;
        *identity = None;
        Ok(())
    }
}
fn target_to_bridge(target: command::RecoveryTarget) -> super::recovery::BridgeRecoveryFeature {
    use super::recovery::BridgeRecoveryFeature as B;
    use command::RecoveryTarget as T;
    match target {
        T::Bhpan => B::Bhpan,
        T::User => B::User,
        T::Portal => B::Portal,
        T::Network => B::Network,
        T::Finance => B::Finance,
        T::Ihome => B::Ihome,
        T::Schedule => B::Schedule,
        T::Exam => B::Exam,
        T::Grades => B::Grades,
        T::Classroom => B::Classroom,
        T::Spoc => B::Spoc,
        T::Judge => B::Judge,
        T::Signin => B::Signin,
        T::LibBook => B::LibBook,
        T::Bykc => B::Bykc,
        T::Cgyy => B::Cgyy,
        T::Ygdk => B::Ygdk,
        T::Evaluation => B::Evaluation,
    }
}

#[cfg(test)]
mod tests;
