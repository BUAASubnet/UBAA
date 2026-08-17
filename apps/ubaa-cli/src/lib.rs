//! Command-line parsing and presentation for UBAA Core.

use std::fs::OpenOptions;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use base64::Engine as _;
use clap::{Args, Parser, Subcommand, ValueEnum};
use serde_json::{Value, json};
use ubaa_core::domain::{
    AuthStatus, ConnectionMode, LoginChallenge, LoginInput, SecretValue, UserProfile,
};
use ubaa_core::error::{ErrorCode, ErrorKind, ExitCode, Result, UbaaError};
use ubaa_core::facade::UbaaClient;
use ubaa_core::output::{JSON_SCHEMA_VERSION, JsonEnvelope, JsonMeta};
use ubaa_core::ports::HttpTransport;
use ubaa_core::session::SessionStore;

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

/// Top-level command groups.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Authenticate and manage the persisted session.
    Auth(AuthArgs),
    /// Query the authenticated User Center profile.
    User(UserArgs),
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
    #[arg(long, value_enum)]
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
            })
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
}

#[async_trait]
impl<T, S> CliBackend for UbaaClient<T, S>
where
    T: HttpTransport + Send,
    S: SessionStore + Send,
{
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
    };

    render_result(cli.json, mode, result, stdout, stderr)
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

enum CommandOutput {
    Profile(UserProfile),
    Status(AuthStatus),
    Logout(Value),
}

fn render_result<O: Write, E: Write>(
    json_mode: bool,
    mode: ConnectionMode,
    result: Result<CommandOutput>,
    stdout: &mut O,
    stderr: &mut E,
) -> i32 {
    match result {
        Ok(output) => {
            if json_mode {
                let value = match output {
                    CommandOutput::Profile(profile) => json!(profile),
                    CommandOutput::Status(status) => json!(status),
                    CommandOutput::Logout(value) => value,
                };
                if write_json(stdout, &JsonEnvelope::success(value, mode)).is_err() {
                    return ExitCode::Internal as i32;
                }
            } else if render_human(output, stdout).is_err() {
                return ExitCode::Internal as i32;
            }
            ExitCode::Success as i32
        }
        Err(error) => render_error(json_mode, Some(mode), error, stdout, stderr),
    }
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
