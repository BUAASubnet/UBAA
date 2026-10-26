use ubaa_core::facade::testing::{from_webvpn_url, to_webvpn_url};

#[test]
fn webvpn_round_trip_preserves_path_query_and_fragment() {
    let original = "https://spoc.buaa.edu.cn/spocnewht/cas?token=fixture-token#/home?tab=one";
    let wrapped = to_webvpn_url(original).expect("URL wraps");

    assert!(wrapped.starts_with("https://d.buaa.edu.cn/https/"));
    assert_eq!(from_webvpn_url(&wrapped).expect("URL unwraps"), original);
}

#[test]
fn webvpn_round_trip_preserves_custom_port_and_http_scheme() {
    let original = "http://iclass.buaa.edu.cn:8081/app/course?id=fixture#section";
    let wrapped = to_webvpn_url(original).expect("URL wraps");

    assert!(wrapped.starts_with("https://d.buaa.edu.cn/http-8081/"));
    assert_eq!(from_webvpn_url(&wrapped).expect("URL unwraps"), original);
}

#[test]
fn webvpn_root_path_preserves_an_explicit_trailing_slash() {
    let wrapped = to_webvpn_url("https://judge.buaa.edu.cn/").expect("URL wraps");

    assert_eq!(
        from_webvpn_url(&wrapped).expect("URL unwraps"),
        "https://judge.buaa.edu.cn/"
    );
}

#[test]
fn webvpn_omits_empty_query_and_fragment_like_the_frozen_codec() {
    let wrapped = to_webvpn_url("https://judge.buaa.edu.cn/path?#").expect("URL wraps");

    assert!(!wrapped.contains('?'));
    assert!(!wrapped.contains('#'));
    assert_eq!(
        from_webvpn_url(&wrapped).expect("URL unwraps"),
        "https://judge.buaa.edu.cn/path"
    );
    assert_eq!(
        from_webvpn_url(&format!("{wrapped}?#")).expect("URL unwraps"),
        "https://judge.buaa.edu.cn/path"
    );
}

#[test]
fn webvpn_default_http_and_https_ports_use_plain_protocol_segments() {
    let http = to_webvpn_url("http://sso.buaa.edu.cn:80/login").unwrap();
    let https = to_webvpn_url("https://sso.buaa.edu.cn:443/login").unwrap();

    assert!(http.starts_with("https://d.buaa.edu.cn/http/"));
    assert!(https.starts_with("https://d.buaa.edu.cn/https/"));
    assert_eq!(
        from_webvpn_url(&http).unwrap(),
        "http://sso.buaa.edu.cn/login"
    );
    assert_eq!(
        from_webvpn_url(&https).unwrap(),
        "https://sso.buaa.edu.cn/login"
    );
}

#[test]
fn already_wrapped_or_invalid_urls_are_not_wrapped_again() {
    let wrapped = to_webvpn_url("https://d.buaa.edu.cn/https/fixture/path").unwrap();
    assert_eq!(wrapped, "https://d.buaa.edu.cn/https/fixture/path");
    assert_eq!(to_webvpn_url("not a URL").unwrap(), "not a URL");
    assert_eq!(
        from_webvpn_url("https://example.invalid/path").unwrap(),
        "https://example.invalid/path"
    );
}
