use crate::common::{login_input, login_page, redirect, response, set_cookie};
use ubaa_core::facade::testing::{HttpMethod, SessionStore, from_webvpn_url, to_webvpn_url};
use ubaa_core::facade::{ConnectionMode, ErrorCode, RouteClient};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

const LOGIN: &str = "https://sso.buaa.edu.cn/login";
const ACTIVATE: &str =
    "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
const LANDING: &str = "https://uc.buaa.edu.cn/";
const INFO: &str = "https://uc.buaa.edu.cn/api/uc/userinfo";
const STATUS: &str = "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON";
const SERVICE: &str = "service=https%3a%2f%2fuc.buaa.edu.cn%2fapi%2flogin%3ftarget%3dhttps%253A%252F%252Fuc.buaa.edu.cn%252F%2523%252Fuser%252Flogin&sample=%2b+%2526";
fn routed(mode: ConnectionMode, value: &str) -> String {
    if mode == ConnectionMode::Direct {
        value.into()
    } else {
        to_webvpn_url(value).unwrap()
    }
}
fn login_steps(mode: ConnectionMode, prepared: bool, body: &str) -> Vec<ExpectedRequest> {
    let login = routed(mode, LOGIN);
    let status = routed(mode, STATUS);
    let path = url::Url::parse(&login)
        .unwrap()
        .path()
        .trim_end_matches("login")
        .to_owned();
    let cookie = format!("CASTGC=synthetic-cas; Path={path}; Secure; HttpOnly");
    let mut steps = Vec::new();
    if prepared {
        steps.push(ExpectedRequest::new(
            HttpMethod::Get,
            &login,
            set_cookie(redirect(&login, LANDING), &cookie),
        ));
    } else {
        steps.push(ExpectedRequest::new(
            HttpMethod::Get,
            &login,
            response(200, &login, login_page()),
        ));
        steps.push(ExpectedRequest::new(
            HttpMethod::Post,
            &login,
            set_cookie(redirect(&login, LANDING), &cookie),
        ));
    }
    steps.push(ExpectedRequest::new(
        HttpMethod::Get,
        &status,
        response(200, &status, body),
    ));
    steps
}
#[tokio::test]
async fn 两路线以sso验票核对身份且uc不可达不影响普通或预登录() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        for prepared in [false, true] {
            let transport = MockTransport::with_sso_checks(login_steps(
                mode,
                prepared,
                auth_fixture("userinfo-success.json").unwrap(),
            ));
            let observer = transport.clone();
            let store = MemorySessionStore::new();
            let mut client = RouteClient::with_transport(mode, transport, store.clone()).unwrap();
            assert_eq!(
                client
                    .login(login_input())
                    .await
                    .unwrap()
                    .school_id
                    .as_deref(),
                Some("TEST-0001")
            );
            assert!(store.load().unwrap().is_some());
            let requests = observer.requests().unwrap();
            assert!(requests.iter().all(|request| {
                from_webvpn_url(&request.url)
                    .unwrap()
                    .starts_with("https://sso.buaa.edu.cn/")
                    || request.url == "https://d.buaa.edu.cn/"
            }));
            assert_eq!(
                requests
                    .iter()
                    .filter(|request| request.method == HttpMethod::Post)
                    .count(),
                usize::from(!prepared)
            );
            let validate = requests
                .iter()
                .find(|request| request.url.contains("/serviceValidate?"))
                .unwrap();
            assert!(validate.headers["Cookie"].contains("CASTGC=synthetic-cas"));
            observer.assert_exhausted().unwrap();
        }
    }
}
#[tokio::test]
async fn 验票明确拒绝不能保存已认证会话() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let transport = MockTransport::with_sso_checks(login_steps(
            mode,
            false,
            r#"{"serviceResponse":{"authenticationFailure":{"code":"INVALID_TICKET"}}}"#,
        ));
        let observer = transport.clone();
        let store = MemorySessionStore::new();
        let mut client = RouteClient::with_transport(mode, transport, store.clone()).unwrap();
        assert_eq!(
            client.login(login_input()).await.unwrap_err().code,
            ErrorCode::AuthenticationRequired
        );
        assert!(store.load().unwrap().is_none());
        observer.assert_exhausted().unwrap();
    }
}
#[tokio::test]
async fn uc资料按需激活保留嵌套编码和独立cookie并升级sso到https() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        for wrapped in [false, true] {
            let mut steps =
                login_steps(mode, false, auth_fixture("userinfo-success.json").unwrap());
            let activate = routed(mode, ACTIVATE);
            let info = routed(mode, INFO);
            let landing = routed(mode, LANDING);
            let sso = routed(mode, &format!("{LOGIN}?{SERVICE}"));
            let raw = format!("http://sso.buaa.edu.cn/login?{SERVICE}");
            let location = if wrapped {
                to_webvpn_url(&raw).unwrap()
            } else {
                raw
            };
            let callback = routed(mode, &format!("{ACTIVATE}&ticket=ST-uc-fixture"));
            let path = url::Url::parse(&info)
                .unwrap()
                .path()
                .trim_end_matches("api/uc/userinfo")
                .to_owned();
            let cookie = format!("JSESSIONID=synthetic-uc; Path={path}; Secure; HttpOnly");
            steps.extend([
                ExpectedRequest::new(
                    HttpMethod::Get,
                    &info,
                    response(200, &info, r#"{"code":10600,"data":null}"#),
                ),
                ExpectedRequest::new(HttpMethod::Get, &activate, redirect(&activate, &location)),
                ExpectedRequest::new(HttpMethod::Get, &sso, redirect(&sso, &callback)),
                ExpectedRequest::new(
                    HttpMethod::Get,
                    &callback,
                    set_cookie(redirect(&callback, &activate), &cookie),
                ),
                ExpectedRequest::new(HttpMethod::Get, &activate, redirect(&activate, &landing)),
                ExpectedRequest::new(
                    HttpMethod::Get,
                    &landing,
                    response(200, &landing, "<html></html>"),
                ),
                ExpectedRequest::new(
                    HttpMethod::Get,
                    &info,
                    response(200, &info, auth_fixture("userinfo-success.json").unwrap()),
                ),
            ]);
            let transport = MockTransport::with_sso_checks(steps);
            let observer = transport.clone();
            let mut client =
                RouteClient::with_transport(mode, transport, MemorySessionStore::new()).unwrap();
            client.login(login_input()).await.unwrap();
            client.get_user_info().await.unwrap();
            let requests = observer.requests().unwrap();
            assert!(
                requests
                    .iter()
                    .all(|request| request.url.starts_with("https://"))
            );
            assert!(
                requests
                    .iter()
                    .find(|request| request.url == sso)
                    .unwrap()
                    .headers["Cookie"]
                    .contains("CASTGC=synthetic-cas")
            );
            assert!(
                !requests
                    .iter()
                    .find(|request| request.url == callback)
                    .unwrap()
                    .headers
                    .get("Cookie")
                    .is_some_and(|cookie| cookie.contains("CASTGC="))
            );
            assert!(requests.last().unwrap().headers["Cookie"].contains("JSESSIONID=synthetic-uc"));
            observer.assert_exhausted().unwrap();
        }
    }
}
#[tokio::test]
async fn uc激活循环只使资料读取失败且保留sso会话() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let mut steps = login_steps(mode, false, auth_fixture("userinfo-success.json").unwrap());
        let activate = routed(mode, ACTIVATE);
        let info = routed(mode, INFO);
        steps.push(ExpectedRequest::new(
            HttpMethod::Get,
            &info,
            response(200, &info, r#"{"code":10600,"data":null}"#),
        ));
        for _ in 0..11 {
            steps.push(ExpectedRequest::new(
                HttpMethod::Get,
                &activate,
                redirect(&activate, &activate),
            ));
        }
        let transport = MockTransport::with_sso_checks(steps);
        let observer = transport.clone();
        let store = MemorySessionStore::new();
        let mut client = RouteClient::with_transport(mode, transport, store.clone()).unwrap();
        client.login(login_input()).await.unwrap();
        assert_eq!(
            client.get_user_info().await.unwrap_err().code,
            ErrorCode::UpstreamChanged
        );
        assert!(store.load().unwrap().is_some());
        observer.assert_exhausted().unwrap();
    }
}
