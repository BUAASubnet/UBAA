//! 会话 Cookie 容器与 RFC 风格匹配规则。

use std::time::SystemTime;

use serde::{Deserialize, Serialize};
use url::Url;

use crate::error::Result;
use crate::ports::HttpResponse;

use super::{cookie_matches, header_values, parse_cookie, session_error, unix_seconds};

/// 为安全请求过滤和持久化保留的 Cookie 属性。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct StoredCookie {
    /// Cookie 名称。
    pub name: String,
    /// Cookie 值；这是会话材料，绝不写入日志。
    pub value: String,
    /// Effective domain.
    pub domain: String,
    /// Cookie 是否仅限当前主机。
    pub host_only: bool,
    /// Effective path.
    pub path: String,
    /// Secure-only flag.
    pub secure: bool,
    /// Absolute expiration timestamp in Unix seconds.
    pub expires_at: Option<i64>,
    /// Creation timestamp in Unix seconds, used with Max-Age.
    pub created_at: i64,
    /// Max-Age in seconds when supplied.
    pub max_age: Option<i64>,
}

impl std::fmt::Debug for StoredCookie {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StoredCookie")
            .field("name", &"[REDACTED]")
            .field("value", &"[REDACTED]")
            .field("domain", &"[REDACTED]")
            .field("host_only", &self.host_only)
            .field("path", &"[REDACTED]")
            .field("secure", &self.secure)
            .field("expires_at", &self.expires_at)
            .field("created_at", &self.created_at)
            .field("max_age", &self.max_age)
            .finish()
    }
}

impl StoredCookie {
    /// Construct a cookie fixture for deterministic tests.
    pub fn fixture(name: impl Into<String>, value: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            value: value.into(),
            domain: "sso.buaa.edu.cn".into(),
            host_only: true,
            path: "/".into(),
            secure: true,
            expires_at: None,
            created_at: 1_000,
            max_age: None,
        }
    }
}

/// 依据 RFC 风格进行域、路径和过期过滤的内存 Cookie 容器。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CookieJar {
    cookies: Vec<StoredCookie>,
}

impl CookieJar {
    /// 为请求地址保存响应中的全部 `Set-Cookie` 值。
    pub fn store_response(
        &mut self,
        response: &HttpResponse,
        request_url: &str,
        now: SystemTime,
    ) -> Result<()> {
        let url =
            Url::parse(request_url).map_err(|_| session_error("invalid Cookie request URL"))?;
        let now_seconds = unix_seconds(now)?;
        for raw in header_values(&response.headers, "set-cookie") {
            let Some(cookie) = parse_cookie(raw, &url, now_seconds)? else {
                continue;
            };
            self.cookies.retain(|existing| {
                !(existing.name == cookie.name
                    && existing.domain == cookie.domain
                    && existing.path == cookie.path)
            });
            if cookie.max_age.is_none_or(|age| age > 0)
                && cookie
                    .expires_at
                    .is_none_or(|expires| expires > now_seconds)
            {
                self.cookies.push(cookie);
            }
        }
        self.purge_expired(now_seconds);
        Ok(())
    }

    /// 为地址构造经过过滤的 Cookie 请求头。
    pub fn cookie_header(&mut self, request_url: &str, now: SystemTime) -> Result<String> {
        let url = Url::parse(request_url).map_err(|_| session_error("invalid Cookie URL"))?;
        let now_seconds = unix_seconds(now)?;
        self.purge_expired(now_seconds);
        Ok(self
            .cookies
            .iter()
            .filter(|cookie| cookie_matches(cookie, &url, now_seconds))
            .map(|cookie| format!("{}={}", cookie.name, cookie.value))
            .collect::<Vec<_>>()
            .join("; "))
    }

    /// Borrow currently retained cookies for session serialization.
    #[must_use]
    pub fn cookies(&self) -> &[StoredCookie] {
        &self.cookies
    }

    /// 使用持久化会话替换容器内容。
    pub fn replace(&mut self, cookies: Vec<StoredCookie>) {
        self.cookies = cookies;
    }

    fn purge_expired(&mut self, now: i64) {
        self.cookies
            .retain(|cookie| !super::is_expired(cookie, now));
    }
}
