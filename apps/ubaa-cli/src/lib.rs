//! UBAA Core 的命令行解析与输出展示。

use std::io::{BufRead, Write};
use std::path::PathBuf;

use async_trait::async_trait;
use clap::{Args, Parser, Subcommand, ValueEnum};
use serde::Serialize;
use serde_json::{Value, json};
use ubaa_core::connection::{NetworkState, RouteDiagnostic, RouteResolution};
use ubaa_core::domain::{
    AuthStatus, BykcChosenCourse, BykcCourse, BykcCoursePage, BykcStatistics, BykcUserProfile,
    CgyyDayInfo, CgyyOrder, CgyyOrdersPage, CgyyPurposeType, CgyyVenueSite, ClassroomQuery,
    ConnectionMode, DualLoginInput, ExamArrangement, FeatureResult, GradeData,
    JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary, JudgeAssignmentsDiagnostics,
    LibBookArea, LibBookAreaDetail, LibBookBookingsPage, LibBookLibrary, LibBookSeat, LoginInput,
    LoginReadiness, RoutePolicy, SafeError, SecretValue, SigninClass, SpocAssignmentDetail,
    SpocAssignments, SpocAssignmentsDiagnostics, Term, TodayClass, UserProfile, Week,
    WeeklySchedule, YgdkOverview, YgdkRecordsPage,
};
use ubaa_core::error::{ErrorCode, ErrorKind, ExitCode, Result, UbaaError};
use ubaa_core::facade::{RouteClient, Routed, RoutedError, RoutedResult, UbaaClient};
use ubaa_core::output::{
    AggregateJsonEnvelope, CliFeature, CliJsonError, ResolvedRoutedJsonMeta, RoutedJsonEnvelope,
    UnresolvedRoutedJsonMeta,
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

/// Core 门面完成路由解析后返回的安全路由决策上下文。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ReadonlyRouteContext {
    /// 当前功能实际使用的路由策略。
    pub policy: RoutePolicy,
    /// 决策所用的网关可达状态；未探测时为未知。
    pub network: NetworkState,
    /// 回退前选择的路由。
    pub initial_route: ConnectionMode,
    /// 回退后选择的路由。
    pub resolved_route: ConnectionMode,
    /// 是否发生了就绪路由回退。
    pub used_fallback: bool,
}

impl ReadonlyRouteContext {
    fn explicit(mode: ConnectionMode) -> Self {
        Self {
            policy: match mode {
                ConnectionMode::Direct => RoutePolicy::Direct,
                ConnectionMode::WebVpn => RoutePolicy::WebVpn,
            },
            network: NetworkState::Unknown,
            initial_route: mode,
            resolved_route: mode,
            used_fallback: false,
        }
    }

    fn meta(self, feature: CliFeature, resolved_route: ConnectionMode) -> ResolvedRoutedJsonMeta {
        ResolvedRoutedJsonMeta::from_resolution(feature, self.resolution(resolved_route))
    }

    fn resolution(self, resolved_route: ConnectionMode) -> RouteResolution {
        RouteResolution {
            mode: resolved_route,
            policy: self.policy,
            diagnostic: RouteDiagnostic {
                network: self.network,
                initial_route: self.initial_route,
                mode: resolved_route,
                used_fallback: self.used_fallback,
            },
        }
    }
}

impl From<RouteResolution> for ReadonlyRouteContext {
    fn from(resolution: RouteResolution) -> Self {
        Self {
            policy: resolution.policy,
            network: resolution.diagnostic.network,
            initial_route: resolution.diagnostic.initial_route,
            resolved_route: resolution.mode,
            used_fallback: resolution.diagnostic.used_fallback,
        }
    }
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
}

/// 场馆预约命令组。
#[derive(Debug, Args)]
pub struct CgyyArgs {
    #[command(subcommand)]
    pub command: CgyyCommand,
}

/// 场馆预约只读操作。
#[derive(Debug, Subcommand)]
pub enum CgyyCommand {
    /// 查询场馆站点。
    Sites,
    /// 查询预约用途。
    Purposes,
    /// 查询指定站点日期的时段与空间状态。
    Day {
        /// 场馆站点编号。
        #[arg(long)]
        site_id: i32,
        /// 日期，格式为 yyyy-MM-dd。
        #[arg(long)]
        date: String,
    },
    /// 查询当前用户订单。
    Orders {
        /// 页码，从 0 开始。
        #[arg(long, default_value_t = 0)]
        page: i32,
        /// 每页数量。
        #[arg(long, default_value_t = 10)]
        size: i32,
    },
    /// 查询订单详情。
    Detail {
        /// 订单编号。
        #[arg(long)]
        id: i32,
    },
}

/// 博雅课程命令组。
#[derive(Debug, Args)]
pub struct BykcArgs {
    #[command(subcommand)]
    pub command: BykcCommand,
}

/// 博雅课程只读操作。
#[derive(Debug, Subcommand)]
pub enum BykcCommand {
    /// 查询用户资料。
    Profile,
    /// 查询课程分页。
    Courses {
        /// 页码，从 1 开始。
        #[arg(long, default_value_t = 1)]
        page: i32,
        /// 每页数量。
        #[arg(long, default_value_t = 20)]
        size: i32,
    },
    /// 查询课程详情。
    Course {
        /// 课程编号。
        #[arg(long)]
        id: i64,
    },
    /// 查询已选课程。
    Chosen {
        /// 学期开始时间。
        #[arg(long)]
        start: String,
        /// 学期结束时间。
        #[arg(long)]
        end: String,
    },
    /// 查询修读统计。
    Statistics,
}

/// 图书馆座位命令组。
#[derive(Debug, Args)]
pub struct LibBookArgs {
    #[command(subcommand)]
    pub command: LibBookCommand,
}

/// 图书馆座位只读操作。
#[derive(Debug, Subcommand)]
pub enum LibBookCommand {
    /// 查询楼馆及楼层列表。
    Libraries {
        /// 查询日期，格式为 yyyy-MM-dd。
        #[arg(long)]
        day: String,
    },
    /// 查询图书馆分区列表。
    Areas {
        /// 楼馆编号。
        #[arg(long)]
        premises_id: String,
        /// 楼层编号。
        #[arg(long)]
        storey_id: Option<String>,
        /// 查询日期，格式为 yyyy-MM-dd。
        #[arg(long)]
        day: String,
    },
    /// 查询分区详情及可用时段。
    AreaDetail {
        /// 分区编号。
        #[arg(long)]
        area_id: String,
    },
    /// 查询指定时段的座位状态。
    Seats {
        /// 分区编号。
        #[arg(long)]
        area_id: String,
        /// 查询日期，格式为 yyyy-MM-dd。
        #[arg(long)]
        day: String,
        /// 开始时间，格式为 HH:mm。
        #[arg(long)]
        start_time: String,
        /// 结束时间，格式为 HH:mm。
        #[arg(long)]
        end_time: String,
    },
    /// 查询当前用户的预约记录。
    Bookings {
        /// 页码，从 1 开始。
        #[arg(long, default_value_t = 1)]
        page: i32,
        /// 每页记录数。
        #[arg(long, default_value_t = 20)]
        limit: i32,
    },
}

/// 阳光打卡命令组。
#[derive(Debug, Args)]
pub struct YgdkArgs {
    #[command(subcommand)]
    pub command: YgdkCommand,
}

/// 阳光打卡只读操作。
#[derive(Debug, Subcommand)]
pub enum YgdkCommand {
    /// 查询阳光打卡概览。
    Overview,
    /// 查询阳光打卡记录。
    Records {
        #[arg(long, default_value_t = 1)]
        page: i32,
        #[arg(long, default_value_t = 20)]
        size: i32,
    },
}

/// 课堂签到命令组。
#[derive(Debug, Args)]
pub struct SigninArgs {
    /// 签到查询操作。
    #[command(subcommand)]
    pub command: SigninCommand,
}

/// 课堂签到只读操作。
#[derive(Debug, Subcommand)]
pub enum SigninCommand {
    /// 列出今日课程及其签到状态。
    Today,
}

/// 认证命令组。
#[derive(Debug, Args)]
pub struct AuthArgs {
    /// 认证操作。
    #[command(subcommand)]
    pub command: AuthCommand,
}

/// 认证操作。
#[derive(Debug, Subcommand)]
pub enum AuthCommand {
    /// 通过 SSO 登录并持久化会话。
    Login(LoginArgs),
    /// 通过用户中心验证已持久化的会话。
    Status,
    /// 尽可能远程退出，并始终清理本地状态。
    Logout,
}

/// 用户中心命令组。
#[derive(Debug, Args)]
pub struct UserArgs {
    /// 用户中心操作。
    #[command(subcommand)]
    pub command: UserCommand,
}

/// 用户中心操作。
#[derive(Debug, Subcommand)]
pub enum UserCommand {
    /// 显示已认证的用户中心资料。
    Show,
}

/// 登录参数。
#[derive(Args)]
pub struct LoginArgs {
    /// 每个请求使用的网络路由；省略时复用已保存的模式。
    #[arg(long, value_enum, hide = true)]
    pub mode: Option<CliConnectionMode>,

    /// SSO 用户名；人类可读模式下省略时会交互询问。
    #[arg(long)]
    pub username: Option<String>,

    /// 从标准输入读取一行用户名（供隐藏的验证与自动化流程使用）。
    #[arg(long, hide = true)]
    pub username_stdin: bool,

    /// 从标准输入读取一行密码。
    #[arg(long)]
    pub password_stdin: bool,
}

/// 课表操作。
#[derive(Debug, Args)]
pub struct ScheduleArgs {
    /// 课表操作。
    #[command(subcommand)]
    pub command: ScheduleCommand,
}

/// 课表子命令。
#[derive(Debug, Subcommand)]
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

/// 考试操作。
#[derive(Debug, Args)]
pub struct ExamArgs {
    /// 考试操作。
    #[command(subcommand)]
    pub command: ExamCommand,
}

/// 考试子命令。
#[derive(Debug, Subcommand)]
pub enum ExamCommand {
    /// 列出指定学期的考试。
    List {
        #[arg(long)]
        term: String,
    },
}

/// 成绩操作。
#[derive(Debug, Args)]
pub struct GradesArgs {
    /// 成绩操作。
    #[command(subcommand)]
    pub command: GradesCommand,
}

/// 成绩子命令。
#[derive(Debug, Subcommand)]
pub enum GradesCommand {
    /// 列出指定学期的成绩。
    List {
        #[arg(long)]
        term: String,
    },
}

/// 空闲教室操作。
#[derive(Debug, Args)]
pub struct ClassroomArgs {
    /// 空闲教室操作。
    #[command(subcommand)]
    pub command: ClassroomCommand,
}

/// 空闲教室子命令。
#[derive(Debug, Subcommand)]
pub enum ClassroomCommand {
    /// 查询空闲教室。
    Search {
        #[arg(long)]
        campus: i32,
        #[arg(long)]
        date: String,
    },
}

/// SPOC 操作。
#[derive(Debug, Args)]
pub struct SpocArgs {
    /// SPOC 操作。
    #[command(subcommand)]
    pub command: SpocCommand,
}

/// SPOC 子命令。
#[derive(Debug, Subcommand)]
pub enum SpocCommand {
    /// 列出作业。
    Assignments,
    /// 输出用于实时验证的安全全局分页证据。
    #[command(hide = true)]
    Diagnostics,
    /// 显示一项作业。
    Assignment {
        #[command(subcommand)]
        command: SpocAssignmentCommand,
    },
}

/// SPOC 作业子命令。
#[derive(Debug, Subcommand)]
pub enum SpocAssignmentCommand {
    /// 显示作业详情。
    Show {
        #[arg(long)]
        id: String,
    },
}

/// 希冀作业操作。
#[derive(Debug, Args)]
pub struct JudgeArgs {
    /// 希冀作业操作。
    #[command(subcommand)]
    pub command: JudgeCommand,
}

/// 希冀作业子命令。
#[derive(Debug, Subcommand)]
pub enum JudgeCommand {
    /// 列出作业。
    Assignments {
        #[arg(long)]
        include_expired: bool,
    },
    /// 输出用于实时验证的安全列表解析计数。
    #[command(hide = true)]
    Diagnostics {
        #[arg(long)]
        include_expired: bool,
    },
    /// 作业操作。
    Assignment {
        #[command(subcommand)]
        command: JudgeAssignmentCommand,
    },
}

/// 希冀作业子命令。
#[derive(Debug, Subcommand)]
pub enum JudgeAssignmentCommand {
    /// 显示一项详情。
    Show {
        #[arg(long)]
        course_id: String,
        #[arg(long)]
        id: String,
    },
    /// 显示多项详情。
    Details {
        #[arg(long = "key")]
        keys: Vec<String>,
    },
}

impl std::fmt::Debug for LoginArgs {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LoginArgs")
            .field("mode", &self.mode)
            .field("username", &self.username.as_ref().map(|_| "[REDACTED]"))
            .field("username_stdin", &self.username_stdin)
            .field("password_stdin", &self.password_stdin)
            .finish()
    }
}

/// CLI 中的连接模式写法。
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum CliConnectionMode {
    /// 直接访问北航服务。
    Direct,
    /// 通过 `WebVPN` 访问北航服务。
    Webvpn,
}

impl From<CliConnectionMode> for ConnectionMode {
    fn from(value: CliConnectionMode) -> Self {
        match value {
            CliConnectionMode::Direct => Self::Direct,
            CliConnectionMode::Webvpn => Self::WebVpn,
        }
    }
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

/// 命令执行所需的认证门面。
#[async_trait]
pub trait CliBackend {
    /// 当前后端固定使用的连接模式。
    fn mode(&self) -> ConnectionMode;
    /// 提交凭据并返回已认证的用户资料。
    async fn login(&mut self, input: LoginInput) -> Result<UserProfile>;
    /// 验证活动会话。
    async fn auth_status(&mut self) -> Result<AuthStatus>;
    /// 获取用户中心资料。
    async fn get_user_info(&mut self) -> Result<UserProfile>;
    /// 退出并清理本地状态。
    async fn logout(&mut self) -> Result<()>;

    /// 查询今日签到课程。
    async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        Err(internal_error("签到功能不可用"))
    }
    /// 查询图书馆楼馆列表。
    async fn libbook_libraries(
        &mut self,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询图书馆分区列表。
    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询图书馆分区详情。
    async fn libbook_area_detail(
        &mut self,
        _area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询图书馆座位状态。
    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询当前用户的图书馆预约记录。
    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        Err(internal_error("图书馆功能不可用"))
    }
    /// 查询博雅用户资料。
    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 分页查询博雅课程。
    async fn bykc_courses(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询博雅课程详情。
    async fn bykc_course_detail(&mut self, _id: i64) -> Result<FeatureResult<BykcCourse>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询博雅已选课程。
    async fn bykc_chosen_courses(
        &mut self,
        _start: &str,
        _end: &str,
    ) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询博雅修读统计。
    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        Err(internal_error("博雅功能不可用"))
    }
    /// 查询场馆站点。
    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询预约用途。
    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询日期预约信息。
    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询当前用户订单。
    async fn cgyy_orders(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<CgyyOrdersPage>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    /// 查询订单详情。
    async fn cgyy_order_detail(&mut self, _id: i32) -> Result<FeatureResult<CgyyOrder>> {
        Err(internal_error("场馆预约功能不可用"))
    }
    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        Err(internal_error("阳光打卡不可用"))
    }
    async fn ygdk_records(
        &mut self,
        _page: i32,
        _size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        Err(internal_error("阳光打卡不可用"))
    }

    /// 查询学期。
    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询教学周。
    async fn schedule_weeks(&mut self, _term: &str) -> Result<FeatureResult<Vec<Week>>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询指定教学周。
    async fn schedule_week(
        &mut self,
        _term: &str,
        _week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询今日课程。
    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        Err(internal_error("课表功能不可用"))
    }
    /// 查询考试。
    async fn exam_arrangement(&mut self, _term: &str) -> Result<FeatureResult<ExamArrangement>> {
        Err(internal_error("考试功能不可用"))
    }
    /// 查询成绩。
    async fn grades(&mut self, _term: &str) -> Result<FeatureResult<GradeData>> {
        Err(internal_error("成绩功能不可用"))
    }
    /// 查询空闲教室。
    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        Err(internal_error("空教室功能不可用"))
    }
    /// 查询 SPOC 作业。
    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        Err(internal_error("SPOC 功能不可用"))
    }
    /// 查询安全的 SPOC 全局分页诊断。
    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        Err(internal_error("SPOC 诊断功能不可用"))
    }
    /// 查询 SPOC 作业详情。
    async fn spoc_assignment(&mut self, _id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        Err(internal_error("SPOC 功能不可用"))
    }
    /// 查询希冀作业。
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        Err(internal_error("希冀功能不可用"))
    }
    /// 查询安全的希冀解析诊断。
    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        Err(internal_error("希冀诊断功能不可用"))
    }
    /// 查询希冀作业详情。
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        Err(internal_error("希冀功能不可用"))
    }
    /// 批量查询希冀作业详情。
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        Err(internal_error("希冀功能不可用"))
    }
}

/// 普通用户命令和只读命令所需的聚合 Core 门面。
///
/// Core 会把每个已完成的路由决策与操作结果一起返回。CLI 仅展示该决策，
/// 不自行选择或修复路由。
#[async_trait]
pub trait RoutedCliBackend {
    /// 查询今日课堂签到状态。
    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        Err(routed_unavailable("签到功能不可用"))
    }
    /// 通过 Core 路由查询图书馆楼馆列表。
    async fn libbook_libraries(&mut self, _day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆分区列表。
    async fn libbook_areas(
        &mut self,
        _premises_id: &str,
        _storey_id: Option<&str>,
        _day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆分区详情。
    async fn libbook_area_detail(&mut self, _area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆座位状态。
    async fn libbook_seats(
        &mut self,
        _area_id: &str,
        _day: &str,
        _start_time: &str,
        _end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询图书馆预约记录。
    async fn libbook_bookings(
        &mut self,
        _page: i32,
        _limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        Err(routed_unavailable("图书馆功能不可用"))
    }
    /// 通过 Core 路由查询博雅用户资料。
    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由分页查询博雅课程。
    async fn bykc_courses(&mut self, _page: i32, _size: i32) -> RoutedResult<BykcCoursePage> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询博雅课程详情。
    async fn bykc_course_detail(&mut self, _id: i64) -> RoutedResult<BykcCourse> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询博雅已选课程。
    async fn bykc_chosen_courses(
        &mut self,
        _start: &str,
        _end: &str,
    ) -> RoutedResult<Vec<BykcChosenCourse>> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询博雅修读统计。
    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        Err(routed_unavailable("博雅功能不可用"))
    }
    /// 通过 Core 路由查询场馆站点。
    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询预约用途。
    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询日期预约信息。
    async fn cgyy_day(&mut self, _site_id: i32, _date: &str) -> RoutedResult<CgyyDayInfo> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询当前用户订单。
    async fn cgyy_orders(&mut self, _page: i32, _size: i32) -> RoutedResult<CgyyOrdersPage> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    /// 通过 Core 路由查询订单详情。
    async fn cgyy_order_detail(&mut self, _id: i32) -> RoutedResult<CgyyOrder> {
        Err(routed_unavailable("场馆预约功能不可用"))
    }
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        Err(routed_unavailable("阳光打卡不可用"))
    }
    async fn ygdk_records(&mut self, _page: i32, _size: i32) -> RoutedResult<YgdkRecordsPage> {
        Err(routed_unavailable("阳光打卡不可用"))
    }
    /// 通过 Core 路由获取用户中心资料。
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        Err(routed_unavailable("用户资料功能不可用"))
    }
    /// 通过 Core 路由查询学期。
    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询教学周。
    async fn schedule_weeks(&mut self, _term: &str) -> RoutedResult<Vec<Week>> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询指定教学周。
    async fn schedule_week(&mut self, _term: &str, _week: i32) -> RoutedResult<WeeklySchedule> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询今日课程。
    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        Err(routed_unavailable("课表功能不可用"))
    }
    /// 通过 Core 路由查询考试。
    async fn exam_arrangement(&mut self, _term: &str) -> RoutedResult<ExamArrangement> {
        Err(routed_unavailable("考试功能不可用"))
    }
    /// 通过 Core 路由查询成绩。
    async fn grades(&mut self, _term: &str) -> RoutedResult<GradeData> {
        Err(routed_unavailable("成绩功能不可用"))
    }
    /// 通过 Core 路由查询空闲教室。
    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> RoutedResult<ClassroomQuery> {
        Err(routed_unavailable("空教室功能不可用"))
    }
    /// 通过 Core 路由查询 SPOC 作业。
    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        Err(routed_unavailable("SPOC 功能不可用"))
    }
    /// 通过 Core 路由查询安全的 SPOC 全局分页诊断。
    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        Err(routed_unavailable("SPOC 诊断功能不可用"))
    }
    /// 通过 Core 路由查询一项 SPOC 作业。
    async fn spoc_assignment(&mut self, _id: &str) -> RoutedResult<SpocAssignmentDetail> {
        Err(routed_unavailable("SPOC 功能不可用"))
    }
    /// 通过 Core 路由查询希冀作业。
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        Err(routed_unavailable("希冀功能不可用"))
    }
    /// 通过 Core 路由查询安全的希冀解析诊断。
    async fn judge_assignments_diagnostics(
        &mut self,
        _include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        Err(routed_unavailable("希冀诊断功能不可用"))
    }
    /// 通过 Core 路由查询一项希冀作业。
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        Err(routed_unavailable("希冀功能不可用"))
    }
    /// 通过一次 Core 路由决策查询多项希冀作业详情。
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        Err(routed_unavailable("希冀功能不可用"))
    }
}

/// 通过双路门面执行普通聚合登录流程。
pub async fn run_dual_login<R, O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    input: &mut R,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    R: BufRead,
    O: Write,
    E: Write,
{
    let json_mode = cli.json;
    let route_policy = backend.default_route_policy();
    let Command::Auth(AuthArgs {
        command: AuthCommand::Login(arguments),
    }) = cli.command
    else {
        return render_aggregate_input_error(
            json_mode,
            invalid_input("聚合登录必须先执行 auth login"),
            stdout,
            stderr,
        );
    };
    let (username, password) = match read_dual_credentials(json_mode, &arguments, input, stderr) {
        Ok(credentials) => credentials,
        Err(error) => {
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
        }
    };
    let mut outcome = match backend
        .login(DualLoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
    {
        Ok(outcome) => outcome,
        Err(error) => {
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
        }
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(json_mode, outcome, route_policy, stdout, stderr)
}

/// 执行普通聚合认证状态流程。
pub async fn run_dual_status<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let route_policy = backend.default_route_policy();
    let mut outcome = match backend.auth_status().await {
        Ok(outcome) => outcome,
        Err(error) => return render_aggregate_input_error(cli.json, error, stdout, stderr),
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(cli.json, outcome, route_policy, stdout, stderr)
}

/// 使用固定的聚合路由元数据退出两个路由槽位。
pub async fn run_dual_logout<O, E>(
    cli: Cli,
    backend: &mut UbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let route_policy = backend.default_route_policy();
    let result = backend.logout().await;
    match result {
        Ok(()) => {
            if cli.json {
                let envelope = AggregateJsonEnvelope::logout_success(route_policy);
                if write_json(stdout, &envelope).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if writeln!(stdout, "已退出登录。").is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_startup_error(cli.json, CliFeature::Auth, error, stdout, stderr),
    }
}

fn read_dual_credentials<R: BufRead, E: Write>(
    json_mode: bool,
    arguments: &LoginArgs,
    input: &mut R,
    stderr: &mut E,
) -> Result<(String, String)> {
    let username = if arguments.username_stdin {
        if arguments.username.is_some() {
            return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
        }
        let username = read_secret_line(input, "标准输入中缺少用户名")?;
        if username.trim().is_empty() {
            return Err(invalid_input("用户名不能为空"));
        }
        username
    } else {
        match arguments.username.as_deref() {
            Some(username) if !username.trim().is_empty() => username.to_owned(),
            Some(_) => return Err(invalid_input("用户名不能为空")),
            None if json_mode => return Err(invalid_input("JSON 模式必须提供 --username")),
            None => prompt_line(input, stderr, "用户名：")?,
        }
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "标准输入中缺少密码")?
    } else if json_mode {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    } else {
        rpassword::prompt_password("密码：").map_err(|_| internal_error("无法安全读取密码"))?
    };
    Ok((username, password))
}

fn render_dual_outcome<O: Write, E: Write>(
    json_mode: bool,
    outcome: ubaa_core::domain::LoginOutcome,
    route_policy: RoutePolicy,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let error = aggregate_error(&outcome);
    let exit_code = aggregate_exit_code(&outcome, error.as_ref());
    if json_mode {
        let envelope = match error {
            Some(error) => AggregateJsonEnvelope::auth_failure(outcome, error, route_policy),
            None => AggregateJsonEnvelope::auth_success(outcome, route_policy),
        };
        let envelope = match envelope {
            Ok(envelope) => envelope,
            Err(error) => {
                return render_startup_error(true, CliFeature::Auth, error, stdout, stderr);
            }
        };
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else {
        for route in &outcome.routes {
            let _ = writeln!(stdout, "{:?}: {:?}", route.route, route.state);
        }
        if outcome
            .profile
            .as_ref()
            .is_some_and(|profile| write_profile(stdout, profile).is_err())
        {
            return ExitCode::Internal as i32;
        }
        if let Some(error) = error {
            let _ = writeln!(stderr, "错误：{}", error.message);
        }
    }
    exit_code
}

fn aggregate_error(outcome: &ubaa_core::domain::LoginOutcome) -> Option<SafeError> {
    if outcome.readiness == LoginReadiness::NoneReady {
        Some(
            outcome
                .routes
                .iter()
                .find_map(|route| route.error.clone())
                .unwrap_or_else(|| SafeError {
                    code: "internal_error".into(),
                    kind: "internal".into(),
                    retryable: false,
                    message: "没有认证路线成功建立会话".into(),
                }),
        )
    } else {
        None
    }
}

fn aggregate_exit_code(
    outcome: &ubaa_core::domain::LoginOutcome,
    error: Option<&SafeError>,
) -> i32 {
    if outcome.readiness == LoginReadiness::NoneReady {
        error.map_or(ExitCode::Internal as i32, safe_error_exit_code)
    } else {
        ExitCode::Success as i32
    }
}

fn safe_error_exit_code(error: &SafeError) -> i32 {
    match error.code.as_str() {
        "invalid_input" => ExitCode::InvalidInput as i32,
        "authentication_required"
        | "invalid_credentials"
        | "password_risk_confirmation_failed"
        | "permission_denied" => ExitCode::Authentication as i32,
        "network_error" | "timeout" | "upstream_unavailable" => ExitCode::Network as i32,
        "upstream_changed" | "parse_error" => ExitCode::Upstream as i32,
        _ => ExitCode::Internal as i32,
    }
}

fn render_aggregate_input_error<O: Write, E: Write>(
    json_mode: bool,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    render_startup_error(json_mode, CliFeature::Auth, error, stdout, stderr)
}

#[async_trait]
impl CliBackend for RouteClient {
    fn mode(&self) -> ConnectionMode {
        self.mode()
    }

    async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        self.login(input).await
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        self.auth_status().await
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        self.get_user_info().await
    }

    async fn logout(&mut self) -> Result<()> {
        self.logout().await
    }

    async fn signin_today(&mut self) -> Result<FeatureResult<Vec<SigninClass>>> {
        self.signin_today().await
    }
    async fn libbook_libraries(&mut self, day: &str) -> Result<FeatureResult<Vec<LibBookLibrary>>> {
        self.libbook_libraries(day).await
    }
    async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> Result<FeatureResult<Vec<LibBookArea>>> {
        self.libbook_areas(premises_id, storey_id, day).await
    }
    async fn libbook_area_detail(
        &mut self,
        area_id: &str,
    ) -> Result<FeatureResult<LibBookAreaDetail>> {
        self.libbook_area_detail(area_id).await
    }
    async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> Result<FeatureResult<Vec<LibBookSeat>>> {
        self.libbook_seats(area_id, day, start_time, end_time).await
    }
    async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> Result<FeatureResult<LibBookBookingsPage>> {
        self.libbook_bookings(page, limit).await
    }
    async fn bykc_profile(&mut self) -> Result<FeatureResult<BykcUserProfile>> {
        self.bykc_profile().await
    }
    async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
    ) -> Result<FeatureResult<BykcCoursePage>> {
        self.bykc_courses(page, size).await
    }
    async fn bykc_course_detail(&mut self, id: i64) -> Result<FeatureResult<BykcCourse>> {
        self.bykc_course_detail(id).await
    }
    async fn bykc_chosen_courses(
        &mut self,
        start: &str,
        end: &str,
    ) -> Result<FeatureResult<Vec<BykcChosenCourse>>> {
        self.bykc_chosen_courses(start, end).await
    }
    async fn bykc_statistics(&mut self) -> Result<FeatureResult<BykcStatistics>> {
        self.bykc_statistics().await
    }
    async fn cgyy_sites(&mut self) -> Result<FeatureResult<Vec<CgyyVenueSite>>> {
        self.cgyy_sites().await
    }
    async fn cgyy_purposes(&mut self) -> Result<FeatureResult<Vec<CgyyPurposeType>>> {
        self.cgyy_purposes().await
    }
    async fn cgyy_day(&mut self, site_id: i32, date: &str) -> Result<FeatureResult<CgyyDayInfo>> {
        self.cgyy_day(site_id, date).await
    }
    async fn cgyy_orders(&mut self, page: i32, size: i32) -> Result<FeatureResult<CgyyOrdersPage>> {
        self.cgyy_orders(page, size).await
    }
    async fn cgyy_order_detail(&mut self, id: i32) -> Result<FeatureResult<CgyyOrder>> {
        self.cgyy_order_detail(id).await
    }
    async fn ygdk_overview(&mut self) -> Result<FeatureResult<YgdkOverview>> {
        self.ygdk_overview().await
    }
    async fn ygdk_records(
        &mut self,
        page: i32,
        size: i32,
    ) -> Result<FeatureResult<YgdkRecordsPage>> {
        self.ygdk_records(page, size).await
    }

    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        self.schedule_terms().await
    }
    async fn schedule_weeks(&mut self, term: &str) -> Result<FeatureResult<Vec<Week>>> {
        self.schedule_weeks(term).await
    }
    async fn schedule_week(
        &mut self,
        term: &str,
        week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        self.schedule_week(term, week).await
    }
    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        self.schedule_today().await
    }
    async fn exam_arrangement(&mut self, term: &str) -> Result<FeatureResult<ExamArrangement>> {
        self.exam_arrangement(term).await
    }
    async fn grades(&mut self, term: &str) -> Result<FeatureResult<GradeData>> {
        self.grades(term).await
    }
    async fn classroom_search(
        &mut self,
        campus: i32,
        date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        self.classroom_search(campus, date).await
    }
    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        self.spoc_assignments().await
    }
    async fn spoc_assignments_diagnostics(
        &mut self,
    ) -> Result<FeatureResult<SpocAssignmentsDiagnostics>> {
        self.spoc_assignments_diagnostics().await
    }
    async fn spoc_assignment(&mut self, id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        self.spoc_assignment(id).await
    }
    async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        self.judge_assignments(include_expired).await
    }
    async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<JudgeAssignmentsDiagnostics>> {
        self.judge_assignments_diagnostics(include_expired).await
    }
    async fn judge_assignment(
        &mut self,
        course_id: &str,
        id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        self.judge_assignment(course_id, id).await
    }
    async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        self.judge_assignment_details(keys).await
    }
}

#[async_trait]
impl RoutedCliBackend for UbaaClient {
    async fn signin_today(&mut self) -> RoutedResult<Vec<SigninClass>> {
        UbaaClient::signin_today(self).await
    }
    async fn libbook_libraries(&mut self, day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        UbaaClient::libbook_libraries(self, day).await
    }
    async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        UbaaClient::libbook_areas(self, premises_id, storey_id, day).await
    }
    async fn libbook_area_detail(&mut self, area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        UbaaClient::libbook_area_detail(self, area_id).await
    }
    async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        UbaaClient::libbook_seats(self, area_id, day, start_time, end_time).await
    }
    async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        UbaaClient::libbook_bookings(self, page, limit).await
    }
    async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        UbaaClient::cgyy_sites(self).await
    }
    async fn cgyy_purposes(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        UbaaClient::cgyy_purpose_types(self).await
    }
    async fn cgyy_day(&mut self, site_id: i32, date: &str) -> RoutedResult<CgyyDayInfo> {
        UbaaClient::cgyy_day_info(self, site_id, date).await
    }
    async fn cgyy_orders(&mut self, page: i32, size: i32) -> RoutedResult<CgyyOrdersPage> {
        UbaaClient::cgyy_orders(self, page, size).await
    }
    async fn cgyy_order_detail(&mut self, id: i32) -> RoutedResult<CgyyOrder> {
        UbaaClient::cgyy_order_detail(self, id).await
    }
    async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        UbaaClient::bykc_profile(self).await
    }
    async fn bykc_courses(&mut self, page: i32, size: i32) -> RoutedResult<BykcCoursePage> {
        UbaaClient::bykc_courses(self, page, size).await
    }
    async fn bykc_course_detail(&mut self, id: i64) -> RoutedResult<BykcCourse> {
        UbaaClient::bykc_course_detail(self, id).await
    }
    async fn bykc_chosen_courses(
        &mut self,
        start: &str,
        end: &str,
    ) -> RoutedResult<Vec<BykcChosenCourse>> {
        UbaaClient::bykc_chosen_courses(self, start, end).await
    }
    async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        UbaaClient::bykc_statistics(self).await
    }
    async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        UbaaClient::ygdk_overview(self).await
    }
    async fn ygdk_records(&mut self, page: i32, size: i32) -> RoutedResult<YgdkRecordsPage> {
        UbaaClient::ygdk_records(self, page, size).await
    }
    async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        UbaaClient::get_user_info(self).await
    }

    async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        UbaaClient::schedule_terms(self).await
    }

    async fn schedule_weeks(&mut self, term: &str) -> RoutedResult<Vec<Week>> {
        UbaaClient::schedule_weeks(self, term).await
    }

    async fn schedule_week(&mut self, term: &str, week: i32) -> RoutedResult<WeeklySchedule> {
        UbaaClient::schedule_week(self, term, week).await
    }

    async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        UbaaClient::schedule_today(self).await
    }

    async fn exam_arrangement(&mut self, term: &str) -> RoutedResult<ExamArrangement> {
        UbaaClient::exam_arrangement(self, term).await
    }

    async fn grades(&mut self, term: &str) -> RoutedResult<GradeData> {
        UbaaClient::grades(self, term).await
    }

    async fn classroom_search(&mut self, campus: i32, date: &str) -> RoutedResult<ClassroomQuery> {
        UbaaClient::classroom_search(self, campus, date).await
    }

    async fn spoc_assignments(&mut self) -> RoutedResult<SpocAssignments> {
        UbaaClient::spoc_assignments(self).await
    }
    async fn spoc_assignments_diagnostics(&mut self) -> RoutedResult<SpocAssignmentsDiagnostics> {
        UbaaClient::spoc_assignments_diagnostics(self).await
    }

    async fn spoc_assignment(&mut self, id: &str) -> RoutedResult<SpocAssignmentDetail> {
        UbaaClient::spoc_assignment(self, id).await
    }

    async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<Vec<JudgeAssignmentSummary>> {
        UbaaClient::judge_assignments(self, include_expired).await
    }
    async fn judge_assignments_diagnostics(
        &mut self,
        include_expired: bool,
    ) -> RoutedResult<JudgeAssignmentsDiagnostics> {
        UbaaClient::judge_assignments_diagnostics(self, include_expired).await
    }

    async fn judge_assignment(
        &mut self,
        course_id: &str,
        id: &str,
    ) -> RoutedResult<JudgeAssignmentDetail> {
        UbaaClient::judge_assignment(self, course_id, id).await
    }

    async fn judge_assignment_details(
        &mut self,
        keys: &[JudgeAssignmentKey],
    ) -> RoutedResult<Vec<JudgeAssignmentDetail>> {
        UbaaClient::judge_assignment_details(self, keys).await
    }
}

/// 使用 Core 所有的路由解析执行普通用户命令或只读命令。
pub async fn run_with_routed_backend<B, O, E>(
    cli: Cli,
    backend: &mut B,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    B: RoutedCliBackend + Send,
    O: Write,
    E: Write,
{
    let json_mode = cli.json;
    let (feature, result) = match cli.command {
        Command::User(UserArgs {
            command: UserCommand::Show,
        }) => (
            CliFeature::User,
            routed_map(backend.get_user_info().await, |profile| {
                CommandOutput::Profile(redacted_profile(profile))
            }),
        ),
        Command::Schedule(arguments) => (
            CliFeature::Schedule,
            run_routed_schedule(arguments, backend).await,
        ),
        Command::Exam(arguments) => (CliFeature::Exam, run_routed_exam(arguments, backend).await),
        Command::Grades(arguments) => (
            CliFeature::Grades,
            run_routed_grades(arguments, backend).await,
        ),
        Command::Classroom(arguments) => (
            CliFeature::Classroom,
            run_routed_classroom(arguments, backend).await,
        ),
        Command::Spoc(arguments) => (CliFeature::Spoc, run_routed_spoc(arguments, backend).await),
        Command::Judge(arguments) => (
            CliFeature::Judge,
            run_routed_judge(arguments, backend).await,
        ),
        Command::Signin(SigninArgs {
            command: SigninCommand::Today,
        }) => (
            CliFeature::Signin,
            routed_readonly(backend.signin_today().await, CliFeature::Signin),
        ),
        Command::Libbook(arguments) => (
            CliFeature::LibBook,
            run_routed_libbook(arguments, backend).await,
        ),
        Command::Bykc(arguments) => (CliFeature::Bykc, run_routed_bykc(arguments, backend).await),
        Command::Cgyy(arguments) => (CliFeature::Cgyy, run_routed_cgyy(arguments, backend).await),
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Overview,
        }) => (
            CliFeature::Ygdk,
            routed_readonly(backend.ygdk_overview().await, CliFeature::Ygdk),
        ),
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Records { page, size },
        }) => (
            CliFeature::Ygdk,
            routed_readonly(backend.ygdk_records(page, size).await, CliFeature::Ygdk),
        ),
        Command::Auth(_) => (
            CliFeature::Auth,
            Err(RoutedError {
                error: invalid_input("普通路由执行不接受认证命令"),
                resolution: None,
            }),
        ),
    };

    render_routed_result(json_mode, feature, result, stdout, stderr)
}

async fn run_routed_schedule<B: RoutedCliBackend + Send>(
    arguments: ScheduleArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ScheduleCommand::Terms => {
            routed_readonly(backend.schedule_terms().await, CliFeature::Schedule)
        }
        ScheduleCommand::Weeks { term } => {
            routed_readonly(backend.schedule_weeks(&term).await, CliFeature::Schedule)
        }
        ScheduleCommand::Current { term, week } => routed_readonly(
            backend.schedule_week(&term, week).await,
            CliFeature::Schedule,
        ),
        ScheduleCommand::Today => {
            routed_readonly(backend.schedule_today().await, CliFeature::Schedule)
        }
    }
}

async fn run_routed_exam<B: RoutedCliBackend + Send>(
    arguments: ExamArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ExamCommand::List { term } => {
            routed_readonly(backend.exam_arrangement(&term).await, CliFeature::Exam)
        }
    }
}

async fn run_routed_grades<B: RoutedCliBackend + Send>(
    arguments: GradesArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        GradesCommand::List { term } => {
            routed_readonly(backend.grades(&term).await, CliFeature::Grades)
        }
    }
}

async fn run_routed_classroom<B: RoutedCliBackend + Send>(
    arguments: ClassroomArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        ClassroomCommand::Search { campus, date } => routed_readonly(
            backend.classroom_search(campus, &date).await,
            CliFeature::Classroom,
        ),
    }
}

async fn run_routed_spoc<B: RoutedCliBackend + Send>(
    arguments: SpocArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        SpocCommand::Assignments => {
            routed_readonly(backend.spoc_assignments().await, CliFeature::Spoc)
        }
        SpocCommand::Diagnostics => routed_readonly(
            backend.spoc_assignments_diagnostics().await,
            CliFeature::Spoc,
        ),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => routed_readonly(backend.spoc_assignment(&id).await, CliFeature::Spoc),
    }
}

async fn run_routed_judge<B: RoutedCliBackend + Send>(
    arguments: JudgeArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        JudgeCommand::Assignments { include_expired } => routed_readonly(
            backend.judge_assignments(include_expired).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Diagnostics { include_expired } => routed_readonly(
            backend.judge_assignments_diagnostics(include_expired).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => routed_readonly(
            backend.judge_assignment(&course_id, &id).await,
            CliFeature::Judge,
        ),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("希冀详情键必须使用 course-id:assignment-id 格式")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "希冀详情键必须使用 course-id:assignment-id 格式",
                        ));
                    }
                    Ok(JudgeAssignmentKey {
                        course_id: course_id.into(),
                        assignment_id: assignment_id.into(),
                    })
                })
                .collect::<Result<Vec<_>>>()
                .map_err(|error| RoutedError {
                    error,
                    resolution: None,
                })?;
            routed_readonly(
                backend.judge_assignment_details(&parsed).await,
                CliFeature::Judge,
            )
        }
    }
}

async fn run_routed_libbook<B: RoutedCliBackend + Send>(
    arguments: LibBookArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        LibBookCommand::Libraries { day } => {
            routed_readonly(backend.libbook_libraries(&day).await, CliFeature::LibBook)
        }
        LibBookCommand::Areas {
            premises_id,
            storey_id,
            day,
        } => routed_readonly(
            backend
                .libbook_areas(&premises_id, storey_id.as_deref(), &day)
                .await,
            CliFeature::LibBook,
        ),
        LibBookCommand::AreaDetail { area_id } => routed_readonly(
            backend.libbook_area_detail(&area_id).await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Seats {
            area_id,
            day,
            start_time,
            end_time,
        } => routed_readonly(
            backend
                .libbook_seats(&area_id, &day, &start_time, &end_time)
                .await,
            CliFeature::LibBook,
        ),
        LibBookCommand::Bookings { page, limit } => routed_readonly(
            backend.libbook_bookings(page, limit).await,
            CliFeature::LibBook,
        ),
    }
}

async fn run_routed_bykc<B: RoutedCliBackend + Send>(
    arguments: BykcArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        BykcCommand::Profile => routed_readonly(backend.bykc_profile().await, CliFeature::Bykc),
        BykcCommand::Courses { page, size } => {
            routed_readonly(backend.bykc_courses(page, size).await, CliFeature::Bykc)
        }
        BykcCommand::Course { id } => {
            routed_readonly(backend.bykc_course_detail(id).await, CliFeature::Bykc)
        }
        BykcCommand::Chosen { start, end } => routed_readonly(
            backend.bykc_chosen_courses(&start, &end).await,
            CliFeature::Bykc,
        ),
        BykcCommand::Statistics => {
            routed_readonly(backend.bykc_statistics().await, CliFeature::Bykc)
        }
    }
}

async fn run_routed_cgyy<B: RoutedCliBackend + Send>(
    arguments: CgyyArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        CgyyCommand::Sites => routed_readonly(backend.cgyy_sites().await, CliFeature::Cgyy),
        CgyyCommand::Purposes => routed_readonly(backend.cgyy_purposes().await, CliFeature::Cgyy),
        CgyyCommand::Day { site_id, date } => {
            routed_readonly(backend.cgyy_day(site_id, &date).await, CliFeature::Cgyy)
        }
        CgyyCommand::Orders { page, size } => {
            routed_readonly(backend.cgyy_orders(page, size).await, CliFeature::Cgyy)
        }
        CgyyCommand::Detail { id } => {
            routed_readonly(backend.cgyy_order_detail(id).await, CliFeature::Cgyy)
        }
    }
}

fn routed_map<T>(
    result: RoutedResult<T>,
    map: impl FnOnce(T) -> CommandOutput,
) -> RoutedResult<CommandOutput> {
    result.map(|Routed { data, resolution }| Routed {
        data: map(data),
        resolution,
    })
}

fn routed_readonly<T: Serialize>(
    result: RoutedResult<T>,
    feature: CliFeature,
) -> RoutedResult<CommandOutput> {
    result.and_then(|Routed { data, resolution }| {
        let data = serde_json::to_value(data).map_err(|_| RoutedError {
            error: internal_error("无法序列化命令输出"),
            resolution: Some(resolution),
        })?;
        Ok(Routed {
            data: CommandOutput::Readonly {
                data,
                route: resolution.mode,
                feature,
            },
            resolution,
        })
    })
}

fn render_routed_result<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    result: RoutedResult<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(Routed { data, resolution }) => {
            if json_mode {
                let value = match command_output_value(data) {
                    Ok(value) => value,
                    Err(error) => {
                        return render_resolved_error(
                            true, feature, resolution, error, stdout, stderr,
                        );
                    }
                };
                let meta = ResolvedRoutedJsonMeta::from_resolution(feature, resolution);
                if write_json(stdout, &RoutedJsonEnvelope::success(value, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else {
                match data {
                    CommandOutput::Readonly {
                        data,
                        route,
                        feature,
                    } => {
                        if writeln!(stdout, "{} ({route:?}): {data}", feature.as_str()).is_err() {
                            return ExitCode::Internal as i32;
                        }
                    }
                    output => {
                        if render_human(output, stdout).is_err() {
                            return ExitCode::Internal as i32;
                        }
                    }
                }
            }
            ExitCode::Success as i32
        }
        Err(RoutedError {
            error,
            resolution: Some(resolution),
        }) => render_resolved_error(json_mode, feature, resolution, error, stdout, stderr),
        Err(RoutedError {
            error,
            resolution: None,
        }) => render_startup_error(json_mode, feature, error, stdout, stderr),
    }
}

fn routed_unavailable(message: impl Into<String>) -> RoutedError {
    RoutedError {
        error: internal_error(message),
        resolution: None,
    }
}

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

/// 使用宿主已验证的只读路由决策执行已解析命令。
pub async fn run_with_backend_with_route<B, R, O, E>(
    cli: Cli,
    backend: &mut B,
    route_context: ReadonlyRouteContext,
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
    let feature = command_feature(&cli.command);
    let result = match cli.command {
        Command::Auth(AuthArgs {
            command: AuthCommand::Login(arguments),
        }) => run_login(cli.json, arguments, backend, input, stderr).await,
        Command::Auth(AuthArgs {
            command: AuthCommand::Status,
        }) => backend
            .auth_status()
            .await
            .map(|status| CommandOutput::Status(redacted_status(status))),
        Command::Auth(AuthArgs {
            command: AuthCommand::Logout,
        }) => backend
            .logout()
            .await
            .map(|()| CommandOutput::Logout(json!({ "loggedOut": true }))),
        Command::User(UserArgs {
            command: UserCommand::Show,
        }) => backend
            .get_user_info()
            .await
            .map(|profile| CommandOutput::Profile(redacted_profile(profile))),
        Command::Schedule(arguments) => run_schedule(arguments, backend).await,
        Command::Exam(arguments) => run_exam(arguments, backend).await,
        Command::Grades(arguments) => run_grades(arguments, backend).await,
        Command::Classroom(arguments) => run_classroom(arguments, backend).await,
        Command::Spoc(arguments) => run_spoc(arguments, backend).await,
        Command::Judge(arguments) => run_judge(arguments, backend).await,
        Command::Signin(SigninArgs {
            command: SigninCommand::Today,
        }) => backend
            .signin_today()
            .await
            .and_then(|data| readonly(data, CliFeature::Signin)),
        Command::Libbook(arguments) => run_libbook(arguments, backend).await,
        Command::Bykc(arguments) => run_bykc(arguments, backend).await,
        Command::Cgyy(arguments) => run_cgyy(arguments, backend).await,
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Overview,
        }) => backend
            .ygdk_overview()
            .await
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        Command::Ygdk(YgdkArgs {
            command: YgdkCommand::Records { page, size },
        }) => backend
            .ygdk_records(page, size)
            .await
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
    };

    render_result(
        cli.json,
        mode,
        feature,
        route_context,
        result,
        stdout,
        stderr,
    )
}

const fn command_feature(command: &Command) -> CliFeature {
    match command {
        Command::Auth(_) => CliFeature::Auth,
        Command::User(_) => CliFeature::User,
        Command::Schedule(_) => CliFeature::Schedule,
        Command::Exam(_) => CliFeature::Exam,
        Command::Grades(_) => CliFeature::Grades,
        Command::Classroom(_) => CliFeature::Classroom,
        Command::Spoc(_) => CliFeature::Spoc,
        Command::Judge(_) => CliFeature::Judge,
        Command::Signin(_) => CliFeature::Signin,
        Command::Libbook(_) => CliFeature::LibBook,
        Command::Bykc(_) => CliFeature::Bykc,
        Command::Cgyy(_) => CliFeature::Cgyy,
        Command::Ygdk(_) => CliFeature::Ygdk,
    }
}

async fn run_login<B, R, E>(
    json_mode: bool,
    arguments: LoginArgs,
    backend: &mut B,
    input: &mut R,
    stderr: &mut E,
) -> Result<CommandOutput>
where
    B: CliBackend + Send,
    R: BufRead,
    E: Write,
{
    let username = if arguments.username_stdin {
        if arguments.username.is_some() {
            return Err(invalid_input("--username 与 --username-stdin 不能同时使用"));
        }
        let username = read_secret_line(input, "标准输入中缺少用户名")?;
        if username.trim().is_empty() {
            return Err(invalid_input("用户名不能为空"));
        }
        username
    } else {
        match arguments.username {
            Some(username) if !username.trim().is_empty() => username,
            Some(_) if json_mode => return Err(invalid_input("用户名不能为空")),
            None if json_mode => return Err(invalid_input("JSON 模式必须提供 --username")),
            _ => prompt_line(input, stderr, "用户名：")?,
        }
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "标准输入中缺少密码")?
    } else if json_mode {
        return Err(invalid_input("JSON 模式必须提供 --password-stdin"));
    } else {
        rpassword::prompt_password("密码：").map_err(|_| internal_error("无法安全读取密码"))?
    };

    backend
        .login(LoginInput {
            username,
            password: SecretValue::new(password),
        })
        .await
        .map(|profile| CommandOutput::Profile(redacted_profile(profile)))
}

async fn run_schedule<B: CliBackend + Send>(
    arguments: ScheduleArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ScheduleCommand::Terms => backend
            .schedule_terms()
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Weeks { term } => backend
            .schedule_weeks(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Current { term, week } => backend
            .schedule_week(&term, week)
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
        ScheduleCommand::Today => backend
            .schedule_today()
            .await
            .and_then(|result| readonly(result, CliFeature::Schedule)),
    }
}

async fn run_exam<B: CliBackend + Send>(
    arguments: ExamArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ExamCommand::List { term } => backend
            .exam_arrangement(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Exam)),
    }
}

async fn run_grades<B: CliBackend + Send>(
    arguments: GradesArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        GradesCommand::List { term } => backend
            .grades(&term)
            .await
            .and_then(|result| readonly(result, CliFeature::Grades)),
    }
}

async fn run_classroom<B: CliBackend + Send>(
    arguments: ClassroomArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        ClassroomCommand::Search { campus, date } => backend
            .classroom_search(campus, &date)
            .await
            .and_then(|result| readonly(result, CliFeature::Classroom)),
    }
}

async fn run_spoc<B: CliBackend + Send>(
    arguments: SpocArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        SpocCommand::Assignments => backend
            .spoc_assignments()
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
        SpocCommand::Diagnostics => backend
            .spoc_assignments_diagnostics()
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => backend
            .spoc_assignment(&id)
            .await
            .and_then(|result| readonly(result, CliFeature::Spoc)),
    }
}

async fn run_judge<B: CliBackend + Send>(
    arguments: JudgeArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        JudgeCommand::Assignments { include_expired } => backend
            .judge_assignments(include_expired)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Diagnostics { include_expired } => backend
            .judge_assignments_diagnostics(include_expired)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => backend
            .judge_assignment(&course_id, &id)
            .await
            .and_then(|result| readonly(result, CliFeature::Judge)),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("希冀详情键必须使用 course-id:assignment-id 格式")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "希冀详情键必须使用 course-id:assignment-id 格式",
                        ));
                    }
                    Ok(JudgeAssignmentKey {
                        course_id: course_id.into(),
                        assignment_id: assignment_id.into(),
                    })
                })
                .collect::<Result<Vec<_>>>()?;
            backend
                .judge_assignment_details(&parsed)
                .await
                .and_then(|result| readonly(result, CliFeature::Judge))
        }
    }
}

async fn run_libbook<B: CliBackend + Send>(
    arguments: LibBookArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        LibBookCommand::Libraries { day } => backend
            .libbook_libraries(&day)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Areas {
            premises_id,
            storey_id,
            day,
        } => backend
            .libbook_areas(&premises_id, storey_id.as_deref(), &day)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::AreaDetail { area_id } => backend
            .libbook_area_detail(&area_id)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Seats {
            area_id,
            day,
            start_time,
            end_time,
        } => backend
            .libbook_seats(&area_id, &day, &start_time, &end_time)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
        LibBookCommand::Bookings { page, limit } => backend
            .libbook_bookings(page, limit)
            .await
            .and_then(|result| readonly(result, CliFeature::LibBook)),
    }
}

async fn run_bykc<B: CliBackend + Send>(
    arguments: BykcArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        BykcCommand::Profile => backend
            .bykc_profile()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Courses { page, size } => backend
            .bykc_courses(page, size)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Course { id } => backend
            .bykc_course_detail(id)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Chosen { start, end } => backend
            .bykc_chosen_courses(&start, &end)
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
        BykcCommand::Statistics => backend
            .bykc_statistics()
            .await
            .and_then(|r| readonly(r, CliFeature::Bykc)),
    }
}

async fn run_cgyy<B: CliBackend + Send>(
    arguments: CgyyArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        CgyyCommand::Sites => backend
            .cgyy_sites()
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Purposes => backend
            .cgyy_purposes()
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Day { site_id, date } => backend
            .cgyy_day(site_id, &date)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Orders { page, size } => backend
            .cgyy_orders(page, size)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
        CgyyCommand::Detail { id } => backend
            .cgyy_order_detail(id)
            .await
            .and_then(|result| readonly(result, CliFeature::Cgyy)),
    }
}

fn readonly<T: Serialize>(result: FeatureResult<T>, feature: CliFeature) -> Result<CommandOutput> {
    let data =
        serde_json::to_value(result.data).map_err(|_| internal_error("无法序列化命令输出"))?;
    Ok(CommandOutput::Readonly {
        data,
        route: result.resolved_route,
        feature,
    })
}

enum CommandOutput {
    Profile(UserProfile),
    Status(AuthStatus),
    Logout(Value),
    Readonly {
        data: Value,
        route: ConnectionMode,
        feature: CliFeature,
    },
}

fn render_result<O: Write, E: Write>(
    json_mode: bool,
    mode: ConnectionMode,
    feature: CliFeature,
    route_context: ReadonlyRouteContext,
    result: Result<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(output) => {
            let resolved_route = match &output {
                CommandOutput::Readonly { route, .. } => *route,
                _ => mode,
            };
            if json_mode {
                let value = match command_output_value(output) {
                    Ok(value) => value,
                    Err(error) => {
                        return render_resolved_error(
                            true,
                            feature,
                            route_context.resolution(resolved_route),
                            error,
                            stdout,
                            stderr,
                        );
                    }
                };
                let meta = route_context.meta(feature, resolved_route);
                if write_json(stdout, &RoutedJsonEnvelope::success(value, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if let CommandOutput::Readonly {
                data,
                route,
                feature,
            } = output
            {
                if writeln!(stdout, "{}（{route:?}）：{data}", feature.as_str()).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if render_human(output, stdout).is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_resolved_error(
            json_mode,
            feature,
            route_context.resolution(mode),
            error,
            stdout,
            stderr,
        ),
    }
}

fn command_output_value(output: CommandOutput) -> Result<Value> {
    match output {
        CommandOutput::Profile(profile) => serde_json::to_value(profile),
        CommandOutput::Status(status) => serde_json::to_value(status),
        CommandOutput::Logout(value) | CommandOutput::Readonly { data: value, .. } => Ok(value),
    }
    .map_err(|_| internal_error("无法序列化命令输出"))
}

fn render_resolved_error<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    resolution: RouteResolution,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit_code = error.code.exit_code() as i32;
    if json_mode {
        let error = project_cli_error(error, feature, resolution.mode);
        let meta = ResolvedRoutedJsonMeta::from_resolution(feature, resolution);
        let envelope = RoutedJsonEnvelope::<Value>::resolved_failure(error, meta);
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "错误：{error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

fn project_cli_error(
    error: UbaaError,
    _feature: CliFeature,
    _route: ConnectionMode,
) -> CliJsonError {
    CliJsonError::from_core(error)
}

/// 在后端构造前展示错误，并保持 JSON 标准输出约束。
pub fn render_startup_error<O: Write, E: Write>(
    json_mode: bool,
    feature: CliFeature,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let exit_code = error.code.exit_code() as i32;
    if json_mode {
        let envelope = RoutedJsonEnvelope::<Value>::unresolved_failure(
            CliJsonError::from_core(error),
            UnresolvedRoutedJsonMeta::new(feature),
        );
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "错误：{error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

fn render_human<O: Write>(output: CommandOutput, stdout: &mut O) -> std::io::Result<()> {
    match output {
        CommandOutput::Profile(profile) => write_profile(stdout, &profile),
        CommandOutput::Status(status) => {
            writeln!(stdout, "已认证：是")?;
            writeln!(stdout, "连接检查时间：{}", status.last_activity)?;
            write_profile(stdout, &status.user)
        }
        CommandOutput::Logout(_) => writeln!(stdout, "已退出登录。"),
        CommandOutput::Readonly { .. } => unreachable!("readonly output handled above"),
    }
}

fn write_profile<O: Write>(stdout: &mut O, profile: &UserProfile) -> std::io::Result<()> {
    write_optional(stdout, "姓名", profile.name.as_deref())?;
    write_optional(stdout, "学号", profile.school_id.as_deref())?;
    write_optional(stdout, "用户名", profile.username.as_deref())?;
    write_optional(stdout, "手机号", profile.phone.as_deref())?;
    write_optional(stdout, "身份证号", profile.id_card_number.as_deref())?;
    write_optional(stdout, "邮箱", profile.email.as_deref())
}

fn write_optional<O: Write>(
    stdout: &mut O,
    label: &str,
    value: Option<&str>,
) -> std::io::Result<()> {
    if let Some(value) = value {
        writeln!(stdout, "{label}: {value}")?;
    }
    Ok(())
}

fn redacted_status(mut status: AuthStatus) -> AuthStatus {
    status.user = redacted_profile(status.user);
    status
}

fn redacted_profile(mut profile: UserProfile) -> UserProfile {
    profile.phone = profile.phone.as_deref().map(mask_sensitive);
    profile.id_card_number = profile.id_card_number.as_deref().map(mask_sensitive);
    profile
}

fn mask_sensitive(value: &str) -> String {
    let characters: Vec<char> = value.chars().collect();
    match characters.len() {
        0 => String::new(),
        1..=4 => "*".repeat(characters.len()),
        length => format!(
            "{}{}{}",
            characters[..2].iter().collect::<String>(),
            "*".repeat(length - 4),
            characters[length - 2..].iter().collect::<String>()
        ),
    }
}

fn prompt_line<R: BufRead, E: Write>(
    input: &mut R,
    stderr: &mut E,
    prompt: &str,
) -> Result<String> {
    loop {
        write!(stderr, "{prompt}").map_err(|_| internal_error("无法写入提示"))?;
        stderr.flush().map_err(|_| internal_error("无法刷新提示"))?;
        let mut value = String::new();
        let read = input
            .read_line(&mut value)
            .map_err(|_| invalid_input("无法读取必填输入"))?;
        if read == 0 {
            return Err(invalid_input("缺少必填输入"));
        }
        let value = value.trim_end_matches(['\r', '\n']).to_string();
        if !value.is_empty() {
            return Ok(value);
        }
        writeln!(stderr, "必须提供一个值。").map_err(|_| internal_error("无法写入提示"))?;
    }
}

fn read_secret_line<R: BufRead>(input: &mut R, missing_message: &str) -> Result<String> {
    let mut value = String::new();
    input
        .read_line(&mut value)
        .map_err(|_| invalid_input(missing_message))?;
    let value = value.trim_end_matches(['\r', '\n']).to_string();
    if value.is_empty() {
        Err(invalid_input(missing_message))
    } else {
        Ok(value)
    }
}

fn write_json<O: Write, T: serde::Serialize>(stdout: &mut O, value: &T) -> std::io::Result<()> {
    serde_json::to_writer(&mut *stdout, value)?;
    writeln!(stdout)
}

fn invalid_input(message: impl Into<String>) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

/// 构造进程入口使用的稳定缺失会话错误。
#[must_use]
pub fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "需要先完成认证",
    )
}

fn internal_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sensitive_mask_handles_unicode_without_byte_slicing() {
        assert_eq!(mask_sensitive("ABCD1234"), "AB****34");
        assert_eq!(mask_sensitive("北航用户甲乙"), "北航**甲乙");
    }
}
