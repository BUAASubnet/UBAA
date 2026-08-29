use md5::{Digest, Md5};
use std::collections::BTreeMap;

const PREFIX: &str = "c640ca392cd45fb3a55b00a63a86c618";
const REMOVE_KEYS: [&str; 7] = [
    "gmtCreate",
    "gmtModified",
    "creator",
    "modifier",
    "id",
    "_index",
    "_rowKey",
];

pub(crate) fn timestamp_millis() -> crate::error::Result<i64> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| {
            crate::error::UbaaError::new(
                crate::error::ErrorCode::UpstreamChanged,
                crate::error::ErrorKind::Upstream,
                false,
                "系统时间无效",
            )
        })?
        .as_millis()
        .try_into()
        .map_err(|_| {
            crate::error::UbaaError::new(
                crate::error::ErrorCode::UpstreamChanged,
                crate::error::ErrorKind::Upstream,
                false,
                "系统时间无效",
            )
        })
}

pub(crate) fn sign(path: &str, params: &BTreeMap<String, String>, timestamp: i64) -> String {
    let path = if path.starts_with('/') {
        path.to_owned()
    } else {
        format!("/{path}")
    };
    let mut payload = format!("{PREFIX}{path}");
    for (key, value) in params
        .iter()
        .filter(|(key, value)| !value.is_empty() && !REMOVE_KEYS.contains(&key.as_str()))
    {
        payload.push_str(key);
        payload.push_str(value);
    }
    payload.push_str(&timestamp.to_string());
    payload.push(' ');
    payload.push_str(PREFIX);
    format!("{:x}", Md5::digest(payload.as_bytes()))
}
