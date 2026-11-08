//! 课表、考试、成绩与空闲教室命令参数。

use clap::{Args, Subcommand};

/// 课表命令组。
#[derive(Clone, Debug, Args)]
pub struct ScheduleArgs {
    #[command(subcommand)]
    pub command: ScheduleCommand,
}

/// 课表操作。
#[derive(Clone, Debug, Subcommand)]
pub enum ScheduleCommand {
    /// 列出学期。
    Terms,
    /// 列出教学周。
    Weeks {
        #[arg(long)]
        term: String,
    },
    /// 查询指定教学周。
    Current {
        #[arg(long)]
        term: String,
        #[arg(long)]
        week: i32,
    },
    /// 查询今日课程。
    Today,
}

/// 考试命令组。
#[derive(Clone, Debug, Args)]
pub struct ExamArgs {
    #[command(subcommand)]
    pub command: ExamCommand,
}

/// 考试操作。
#[derive(Clone, Debug, Subcommand)]
pub enum ExamCommand {
    /// 列出考试系统学期。
    Terms,
    /// 列出指定学期的考试。
    List {
        #[arg(long)]
        term: String,
    },
}

/// 成绩命令组。
#[derive(Clone, Debug, Args)]
pub struct GradesArgs {
    #[command(subcommand)]
    pub command: GradesCommand,
}

/// 成绩操作。
#[derive(Clone, Debug, Subcommand)]
pub enum GradesCommand {
    /// 读取研究生完整历史成绩及统计。
    Overview,
    /// 列出指定学期的成绩。
    List {
        #[arg(long)]
        term: String,
    },
}

/// 空闲教室命令组。
#[derive(Clone, Debug, Args)]
pub struct ClassroomArgs {
    #[command(subcommand)]
    pub command: ClassroomCommand,
}

/// 空闲教室操作。
#[derive(Clone, Debug, Subcommand)]
pub enum ClassroomCommand {
    /// 查询空闲教室。
    Search {
        #[arg(long)]
        campus: i32,
        #[arg(long)]
        date: String,
    },
}
