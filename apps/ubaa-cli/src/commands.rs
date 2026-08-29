use std::path::PathBuf;

use clap::{Parser, Subcommand};

use super::execution::command_feature;
use super::{
    AuthArgs, BykcArgs, CgyyArgs, ClassroomArgs, EvaluationArgs, ExamArgs, GradesArgs, JudgeArgs,
    LibBookArgs, ScheduleArgs, SigninArgs, SpocArgs, UserArgs, YgdkArgs,
};
use super::{AuthCommand, CliFeature, ConnectionMode, UserCommand};

/// UBAA 命令行接口。
#[derive(Debug, Parser)]
#[command(name = "ubaa", version, about = "北航统一认证命令行客户端")]
pub struct Cli {
    /// 在标准输出中生成带版本号的 JSON 信封。
    #[arg(long, global = true)]
    pub json: bool,

    /// 将会话状态存储在此目录中。
    #[arg(long, global = true, value_name = "DIR")]
    pub config_dir: Option<PathBuf>,

    /// 禁用终端颜色。
    #[arg(long, global = true)]
    pub no_color: bool,

    /// 要执行的命令。
    #[command(subcommand)]
    pub command: Command,
}

/// 顶层命令组。
#[derive(Debug, Subcommand)]
pub enum Command {
    /// 认证并管理持久化会话。
    Auth(AuthArgs),
    /// 查询已认证的用户中心资料。
    User(UserArgs),
    /// 课表只读操作。
    Schedule(ScheduleArgs),
    /// 考试只读操作。
    Exam(ExamArgs),
    /// 成绩只读操作。
    Grades(GradesArgs),
    /// 空闲教室只读操作。
    Classroom(ClassroomArgs),
    /// SPOC 只读操作。
    Spoc(SpocArgs),
    /// 希冀作业只读操作。
    Judge(JudgeArgs),
    /// 课堂签到只读操作。
    Signin(SigninArgs),
    /// 图书馆座位只读操作。
    Libbook(LibBookArgs),
    /// 阳光打卡只读操作。
    Ygdk(YgdkArgs),
    /// 博雅课程只读操作。
    Bykc(BykcArgs),
    /// 场馆预约只读操作。
    Cgyy(CgyyArgs),
    /// 教学评教只读操作。
    Evaluation(EvaluationArgs),
}

impl Cli {
    /// 当前命令是否为认证登录命令。
    #[must_use]
    pub const fn is_login(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Login(_)
            })
        )
    }

    /// 当前命令为认证登录命令时，返回显式登录模式。
    #[must_use]
    pub fn login_mode(&self) -> Option<ConnectionMode> {
        match &self.command {
            Command::Auth(AuthArgs {
                command: AuthCommand::Login(arguments),
            }) => arguments.mode.map(Into::into),
            _ => None,
        }
    }

    /// 构造客户端前，当前命令是否要求已有会话。
    #[must_use]
    pub const fn requires_session(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Status
            }) | Command::User(UserArgs {
                command: UserCommand::Show
            }) | Command::Schedule(_)
                | Command::Exam(_)
                | Command::Grades(_)
                | Command::Classroom(_)
                | Command::Spoc(_)
                | Command::Judge(_)
                | Command::Signin(_)
                | Command::Libbook(_)
                | Command::Bykc(_)
                | Command::Cgyy(_)
                | Command::Ygdk(_)
                | Command::Evaluation(_)
        )
    }

    /// 当前命令是否为退出命令。
    #[must_use]
    pub const fn is_logout(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Logout
            })
        )
    }

    /// 当前命令是否为普通的聚合认证状态命令。
    #[must_use]
    pub const fn is_auth_status(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Status
            })
        )
    }

    /// 返回与当前命令关联的稳定 JSON 功能标识。
    #[must_use]
    pub const fn feature(&self) -> CliFeature {
        command_feature(&self.command)
    }
}
