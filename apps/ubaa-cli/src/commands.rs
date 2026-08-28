use std::path::PathBuf;

use clap::{Parser, Subcommand};

use super::{
    AuthArgs, BykcArgs, CgyyArgs, ClassroomArgs, EvaluationArgs, ExamArgs, GradesArgs, JudgeArgs,
    LibBookArgs, ScheduleArgs, SigninArgs, SpocArgs, UserArgs, YgdkArgs,
};

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
