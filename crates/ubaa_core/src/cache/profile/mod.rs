//! 资料缓存仅保存可辨认账号的遮罩，不是身份或认证材料。
use crate::domain::UserProfile;
use serde::{Deserialize, Serialize};

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
