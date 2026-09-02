use ubaa_core::domain::{ConnectionMode, LoginInput, SecretValue};
use ubaa_core::error::ErrorCode;
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::HttpMethod;
use ubaa_test_support::{ExpectedRequest, MockTransport, readonly_fixture};

use crate::common::{expected_get, redirect_from, response, session_store, session_store_for};

const FROZEN_CLASSROOM_USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 16; 24031PN0DC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36 XWEB/1380275 MMWEBSDK/20230806 MMWEBID/4102 wxworklocal/3.2.200 wwlocal/3.2.200 wxwork/4.0.0 appname/wxworklocal-customized wxworklocal-device-code/195ef5586d7d3c2808fcbea32d77c0d4 MicroMessenger/7.0.1 appScheme/wxworklocalcustomized Language/zh_CN ColorScheme/Light WXWorklocalClientType/Android Brand/xiaomi";
#[tokio::test]
async fn direct_and_webvpn_classroom_sync_state_is_route_local() {
    use ubaa_core::connection::to_webvpn_url;

    let direct_sync = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let direct_query = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let webvpn_sync = to_webvpn_url(direct_sync).unwrap();
    let webvpn_query = to_webvpn_url(&direct_query).unwrap();
    let direct_transport = MockTransport::new([
        expected_get(direct_sync, ""),
        expected_get(&direct_query, readonly_fixture("classroom.json").unwrap()),
        expected_get(&direct_query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let webvpn_transport = MockTransport::new([
        expected_get(&webvpn_sync, ""),
        expected_get(&webvpn_query, readonly_fixture("classroom.json").unwrap()),
        expected_get(&webvpn_query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let direct_observed = direct_transport.clone();
    let webvpn_observed = webvpn_transport.clone();
    let mut direct = RouteClient::with_transport(
        ConnectionMode::Direct,
        direct_transport,
        session_store_for(ConnectionMode::Direct, "direct-route-state"),
    )
    .unwrap();
    let mut webvpn = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        webvpn_transport,
        session_store_for(ConnectionMode::WebVpn, "webvpn-route-state"),
    )
    .unwrap();

    direct.classroom_search(1, "2026-04-20").await.unwrap();
    webvpn.classroom_search(1, "2026-04-20").await.unwrap();
    direct.classroom_search(1, "2026-04-20").await.unwrap();
    webvpn.classroom_search(1, "2026-04-20").await.unwrap();

    direct_observed.assert_exhausted().unwrap();
    webvpn_observed.assert_exhausted().unwrap();
    assert_eq!(
        direct_observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == direct_sync)
            .count(),
        1
    );
    assert_eq!(
        webvpn_observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == webvpn_sync)
            .count(),
        1
    );
}

#[tokio::test]
async fn successful_login_replacement_clears_classroom_sync_state() {
    let sync = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let login = "https://sso.buaa.edu.cn/login";
    let activate =
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
    let status = "https://uc.buaa.edu.cn/api/uc/status";
    let userinfo = "https://uc.buaa.edu.cn/api/uc/userinfo";
    let profile = r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"#;
    let transport = MockTransport::new([
        expected_get(sync, ""),
        expected_get(&query, readonly_fixture("classroom.json").unwrap()),
        ExpectedRequest::new(
            HttpMethod::Get,
            login,
            redirect_from(login, "/already-authenticated"),
        ),
        expected_get(activate, ""),
        ExpectedRequest::new(HttpMethod::Get, status, response(200, status, profile)),
        ExpectedRequest::new(HttpMethod::Get, userinfo, response(200, userinfo, profile)),
        expected_get(sync, ""),
        expected_get(&query, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    client.classroom_search(1, "2026-04-20").await.unwrap();
    client.prepare_login().await.unwrap();
    client
        .login(LoginInput {
            username: "fixture-user".into(),
            password: SecretValue::new("fixture-password"),
        })
        .await
        .unwrap();
    client.classroom_search(1, "2026-04-20").await.unwrap();

    observed.assert_exhausted().unwrap();
    assert_eq!(
        observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == sync)
            .count(),
        2,
        "a successful session replacement must force a new Classroom sync"
    );
}

#[tokio::test]
async fn classroom_uses_verified_sync_headers_and_sanitized_fixture() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        expected_get(sync_url, ""),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    let result = client.classroom_search(1, "2026-04-20").await.unwrap();
    let repeated = client.classroom_search(1, "2026-04-20").await.unwrap();

    assert_eq!(result.data.floors["Main"][0].name, "Fixture Room");
    assert_eq!(repeated.data.floors["Main"][0].name, "Fixture Room");
    observed.assert_exhausted().unwrap();
    let requests = observed.requests().unwrap();
    assert_eq!(requests.len(), 3, "one client synchronizes its route once");
    assert_eq!(
        requests[0].headers.get("User-Agent").map(String::as_str),
        Some(FROZEN_CLASSROOM_USER_AGENT)
    );
    assert_eq!(
        requests[1].headers.get("User-Agent").map(String::as_str),
        Some(FROZEN_CLASSROOM_USER_AGENT)
    );
    assert_eq!(
        requests[1]
            .headers
            .get("X-Requested-With")
            .map(String::as_str),
        Some("XMLHttpRequest")
    );
    assert_eq!(
        requests[1].headers.get("Accept").map(String::as_str),
        Some("application/json, text/javascript, */*; q=0.01")
    );
    assert_eq!(
        requests[1].headers.get("Referer").map(String::as_str),
        Some("https://app.buaa.edu.cn/site/classRoomQuery/index")
    );
}

#[tokio::test]
async fn classroom_sync_failure_is_best_effort_and_retried_later() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        ExpectedRequest::new(HttpMethod::Get, sync_url, response(503, sync_url, "")),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
        expected_get(sync_url, ""),
        expected_get(&query_url, readonly_fixture("classroom.json").unwrap()),
    ]);
    let observed = transport.clone();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, session_store()).unwrap();

    client.classroom_search(1, "2026-04-20").await.unwrap();
    client.classroom_search(1, "2026-04-20").await.unwrap();

    observed.assert_exhausted().unwrap();
    assert_eq!(
        observed
            .requests()
            .unwrap()
            .iter()
            .filter(|request| request.url == sync_url)
            .count(),
        2,
        "a failed synchronization must remain retryable"
    );
}

#[tokio::test]
async fn classroom_query_does_not_follow_sso_redirect_and_clears_the_route_session() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    let transport = MockTransport::new([
        expected_get(sync_url, ""),
        ExpectedRequest::new(
            HttpMethod::Get,
            &query_url,
            redirect_from(
                &query_url,
                "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn",
            ),
        ),
    ]);
    let observed = transport.clone();
    let store = session_store();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

    let error = client
        .classroom_search(1, "2026-04-20")
        .await
        .expect_err("raw SSO Location must invalidate the selected route");

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(observed.requests().unwrap().len(), 2, "query is sent once");
    observed.assert_exhausted().unwrap();
    assert!(store.snapshot().unwrap().is_none());
}

#[tokio::test]
async fn classroom_unauthorized_and_login_html_clear_the_route_session() {
    let sync_url = ubaa_core::features::classroom::CLASSROOM_SYNC_URL;
    let query_url = format!(
        "{}?xqid=1&floorid=&date=2026-04-20",
        ubaa_core::features::classroom::CLASSROOM_URL
    );
    for query_response in [
        response(401, &query_url, ""),
        response(
            200,
            &query_url,
            "<!DOCTYPE html><html><input name=\"execution\"><title>fixture</title></html>",
        ),
    ] {
        let transport = MockTransport::new([
            expected_get(sync_url, ""),
            ExpectedRequest::new(HttpMethod::Get, &query_url, query_response),
        ]);
        let store = session_store();
        let mut client =
            RouteClient::with_transport(ConnectionMode::Direct, transport, store.clone()).unwrap();

        let error = client
            .classroom_search(1, "2026-04-20")
            .await
            .expect_err("explicit classroom expiry must invalidate the selected route");

        assert_eq!(error.code, ErrorCode::AuthenticationRequired);
        assert!(store.snapshot().unwrap().is_none());
    }
}
