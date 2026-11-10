//! 启动配置的已知字段与向前兼容规则。

use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use url::Url;

use super::{APP_SERVICE_SCHEMA_VERSION, Channel, version::valid_release_version};

/// 启动配置及本机尚未读、未过期的公告。未同意或未接入时返回空视图。
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct AppBootstrapView {
    pub update: Option<AppUpdateView>,
    pub announcements: Vec<AppAnnouncement>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AppUpdateStatus {
    UpToDate,
    UpdateAvailable,
    UpdateRequired,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AppUpdateView {
    pub status: AppUpdateStatus,
    pub latest_version: Option<String>,
    pub min_supported_version: Option<String>,
    pub url: Option<String>,
    pub release_notes: Option<String>,
    pub gate_active: bool,
    pub available_dismissed: bool,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AppAnnouncementLevel {
    Popup,
    Banner,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct AppAnnouncement {
    pub id: String,
    pub level: AppAnnouncementLevel,
    pub title: String,
    pub body: String,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub link_url: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub link_text: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub confirm_text: Option<String>,
    pub starts_at: DateTime<Utc>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub ends_at: Option<DateTime<Utc>>,
}

fn present<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    T::deserialize(deserializer).map(Some)
}

#[derive(Deserialize)]
struct Response {
    schema: u32,
    update: WireUpdate,
    announcements: Vec<Value>,
}

#[derive(Deserialize)]
struct WireUpdate {
    status: String,
    // 这些字段可以是 null，但不可从 v1 响应中删除。
    #[serde(deserialize_with = "Deserialize::deserialize")]
    latest_version: Option<String>,
    #[serde(deserialize_with = "Deserialize::deserialize")]
    min_supported_version: Option<String>,
    #[serde(deserialize_with = "Deserialize::deserialize")]
    url: Option<String>,
    #[serde(deserialize_with = "Deserialize::deserialize")]
    release_notes: Option<String>,
}

/// 持久化已校验的字段，不保留服务端的未知字段。
#[derive(Deserialize, Serialize)]
pub(super) struct Bootstrap {
    pub(super) update: Update,
    pub(super) announcements: Vec<AppAnnouncement>,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Update {
    pub(super) status: AppUpdateStatus,
    pub(super) latest_version: Option<String>,
    pub(super) min_supported_version: Option<String>,
    pub(super) url: Option<String>,
    pub(super) release_notes: Option<String>,
}

impl WireUpdate {
    fn parse(self, channel: Channel) -> Option<Update> {
        let status = match self.status.as_str() {
            "up_to_date" => AppUpdateStatus::UpToDate,
            "update_available" => AppUpdateStatus::UpdateAvailable,
            "update_required" => AppUpdateStatus::UpdateRequired,
            _ => AppUpdateStatus::Unknown,
        };
        if self
            .latest_version
            .iter()
            .chain(self.min_supported_version.iter())
            .any(|version| !valid_release_version(version))
            || self
                .url
                .as_ref()
                .is_some_and(|url| !valid_update_url(url, channel))
            || self
                .release_notes
                .as_ref()
                .is_some_and(|notes| notes.chars().count() > 2000)
        {
            return None;
        }
        let actionable = matches!(
            status,
            AppUpdateStatus::UpdateAvailable | AppUpdateStatus::UpdateRequired
        );
        if (status != AppUpdateStatus::Unknown && self.url.is_none())
            || (status == AppUpdateStatus::UpdateRequired && self.min_supported_version.is_none())
            || (status == AppUpdateStatus::UpdateAvailable && self.latest_version.is_none())
            || (status == AppUpdateStatus::UpToDate && self.release_notes.is_some())
            || (self.status == "unknown"
                && (self.latest_version.is_some()
                    || self.min_supported_version.is_some()
                    || self.url.is_some()
                    || self.release_notes.is_some()))
        {
            return None;
        }
        Some(Update {
            status,
            latest_version: self.latest_version,
            min_supported_version: self.min_supported_version,
            url: self.url,
            release_notes: actionable.then_some(self.release_notes).flatten(),
        })
    }
}

fn https_url(value: &str) -> Option<Url> {
    let (scheme, after_scheme) = value.split_once("://")?;
    let url = Url::parse(value).ok()?;
    (scheme.eq_ignore_ascii_case("https")
        && !after_scheme.starts_with('/')
        && !value.contains('\\')
        && !value.contains(|character: char| character.is_ascii_whitespace())
        && url.has_host())
    .then_some(url)
}

fn valid_update_url(value: &str, channel: Channel) -> bool {
    let Some(url) = https_url(value) else {
        return false;
    };
    if !url.username().is_empty() || url.password().is_some() {
        return false;
    }
    match channel {
        Channel::AppStore => url.port().is_none() && url.host_str() == Some("apps.apple.com"),
        Channel::AppGallery => {
            url.port().is_none()
                && matches!(
                    url.host_str(),
                    Some("appgallery.huawei.com" | "appgallery.cloud.huawei.com")
                )
        }
        Channel::Github => true,
    }
}

pub(super) fn valid_announcement_id(id: &str) -> bool {
    id.len() == 14
        && id.bytes().enumerate().all(|(index, byte)| {
            if matches!(index, 4 | 7 | 10) {
                byte == b'-'
            } else {
                byte.is_ascii_digit()
            }
        })
}

fn parse_announcement(value: Value) -> Option<AppAnnouncement> {
    let announcement: AppAnnouncement = serde_json::from_value(value).ok()?;
    (valid_announcement_id(&announcement.id)
        && announcement.title.chars().count() <= 40
        && announcement.body.chars().count() <= 1000
        && announcement
            .link_url
            .as_ref()
            .is_none_or(|url| https_url(url).is_some()))
    .then_some(announcement)
}

pub(super) fn parse_response(body: &[u8], channel: Channel) -> Option<Bootstrap> {
    let response: Response = serde_json::from_slice(body).ok()?;
    if response.schema != APP_SERVICE_SCHEMA_VERSION || response.announcements.len() > 5 {
        return None;
    }
    Some(Bootstrap {
        update: response.update.parse(channel)?,
        announcements: response
            .announcements
            .into_iter()
            .filter_map(parse_announcement)
            .collect(),
    })
}
