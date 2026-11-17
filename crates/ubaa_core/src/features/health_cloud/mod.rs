//! 健康云的有界 GET 链和成绩解析。
mod parser;
use self::parser::parse;
use crate::domain::{ConnectionMode, HealthCloudPage};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;
use url::Url;

pub(crate) const HOST: &str = "10.212.28.38";
const SCORE: &str = "http://10.212.28.38/main.php?module=stu&title=stu_ht_score";
const SERVICE: &str = "http://10.212.28.38/index.php?module=user&title=logout";

fn score_url(year: Option<&str>) -> Url {
    let mut url = Url::parse(SCORE).expect("固定的健康云成绩 URL");
    if let Some(year) = year {
        url.query_pairs_mut().append_pair("year", year);
    }
    url
}

fn year_label(key: &str) -> Option<u16> {
    let (years, term) = key.split_once('_')?;
    let (start, end) = years.split_once('-')?;
    if start.len() != 4 || end.len() != 4 || term.len() != 1 || !term.as_bytes()[0].is_ascii_digit()
    {
        return None;
    }
    let start: u16 = start.parse().ok()?;
    let end: u16 = end.parse().ok()?;
    (start > 0 && start + 1 == end).then_some(start)
}

fn business_path(url: &Url) -> bool {
    match url.path() {
        "/main.php" => {
            url.query().is_none() || {
                let params: Vec<_> = url.query_pairs().collect();
                matches!(&params[..], [module, title] | [module, title, _]
                    if module.0 == "module" && module.1 == "stu" &&
                    title.0 == "title" && title.1 == "stu_ht_score")
                    && params
                        .get(2)
                        .is_none_or(|(k, v)| k == "year" && year_label(v).is_some())
            }
        }
        "/index.php" => {
            let params: Vec<_> = url.query_pairs().collect();
            matches!(&params[..], [module, title] | [module, title, _]
                if module.0 == "module" && module.1 == "user" &&
                title.0 == "title" && title.1 == "logout")
                && params
                    .get(2)
                    .is_none_or(|(k, v)| k == "ticket" && !v.is_empty())
        }
        _ => false,
    }
}

#[track_caller]
fn invalid() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "健康云返回了无法识别的页面",
    )
}

fn redirect(current: &Url, location: &str, mode: ConnectionMode) -> Result<Url> {
    let url = crate::connection::upstream_redirect_target(current.as_str(), location)
        .map_err(|_| invalid())?;
    if url.port().is_some()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(invalid());
    }
    if url.host_str() == Some(HOST) && url.scheme() == "http" && business_path(&url) {
        return Ok(url);
    }
    if url.host_str() == Some("sso.buaa.edu.cn")
        && url.scheme() == "https"
        && url.path() == "/login"
    {
        let service = url.query_pairs().find(|(k, _)| k == "service");
        let valid = service.is_some_and(|(_, value)| {
            value == SERVICE
                || (mode == ConnectionMode::WebVpn
                    && crate::connection::from_webvpn_url(&value)
                        .is_ok_and(|value| value == SERVICE))
        });
        if valid {
            return Ok(url);
        }
    }
    Err(invalid())
}

pub(crate) async fn get(
    runtime: &mut ClientRuntime,
    year: Option<&str>,
) -> Result<HealthCloudPage> {
    super::require_session(runtime)?;
    if year.is_some_and(|year| year_label(year).is_none()) {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "体测年份无效",
        ));
    }
    let requested = score_url(year);
    let mut target = requested.clone();
    for _ in 0..10 {
        let url = runtime.url(target.as_str())?;
        let response = runtime.request(HttpRequest::get(&url)).await?;
        if response.final_url != url {
            return Err(invalid());
        }
        if matches!(response.status, 301 | 302 | 303 | 307 | 308) {
            let location = response.header_first("location").ok_or_else(invalid)?;
            let current = Url::parse(&url).map_err(|_| invalid())?;
            if runtime.mode() == ConnectionMode::WebVpn
                && response.status == 302
                && current.join(location).is_ok_and(|next| {
                    crate::connection::is_valid_webvpn_gateway(&next)
                        && next.path() == "/login"
                        && next.query().is_none()
                        && next.fragment().is_none()
                })
            {
                return Err(UbaaError::authentication_required("WebVPN 会话需要恢复"));
            }
            target = redirect(&current, location, runtime.mode())?;
            // CAS 回调返回首页；保留调用者所选年份。
            if target.host_str() == Some(HOST) && target.path() == "/main.php" {
                target.clone_from(&requested);
            }
            continue;
        }
        let body = super::body(&response);
        if response.status == 401
            || (target.host_str() == Some("sso.buaa.edu.cn")
                && response.status == 200
                && crate::upstream::extract_execution(&body).is_some())
        {
            return Err(UbaaError::authentication_required("健康云需要恢复统一认证"));
        }
        if response.status != 200 {
            return Err(super::http::http_status_error(&response, "健康云"));
        }
        if target == requested {
            return parse(&body, year, &url);
        }
        return Err(invalid());
    }
    Err(invalid())
}

#[cfg(test)]
mod tests;
