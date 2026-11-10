//! 应用服务载荷使用的白名单维度。

use std::sync::LazyLock;

use regex::Regex;
use serde::{Deserialize, Serialize};

use crate::error::ErrorKind;

static APP_VERSION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\A[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9]+)?\z")
        .expect("版本白名单必须是合法正则")
});
static ERROR_CODE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\A[a-z][a-z0-9_]{0,47}\z").expect("错误码白名单必须是合法正则"));
static CRASH_CODE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\A[A-Za-z_][A-Za-z0-9_]{0,63}\z").expect("崩溃类型白名单必须是合法正则")
});
static SOURCE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"\A(?:package:ubaa_[a-z_]+/[A-Za-z0-9_/]+\.dart|crates/ubaa_[a-z_]+/src/[A-Za-z0-9_/]+\.rs):[0-9]+\z",
    )
    .expect("源码位置白名单必须是合法正则")
});

// 序列化白名单与测试枚举使用同一组变体，避免新变体漏掉合同校验。
macro_rules! wire_enum {
    ($(#[$meta:meta])* pub enum $name:ident { $($(#[$field:meta])* $variant:ident),+ $(,)? }) => {
        #[derive(Clone, Copy, Deserialize, Eq, PartialEq, Serialize)]
        $(#[$meta])*
        pub enum $name {
            $($(#[$field])* $variant),+
        }

        #[cfg(test)]
        impl $name {
            const ALL: &'static [Self] = &[$(Self::$variant),+];
        }
    };
}

wire_enum! {
    /// 安装包的平台。
    #[derive(Debug)]
    #[serde(rename_all = "snake_case")]
    pub enum Platform {
        Android,
        Ios,
        Ohos,
        Macos,
        Windows,
        Linux,
    }
}

wire_enum! {
    /// 构建期选择的分发渠道。
    #[derive(Debug)]
    #[serde(rename_all = "snake_case")]
    pub enum Channel {
        Github,
        AppStore,
        AppGallery,
    }
}

impl Channel {
    /// 解析合同规定的分发渠道。
    #[must_use]
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "github" => Some(Self::Github),
            "app_store" => Some(Self::AppStore),
            "app_gallery" => Some(Self::AppGallery),
            _ => None,
        }
    }
}

wire_enum! {
    /// 事件来源及应用服务请求发起方。
    #[derive(Debug, Ord, PartialOrd)]
    #[serde(rename_all = "snake_case")]
    pub enum Surface {
        Gui,
        Command,
    }
}

wire_enum! {
    /// 允许统计的功能，取值与 Dart `FeatureId.wireName` 一致，另含应用和认证。
    #[serde(rename_all = "snake_case")]
    pub enum Feature {
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
}

wire_enum! {
    /// 业务动作使用的学校路线；无路线时记为 `none`。
    #[serde(rename_all = "snake_case")]
    pub enum Route {
        Direct,
        Webvpn,
        None,
    }
}

wire_enum! {
    /// 普通计数事件。
    #[serde(rename_all = "snake_case")]
    pub enum CounterEvent {
        AppStarted,
        AuthStarted,
        AuthSucceeded,
        SessionExpired,
        RouteResolved,
        FeatureLoaded,
    }
}

wire_enum! {
    /// 普通计数的业务结果。
    #[serde(rename_all = "snake_case")]
    pub enum CounterResult {
        Success,
        Empty,
        Failure,
    }
}

/// 普通计数的聚合维度。
#[derive(Clone, Copy, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CounterDimensions {
    pub event: CounterEvent,
    pub feature: Feature,
    pub route: Route,
    pub result: CounterResult,
}

wire_enum! {
    /// 错误计数事件。
    #[serde(rename_all = "snake_case")]
    pub enum ErrorEvent {
        AuthFailed,
        FeatureFailed,
        UiErrorShown,
        Crash,
    }
}

/// 错误计数的聚合维度，动态字符串由 Core 在入队时校验。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ErrorDimensions {
    pub event: ErrorEvent,
    pub feature: Feature,
    pub route: Route,
    pub error_code: String,
    pub error_kind: ErrorKind,
    pub retryable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

wire_enum! {
    /// 可记录耗时的业务动作。
    #[serde(rename_all = "snake_case")]
    pub enum TimingMetric {
        ColdStart,
        FirstContent,
        Auth,
        FeatureLoad,
    }
}

wire_enum! {
    /// 耗时所属区间，以毫秒为单位。
    pub enum TimingBucket {
        #[serde(rename = "lt_250")]
        Lt250,
        #[serde(rename = "lt_500")]
        Lt500,
        #[serde(rename = "lt_1000")]
        Lt1000,
        #[serde(rename = "lt_2000")]
        Lt2000,
        #[serde(rename = "lt_5000")]
        Lt5000,
        #[serde(rename = "lt_10000")]
        Lt10000,
        #[serde(rename = "ge_10000")]
        Ge10000,
    }
}

/// 耗时计数的聚合维度。
#[derive(Clone, Copy, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TimingDimensions {
    pub metric: TimingMetric,
    pub feature: Feature,
    pub route: Route,
    pub bucket: TimingBucket,
}

/// 一次计数的维度，Core 根据变体选择对应的聚合数组。
#[derive(Clone, Eq, PartialEq)]
pub enum TelemetryEvent {
    Counter(CounterDimensions),
    Error(ErrorDimensions),
    Timing(TimingDimensions),
}

impl TelemetryEvent {
    pub(super) fn is_valid(&self) -> bool {
        let Self::Error(error) = self else {
            return true;
        };
        let valid_code = if error.event == ErrorEvent::Crash {
            CRASH_CODE.is_match(&error.error_code)
        } else {
            ERROR_CODE.is_match(&error.error_code)
        };
        valid_code
            && error
                .source
                .as_ref()
                .is_none_or(|source| source.len() <= 128 && SOURCE.is_match(source))
    }
}

pub(super) fn valid_app_version(version: &str) -> bool {
    version.len() <= 48 && APP_VERSION.is_match(version)
}

#[cfg(test)]
#[path = "tests/dimensions.rs"]
mod tests;
