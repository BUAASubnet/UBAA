//! Versioned, non-secret route configuration.
#![allow(clippy::missing_errors_doc)]

use serde::Deserialize;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::domain::{ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// Parsed route configuration. It contains no account, Cookie, or login state.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RouteConfig {
    /// Schema version accepted by this implementation.
    pub schema_version: u32,
    /// Default policy for commands without a feature-specific override.
    pub default: RoutePolicy,
    features: FeaturePolicies,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct FeaturePolicies {
    schedule: Option<RoutePolicy>,
    exam: Option<RoutePolicy>,
    grades: Option<RoutePolicy>,
    classroom: Option<RoutePolicy>,
    spoc: Option<RoutePolicy>,
    judge: Option<RoutePolicy>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawConfig {
    #[serde(default = "default_schema_version")]
    schema_version: u32,
    #[serde(default)]
    route: RawRoute,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawRoute {
    #[serde(default)]
    default: RoutePolicy,
    #[serde(default)]
    features: RawFeatures,
}

#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawFeatures {
    schedule: Option<RoutePolicy>,
    exam: Option<RoutePolicy>,
    grades: Option<RoutePolicy>,
    classroom: Option<RoutePolicy>,
    spoc: Option<RoutePolicy>,
    judge: Option<RoutePolicy>,
}

const fn default_schema_version() -> u32 {
    1
}

impl Default for RouteConfig {
    fn default() -> Self {
        Self {
            schema_version: 1,
            default: RoutePolicy::Auto,
            features: FeaturePolicies::default(),
        }
    }
}

impl RouteConfig {
    /// Parse versioned TOML, using the contract defaults for missing content.
    pub fn parse(input: &str) -> Result<Self> {
        if input.trim().is_empty() {
            return Ok(Self::default());
        }
        let raw: RawConfig = toml::from_str(input).map_err(|_| invalid_config())?;
        if raw.schema_version != 1 {
            return Err(invalid_config());
        }
        Ok(Self {
            schema_version: raw.schema_version,
            default: raw.route.default,
            features: FeaturePolicies {
                schedule: raw.route.features.schedule,
                exam: raw.route.features.exam,
                grades: raw.route.features.grades,
                classroom: raw.route.features.classroom,
                spoc: raw.route.features.spoc,
                judge: raw.route.features.judge,
            },
        })
    }

    /// Load `config.toml` from a configuration directory; missing files use defaults.
    pub fn load(config_dir: impl AsRef<Path>) -> Result<Self> {
        let dir = config_dir.as_ref();
        if !validate_config_directory(dir, true)? {
            return Ok(Self::default());
        }
        restrict_config_directory(dir)?;

        let path = dir.join("config.toml");
        if !validate_config_target(&path)? {
            return Ok(Self::default());
        }

        let mut options = OpenOptions::new();
        options.read(true);
        prevent_symlink_following(&mut options);

        let mut file = options.open(path).map_err(|_| invalid_config())?;
        if !file
            .metadata()
            .map_err(|_| invalid_config())?
            .file_type()
            .is_file()
        {
            return Err(invalid_config());
        }

        let mut input = String::new();
        file.read_to_string(&mut input)
            .map_err(|_| invalid_config())?;
        Self::parse(&input)
    }

    /// Serialize the stable, non-secret config shape.
    #[must_use]
    pub fn to_toml(&self) -> String {
        let mut output = format!(
            "schema_version = {}\n\n[route]\ndefault = \"{}\"\n\n[route.features]\n",
            self.schema_version,
            policy_name(self.default)
        );
        for feature in [
            ReadonlyFeature::Schedule,
            ReadonlyFeature::Exam,
            ReadonlyFeature::Grades,
            ReadonlyFeature::Classroom,
            ReadonlyFeature::Spoc,
            ReadonlyFeature::Judge,
        ] {
            output.push_str(feature.as_str());
            output.push_str(" = \"");
            output.push_str(policy_name(self.feature(feature)));
            output.push_str("\"\n");
        }
        output
    }

    /// Atomically write the non-secret config file with owner-only permissions where supported.
    pub fn save(&self, config_dir: impl AsRef<Path>) -> Result<PathBuf> {
        let dir = config_dir.as_ref();
        std::fs::create_dir_all(dir).map_err(|_| invalid_config())?;
        validate_config_directory(dir, false)?;
        restrict_config_directory(dir)?;

        let path = dir.join("config.toml");
        validate_config_target(&path)?;

        let (temporary, mut file) = create_temporary_config(dir)?;
        let write_result = (|| {
            file.write_all(self.to_toml().as_bytes())
                .map_err(|_| invalid_config())?;
            file.flush().map_err(|_| invalid_config())?;
            file.sync_all().map_err(|_| invalid_config())?;
            Ok(())
        })();
        drop(file);
        if let Err(error) = write_result {
            remove_temporary_config(&temporary);
            return Err(error);
        }

        if let Err(error) = validate_config_target(&path) {
            remove_temporary_config(&temporary);
            return Err(error);
        }
        if std::fs::rename(&temporary, &path).is_err() {
            remove_temporary_config(&temporary);
            return Err(invalid_config());
        }
        sync_config_directory(dir)?;
        Ok(path)
    }

    /// Return the configured policy for a feature, falling back to the default.
    #[must_use]
    pub fn feature(&self, feature: ReadonlyFeature) -> RoutePolicy {
        match feature {
            ReadonlyFeature::Schedule => self.features.schedule,
            ReadonlyFeature::Exam => self.features.exam,
            ReadonlyFeature::Grades => self.features.grades,
            ReadonlyFeature::Classroom => self.features.classroom,
            ReadonlyFeature::Spoc => self.features.spoc,
            ReadonlyFeature::Judge => self.features.judge,
        }
        .unwrap_or(self.default)
    }
}

fn validate_config_directory(dir: &Path, missing_allowed: bool) -> Result<bool> {
    match std::fs::symlink_metadata(dir) {
        Ok(metadata) if metadata.file_type().is_dir() => Ok(true),
        Err(error) if missing_allowed && error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Ok(_) | Err(_) => Err(invalid_config()),
    }
}

fn validate_config_target(path: &Path) -> Result<bool> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_file() => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Ok(_) | Err(_) => Err(invalid_config()),
    }
}

fn restrict_config_directory(dir: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut options = OpenOptions::new();
        options.read(true);
        prevent_symlink_following(&mut options);
        let directory = options.open(dir).map_err(|_| invalid_config())?;
        if !directory
            .metadata()
            .map_err(|_| invalid_config())?
            .file_type()
            .is_dir()
        {
            return Err(invalid_config());
        }
        directory
            .set_permissions(std::fs::Permissions::from_mode(0o700))
            .map_err(|_| invalid_config())?;
    }
    Ok(())
}

fn create_temporary_config(dir: &Path) -> Result<(PathBuf, File)> {
    static NEXT_TEMPORARY: AtomicU64 = AtomicU64::new(0);

    for _ in 0..128 {
        let sequence = NEXT_TEMPORARY.fetch_add(1, Ordering::Relaxed);
        let path = dir.join(format!(
            ".config.toml.tmp.{}.{}",
            std::process::id(),
            sequence
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        restrict_file_creation(&mut options);
        prevent_symlink_following(&mut options);
        match options.open(&path) {
            Ok(file) => {
                if restrict_open_file(&file).is_err() {
                    remove_temporary_config(&path);
                    return Err(invalid_config());
                }
                return Ok((path, file));
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(_) => return Err(invalid_config()),
        }
    }

    Err(invalid_config())
}

fn remove_temporary_config(path: &Path) {
    let _ = std::fs::remove_file(path);
}

fn restrict_file_creation(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600);
    }
}

fn restrict_open_file(file: &File) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|_| invalid_config())?;
    }
    #[cfg(not(unix))]
    let _ = file;
    Ok(())
}

fn prevent_symlink_following(options: &mut OpenOptions) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt as _;
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        options.custom_flags(FILE_FLAG_OPEN_REPARSE_POINT);
    }
    #[cfg(not(any(unix, windows)))]
    let _ = options;
}

fn sync_config_directory(dir: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        File::open(dir)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| invalid_config())?;
    }
    Ok(())
}

fn policy_name(policy: RoutePolicy) -> &'static str {
    match policy {
        RoutePolicy::Auto => "auto",
        RoutePolicy::Direct => "direct",
        RoutePolicy::WebVpn => "webvpn",
    }
}

/// One route-matrix row used by deterministic policy resolution.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FeatureRouteConfig {
    /// Evidence-backed route that overrides gateway detection only for `auto` policy.
    pub auto_route_override: Option<crate::domain::ConnectionMode>,
    /// Fallback route when gateway reachability is unknown.
    pub unknown_default: crate::domain::ConnectionMode,
    /// Whether another ready route may be used before sending a request.
    pub allow_ready_route_fallback: bool,
    /// Whether an allow-listed network error may be replayed on the other route.
    pub allow_network_fallback: bool,
}

impl FeatureRouteConfig {
    /// Return the evidence-backed initial row for a read-only feature.
    #[must_use]
    pub const fn for_feature(_feature: ReadonlyFeature) -> Self {
        Self {
            auto_route_override: None,
            unknown_default: crate::domain::ConnectionMode::Direct,
            allow_ready_route_fallback: false,
            allow_network_fallback: false,
        }
    }
}

fn invalid_config() -> UbaaError {
    UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "route configuration is invalid",
    )
}
