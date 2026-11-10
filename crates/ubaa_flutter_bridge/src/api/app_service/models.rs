//! 应用服务在 FRB 边界上的白名单维度与状态。

use super::super::client::BridgeErrorKind;
use ubaa_core::facade::{ErrorKind, app_service as core};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAppServicePlatform {
    Android,
    Ios,
    Ohos,
    Macos,
    Windows,
    Linux,
}

impl From<BridgeAppServicePlatform> for core::Platform {
    fn from(value: BridgeAppServicePlatform) -> Self {
        match value {
            BridgeAppServicePlatform::Android => Self::Android,
            BridgeAppServicePlatform::Ios => Self::Ios,
            BridgeAppServicePlatform::Ohos => Self::Ohos,
            BridgeAppServicePlatform::Macos => Self::Macos,
            BridgeAppServicePlatform::Windows => Self::Windows,
            BridgeAppServicePlatform::Linux => Self::Linux,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAppServiceSurface {
    Gui,
    Command,
}

impl From<BridgeAppServiceSurface> for core::Surface {
    fn from(value: BridgeAppServiceSurface) -> Self {
        match value {
            BridgeAppServiceSurface::Gui => Self::Gui,
            BridgeAppServiceSurface::Command => Self::Command,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryCounter {
    AppStarted,
    AuthStarted,
    AuthSucceeded,
    SessionExpired,
    RouteResolved,
    FeatureLoaded,
}

impl From<BridgeTelemetryCounter> for core::CounterEvent {
    fn from(value: BridgeTelemetryCounter) -> Self {
        match value {
            BridgeTelemetryCounter::AppStarted => Self::AppStarted,
            BridgeTelemetryCounter::AuthStarted => Self::AuthStarted,
            BridgeTelemetryCounter::AuthSucceeded => Self::AuthSucceeded,
            BridgeTelemetryCounter::SessionExpired => Self::SessionExpired,
            BridgeTelemetryCounter::RouteResolved => Self::RouteResolved,
            BridgeTelemetryCounter::FeatureLoaded => Self::FeatureLoaded,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryFeature {
    App,
    Auth,
    Schedule,
    Exam,
    Grades,
    Bykc,
    Classroom,
    Spoc,
    Judge,
    Libbook,
    Signin,
    Cgyy,
    Ygdk,
    Evaluation,
}

impl From<BridgeTelemetryFeature> for core::Feature {
    fn from(value: BridgeTelemetryFeature) -> Self {
        match value {
            BridgeTelemetryFeature::App => Self::App,
            BridgeTelemetryFeature::Auth => Self::Auth,
            BridgeTelemetryFeature::Schedule => Self::Schedule,
            BridgeTelemetryFeature::Exam => Self::Exam,
            BridgeTelemetryFeature::Grades => Self::Grades,
            BridgeTelemetryFeature::Bykc => Self::Bykc,
            BridgeTelemetryFeature::Classroom => Self::Classroom,
            BridgeTelemetryFeature::Spoc => Self::Spoc,
            BridgeTelemetryFeature::Judge => Self::Judge,
            BridgeTelemetryFeature::Libbook => Self::Libbook,
            BridgeTelemetryFeature::Signin => Self::Signin,
            BridgeTelemetryFeature::Cgyy => Self::Cgyy,
            BridgeTelemetryFeature::Ygdk => Self::Ygdk,
            BridgeTelemetryFeature::Evaluation => Self::Evaluation,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryRoute {
    Direct,
    Webvpn,
    None,
}

impl From<BridgeTelemetryRoute> for core::Route {
    fn from(value: BridgeTelemetryRoute) -> Self {
        match value {
            BridgeTelemetryRoute::Direct => Self::Direct,
            BridgeTelemetryRoute::Webvpn => Self::Webvpn,
            BridgeTelemetryRoute::None => Self::None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryResult {
    Success,
    Empty,
    Failure,
}

impl From<BridgeTelemetryResult> for core::CounterResult {
    fn from(value: BridgeTelemetryResult) -> Self {
        match value {
            BridgeTelemetryResult::Success => Self::Success,
            BridgeTelemetryResult::Empty => Self::Empty,
            BridgeTelemetryResult::Failure => Self::Failure,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryError {
    AuthFailed,
    FeatureFailed,
    UiErrorShown,
    Crash,
}

impl From<BridgeTelemetryError> for core::ErrorEvent {
    fn from(value: BridgeTelemetryError) -> Self {
        match value {
            BridgeTelemetryError::AuthFailed => Self::AuthFailed,
            BridgeTelemetryError::FeatureFailed => Self::FeatureFailed,
            BridgeTelemetryError::UiErrorShown => Self::UiErrorShown,
            BridgeTelemetryError::Crash => Self::Crash,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryTiming {
    ColdStart,
    FirstContent,
    Auth,
    FeatureLoad,
}

impl From<BridgeTelemetryTiming> for core::TimingMetric {
    fn from(value: BridgeTelemetryTiming) -> Self {
        match value {
            BridgeTelemetryTiming::ColdStart => Self::ColdStart,
            BridgeTelemetryTiming::FirstContent => Self::FirstContent,
            BridgeTelemetryTiming::Auth => Self::Auth,
            BridgeTelemetryTiming::FeatureLoad => Self::FeatureLoad,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTelemetryBucket {
    Lt250,
    Lt500,
    Lt1000,
    Lt2000,
    Lt5000,
    Lt10000,
    Ge10000,
}

impl From<BridgeTelemetryBucket> for core::TimingBucket {
    fn from(value: BridgeTelemetryBucket) -> Self {
        match value {
            BridgeTelemetryBucket::Lt250 => Self::Lt250,
            BridgeTelemetryBucket::Lt500 => Self::Lt500,
            BridgeTelemetryBucket::Lt1000 => Self::Lt1000,
            BridgeTelemetryBucket::Lt2000 => Self::Lt2000,
            BridgeTelemetryBucket::Lt5000 => Self::Lt5000,
            BridgeTelemetryBucket::Lt10000 => Self::Lt10000,
            BridgeTelemetryBucket::Ge10000 => Self::Ge10000,
        }
    }
}

impl From<BridgeErrorKind> for ErrorKind {
    fn from(value: BridgeErrorKind) -> Self {
        match value {
            BridgeErrorKind::Input => Self::Input,
            BridgeErrorKind::Authentication => Self::Authentication,
            BridgeErrorKind::Network => Self::Network,
            BridgeErrorKind::Upstream => Self::Upstream,
            BridgeErrorKind::Parse => Self::Parse,
            BridgeErrorKind::Internal => Self::Internal,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAppServiceConsent {
    Unasked,
    Agreed,
    ReconsentRequired,
    Basic,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeAppServiceEraseOutcome {
    Succeeded,
    Pending,
    Unavailable,
}

impl From<core::EraseAttempt> for BridgeAppServiceEraseOutcome {
    fn from(value: core::EraseAttempt) -> Self {
        match value {
            core::EraseAttempt::Completed => Self::Succeeded,
            core::EraseAttempt::Pending => Self::Pending,
            core::EraseAttempt::NotAttempted => Self::Unavailable,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[allow(clippy::struct_excessive_bools)] // 布尔值分别表示配置、硬关闭、保存值和删除标记。
pub struct BridgeAppServiceState {
    pub available: bool,
    pub telemetry_allowed: bool,
    pub consent: BridgeAppServiceConsent,
    pub policy_version: u32,
    pub agreed_policy_version: Option<u32>,
    pub telemetry_enabled: bool,
    pub can_erase: bool,
    pub erase_pending: bool,
}

impl BridgeAppServiceState {
    pub(super) fn from_core(value: core::AppServiceState, policy_version: u32) -> Self {
        Self {
            available: value.available,
            telemetry_allowed: !value.telemetry_hard_closed,
            consent: match value.consent {
                core::Consent::Unasked => BridgeAppServiceConsent::Unasked,
                core::Consent::Agreed(_) => BridgeAppServiceConsent::Agreed,
                core::Consent::ReconsentRequired(_) => BridgeAppServiceConsent::ReconsentRequired,
                core::Consent::Basic => BridgeAppServiceConsent::Basic,
            },
            policy_version,
            agreed_policy_version: value.agreed_policy_version,
            telemetry_enabled: value.telemetry_enabled.unwrap_or(false),
            can_erase: value.install_id.is_some(),
            erase_pending: value.erasing_install_id.is_some(),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BridgeAppServiceUpload {
    pub erase: BridgeAppServiceEraseOutcome,
    pub batches_sent: u8,
}
