use std::collections::BTreeMap;
use std::time::{Duration, SystemTime};

use super::CookieJar;
use crate::ports::HttpResponse;

fn response(set_cookie: &str) -> HttpResponse {
    let mut headers = BTreeMap::new();
    headers.insert("Set-Cookie".into(), vec![set_cookie.into()]);
    HttpResponse {
        status: 200,
        final_url: "https://sso.buaa.edu.cn/login".into(),
        headers,
        body: Vec::new(),
    }
}

#[test]
fn cookie_jar_filters_domain_path_and_secure_attributes() {
    let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);
    let mut jar = CookieJar::default();
    jar.store_response(
        &response("ROOT=fixture-root; Domain=buaa.edu.cn; Path=/; Secure"),
        "https://sso.buaa.edu.cn/login",
        now,
    )
    .unwrap();
    jar.store_response(
        &response("PATH=fixture-path; Domain=sso.buaa.edu.cn; Path=/cas"),
        "https://sso.buaa.edu.cn/cas/login",
        now,
    )
    .unwrap();
    jar.store_response(
        &response("HOST=fixture-host"),
        "https://sso.buaa.edu.cn/cas/login",
        now,
    )
    .unwrap();

    let cookies = jar
        .cookie_header("https://sso.buaa.edu.cn/cas/step", now)
        .unwrap();
    assert!(cookies.contains("ROOT=fixture-root"));
    assert!(cookies.contains("PATH=fixture-path"));
    assert!(cookies.contains("HOST=fixture-host"));
    assert!(
        !jar.cookie_header("http://uc.buaa.edu.cn/cas/step", now)
            .unwrap()
            .contains("ROOT=")
    );
    assert!(
        !jar.cookie_header("https://sso.buaa.edu.cn/other", now)
            .unwrap()
            .contains("PATH=")
    );
    let uc_cookies = jar
        .cookie_header("https://uc.buaa.edu.cn/cas/step", now)
        .unwrap();
    assert!(uc_cookies.contains("ROOT=fixture-root"));
    assert!(!uc_cookies.contains("HOST="));
}

#[test]
fn cookie_replacement_and_max_age_zero_remove_previous_value() {
    let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);
    let mut jar = CookieJar::default();
    jar.store_response(
        &response("SESSION=old; Domain=sso.buaa.edu.cn; Path=/"),
        "https://sso.buaa.edu.cn/login",
        now,
    )
    .unwrap();
    jar.store_response(
        &response("SESSION=new; Domain=sso.buaa.edu.cn; Path=/"),
        "https://sso.buaa.edu.cn/login",
        now,
    )
    .unwrap();
    assert_eq!(
        jar.cookie_header("https://sso.buaa.edu.cn/", now).unwrap(),
        "SESSION=new"
    );

    jar.store_response(
        &response("SESSION=gone; Domain=sso.buaa.edu.cn; Path=/; Max-Age=0"),
        "https://sso.buaa.edu.cn/login",
        now,
    )
    .unwrap();
    assert_eq!(
        jar.cookie_header("https://sso.buaa.edu.cn/", now).unwrap(),
        ""
    );
}

#[test]
fn expired_cookie_is_not_sent_or_persisted() {
    let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);
    let mut jar = CookieJar::default();
    jar.store_response(
        &response("OLD=fixture; Domain=sso.buaa.edu.cn; Path=/; Max-Age=1"),
        "https://sso.buaa.edu.cn/login",
        now,
    )
    .unwrap();
    assert_eq!(
        jar.cookie_header("https://sso.buaa.edu.cn/", now + Duration::from_secs(2))
            .unwrap(),
        ""
    );
    assert_eq!(jar.cookies().len(), 0);
}

#[test]
fn cookie_value_lookup_respects_domain_path_and_expiry() {
    let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);
    let mut jar = CookieJar::default();
    jar.store_response(
        &response("TOKEN=wrong-domain; Domain=uc.buaa.edu.cn; Path=/"),
        "https://uc.buaa.edu.cn/login",
        now,
    )
    .unwrap();
    jar.store_response(
        &response("TOKEN=wrong-path; Domain=sso.buaa.edu.cn; Path=/other"),
        "https://sso.buaa.edu.cn/other/login",
        now,
    )
    .unwrap();
    jar.store_response(
        &response("OLDTOKEN=expired; Domain=sso.buaa.edu.cn; Path=/cas; Max-Age=1"),
        "https://sso.buaa.edu.cn/cas/login",
        now,
    )
    .unwrap();
    jar.store_response(
        &response("TOKEN=valid; Domain=sso.buaa.edu.cn; Path=/cas"),
        "https://sso.buaa.edu.cn/cas/login",
        now,
    )
    .unwrap();

    assert_eq!(
        jar.cookie_value_for_url("TOKEN", "https://sso.buaa.edu.cn/cas/step", now)
            .unwrap(),
        Some("valid".into())
    );
    assert_eq!(
        jar.cookie_value_for_url(
            "OLDTOKEN",
            "https://sso.buaa.edu.cn/cas/step",
            now + Duration::from_secs(2)
        )
        .unwrap(),
        None
    );
    assert_eq!(
        jar.cookie_value_for_url(
            "TOKEN",
            "https://sso.buaa.edu.cn/cas/step",
            now + Duration::from_secs(2)
        )
        .unwrap(),
        Some("valid".into())
    );
    assert_eq!(
        jar.cookie_value_for_url("TOKEN", "https://uc.buaa.edu.cn/", now)
            .unwrap(),
        Some("wrong-domain".into())
    );
}
