//! 会话 Cookie 容器与 RFC 风格匹配规则。

use std::time::SystemTime;

use cookie_store::{Cookie, CookieDomain, CookieError, CookiePath};
use serde::{Deserialize, Serialize};
use url::Url;

use crate::error::Result;
use crate::ports::HttpResponse;

use super::file_safety::{header_values, session_error, unix_seconds};

/// 为安全请求过滤和持久化保留的 Cookie 属性。
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct StoredCookie {
    /// Cookie 名称。
    pub name: String,
    /// Cookie 值；这是会话材料，绝不写入日志。
    pub value: String,
    /// 生效域名。
    pub domain: String,
    /// Cookie 是否仅限当前主机。
    pub host_only: bool,
    /// 生效路径。
    pub path: String,
    /// 仅限 Secure 的标记。
    pub secure: bool,
    /// Unix 秒表示的绝对过期时间戳。
    pub expires_at: Option<i64>,
    /// Unix 秒表示的创建时间戳，用于计算 Max-Age。
    pub created_at: i64,
    /// 提供时的 Max-Age 秒数。
    pub max_age: Option<i64>,
}

// 保持 time 为 Cookie 库的内部依赖，不因类型投影重复声明版本约束。
#[allow(clippy::redundant_closure_for_method_calls)]
fn parse_cookie(raw: &str, url: &Url, created_at: i64) -> Result<Option<StoredCookie>> {
    let cookie = match Cookie::parse(raw, url) {
        Ok(cookie) => cookie,
        Err(CookieError::DomainMismatch) => return Ok(None),
        Err(_) => return Err(session_error("上游 Cookie 格式无效")),
    };
    if cookie.name().is_empty() {
        return Err(session_error("上游 Cookie 名称为空"));
    }
    Ok(Some(StoredCookie {
        name: cookie.name().to_owned(),
        value: cookie.value().to_owned(),
        domain: String::from(&cookie.domain),
        host_only: matches!(cookie.domain, CookieDomain::HostOnly(_)),
        path: String::from(&cookie.path),
        secure: cookie.secure().unwrap_or(false),
        expires_at: cookie.expires_datetime().map(|time| time.unix_timestamp()),
        created_at,
        max_age: cookie.max_age().map(|age| age.whole_seconds()),
    }))
}

fn cookie_matches(cookie: &StoredCookie, url: &Url, now: i64) -> bool {
    let domain = if cookie.host_only {
        CookieDomain::HostOnly(cookie.domain.clone())
    } else {
        CookieDomain::Suffix(cookie.domain.clone())
    };
    domain.matches(url)
        && CookiePath::parse(&cookie.path).is_some_and(|path| path.matches(url))
        && (!cookie.secure || url.scheme().eq_ignore_ascii_case("https"))
        && !is_expired(cookie, now)
}

// 库的相对过期默认使用系统时钟；会话合同使用调用方时钟，并在重开后保持接收时间。
fn is_expired(cookie: &StoredCookie, now: i64) -> bool {
    match cookie.max_age {
        Some(age) => age <= 0 || now >= cookie.created_at.saturating_add(age),
        None => cookie.expires_at.is_some_and(|expires| expires <= now),
    }
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
    /// 构造确定性测试使用的 Cookie fixture。
    #[cfg(any(test, feature = "test-contract"))]
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
    ///
    /// # Errors
    ///
    /// 请求地址无效、系统时间不可用或上游 Cookie 格式无效时返回安全会话错误。
    #[allow(clippy::needless_continue)]
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
            if !is_expired(&cookie, now_seconds) {
                self.cookies.push(cookie);
            }
        }
        self.purge_expired(now_seconds);
        Ok(())
    }

    /// 为地址构造经过过滤的 Cookie 请求头。
    ///
    /// # Errors
    ///
    /// 请求地址无效或系统时间不可用时返回安全会话错误。
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

    /// 按请求地址和完整 Cookie 匹配规则读取一个 Cookie 值。
    ///
    /// # Errors
    ///
    /// 请求地址无效或系统时间不可用时返回安全会话错误。
    pub fn cookie_value_for_url(
        &mut self,
        name: &str,
        request_url: &str,
        now: SystemTime,
    ) -> Result<Option<String>> {
        let url = Url::parse(request_url).map_err(|_| session_error("invalid Cookie URL"))?;
        let now_seconds = unix_seconds(now)?;
        self.purge_expired(now_seconds);
        Ok(self
            .cookies
            .iter()
            .find(|cookie| cookie.name == name && cookie_matches(cookie, &url, now_seconds))
            .map(|cookie| cookie.value.clone()))
    }

    /// 借用当前保留的 Cookie，以便序列化会话。
    #[must_use]
    pub fn cookies(&self) -> &[StoredCookie] {
        &self.cookies
    }

    /// 使用持久化会话替换容器内容。
    pub fn replace(&mut self, cookies: Vec<StoredCookie>) {
        self.cookies = cookies;
    }

    fn purge_expired(&mut self, now: i64) {
        self.cookies.retain(|cookie| !is_expired(cookie, now));
    }
}

#[cfg(test)]
#[path = "cookies/tests.rs"]
mod tests;
