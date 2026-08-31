//! 带版本且不含秘密信息的路由配置。
#![allow(clippy::missing_errors_doc)]

use serde::Deserialize;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::domain::{ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 已解析的路由配置，不包含账号、Cookie 或登录状态。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RouteConfig {
    /// 本实现接受的架构版本。
    pub schema_version: u32,
    /// 未设置功能专属覆盖项时使用的默认策略。
    pub default: RoutePolicy,
    features: FeaturePolicies,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct FeaturePolicies {
    bykc: Option<RoutePolicy>,
    cgyy: Option<RoutePolicy>,
    libbook: Option<RoutePolicy>,
    ygdk: Option<RoutePolicy>,
    signin: Option<RoutePolicy>,
    schedule: Option<RoutePolicy>,
    exam: Option<RoutePolicy>,
    grades: Option<RoutePolicy>,
    classroom: Option<RoutePolicy>,
    spoc: Option<RoutePolicy>,
    judge: Option<RoutePolicy>,
    evaluation: Option<RoutePolicy>,
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
    bykc: Option<RoutePolicy>,
    cgyy: Option<RoutePolicy>,
    libbook: Option<RoutePolicy>,
    ygdk: Option<RoutePolicy>,
    signin: Option<RoutePolicy>,
    schedule: Option<RoutePolicy>,
    exam: Option<RoutePolicy>,
    grades: Option<RoutePolicy>,
    classroom: Option<RoutePolicy>,
    spoc: Option<RoutePolicy>,
    judge: Option<RoutePolicy>,
    evaluation: Option<RoutePolicy>,
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
    /// 解析带版本的 TOML，缺少内容时使用合同规定的默认值。
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
                bykc: raw.route.features.bykc,
                cgyy: raw.route.features.cgyy,
                libbook: raw.route.features.libbook,
                ygdk: raw.route.features.ygdk,
                signin: raw.route.features.signin,
                schedule: raw.route.features.schedule,
                exam: raw.route.features.exam,
                grades: raw.route.features.grades,
                classroom: raw.route.features.classroom,
                spoc: raw.route.features.spoc,
                judge: raw.route.features.judge,
                evaluation: raw.route.features.evaluation,
            },
        })
    }

    /// 从配置目录加载 `config.toml`；文件缺失时使用默认值。
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

    /// 序列化稳定且不含秘密信息的配置结构。
    #[must_use]
    pub fn to_toml(&self) -> String {
        let mut output = format!(
            "schema_version = {}\n\n[route]\ndefault = \"{}\"\n\n[route.features]\n",
            self.schema_version,
            policy_name(self.default)
        );
        for (feature, policy) in self.explicit_feature_policies() {
            if let Some(policy) = policy {
                output.push_str(feature.as_str());
                output.push_str(" = \"");
                output.push_str(policy_name(policy));
                output.push_str("\"\n");
            }
        }
        output
    }

    /// 替换全局策略并清除 App 不开放的功能覆盖项。
    pub(crate) fn replace_default_policy(&mut self, policy: RoutePolicy) {
        self.default = policy;
        self.features = FeaturePolicies::default();
    }

    /// 原子写入不含秘密信息的配置文件；在支持的平台上仅授予所有者权限。
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

    /// 返回功能的配置策略，未配置时回退到默认策略。
    #[must_use]
    pub fn feature(&self, feature: ReadonlyFeature) -> RoutePolicy {
        match feature {
            ReadonlyFeature::Bykc => self.features.bykc,
            ReadonlyFeature::Cgyy => self.features.cgyy,
            ReadonlyFeature::LibBook => self.features.libbook,
            ReadonlyFeature::Ygdk => self.features.ygdk,
            ReadonlyFeature::Signin => self.features.signin,
            ReadonlyFeature::Schedule => self.features.schedule,
            ReadonlyFeature::Exam => self.features.exam,
            ReadonlyFeature::Grades => self.features.grades,
            ReadonlyFeature::Classroom => self.features.classroom,
            ReadonlyFeature::Spoc => self.features.spoc,
            ReadonlyFeature::Judge => self.features.judge,
            ReadonlyFeature::Evaluation => self.features.evaluation,
        }
        .unwrap_or(self.default)
    }

    fn explicit_feature_policies(&self) -> [(ReadonlyFeature, Option<RoutePolicy>); 12] {
        [
            (ReadonlyFeature::Bykc, self.features.bykc),
            (ReadonlyFeature::Cgyy, self.features.cgyy),
            (ReadonlyFeature::LibBook, self.features.libbook),
            (ReadonlyFeature::Ygdk, self.features.ygdk),
            (ReadonlyFeature::Signin, self.features.signin),
            (ReadonlyFeature::Schedule, self.features.schedule),
            (ReadonlyFeature::Exam, self.features.exam),
            (ReadonlyFeature::Grades, self.features.grades),
            (ReadonlyFeature::Classroom, self.features.classroom),
            (ReadonlyFeature::Spoc, self.features.spoc),
            (ReadonlyFeature::Judge, self.features.judge),
            (ReadonlyFeature::Evaluation, self.features.evaluation),
        ]
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
    #[cfg(windows)]
    {
        let metadata = std::fs::symlink_metadata(dir).map_err(|_| invalid_config())?;
        if !metadata.file_type().is_dir() {
            return Err(invalid_config());
        }
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
    #[cfg(not(unix))]
    let _ = options;
}

fn restrict_open_file(file: &File) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|_| invalid_config())?;
    }
    #[cfg(windows)]
    {
        let metadata = file.metadata().map_err(|_| invalid_config())?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err(invalid_config());
        }
    }
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
    #[cfg(windows)]
    {
        let metadata = std::fs::symlink_metadata(dir).map_err(|_| invalid_config())?;
        if !metadata.file_type().is_dir() {
            return Err(invalid_config());
        }
    }
    Ok(())
}

#[cfg(test)]
mod platform_safety_tests {
    use super::*;

    #[test]
    fn 缺失配置目录不能通过限制与同步门禁() {
        let missing = std::env::temp_dir().join(format!(
            "ubaa-missing-config-directory-{}",
            std::process::id()
        ));
        assert!(restrict_config_directory(&missing).is_err());
        assert!(sync_config_directory(&missing).is_err());
    }
}

fn policy_name(policy: RoutePolicy) -> &'static str {
    match policy {
        RoutePolicy::Auto => "auto",
        RoutePolicy::Direct => "direct",
        RoutePolicy::WebVpn => "webvpn",
    }
}

/// 确定性策略解析使用的一行路由矩阵配置。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FeatureRouteConfig {
    /// 有证据支持的路线，仅在 `auto` 策略下覆盖网关探测结果。
    pub auto_route_override: Option<crate::domain::ConnectionMode>,
    /// 网关可达性未知时使用的回退路线。
    pub unknown_default: crate::domain::ConnectionMode,
    /// 发送请求前是否可以使用另一条已就绪路线。
    pub allow_ready_route_fallback: bool,
    /// 出现列入允许清单的网络错误时，是否可以在另一条路线重放请求。
    pub allow_network_fallback: bool,
}

impl FeatureRouteConfig {
    /// 返回只读功能有证据支持的初始矩阵行。
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
