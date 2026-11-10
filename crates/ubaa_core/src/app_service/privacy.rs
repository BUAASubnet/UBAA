//! 从已确认的账号派生遥测用户标识，不保留学号原文。

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const USER_KEY_PREFIX: &[u8] = b"ubaa-telemetry-user-v1:";

/// 批次中允许携带的账号信息，禁止通过 `Debug` 输出。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct TelemetryUser {
    key: String,
    cohort_type: String,
    cohort_year: Option<i32>,
}

impl TelemetryUser {
    pub(super) fn from_confirmed_username(username: &str, campus_year: i32) -> Option<Self> {
        let normalized = username.trim().to_uppercase();
        if normalized.is_empty() {
            return None;
        }
        let mut digest = Sha256::new();
        digest.update(USER_KEY_PREFIX);
        digest.update(normalized.as_bytes());
        let (cohort_type, cohort_year) = cohort(&normalized, campus_year)
            .map_or(("unknown", None), |(cohort_type, year)| {
                (cohort_type, Some(year))
            });
        Some(Self {
            key: hex::encode(digest.finalize()),
            cohort_type: cohort_type.to_owned(),
            cohort_year,
        })
    }

    pub(super) fn key(&self) -> &str {
        &self.key
    }
}

fn cohort(normalized: &str, campus_year: i32) -> Option<(&str, i32)> {
    let (cohort_type, tens, units) = match normalized.as_bytes() {
        [tens, units, ..] if normalized.bytes().all(|byte| byte.is_ascii_digit()) => {
            ("undergrad", *tens, *units)
        }
        [first, second, tens, units, ..]
            if first.is_ascii_uppercase()
                && second.is_ascii_uppercase()
                && tens.is_ascii_digit()
                && units.is_ascii_digit() =>
        {
            (&normalized[..2], *tens, *units)
        }
        _ => return None,
    };
    let year = 2000 + i32::from(tens - b'0') * 10 + i32::from(units - b'0');
    (year <= campus_year + 1).then_some((cohort_type, year))
}

#[cfg(test)]
#[path = "tests/privacy.rs"]
mod tests;
