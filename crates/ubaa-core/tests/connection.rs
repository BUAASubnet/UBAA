use ubaa_core::connection::{
    AuthHostPolicy, from_webvpn_url, is_allowed_auth_host, resolve_redirect, to_webvpn_url,
};
use ubaa_core::domain::ConnectionMode;

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

#[test]
fn auth_host_policy_accepts_only_verified_sso_uc_and_gateway_hosts() {
    let policy = AuthHostPolicy::default();
    assert!(policy.allows("sso.buaa.edu.cn"));
    assert!(policy.allows("uc.buaa.edu.cn"));
    assert!(policy.allows("d.buaa.edu.cn"));
    assert!(!policy.allows("evil.example.invalid"));
    assert!(is_allowed_auth_host("https://sso.buaa.edu.cn/login"));
    assert!(!is_allowed_auth_host("https://evil.example.invalid/login"));
}

#[test]
fn redirects_resolve_absolute_protocol_relative_root_and_path_relative_locations() {
    let current = "https://sso.buaa.edu.cn/cas/login/step";
    let cases = [
        (
            "https://uc.buaa.edu.cn/landing",
            "https://uc.buaa.edu.cn/landing",
        ),
        ("//uc.buaa.edu.cn/landing", "https://uc.buaa.edu.cn/landing"),
        ("/landing", "https://sso.buaa.edu.cn/landing"),
        ("next", "https://sso.buaa.edu.cn/cas/login/next"),
    ];

    for (location, expected) in cases {
        assert_eq!(
            resolve_redirect(current, location, ConnectionMode::Direct).unwrap(),
            expected
        );
    }
}

#[test]
fn webvpn_absolute_redirects_are_converted_but_gateway_relative_redirects_stay_gateway() {
    let direct = resolve_redirect(
        "https://d.buaa.edu.cn/https/fixture/sso/login",
        "https://uc.buaa.edu.cn/landing",
        ConnectionMode::WebVpn,
    )
    .unwrap();
    assert!(direct.starts_with("https://d.buaa.edu.cn/https/"));
    assert_eq!(
        from_webvpn_url(&direct).unwrap(),
        "https://uc.buaa.edu.cn/landing"
    );

    let relative = resolve_redirect(
        "https://d.buaa.edu.cn/https/fixture/sso/login",
        "/landing",
        ConnectionMode::WebVpn,
    )
    .unwrap();
    assert_eq!(relative, "https://d.buaa.edu.cn/landing");
}

#[test]
fn redirects_to_unverified_hosts_are_rejected_in_both_modes() {
    assert!(
        resolve_redirect(
            "https://sso.buaa.edu.cn/login",
            "https://evil.example.invalid/login",
            ConnectionMode::Direct,
        )
        .is_err()
    );
    assert!(
        resolve_redirect(
            "https://d.buaa.edu.cn/https/fixture/login",
            "https://evil.example.invalid/login",
            ConnectionMode::WebVpn,
        )
        .is_err()
    );
}
