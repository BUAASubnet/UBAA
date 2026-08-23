//! Command-line parsing and presentation for UBAA Core.

use std::fs::OpenOptions;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use base64::Engine as _;
use clap::{Args, Parser, Subcommand, ValueEnum};
use serde::Serialize;
use serde_json::{Value, json};
use ubaa_core::connection::{NetworkState, RouteResolution};
use ubaa_core::domain::{
    AuthStatus, CaptchaAnswer, ClassroomQuery, ConnectionMode, DualLoginInput, ExamArrangement,
    FeatureResult, GradeData, JudgeAssignmentDetail, JudgeAssignmentKey, JudgeAssignmentSummary,
    LoginChallenge, LoginInput, LoginReadiness, RouteLoginState, RoutePolicy, SafeError,
    SecretValue, SpocAssignmentDetail, SpocAssignments, Term, TodayClass, UserProfile, Week,
    WeeklySchedule,
};
use ubaa_core::error::{ErrorCode, ErrorKind, ExitCode, Result, UbaaError};
use ubaa_core::facade::{DualUbaaClient, UbaaClient};
use ubaa_core::output::{
    AggregateJsonEnvelope, AggregateJsonMeta, JSON_SCHEMA_VERSION, JsonEnvelope, JsonMeta,
    ReadonlyJsonEnvelope, ReadonlyJsonMeta,
};

/// UBAA command-line interface.
#[derive(Debug, Parser)]
#[command(name = "ubaa", version, about = "BUAA unified authentication client")]
pub struct Cli {
    /// Emit one versioned JSON envelope on standard output.
    #[arg(long, global = true)]
    pub json: bool,

    /// Store session state in this directory.
    #[arg(long, global = true, value_name = "DIR")]
    pub config_dir: Option<PathBuf>,

    /// Disable terminal colors.
    #[arg(long, global = true)]
    pub no_color: bool,

    /// Command to run.
    #[command(subcommand)]
    pub command: Command,
}

/// Safe route decision context supplied by the host after configuration and DNS resolution.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ReadonlyRouteContext {
    /// Effective feature route policy.
    pub policy: RoutePolicy,
    /// DNS state used for the decision, or unknown when no probe ran.
    pub network: NetworkState,
    /// Route selected before fallback.
    pub initial_route: ConnectionMode,
    /// Route selected after fallback.
    pub resolved_route: ConnectionMode,
    /// Whether a ready-route fallback occurred.
    pub used_fallback: bool,
}

impl ReadonlyRouteContext {
    fn compatibility(mode: ConnectionMode) -> Self {
        Self {
            policy: RoutePolicy::Auto,
            network: NetworkState::Unknown,
            initial_route: mode,
            resolved_route: mode,
            used_fallback: false,
        }
    }

    fn meta(self, feature: &'static str, resolved_route: ConnectionMode) -> ReadonlyJsonMeta {
        ReadonlyJsonMeta {
            route_policy: self.policy,
            network_state: self.network,
            initial_route: self.initial_route,
            resolved_route,
            used_fallback: self.used_fallback,
            feature: feature.into(),
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

/// Top-level command groups.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Authenticate and manage the persisted session.
    Auth(AuthArgs),
    /// Query the authenticated User Center profile.
    User(UserArgs),
    /// Schedule and exam read-only operations.
    Schedule(ScheduleArgs),
    /// Exam read-only operations.
    Exam(ExamArgs),
    /// Grades read-only operations.
    Grades(GradesArgs),
    /// Empty classroom read-only operations.
    Classroom(ClassroomArgs),
    /// SPOC read-only operations.
    Spoc(SpocArgs),
    /// Judge read-only operations.
    Judge(JudgeArgs),
}

/// Authentication command group.
#[derive(Debug, Args)]
pub struct AuthArgs {
    /// Authentication operation.
    #[command(subcommand)]
    pub command: AuthCommand,
}

/// Authentication operations.
#[derive(Debug, Subcommand)]
pub enum AuthCommand {
    /// Sign in through SSO and persist the resulting session.
    Login(LoginArgs),
    /// Validate the persisted session against User Center.
    Status,
    /// Sign out remotely when possible and always clear local state.
    Logout,
}

/// User Center command group.
#[derive(Debug, Args)]
pub struct UserArgs {
    /// User Center operation.
    #[command(subcommand)]
    pub command: UserCommand,
}

/// User Center operations.
#[derive(Debug, Subcommand)]
pub enum UserCommand {
    /// Show the authenticated User Center profile.
    Show,
}

/// Login arguments.
#[derive(Args)]
pub struct LoginArgs {
    /// Network route used for every request; reuses a saved mode when omitted.
    #[arg(long, value_enum, hide = true)]
    pub mode: Option<CliConnectionMode>,

    /// SSO username. Human mode prompts when omitted.
    #[arg(long)]
    pub username: Option<String>,

    /// Read one password line from standard input.
    #[arg(long)]
    pub password_stdin: bool,

    /// Captcha answer for a currently required challenge.
    #[arg(long)]
    pub captcha: Option<String>,
}

/// Schedule operations.
#[derive(Debug, Args)]
pub struct ScheduleArgs {
    /// Schedule operation.
    #[command(subcommand)]
    pub command: ScheduleCommand,
}

/// Schedule subcommands.
#[derive(Debug, Subcommand)]
pub enum ScheduleCommand {
    /// List terms.
    Terms,
    /// List teaching weeks.
    Weeks {
        #[arg(long)]
        term: String,
    },
    /// Read one week.
    Current {
        #[arg(long)]
        term: String,
        #[arg(long)]
        week: i32,
    },
    /// Read today's classes.
    Today,
}

/// Exam operations.
#[derive(Debug, Args)]
pub struct ExamArgs {
    /// Exam operation.
    #[command(subcommand)]
    pub command: ExamCommand,
}

/// Exam subcommands.
#[derive(Debug, Subcommand)]
pub enum ExamCommand {
    /// List a term's exams.
    List {
        #[arg(long)]
        term: String,
    },
}

/// Grade operations.
#[derive(Debug, Args)]
pub struct GradesArgs {
    /// Grade operation.
    #[command(subcommand)]
    pub command: GradesCommand,
}

/// Grade subcommands.
#[derive(Debug, Subcommand)]
pub enum GradesCommand {
    /// List a term's grades.
    List {
        #[arg(long)]
        term: String,
    },
}

/// Classroom operations.
#[derive(Debug, Args)]
pub struct ClassroomArgs {
    /// Classroom operation.
    #[command(subcommand)]
    pub command: ClassroomCommand,
}

/// Classroom subcommands.
#[derive(Debug, Subcommand)]
pub enum ClassroomCommand {
    /// Search free classrooms.
    Search {
        #[arg(long)]
        campus: i32,
        #[arg(long)]
        date: String,
    },
}

/// SPOC operations.
#[derive(Debug, Args)]
pub struct SpocArgs {
    /// SPOC operation.
    #[command(subcommand)]
    pub command: SpocCommand,
}

/// SPOC subcommands.
#[derive(Debug, Subcommand)]
pub enum SpocCommand {
    /// List assignments.
    Assignments,
    /// Show one assignment.
    Assignment {
        #[command(subcommand)]
        command: SpocAssignmentCommand,
    },
}

/// SPOC assignment subcommands.
#[derive(Debug, Subcommand)]
pub enum SpocAssignmentCommand {
    /// Show assignment detail.
    Show {
        #[arg(long)]
        id: String,
    },
}

/// Judge operations.
#[derive(Debug, Args)]
pub struct JudgeArgs {
    /// Judge operation.
    #[command(subcommand)]
    pub command: JudgeCommand,
}

/// Judge subcommands.
#[derive(Debug, Subcommand)]
pub enum JudgeCommand {
    /// List assignments.
    Assignments {
        #[arg(long)]
        include_expired: bool,
    },
    /// Assignment operations.
    Assignment {
        #[command(subcommand)]
        command: JudgeAssignmentCommand,
    },
}

/// Judge assignment subcommands.
#[derive(Debug, Subcommand)]
pub enum JudgeAssignmentCommand {
    /// Show one detail.
    Show {
        #[arg(long)]
        course_id: String,
        #[arg(long)]
        id: String,
    },
    /// Show multiple details.
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
            .field("password_stdin", &self.password_stdin)
            .field("captcha", &self.captcha.as_ref().map(|_| "[REDACTED]"))
            .finish()
    }
}

/// CLI spelling of a connection mode.
#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum CliConnectionMode {
    /// Reach BUAA services directly.
    Direct,
    /// Route BUAA services through `WebVPN`.
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
    /// Whether this is an authentication login command.
    #[must_use]
    pub const fn is_login(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Login(_)
            })
        )
    }

    /// Return the explicit login mode, when this is an authentication login command.
    #[must_use]
    pub fn login_mode(&self) -> Option<ConnectionMode> {
        match &self.command {
            Command::Auth(AuthArgs {
                command: AuthCommand::Login(arguments),
            }) => arguments.mode.map(Into::into),
            _ => None,
        }
    }

    /// Resolve an explicit login mode or a mode loaded from persisted session state.
    ///
    /// # Errors
    ///
    /// Returns invalid input when login has neither an explicit nor saved mode.
    pub fn resolve_mode(&self, saved_mode: Option<ConnectionMode>) -> Result<ConnectionMode> {
        self.login_mode().or(saved_mode).ok_or_else(|| {
            invalid_input("--mode is required when no saved session mode is available")
        })
    }

    /// Whether this command requires an existing session before constructing a client.
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
        )
    }

    /// Whether this is a logout command.
    #[must_use]
    pub const fn is_logout(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Logout
            })
        )
    }

    /// Whether this is an ordinary aggregate authentication status command.
    #[must_use]
    pub const fn is_auth_status(&self) -> bool {
        matches!(
            self.command,
            Command::Auth(AuthArgs {
                command: AuthCommand::Status
            })
        )
    }
}

/// Authentication facade needed by command execution.
#[async_trait]
pub trait CliBackend {
    /// Fixed connection mode for this backend.
    fn mode(&self) -> ConnectionMode;
    /// Prepare the SSO form and optional captcha challenge.
    async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>>;
    /// Submit credentials and return the authenticated profile.
    async fn login(&mut self, input: LoginInput) -> Result<UserProfile>;
    /// Validate the active session.
    async fn auth_status(&mut self) -> Result<AuthStatus>;
    /// Fetch User Center profile data.
    async fn get_user_info(&mut self) -> Result<UserProfile>;
    /// Sign out and clear local state.
    async fn logout(&mut self) -> Result<()>;

    /// Read terms.
    async fn schedule_terms(&mut self) -> Result<FeatureResult<Vec<Term>>> {
        Err(internal_error("schedule is unavailable"))
    }
    /// Read weeks.
    async fn schedule_weeks(&mut self, _term: &str) -> Result<FeatureResult<Vec<Week>>> {
        Err(internal_error("schedule is unavailable"))
    }
    /// Read one week.
    async fn schedule_week(
        &mut self,
        _term: &str,
        _week: i32,
    ) -> Result<FeatureResult<WeeklySchedule>> {
        Err(internal_error("schedule is unavailable"))
    }
    /// Read today.
    async fn schedule_today(&mut self) -> Result<FeatureResult<Vec<TodayClass>>> {
        Err(internal_error("schedule is unavailable"))
    }
    /// Read exams.
    async fn exam_arrangement(&mut self, _term: &str) -> Result<FeatureResult<ExamArrangement>> {
        Err(internal_error("exam is unavailable"))
    }
    /// Read grades.
    async fn grades(&mut self, _term: &str) -> Result<FeatureResult<GradeData>> {
        Err(internal_error("grades are unavailable"))
    }
    /// Search classrooms.
    async fn classroom_search(
        &mut self,
        _campus: i32,
        _date: &str,
    ) -> Result<FeatureResult<ClassroomQuery>> {
        Err(internal_error("classroom is unavailable"))
    }
    /// Read SPOC assignments.
    async fn spoc_assignments(&mut self) -> Result<FeatureResult<SpocAssignments>> {
        Err(internal_error("SPOC is unavailable"))
    }
    /// Read SPOC detail.
    async fn spoc_assignment(&mut self, _id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        Err(internal_error("SPOC is unavailable"))
    }
    /// Read Judge assignments.
    async fn judge_assignments(
        &mut self,
        _include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        Err(internal_error("Judge is unavailable"))
    }
    /// Read Judge detail.
    async fn judge_assignment(
        &mut self,
        _course_id: &str,
        _id: &str,
    ) -> Result<FeatureResult<JudgeAssignmentDetail>> {
        Err(internal_error("Judge is unavailable"))
    }
    /// Read Judge details in batch.
    async fn judge_assignment_details(
        &mut self,
        _keys: &[JudgeAssignmentKey],
    ) -> Result<FeatureResult<Vec<JudgeAssignmentDetail>>> {
        Err(internal_error("Judge is unavailable"))
    }
}

/// Execute the ordinary aggregate login path against the dual-route facade.
pub async fn run_dual_login<R, O, E>(
    cli: Cli,
    backend: &mut DualUbaaClient,
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
    let Command::Auth(AuthArgs {
        command: AuthCommand::Login(arguments),
    }) = cli.command
    else {
        return render_aggregate_input_error(
            json_mode,
            invalid_input("aggregate login requires auth login"),
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
    let preparation = backend.prepare_login().await;
    let answers =
        match collect_dual_captcha_answers(json_mode, arguments.captcha, &preparation, stderr) {
            Ok(answers) => answers,
            Err(error) => {
                return render_aggregate_input_error(json_mode, error, stdout, stderr);
            }
        };
    let mut outcome = match backend
        .login(DualLoginInput {
            username,
            password: SecretValue::new(password),
            captcha_answers: answers,
        })
        .await
    {
        Ok(outcome) => outcome,
        Err(error) => {
            return render_aggregate_input_error(json_mode, error, stdout, stderr);
        }
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(json_mode, &outcome, &preparation, stdout, stderr)
}

/// Execute the ordinary aggregate authentication status path.
pub async fn run_dual_status<O, E>(
    cli: Cli,
    backend: &mut DualUbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let mut outcome = match backend.auth_status().await {
        Ok(outcome) => outcome,
        Err(error) => return render_aggregate_input_error(cli.json, error, stdout, stderr),
    };
    outcome.profile = outcome.profile.map(redacted_profile);
    render_dual_outcome(
        cli.json,
        &outcome,
        &ubaa_core::domain::DualLoginPreparation {
            routes: Vec::new(),
            challenges: Vec::new(),
        },
        stdout,
        stderr,
    )
}

/// Execute logout for both route slots while retaining the v1 logout response shape.
pub async fn run_dual_logout<O, E>(
    cli: Cli,
    backend: &mut DualUbaaClient,
    stdout: &mut O,
    stderr: &mut E,
) -> i32
where
    O: Write,
    E: Write,
{
    let active_routes = backend.active_routes();
    let result = backend.logout().await;
    match result {
        Ok(()) => {
            let mode = (active_routes.len() == 1).then(|| active_routes[0]);
            if cli.json {
                let envelope = JsonEnvelope::success(
                    json!({ "loggedOut": true }),
                    mode.unwrap_or(ConnectionMode::Direct),
                );
                // A missing session must not invent a route in the public metadata.
                let value = serde_json::to_value(envelope).unwrap_or_else(|_| json!({}));
                let mut value = value;
                if mode.is_none() {
                    value["meta"] = json!({});
                }
                if write_json(stdout, &value).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if writeln!(stdout, "Signed out.").is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_startup_error(cli.json, error, stdout, stderr),
    }
}

fn read_dual_credentials<R: BufRead, E: Write>(
    json_mode: bool,
    arguments: &LoginArgs,
    input: &mut R,
    stderr: &mut E,
) -> Result<(String, String)> {
    let username = match arguments.username.as_deref() {
        Some(username) if !username.trim().is_empty() => username.to_owned(),
        Some(_) => return Err(invalid_input("username must not be empty")),
        None if json_mode => return Err(invalid_input("--username is required in JSON mode")),
        None => prompt_line(input, stderr, "Username: ")?,
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "password is missing on standard input")?
    } else if json_mode {
        return Err(invalid_input("--password-stdin is required in JSON mode"));
    } else {
        rpassword::prompt_password("Password: ")
            .map_err(|_| internal_error("could not read password securely"))?
    };
    Ok((username, password))
}

fn collect_dual_captcha_answers<E: Write>(
    json_mode: bool,
    compatibility_captcha: Option<String>,
    preparation: &ubaa_core::domain::DualLoginPreparation,
    stderr: &mut E,
) -> Result<Vec<CaptchaAnswer>> {
    let mut compatibility_captcha = compatibility_captcha;
    let mut answers = Vec::new();
    for challenge in &preparation.challenges {
        let answer = if let Some(answer) = compatibility_captcha.take() {
            Some(answer)
        } else if json_mode {
            None
        } else if let Some(data_url) = challenge.image_data_url.as_deref() {
            let image = CaptchaImage::create_data_url(data_url)?;
            writeln!(
                stderr,
                "Captcha image ({:?}): {}",
                challenge.route,
                image.path().display()
            )
            .map_err(|_| internal_error("could not display captcha path"))?;
            let answer =
                rpassword::prompt_password(format!("Captcha ({:?}): ", challenge.route)).ok();
            drop(image);
            answer
        } else {
            rpassword::prompt_password(format!("Captcha ({:?}): ", challenge.route)).ok()
        };
        if let Some(answer) = answer.filter(|answer| !answer.trim().is_empty()) {
            answers.push(CaptchaAnswer {
                challenge_id: challenge.challenge_id.clone(),
                value: SecretValue::new(answer),
            });
        }
    }
    Ok(answers)
}

fn render_dual_outcome<O: Write, E: Write>(
    json_mode: bool,
    outcome: &ubaa_core::domain::LoginOutcome,
    preparation: &ubaa_core::domain::DualLoginPreparation,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    let resolved_routes = outcome
        .routes
        .iter()
        .filter(|route| route.state == RouteLoginState::Ready)
        .map(|route| route.route)
        .collect::<Vec<_>>();
    let has_captcha = outcome
        .routes
        .iter()
        .any(|route| route.state == RouteLoginState::CaptchaRequired);
    let error = aggregate_error(outcome, has_captcha);
    let exit_code = aggregate_exit_code(outcome, has_captcha, error.as_ref());
    if json_mode {
        let challenges = preparation
            .challenges
            .iter()
            .filter(|challenge| {
                outcome.routes.iter().any(|route| {
                    route.route == challenge.route
                        && route.state == RouteLoginState::CaptchaRequired
                })
            })
            .map(|challenge| {
                json!({
                    "route": challenge.route,
                    "challengeId": challenge.challenge_id,
                    "imageAvailable": challenge.image_data_url.is_some()
                })
            })
            .collect::<Vec<_>>();
        let envelope = AggregateJsonEnvelope {
            schema_version: ubaa_core::output::READONLY_JSON_SCHEMA_VERSION,
            ok: exit_code == 0,
            data: json!({
                "readiness": outcome.readiness,
                "routes": outcome.routes,
                "profile": outcome.profile,
                "challenges": challenges
            }),
            error,
            meta: AggregateJsonMeta {
                route_policy: ubaa_core::domain::RoutePolicy::Auto,
                resolved_routes,
                feature: "auth".into(),
            },
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
            let _ = writeln!(stderr, "Error: {}", error.message);
        }
    }
    exit_code
}

fn aggregate_error(
    outcome: &ubaa_core::domain::LoginOutcome,
    has_captcha: bool,
) -> Option<SafeError> {
    if has_captcha {
        Some(SafeError {
            code: "captcha_required".into(),
            kind: "authentication".into(),
            retryable: true,
            message: "captcha input is required for one or more routes".into(),
        })
    } else if outcome.readiness == LoginReadiness::NoneReady {
        outcome.routes.iter().find_map(|route| route.error.clone())
    } else {
        None
    }
}

fn aggregate_exit_code(
    outcome: &ubaa_core::domain::LoginOutcome,
    has_captcha: bool,
    error: Option<&SafeError>,
) -> i32 {
    if has_captcha {
        ExitCode::CaptchaRequired as i32
    } else if outcome.readiness == LoginReadiness::NoneReady {
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
        "captcha_required" => ExitCode::CaptchaRequired as i32,
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
    let safe = SafeError {
        code: serde_json::to_value(error.code)
            .ok()
            .and_then(|value| value.as_str().map(str::to_owned))
            .unwrap_or_else(|| "internal_error".into()),
        kind: serde_json::to_value(error.kind)
            .ok()
            .and_then(|value| value.as_str().map(str::to_owned))
            .unwrap_or_else(|| "internal".into()),
        retryable: error.retryable,
        message: error.message,
    };
    let code = safe_error_exit_code(&safe);
    if json_mode {
        let envelope = AggregateJsonEnvelope {
            schema_version: ubaa_core::output::READONLY_JSON_SCHEMA_VERSION,
            ok: false,
            data: json!({ "readiness": "none_ready", "routes": [], "challenges": [] }),
            error: Some(safe),
            meta: AggregateJsonMeta {
                route_policy: ubaa_core::domain::RoutePolicy::Auto,
                resolved_routes: Vec::new(),
                feature: "auth".into(),
            },
        };
        if write_json(stdout, &envelope).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "Error: {}", safe.message).is_err() {
        return ExitCode::Internal as i32;
    }
    code
}

#[async_trait]
impl CliBackend for UbaaClient {
    fn mode(&self) -> ConnectionMode {
        self.mode()
    }

    async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>> {
        self.prepare_login().await
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
    async fn spoc_assignment(&mut self, id: &str) -> Result<FeatureResult<SpocAssignmentDetail>> {
        self.spoc_assignment(id).await
    }
    async fn judge_assignments(
        &mut self,
        include_expired: bool,
    ) -> Result<FeatureResult<Vec<JudgeAssignmentSummary>>> {
        self.judge_assignments(include_expired).await
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

/// Execute a parsed command against an injected backend.
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
        ReadonlyRouteContext::compatibility(mode),
        input,
        stdout,
        stderr,
    )
    .await
}

/// Execute a parsed command with the host's verified read-only route decision.
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
    let readonly_feature = readonly_command_feature(&cli.command);
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
    };

    render_result(
        cli.json,
        mode,
        readonly_feature,
        route_context,
        result,
        stdout,
        stderr,
    )
}

fn readonly_command_feature(command: &Command) -> Option<&'static str> {
    match command {
        Command::Schedule(_) => Some("schedule"),
        Command::Exam(_) => Some("exam"),
        Command::Grades(_) => Some("grades"),
        Command::Classroom(_) => Some("classroom"),
        Command::Spoc(_) => Some("spoc"),
        Command::Judge(_) => Some("judge"),
        _ => None,
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
    let username = match arguments.username {
        Some(username) if !username.trim().is_empty() => username,
        Some(_) if json_mode => return Err(invalid_input("username must not be empty")),
        None if json_mode => return Err(invalid_input("--username is required in JSON mode")),
        _ => prompt_line(input, stderr, "Username: ")?,
    };
    let password = if arguments.password_stdin {
        read_secret_line(input, "password is missing on standard input")?
    } else if json_mode {
        return Err(invalid_input("--password-stdin is required in JSON mode"));
    } else {
        rpassword::prompt_password("Password: ")
            .map_err(|_| internal_error("could not read password securely"))?
    };

    let challenge = backend.prepare_login().await?;
    let captcha = match (challenge, arguments.captcha) {
        (Some(_), Some(answer)) if !answer.trim().is_empty() => Some(answer),
        (Some(mut challenge), _) if json_mode => {
            challenge.image_data_url = None;
            return Err(UbaaError::new(
                ErrorCode::CaptchaRequired,
                ErrorKind::Authentication,
                true,
                "captcha input is required",
            )
            .with_challenge(challenge));
        }
        (Some(challenge), _) => Some(prompt_captcha(&challenge, input, stderr)?),
        (None, _) => None,
    };

    backend
        .login(LoginInput {
            username,
            password: SecretValue::new(password),
            captcha,
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
            .map(|result| readonly(result, "schedule")),
        ScheduleCommand::Weeks { term } => backend
            .schedule_weeks(&term)
            .await
            .map(|result| readonly(result, "schedule")),
        ScheduleCommand::Current { term, week } => backend
            .schedule_week(&term, week)
            .await
            .map(|result| readonly(result, "schedule")),
        ScheduleCommand::Today => backend
            .schedule_today()
            .await
            .map(|result| readonly(result, "schedule")),
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
            .map(|result| readonly(result, "exam")),
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
            .map(|result| readonly(result, "grades")),
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
            .map(|result| readonly(result, "classroom")),
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
            .map(|result| readonly(result, "spoc")),
        SpocCommand::Assignment {
            command: SpocAssignmentCommand::Show { id },
        } => backend
            .spoc_assignment(&id)
            .await
            .map(|result| readonly(result, "spoc")),
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
            .map(|result| readonly(result, "judge")),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Show { course_id, id },
        } => backend
            .judge_assignment(&course_id, &id)
            .await
            .map(|result| readonly(result, "judge")),
        JudgeCommand::Assignment {
            command: JudgeAssignmentCommand::Details { keys },
        } => {
            let parsed = keys
                .into_iter()
                .map(|key| {
                    let (course_id, assignment_id) = key.split_once(':').ok_or_else(|| {
                        invalid_input("judge detail key must use course-id:assignment-id")
                    })?;
                    if course_id.is_empty() || assignment_id.is_empty() {
                        return Err(invalid_input(
                            "judge detail key must use course-id:assignment-id",
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
                .map(|result| readonly(result, "judge"))
        }
    }
}

fn readonly<T: Serialize>(result: FeatureResult<T>, feature: &'static str) -> CommandOutput {
    CommandOutput::Readonly {
        data: serde_json::to_value(result.data).unwrap_or_else(|_| json!({})),
        route: result.resolved_route,
        feature,
    }
}

enum CommandOutput {
    Profile(UserProfile),
    Status(AuthStatus),
    Logout(Value),
    Readonly {
        data: Value,
        route: ConnectionMode,
        feature: &'static str,
    },
}

fn render_result<O: Write, E: Write>(
    json_mode: bool,
    mode: ConnectionMode,
    readonly_feature: Option<&'static str>,
    route_context: ReadonlyRouteContext,
    result: Result<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(CommandOutput::Readonly {
            data,
            route,
            feature,
        }) => {
            if json_mode {
                let meta = route_context.meta(feature, route);
                if write_json(stdout, &ReadonlyJsonEnvelope::success(data, meta)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if writeln!(stdout, "{feature} ({route:?}): {data}").is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Ok(output) => {
            if json_mode {
                let value = match output {
                    CommandOutput::Profile(profile) => json!(profile),
                    CommandOutput::Status(status) => json!(status),
                    CommandOutput::Logout(value) => value,
                    CommandOutput::Readonly { .. } => unreachable!("readonly output handled above"),
                };
                if write_json(stdout, &JsonEnvelope::success(value, mode)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if let CommandOutput::Readonly {
                data,
                route,
                feature,
            } = output
            {
                if writeln!(stdout, "{feature} ({route:?}): {data}").is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if render_human(output, stdout).is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => match readonly_feature {
            Some(feature) => render_readonly_error(
                json_mode,
                mode,
                feature,
                route_context,
                error,
                stdout,
                stderr,
            ),
            None => render_error(json_mode, Some(mode), error, stdout, stderr),
        },
    }
}

fn render_readonly_error<O: Write, E: Write>(
    json_mode: bool,
    mode: ConnectionMode,
    feature: &'static str,
    route_context: ReadonlyRouteContext,
    mut error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    if !json_mode {
        return render_error(false, Some(mode), error, stdout, stderr);
    }
    // A feature request never exposes an authentication execution token or image. If an
    // upstream unexpectedly returns a captcha-shaped error, keep the stable v2 error schema
    // by dropping the ephemeral challenge rather than serializing its internal fields.
    let exit_code = error.code.exit_code() as i32;
    error.challenge = None;
    let meta = route_context.meta(feature, route_context.resolved_route);
    if write_json(stdout, &ReadonlyJsonEnvelope::<Value>::failure(error, meta)).is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

/// Render a safe post-resolution read-only failure before a backend is available.
pub fn render_readonly_startup_error<O: Write, E: Write>(
    json_mode: bool,
    feature: &'static str,
    route_context: ReadonlyRouteContext,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    render_readonly_error(
        json_mode,
        route_context.resolved_route,
        feature,
        route_context,
        error,
        stdout,
        stderr,
    )
}

/// Render an error before a backend exists, preserving JSON stdout discipline.
pub fn render_startup_error<O: Write, E: Write>(
    json_mode: bool,
    error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    render_error(json_mode, None, error, stdout, stderr)
}

/// Render a successful no-op logout when no persisted session exists.
pub fn render_empty_logout<O: Write>(json_mode: bool, stdout: &mut O) -> i32 {
    let rendered = if json_mode {
        write_json(
            stdout,
            &JsonEnvelope {
                schema_version: JSON_SCHEMA_VERSION,
                ok: true,
                data: Some(json!({ "loggedOut": true })),
                error: None,
                meta: JsonMeta {
                    connection_mode: None,
                },
            },
        )
    } else {
        writeln!(stdout, "Signed out.")
    };
    if rendered.is_ok() {
        ExitCode::Success as i32
    } else {
        ExitCode::Internal as i32
    }
}

fn render_error<O: Write, E: Write>(
    json_mode: bool,
    mode: Option<ConnectionMode>,
    mut error: UbaaError,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    if let Some(challenge) = error.challenge.as_mut() {
        challenge.image_data_url = None;
    }
    let exit_code = error.code.exit_code() as i32;
    if json_mode {
        if write_json(stdout, &JsonEnvelope::<Value>::failure(error, mode)).is_err() {
            return ExitCode::Internal as i32;
        }
    } else if writeln!(stderr, "Error: {error}").is_err() {
        return ExitCode::Internal as i32;
    }
    exit_code
}

fn render_human<O: Write>(output: CommandOutput, stdout: &mut O) -> std::io::Result<()> {
    match output {
        CommandOutput::Profile(profile) => write_profile(stdout, &profile),
        CommandOutput::Status(status) => {
            writeln!(stdout, "Authenticated: yes")?;
            writeln!(stdout, "Connection checked: {}", status.last_activity)?;
            write_profile(stdout, &status.user)
        }
        CommandOutput::Logout(_) => writeln!(stdout, "Signed out."),
        CommandOutput::Readonly { .. } => unreachable!("readonly output handled above"),
    }
}

fn write_profile<O: Write>(stdout: &mut O, profile: &UserProfile) -> std::io::Result<()> {
    write_optional(stdout, "Name", profile.name.as_deref())?;
    write_optional(stdout, "School ID", profile.school_id.as_deref())?;
    write_optional(stdout, "Username", profile.username.as_deref())?;
    write_optional(stdout, "Phone", profile.phone.as_deref())?;
    write_optional(stdout, "ID card", profile.id_card_number.as_deref())?;
    write_optional(stdout, "Email", profile.email.as_deref())
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
        write!(stderr, "{prompt}").map_err(|_| internal_error("could not write prompt"))?;
        stderr
            .flush()
            .map_err(|_| internal_error("could not flush prompt"))?;
        let mut value = String::new();
        let read = input
            .read_line(&mut value)
            .map_err(|_| invalid_input("required input could not be read"))?;
        if read == 0 {
            return Err(invalid_input("required input is missing"));
        }
        let value = value.trim_end_matches(['\r', '\n']).to_string();
        if !value.is_empty() {
            return Ok(value);
        }
        writeln!(stderr, "A value is required.")
            .map_err(|_| internal_error("could not write prompt"))?;
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

fn prompt_captcha<R: BufRead, E: Write>(
    challenge: &LoginChallenge,
    input: &mut R,
    stderr: &mut E,
) -> Result<String> {
    let image = CaptchaImage::create(challenge)?;
    writeln!(stderr, "Captcha image: {}", image.path().display())
        .map_err(|_| internal_error("could not display captcha path"))?;
    prompt_line(input, stderr, "Captcha: ")
}

struct CaptchaImage {
    path: PathBuf,
}

impl CaptchaImage {
    fn create(challenge: &LoginChallenge) -> Result<Self> {
        let data_url = challenge
            .image_data_url
            .as_deref()
            .ok_or_else(|| internal_error("captcha image data is unavailable"))?;
        Self::create_data_url(data_url)
    }

    fn create_data_url(data_url: &str) -> Result<Self> {
        let (_, encoded) = data_url
            .split_once(',')
            .ok_or_else(|| internal_error("captcha image data is invalid"))?;
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(encoded)
            .map_err(|_| internal_error("captcha image data is invalid"))?;
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| internal_error("system clock is before Unix epoch"))?
            .as_nanos();
        let path =
            std::env::temp_dir().join(format!("ubaa-captcha-{}-{nonce}.jpg", std::process::id()));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options
            .open(&path)
            .map_err(|_| internal_error("could not create captcha image"))?;
        file.write_all(&bytes)
            .map_err(|_| internal_error("could not write captcha image"))?;
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for CaptchaImage {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

fn write_json<O: Write, T: serde::Serialize>(stdout: &mut O, value: &T) -> std::io::Result<()> {
    serde_json::to_writer(&mut *stdout, value)?;
    writeln!(stdout)
}

fn invalid_input(message: impl Into<String>) -> UbaaError {
    UbaaError::new(ErrorCode::InvalidInput, ErrorKind::Input, false, message)
}

/// Construct the stable missing-session error used by the process entrypoint.
#[must_use]
pub fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "authentication is required",
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
    fn captcha_image_is_restricted_and_removed_on_drop() {
        let challenge = LoginChallenge {
            id: "captcha-fixture".into(),
            execution: "execution-fixture".into(),
            image_data_url: Some("data:image/jpeg;base64,RklYVFVSRS1JTUFHRQ==".into()),
        };
        let image = CaptchaImage::create(&challenge).unwrap();
        let path = image.path().to_path_buf();
        assert!(path.exists());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        drop(image);
        assert!(!path.exists());
    }

    #[test]
    fn sensitive_mask_handles_unicode_without_byte_slicing() {
        assert_eq!(mask_sensitive("ABCD1234"), "AB****34");
        assert_eq!(mask_sensitive("北航用户甲乙"), "北航**甲乙");
    }
}
