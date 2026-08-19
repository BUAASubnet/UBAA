//! Versioned, non-secret route configuration.
#![allow(clippy::missing_errors_doc)]

use serde::Deserialize;
use std::path::{Path, PathBuf};

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
        let path = config_dir.as_ref().join("config.toml");
        match std::fs::read_to_string(&path) {
            Ok(input) => Self::parse(&input),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(_) => Err(invalid_config()),
        }
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
        let path = dir.join("config.toml");
        let temporary = dir.join(".config.toml.tmp");
        std::fs::write(&temporary, self.to_toml()).map_err(|_| invalid_config())?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&temporary, std::fs::Permissions::from_mode(0o600))
                .map_err(|_| invalid_config())?;
        }
        std::fs::rename(&temporary, &path).map_err(|_| invalid_config())?;
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
    /// Evidence-backed route that overrides DNS only while the user policy is `auto`.
    pub auto_route_override: Option<crate::domain::ConnectionMode>,
    /// Fallback route when DNS is unknown.
    pub unknown_default: crate::domain::ConnectionMode,
    /// Whether another ready route may be used before sending a request.
    pub allow_ready_route_fallback: bool,
    /// Whether an allow-listed network error may be replayed on the other route.
    pub allow_network_fallback: bool,
}

impl FeatureRouteConfig {
    /// Return the evidence-backed initial row for a read-only feature.
    #[must_use]
    pub const fn for_feature(feature: ReadonlyFeature) -> Self {
        Self {
            auto_route_override: match feature {
                ReadonlyFeature::Judge => Some(crate::domain::ConnectionMode::WebVpn),
                _ => None,
            },
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
