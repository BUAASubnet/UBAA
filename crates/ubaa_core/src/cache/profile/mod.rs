//! 账号加密缓存中的展示资料，不作为身份或认证材料。
use crate::domain::UserProfile;
use serde::{Deserialize, Serialize};

/// 与在线界面相同的展示字段；不包含证件号码、凭据或原始响应。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CachedDisplayProfile {
    username: Option<String>,
    name: Option<String>,
    school_id: Option<String>,
    email: Option<String>,
    phone: Option<String>,
}
impl CachedDisplayProfile {
    #[must_use]
    pub fn from_profile(value: &UserProfile) -> Self {
        Self {
            username: value.username.clone(),
            name: value.name.clone(),
            school_id: value.school_id.clone(),
            email: value.email.clone(),
            phone: value.phone.clone(),
        }
    }
    #[must_use]
    pub fn into_profile(self) -> UserProfile {
        UserProfile {
            username: self.username,
            name: self.name,
            school_id: self.school_id,
            email: self.email,
            phone: self.phone,
            ..UserProfile::default()
        }
    }
    pub(super) fn valid(&self) -> bool {
        [self.username.as_deref(), self.school_id.as_deref()]
            .into_iter()
            .flatten()
            .any(|value| !value.trim().is_empty())
    }
}

/// 兼容已保存的旧遮罩资料，下一次在线成功时写入展示资料。

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CachedMaskedProfile {
    #[serde(rename = "maskedUsername")]
    username: Option<String>,
    #[serde(rename = "maskedName")]
    name: Option<String>,
    #[serde(rename = "maskedSchoolId")]
    school_id: Option<String>,
}
impl CachedMaskedProfile {
    /// 只在内存接触原资料；联系方式、证件和原始标识不进入此类型。
    #[must_use]
    pub fn from_profile(value: &UserProfile) -> Self {
        Self {
            username: mask(value.username.as_deref()),
            name: mask(value.name.as_deref()),
            school_id: mask(value.school_id.as_deref()),
        }
    }
    #[must_use]
    pub fn masked_username(&self) -> Option<&str> {
        self.username.as_deref()
    }
    #[must_use]
    pub fn masked_name(&self) -> Option<&str> {
        self.name.as_deref()
    }
    #[must_use]
    pub fn masked_school_id(&self) -> Option<&str> {
        self.school_id.as_deref()
    }
    pub(super) fn valid(&self) -> bool {
        (self.username.is_some() || self.school_id.is_some())
            && [&self.username, &self.name, &self.school_id]
                .into_iter()
                .all(|value| value.as_deref().is_none_or(is_masked))
    }
}
fn mask(value: Option<&str>) -> Option<String> {
    let value = value?.trim();
    if value.is_empty() {
        return None;
    }
    let mut chars = value.chars();
    let first = chars.next()?;
    let second = chars.next();
    let last = chars.last();
    Some(match (second, last) {
        (Some(_), Some(last)) => format!("{first}***{last}"),
        _ => "***".into(),
    })
}
fn is_masked(value: &str) -> bool {
    if value == "***" {
        return true;
    }
    let chars: Vec<_> = value.chars().collect();
    chars.len() == 5
        && chars[1..4] == ['*', '*', '*']
        && !chars[0].is_whitespace()
        && !chars[4].is_whitespace()
}
