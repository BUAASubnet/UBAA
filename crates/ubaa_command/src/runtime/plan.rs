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
    User,
    Portal,
    Network,
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
            Command::Agenda(_) => CommandClass::Local,
            Command::Auth(_) => CommandClass::ExplicitAuth,
            Command::Signin(SigninArgs {
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
            _ => CommandClass::Readonly,
        };
        let recovery_target = match self.cli.feature() {
            CliFeature::User => Some(RecoveryTarget::User),
            CliFeature::Portal => Some(RecoveryTarget::Portal),
            CliFeature::Network => Some(RecoveryTarget::Network),
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
        );
        CommandRequirements {
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
/// argv 包含 argv[0]，使用与旧二进制相同的唯一 clap 命令树。
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
        .map(CommandPlan::from)
        .map_err(|error| ParseFailure { error, json })
}
