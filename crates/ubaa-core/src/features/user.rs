//! User Center response classification shared by status and profile operations.

use crate::connection::from_webvpn_url;

pub(crate) fn looks_unauthenticated(status: u16, final_url: &str, body: &str) -> bool {
    if status == 401 {
        return true;
    }
    let direct_url = from_webvpn_url(final_url).unwrap_or_else(|_| final_url.into());
    if direct_url.contains("sso.buaa.edu.cn") {
        return true;
    }
    let trimmed = body.trim_start();
    trimmed.starts_with("<!DOCTYPE html")
        || trimmed.starts_with("<html")
        || body.contains("input name=\"execution\"")
        || body.contains("input name='execution'")
        || body.contains("统一身份认证")
}
