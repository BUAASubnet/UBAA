use ubaa_core::facade::{ConnectionMode, ErrorCode, NetworkState, UbaaClient};
use ubaa_test_support::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, MockTransport, RouteConfig,
    RouteSessionSnapshot, SessionSnapshot, StoredCookie, to_webvpn_url,
};

use crate::common::expected_get;

struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线无需探测");
    }
}

#[tokio::test]
async fn signin_qr_两条路线单独取时且均生成直连二维码() {
    let direct_url = "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action";
    let vpn_url =
        to_webvpn_url("https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action").unwrap();
    let direct = MockTransport::new([
        expected_get(direct_url, r#"{"timestamp":1700000000000}"#),
        expected_get(direct_url, r#"{"timestamp":"1700000001000"}"#),
    ]);
    let vpn = MockTransport::new([expected_get(&vpn_url, r#"{"timestamp":"1700000001000"}"#)]);
    let root = ubaa_test_support::test_temp_dir("ubaa_test_support_readonly_signin_qr").unwrap();
    std::fs::create_dir_all(root.parent().unwrap()).unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    let config = RouteConfig::parse("[route]\ndefault = 'direct'\n").unwrap();
    let mut client =
        UbaaClient::with_routing(direct.clone(), vpn.clone(), store.clone(), config, NoProbe)
            .unwrap();

    assert_eq!(
        client
            .signin_qr("course-1", 0)
            .await
            .unwrap_err()
            .error
            .code,
        ErrorCode::AuthenticationRequired
    );
    let slot = |mode| {
        RouteSessionSnapshot::from_legacy(&SessionSnapshot {
            mode,
            cookies: vec![StoredCookie::fixture("SID", "fixture")],
            authenticated_at: 1,
            last_activity: 2,
        })
    };
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(slot(ConnectionMode::Direct)),
            Some(slot(ConnectionMode::WebVpn)),
        ))
        .unwrap();
    let config = RouteConfig::parse("[route]\ndefault = 'direct'\n").unwrap();
    let mut client =
        UbaaClient::with_routing(direct.clone(), vpn.clone(), store.clone(), config, NoProbe)
            .unwrap();
    for (course, offset) in [(" ", 0), ("course-1", 60_001)] {
        assert_eq!(
            client
                .signin_qr(course, offset)
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::InvalidInput
        );
    }
    let course = "排课&+/#";
    let live = client.signin_qr(course, 0).await.unwrap();
    let saved = client.signin_qr(course, 2_000).await.unwrap();
    assert_eq!(live.data.timestamp, 1_700_000_000_000);
    assert_eq!(saved.data.timestamp, 1_700_000_003_000);

    let config = RouteConfig::parse("[route]\ndefault = 'webvpn'\n").unwrap();
    let mut client =
        UbaaClient::with_routing(direct.clone(), vpn.clone(), store, config, NoProbe).unwrap();
    let wrapped = client.signin_qr(course, 2_000).await.unwrap();
    assert_eq!(wrapped.resolution.mode, ConnectionMode::WebVpn);
    assert_eq!(wrapped.data, saved.data);
    for qr in [live.data, saved.data, wrapped.data] {
        let url = url::Url::parse(&qr.content).unwrap();
        assert_eq!(url.scheme(), "http");
        assert_eq!(url.host_str(), Some("iclass.buaa.edu.cn"));
        assert_eq!(url.port(), Some(8081));
        assert_eq!(url.path(), "/eschool/app/course/stu_scan_sign.action");
        assert!(url.fragment().is_none());
        assert_eq!(
            url.query_pairs().into_owned().collect::<Vec<_>>(),
            vec![
                ("courseSchedId".into(), course.into()),
                ("timestamp".into(), qr.timestamp.to_string()),
            ]
        );
    }
    for transport in [direct, vpn] {
        transport.assert_exhausted().unwrap();
        for request in transport.requests().unwrap() {
            assert_eq!(request.body, [] as [u8; 0]);
            assert!(
                !request
                    .headers
                    .keys()
                    .any(|key| key.eq_ignore_ascii_case("sessionId"))
            );
        }
    }
    std::fs::remove_dir_all(root).unwrap();
}
