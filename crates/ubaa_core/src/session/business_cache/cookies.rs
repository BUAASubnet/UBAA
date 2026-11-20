use super::super::StoredCookie;
use crate::domain::ConnectionMode;
use url::Url;

// 仅复用没有业务 Token 或服务端选择状态绑定的已对照 Cookie。
const BUSINESS_HOSTS: [&str; 2] = ["it.buaa.edu.cn", "byxt.buaa.edu.cn"];

pub(crate) fn reusable_cookie_scope(
    mode: ConnectionMode,
    cookie: &StoredCookie,
) -> Option<&'static str> {
    let known_host = |host: &str| BUSINESS_HOSTS.into_iter().find(|known| *known == host);
    match mode {
        ConnectionMode::Direct => known_host(&cookie.domain),
        ConnectionMode::WebVpn if cookie.domain == "d.buaa.edu.cn" => {
            let url = webvpn_cookie_upstream(cookie)?;
            if url.scheme() != "https" || url.port_or_known_default() != Some(443) {
                return None;
            }
            known_host(url.host_str()?)
        }
        ConnectionMode::WebVpn => None,
    }
}

fn webvpn_cookie_upstream(cookie: &StoredCookie) -> Option<Url> {
    if cookie.domain != "d.buaa.edu.cn" && (cookie.host_only || cookie.domain != "buaa.edu.cn") {
        return None;
    }
    let mut gateway = Url::parse("https://d.buaa.edu.cn/").ok()?;
    gateway.set_path(&cookie.path);
    let upstream = crate::connection::from_webvpn_url(gateway.as_str()).ok()?;
    Url::parse(&upstream).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 直连只识别业务域且网关只识别包装的业务路径() {
        let path_for = |url: &str| {
            let encoded = crate::connection::to_webvpn_url(url).unwrap();
            Url::parse(&encoded).unwrap().path().to_owned()
        };
        let mut cookie = StoredCookie::fixture("fixture", "material");
        for host in BUSINESS_HOSTS {
            cookie.domain = host.into();
            assert_eq!(
                reusable_cookie_scope(ConnectionMode::Direct, &cookie),
                Some(host)
            );
            assert_eq!(reusable_cookie_scope(ConnectionMode::WebVpn, &cookie), None);
            cookie.domain = "d.buaa.edu.cn".into();
            cookie.path = path_for(&format!("https://{host}/fixture"));
            assert_eq!(
                reusable_cookie_scope(ConnectionMode::WebVpn, &cookie),
                Some(host)
            );
            assert_eq!(reusable_cookie_scope(ConnectionMode::Direct, &cookie), None);
        }
        for target in [
            "https://byxt.buaa.edu.cn:8443/fixture",
            "http://it.buaa.edu.cn/fixture",
            "https://sso.buaa.edu.cn/fixture",
            "https://uc.buaa.edu.cn/fixture",
        ] {
            cookie.path = path_for(target);
            assert_eq!(reusable_cookie_scope(ConnectionMode::WebVpn, &cookie), None);
        }
        cookie.path = "/".into();
        assert_eq!(reusable_cookie_scope(ConnectionMode::WebVpn, &cookie), None);
    }
}
