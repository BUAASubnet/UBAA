use crate::command::{
    AuthArgs, AuthCommand, BykcArgs, BykcCommand, CgyyArgs, CgyyCommand, Cli, Command,
    EvaluationArgs, EvaluationCommand, LibBookArgs, LibBookCommand, SigninArgs, SigninCommand,
    YgdkArgs, YgdkCommand,
};
use crate::{CliFeature, render_startup_error};
use clap::Parser;
use std::{ffi::OsString, io::Write, path::PathBuf};
use ubaa_core::facade::{ErrorCode, ErrorKind, UbaaError};

/// 分类按具体操作判断，学校写入不能进入只读恢复重跑器。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandClass {
    Local,
    Readonly,
    ExplicitAuth,
    SchoolWrite,
}
/// 恢复目标独立于 UI 菜单，后续 Bridge 适配可逐项映射。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecoveryTarget {
    Bhpan,
    User,
    Portal,
    Network,
    Finance,
    Ihome,
    Schedule,
    Exam,
    Grades,
    Classroom,
    Spoc,
    Judge,
    Signin,
    LibBook,
    Bykc,
    Cgyy,
    Ygdk,
    Evaluation,
}
#[derive(Clone, Debug)]
pub struct CommandRequirements {
    pub class: CommandClass,
    pub recovery_target: Option<RecoveryTarget>,
    pub stdin: bool,
    pub file_input: bool,
    pub has_transfer: bool,
    pub config_dir: Option<PathBuf>,
}
#[derive(Clone)]
pub struct CommandPlan {
    pub(crate) cli: Cli,
}
impl CommandPlan {
    #[must_use]
    pub fn requirements(&self) -> CommandRequirements {
        let class = match &self.cli.command {
            Command::Bhpan(args) if args.command.confirmation().is_some() => {
                CommandClass::SchoolWrite
            }
            Command::Auth(_) => CommandClass::ExplicitAuth,
            Command::Agenda(crate::AgendaArgs {
                command: crate::AgendaCommand::Sync { .. },
            })
            | Command::Signin(SigninArgs {
                command: SigninCommand::Perform { .. },
            })
            | Command::Libbook(LibBookArgs {
                command: LibBookCommand::Reserve { .. } | LibBookCommand::Cancel { .. },
            })
            | Command::Bykc(BykcArgs {
                command:
                    BykcCommand::Select { .. } | BykcCommand::Deselect { .. } | BykcCommand::Sign { .. },
            })
            | Command::Cgyy(CgyyArgs {
                command: CgyyCommand::Submit { .. } | CgyyCommand::Cancel { .. },
            })
            | Command::Ygdk(YgdkArgs {
                command: YgdkCommand::Submit { .. },
            })
            | Command::Evaluation(EvaluationArgs {
                command: EvaluationCommand::SubmitPending { .. },
            }) => CommandClass::SchoolWrite,
            Command::Agenda(_) => CommandClass::Local,
            _ => CommandClass::Readonly,
        };
        let recovery_target = match self.cli.feature() {
            CliFeature::Bhpan => Some(RecoveryTarget::Bhpan),
            CliFeature::User => Some(RecoveryTarget::User),
            CliFeature::Portal => Some(RecoveryTarget::Portal),
            CliFeature::Network => Some(RecoveryTarget::Network),
            CliFeature::Finance => Some(RecoveryTarget::Finance),
            CliFeature::Ihome => Some(RecoveryTarget::Ihome),
            CliFeature::Schedule => Some(RecoveryTarget::Schedule),
            CliFeature::Exam => Some(RecoveryTarget::Exam),
            CliFeature::Grades => Some(RecoveryTarget::Grades),
            CliFeature::Classroom => Some(RecoveryTarget::Classroom),
            CliFeature::Spoc => Some(RecoveryTarget::Spoc),
            CliFeature::Judge => Some(RecoveryTarget::Judge),
            CliFeature::Signin => Some(RecoveryTarget::Signin),
            CliFeature::LibBook => Some(RecoveryTarget::LibBook),
            CliFeature::Bykc => Some(RecoveryTarget::Bykc),
            CliFeature::Cgyy => Some(RecoveryTarget::Cgyy),
            CliFeature::Ygdk => Some(RecoveryTarget::Ygdk),
            CliFeature::Evaluation => Some(RecoveryTarget::Evaluation),
            CliFeature::Cli | CliFeature::Auth | CliFeature::Agenda => None,
        };
        let stdin = matches!(
            &self.cli.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Login(_)
            }) | Command::Cgyy(CgyyArgs {
                command: CgyyCommand::Submit {
                    request_stdin: true,
                    confirm_write: true
                }
            })
        ) || matches!(&self.cli.command, Command::Bhpan(args) if args.command.password_stdin())
            || matches!(&self.cli.command, Command::Agenda(args) if crate::agenda::confirmed(&args.command) && crate::agenda::input_path(&args.command).is_some_and(|p| p==std::path::Path::new("-")));
        CommandRequirements {
            has_transfer: matches!(&self.cli.command,Command::Bhpan(args) if args.command.is_transfer()),
            class,
            recovery_target,
            stdin,
            file_input: matches!(
                &self.cli.command,
                Command::Ygdk(YgdkArgs {
                    command: YgdkCommand::Submit { .. }
                })
            ),
            config_dir: self.cli.config_dir.clone(),
        }
    }
    /// 在读取密码前核对指定资料路径，不创建目录或读取账号材料。
    /// # Errors
    /// 指定路径及其既有父路径不可用时返回本机启动错误。
    pub fn validate_configuration(&self) -> ubaa_core::facade::Result<()> {
        let Some(mut path) = self.cli.config_dir.as_deref() else {
            return Ok(());
        };
        loop {
            if path.as_os_str().is_empty() {
                return Ok(());
            }
            match std::fs::metadata(path) {
                Ok(value) if value.is_dir() => return Ok(()),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    if let Some(parent) = path.parent() {
                        path = parent;
                        continue;
                    }
                }
                _ => {}
            }
            return Err(UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "本机资料目录不可用",
            ));
        }
    }
    /// 核对不依赖账号或网络的参数，避免为无效命令读取密码和本机材料。
    /// # Errors
    /// 登录输入方式或写入确认不完整时返回参数错误。
    pub fn validate_local_arguments(&self) -> ubaa_core::facade::Result<()> {
        if let Command::Bhpan(args) = &self.cli.command {
            args.command.validate()?;
        }
        if let Command::Agenda(args) = &self.cli.command {
            crate::agenda::validate_arguments(&args.command)
                .map_err(|error| crate::io::input::invalid_input(error.message()))?;
        }
        if !self.school_write_confirmed() {
            return Err(crate::io::input::invalid_input(
                "学校写入需要 --confirm-write",
            ));
        }
        if let Command::Auth(AuthArgs {
            command: AuthCommand::Login(args),
        }) = &self.cli.command
        {
            crate::execute::aggregate::validate_login_arguments(self.cli.json, args)?;
        }
        if let Command::Cgyy(CgyyArgs {
            command:
                CgyyCommand::Submit {
                    request_stdin: false,
                    ..
                },
        }) = self.cli.command
        {
            return Err(crate::io::input::invalid_input(
                "研讨室预约需要 --request-stdin",
            ));
        }
        Ok(())
    }
    pub(crate) fn school_write_confirmed(&self) -> bool {
        match &self.cli.command {
            Command::Agenda(crate::AgendaArgs {
                command:
                    crate::AgendaCommand::Sync {
                        pull,
                        confirm_write,
                        ..
                    },
            }) => *pull || *confirm_write,
            Command::Bhpan(args) => args.command.confirmation().unwrap_or(true),
            Command::Signin(SigninArgs {
                command: SigninCommand::Perform { confirm_write, .. },
            })
            | Command::Libbook(LibBookArgs {
                command:
                    LibBookCommand::Reserve { confirm_write, .. }
                    | LibBookCommand::Cancel { confirm_write, .. },
            })
            | Command::Bykc(BykcArgs {
                command:
                    BykcCommand::Select { confirm_write, .. }
                    | BykcCommand::Deselect { confirm_write, .. }
                    | BykcCommand::Sign { confirm_write, .. },
            })
            | Command::Cgyy(CgyyArgs {
                command:
                    CgyyCommand::Submit { confirm_write, .. }
                    | CgyyCommand::Cancel { confirm_write, .. },
            })
            | Command::Ygdk(YgdkArgs {
                command: YgdkCommand::Submit { confirm_write, .. },
            })
            | Command::Evaluation(EvaluationArgs {
                command: EvaluationCommand::SubmitPending { confirm_write, .. },
            }) => *confirm_write,
            _ => true,
        }
    }
    #[must_use]
    pub fn cli(&self) -> &Cli {
        &self.cli
    }
    #[must_use]
    pub fn into_cli(self) -> Cli {
        self.cli
    }
}
impl From<Cli> for CommandPlan {
    fn from(cli: Cli) -> Self {
        Self { cli }
    }
}
/// help、version 和参数失败均可在材料初始化前交付。
#[derive(Debug)]
pub struct ParseFailure {
    error: clap::Error,
    json: bool,
}
impl ParseFailure {
    pub fn render(self, stdout: &mut impl Write, stderr: &mut impl Write) -> i32 {
        let code = self.error.exit_code();
        if code != 0 && self.json {
            return render_startup_error(
                true,
                CliFeature::Cli,
                UbaaError::new(
                    ErrorCode::InvalidInput,
                    ErrorKind::Input,
                    false,
                    "命令行参数无效",
                ),
                stdout,
                stderr,
            );
        }
        let text = self.error.to_string();
        let result = if self.error.use_stderr() {
            stderr.write_all(text.as_bytes())
        } else {
            stdout.write_all(text.as_bytes())
        };
        if result.is_err() {
            return 7;
        }
        super::finish_output(code, stdout, stderr)
    }
}
/// argv 包含 `argv[0]`，使用与旧二进制相同的唯一 clap 命令树。
/// # Errors
/// 返回可渲染的 help/version 或参数错误。
pub fn parse<I, T>(argv: I) -> Result<CommandPlan, ParseFailure>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString> + Clone,
{
    let argv: Vec<OsString> = argv.into_iter().map(Into::into).collect();
    let json = argv.iter().any(|s| s == "--json");
    Cli::try_parse_from(argv)
        .and_then(|cli| {
            if cli.json
                && matches!(
                    cli.command,
                    Command::Agenda(crate::AgendaArgs {
                        command: crate::AgendaCommand::Export { stdout: true, .. }
                    })
                )
            {
                Err(clap::Error::raw(
                    clap::error::ErrorKind::ArgumentConflict,
                    "--stdout 不能与 --json 同时使用",
                ))
            } else {
                Ok(cli)
            }
        })
        .map(CommandPlan::from)
        .map_err(|error| ParseFailure { error, json })
}

#[cfg(test)]
mod agenda_delivery_tests {
    use super::parse;
    #[test]
    fn 日程本地修改与导出由统一命令树解析() {
        for arguments in [
            vec!["create", "--input", "-", "--confirm-local-write"],
            vec!["clear", "--expected-unsynced", "0", "--confirm-local-write"],
            vec![
                "export",
                "--from",
                "2026-11-01",
                "--to",
                "2026-11-02",
                "--stdout",
            ],
        ] {
            let mut argv = vec!["ubaa", "agenda"];
            argv.extend(arguments);
            assert!(parse(argv.clone()).is_ok(), "命令应可用：{argv:?}");
        }
    }
    #[test]
    fn stdout导出与_json在材料初始化前拒绝() {
        assert!(
            parse([
                "ubaa",
                "--json",
                "agenda",
                "export",
                "--from",
                "2026-12-01",
                "--to",
                "2026-12-02",
                "--stdout"
            ])
            .is_err()
        );
    }
    #[test]
    fn 未确认学校写入在准备阶段拒绝且不读取输入() {
        let plan = parse(["ubaa", "bykc", "select", "--course-id", "42"]).unwrap();
        let mut input = std::io::Cursor::new("不得读取".as_bytes());
        let error = crate::prepare_input(plan, &mut input, &crate::CommandControl::default())
            .err()
            .expect("准备阶段应拒绝缺少确认的写操作");
        assert_eq!(error.code, ubaa_core::facade::ErrorCode::InvalidInput);
        assert_eq!(input.position(), 0);
    }
}
