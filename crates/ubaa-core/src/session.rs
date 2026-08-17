//! Cookie jar and restricted on-disk session persistence.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use url::Url;

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpResponse;

/// Cookie attributes retained for safe request filtering and persistence.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct StoredCookie {
    /// Cookie name.
    pub name: String,
    /// Cookie value; this is session material and is never logged.
    pub value: String,
    /// Effective domain.
    pub domain: String,
    /// Whether the cookie was host-only.
    pub host_only: bool,
    /// Effective path.
    pub path: String,
    /// Secure-only flag.
    pub secure: bool,
    /// Absolute expiration timestamp in Unix seconds.
    pub expires_at: Option<i64>,
    /// Creation timestamp in Unix seconds, used with Max-Age.
    pub created_at: i64,
    /// Max-Age in seconds when supplied.
    pub max_age: Option<i64>,
}

impl std::fmt::Debug for StoredCookie {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StoredCookie")
            .field("name", &"[REDACTED]")
            .field("value", &"[REDACTED]")
            .field("domain", &"[REDACTED]")
            .field("host_only", &self.host_only)
            .field("path", &"[REDACTED]")
            .field("secure", &self.secure)
            .field("expires_at", &self.expires_at)
            .field("created_at", &self.created_at)
            .field("max_age", &self.max_age)
            .finish()
    }
}

impl StoredCookie {
    /// Construct a cookie fixture for deterministic tests.
    pub fn fixture(name: impl Into<String>, value: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            value: value.into(),
            domain: "sso.buaa.edu.cn".into(),
            host_only: true,
            path: "/".into(),
            secure: true,
            expires_at: None,
            created_at: 1_000,
            max_age: None,
        }
    }
}

/// In-memory Cookie jar with RFC-inspired domain/path/expiry filtering.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CookieJar {
    cookies: Vec<StoredCookie>,
}

impl CookieJar {
    /// Store all response `Set-Cookie` values for a request URL.
    ///
    /// # Errors
    ///
    /// Returns an internal session error for malformed request URLs, clock values, or cookies.
    pub fn store_response(
        &mut self,
        response: &HttpResponse,
        request_url: &str,
        now: SystemTime,
    ) -> Result<()> {
        let url =
            Url::parse(request_url).map_err(|_| session_error("invalid Cookie request URL"))?;
        let now_seconds = unix_seconds(now)?;
        for raw in header_values(&response.headers, "set-cookie") {
            let Some(cookie) = parse_cookie(raw, &url, now_seconds)? else {
                continue;
            };
            self.cookies.retain(|existing| {
                !(existing.name == cookie.name
                    && existing.domain == cookie.domain
                    && existing.path == cookie.path)
            });
            if cookie.max_age.is_none_or(|age| age > 0)
                && cookie
                    .expires_at
                    .is_none_or(|expires| expires > now_seconds)
            {
                self.cookies.push(cookie);
            }
        }
        self.purge_expired(now_seconds);
        Ok(())
    }

    /// Build the filtered Cookie request header for a URL.
    ///
    /// # Errors
    ///
    /// Returns an internal session error for a malformed URL or clock value.
    pub fn cookie_header(&mut self, request_url: &str, now: SystemTime) -> Result<String> {
        let url = Url::parse(request_url).map_err(|_| session_error("invalid Cookie URL"))?;
        let now_seconds = unix_seconds(now)?;
        self.purge_expired(now_seconds);
        Ok(self
            .cookies
            .iter()
            .filter(|cookie| cookie_matches(cookie, &url, now_seconds))
            .map(|cookie| format!("{}={}", cookie.name, cookie.value))
            .collect::<Vec<_>>()
            .join("; "))
    }

    /// Borrow currently retained cookies for session serialization.
    #[must_use]
    pub fn cookies(&self) -> &[StoredCookie] {
        &self.cookies
    }

    /// Replace the jar contents from a persisted session.
    pub fn replace(&mut self, cookies: Vec<StoredCookie>) {
        self.cookies = cookies;
    }

    fn purge_expired(&mut self, now: i64) {
        self.cookies.retain(|cookie| !is_expired(cookie, now));
    }
}

/// Snapshot persisted across CLI processes.
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct SessionSnapshot {
    /// Connection strategy used by this session.
    pub mode: ConnectionMode,
    /// Filtered upstream cookies.
    pub cookies: Vec<StoredCookie>,
    /// Unix timestamp when authentication succeeded.
    pub authenticated_at: i64,
    /// Unix timestamp of the last successful validation.
    pub last_activity: i64,
}

impl std::fmt::Debug for SessionSnapshot {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SessionSnapshot")
            .field("mode", &self.mode)
            .field("cookie_count", &self.cookies.len())
            .field("authenticated_at", &self.authenticated_at)
            .field("last_activity", &self.last_activity)
            .finish()
    }
}

/// Result of validating a persisted session.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionValidation {
    /// Upstream confirmed a valid session.
    Valid,
    /// Upstream explicitly rejected or redirected the session.
    Invalid,
    /// Upstream returned a temporary server failure.
    ServerError,
    /// The request timed out before a conclusion.
    Timeout,
}

impl SessionValidation {
    /// Whether local authentication state must be cleared.
    #[must_use]
    pub const fn should_clear(self) -> bool {
        matches!(self, Self::Invalid)
    }
}

/// Persistence port for one client-owned session.
pub trait SessionStore: Send + Sync {
    /// Load a session snapshot, if present.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence or parsing error.
    fn load(&self) -> Result<Option<SessionSnapshot>>;
    /// Replace the persisted snapshot.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence or serialization error.
    fn save(&self, snapshot: &SessionSnapshot) -> Result<()>;
    /// Remove local session state.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when the state cannot be removed.
    fn clear(&self) -> Result<()>;
}

/// File-backed session store using `<config-dir>/session.json`.
#[derive(Clone, Debug)]
pub struct FileSessionStore {
    path: PathBuf,
}

impl FileSessionStore {
    /// Create a restricted configuration directory and session path.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when the directory cannot be created or restricted.
    pub fn new(config_dir: impl AsRef<Path>) -> Result<Self> {
        let config_dir = config_dir.as_ref();
        fs::create_dir_all(config_dir)
            .map_err(|_| session_error("could not create config directory"))?;
        restrict_directory(config_dir)?;
        Ok(Self {
            path: config_dir.join("session.json"),
        })
    }

    /// Return the exact session path for diagnostics and tests.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl SessionStore for FileSessionStore {
    fn load(&self) -> Result<Option<SessionSnapshot>> {
        if !self.path.exists() {
            return Ok(None);
        }
        let body =
            fs::read_to_string(&self.path).map_err(|_| session_error("could not read session"))?;
        serde_json::from_str(&body)
            .map(Some)
            .map_err(|_| session_error("session format is invalid"))
    }

    fn save(&self, snapshot: &SessionSnapshot) -> Result<()> {
        let body = serde_json::to_vec_pretty(snapshot)
            .map_err(|_| session_error("could not encode session"))?;
        let temporary = self.path.with_extension("json.tmp");
        let mut options = OpenOptions::new();
        options.write(true).create(true).truncate(true);
        restrict_file_creation(&mut options);
        let file = options
            .open(&temporary)
            .map_err(|_| session_error("could not open session"))?;
        let mut writer = std::io::BufWriter::new(file);
        writer
            .write_all(&body)
            .map_err(|_| session_error("could not write session"))?;
        writer
            .flush()
            .map_err(|_| session_error("could not flush session"))?;
        drop(writer);
        restrict_file(&temporary)?;
        fs::rename(&temporary, &self.path)
            .map_err(|_| session_error("could not replace session"))?;
        restrict_file(&self.path)?;
        Ok(())
    }

    fn clear(&self) -> Result<()> {
        match fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(session_error("could not clear session")),
        }
    }
}

fn parse_cookie(raw: &str, url: &Url, created_at: i64) -> Result<Option<StoredCookie>> {
    let mut parts = raw.split(';');
    let Some((name, value)) = parts.next().and_then(|part| part.trim().split_once('=')) else {
        return Err(session_error("upstream Set-Cookie has no name/value"));
    };
    let host = url
        .host_str()
        .ok_or_else(|| session_error("Cookie URL has no host"))?
        .to_ascii_lowercase();
    let mut cookie = StoredCookie {
        name: name.trim().to_string(),
        value: value.trim().to_string(),
        domain: host.clone(),
        host_only: true,
        path: default_cookie_path(url.path()),
        secure: false,
        expires_at: None,
        created_at,
        max_age: None,
    };
    if cookie.name.is_empty() {
        return Err(session_error("upstream Set-Cookie has an empty name"));
    }
    for attribute in parts {
        let attribute = attribute.trim();
        if attribute.eq_ignore_ascii_case("secure") {
            cookie.secure = true;
        } else if let Some((key, value)) = attribute.split_once('=') {
            match key.trim().to_ascii_lowercase().as_str() {
                "domain" => {
                    let domain = value.trim().trim_start_matches('.').to_ascii_lowercase();
                    if !domain_matches(&host, &domain) {
                        return Ok(None);
                    }
                    cookie.domain = domain;
                    cookie.host_only = false;
                }
                "path" if value.trim().starts_with('/') => cookie.path = value.trim().to_string(),
                "max-age" => cookie.max_age = value.trim().parse().ok(),
                "expires" => {
                    cookie.expires_at = httpdate::parse_http_date(value.trim())
                        .ok()
                        .and_then(|time| unix_seconds(time).ok());
                }
                _ => {}
            }
        }
    }
    Ok(Some(cookie))
}

fn cookie_matches(cookie: &StoredCookie, url: &Url, now: i64) -> bool {
    let Some(host) = url.host_str() else {
        return false;
    };
    let domain_match = if cookie.host_only {
        host.eq_ignore_ascii_case(&cookie.domain)
    } else {
        domain_matches(host, &cookie.domain)
    };
    let path_match = path_matches(url.path(), &cookie.path);
    let secure_match = !cookie.secure || url.scheme().eq_ignore_ascii_case("https");
    domain_match && path_match && secure_match && !is_expired(cookie, now)
}

fn is_expired(cookie: &StoredCookie, now: i64) -> bool {
    cookie.expires_at.is_some_and(|expires| expires <= now)
        || cookie
            .max_age
            .is_some_and(|age| age <= 0 || now >= cookie.created_at.saturating_add(age))
}

fn default_cookie_path(path: &str) -> String {
    if path.is_empty() || !path.starts_with('/') || path == "/" {
        return "/".into();
    }
    path.rsplit_once('/').map_or_else(
        || "/".into(),
        |(prefix, _)| {
            if prefix.is_empty() {
                "/".into()
            } else {
                prefix.into()
            }
        },
    )
}

fn path_matches(request: &str, cookie: &str) -> bool {
    if request == cookie {
        return true;
    }
    request
        .strip_prefix(cookie)
        .is_some_and(|rest| cookie.ends_with('/') || rest.starts_with('/'))
}

fn domain_matches(host: &str, domain: &str) -> bool {
    host.eq_ignore_ascii_case(domain) || host.to_ascii_lowercase().ends_with(&format!(".{domain}"))
}

fn header_values<'a>(
    headers: &'a std::collections::BTreeMap<String, Vec<String>>,
    name: &str,
) -> impl Iterator<Item = &'a str> {
    headers
        .iter()
        .filter(move |(key, _)| key.eq_ignore_ascii_case(name))
        .flat_map(|(_, values)| values.iter().map(String::as_str))
}

fn unix_seconds(time: SystemTime) -> Result<i64> {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_secs()).unwrap_or(i64::MAX))
        .map_err(|_| session_error("system clock is before Unix epoch"))
}

fn session_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        false,
        message,
    )
}

fn restrict_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .map_err(|_| session_error("could not restrict config directory"))?;
    }
    Ok(())
}

fn restrict_file_creation(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
}

fn restrict_file(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))
            .map_err(|_| session_error("could not restrict session file"))?;
    }
    Ok(())
}
