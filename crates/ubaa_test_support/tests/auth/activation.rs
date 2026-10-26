use ubaa_core::facade::testing::{
    HttpMethod, HttpRequest, SessionStore, from_webvpn_url, to_webvpn_url,
};
use ubaa_core::facade::{ConnectionMode, ErrorCode, RouteClient};
use ubaa_test_support::{ExpectedRequest, MemorySessionStore, MockTransport, auth_fixture};

use crate::common::{login_input, login_page, redirect, response, set_cookie};

const LOGIN: &str = "https://sso.buaa.edu.cn/login";
const ACTIVATE: &str =
    "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin";
const LANDING: &str = "https://uc.buaa.edu.cn/";
const STATUS: &str = "https://uc.buaa.edu.cn/api/uc/status";
const INFO: &str = "https://uc.buaa.edu.cn/api/uc/userinfo";
// 合成嵌套编码，检测跳转过程中是否错误地重编码 service。
const SERVICE: &str = "service=https%3a%2f%2fuc.buaa.edu.cn%2fapi%2flogin%3ftarget%3dhttps%253A%252F%252Fuc.buaa.edu.cn%252F%2523%252Fuser%252Flogin&sample=%2b+%2526";

fn routed(mode: ConnectionMode, value: &str) -> String {
    match mode {
        ConnectionMode::Direct => value.into(),
        ConnectionMode::WebVpn => to_webvpn_url(value).unwrap(),
    }
}

async fn activation(mode: ConnectionMode, prepared: bool, wrapped: bool, valid: bool) {
    let login = routed(mode, LOGIN);
    let activate = routed(mode, ACTIVATE);
    let landing = routed(mode, LANDING);
    let status = routed(mode, STATUS);
    let info = routed(mode, INFO);
    let sso = routed(mode, &format!("{LOGIN}?{SERVICE}"));
    let raw_location = format!("http://sso.buaa.edu.cn/login?{SERVICE}");
    let location = if wrapped {
        to_webvpn_url(&raw_location).unwrap()
    } else {
        raw_location
    };
    let callback = routed(mode, &format!("{ACTIVATE}&ticket=ST-synthetic"));
    let sso_path = url::Url::parse(&login)
        .unwrap()
        .path()
        .trim_end_matches("login")
        .to_string();
    let uc_path = url::Url::parse(&status)
        .unwrap()
        .path()
        .trim_end_matches("api/uc/status")
        .to_string();
    let cas_cookie = format!("CASTGC=synthetic-cas; Path={sso_path}; Secure; HttpOnly");
    let uc_cookie = format!("JSESSIONID=synthetic-uc; Path={uc_path}; Secure; HttpOnly");
    let mut steps = vec![];
    if prepared {
        steps.push(ExpectedRequest::new(
            HttpMethod::Get,
            &login,
            set_cookie(redirect(&login, &landing), &cas_cookie),
        ));
    } else {
        steps.extend([
            ExpectedRequest::new(HttpMethod::Get, &login, response(200, &login, login_page())),
            ExpectedRequest::new(
                HttpMethod::Post,
                &login,
                set_cookie(redirect(&login, &landing), &cas_cookie),
            ),
            ExpectedRequest::new(
                HttpMethod::Get,
                &landing,
                response(200, &landing, "<html></html>"),
            ),
        ]);
    }
    steps.extend([
        ExpectedRequest::new(HttpMethod::Get, &activate, redirect(&activate, &location)),
        ExpectedRequest::new(HttpMethod::Get, &sso, redirect(&sso, &callback)),
        ExpectedRequest::new(HttpMethod::Get, &callback, set_cookie(redirect(&callback, &activate), &uc_cookie)),
        ExpectedRequest::new(HttpMethod::Get, &activate, redirect(&activate, &landing)),
        ExpectedRequest::new(HttpMethod::Get, &landing, response(200, &landing, "<html></html>")),
        ExpectedRequest::new(HttpMethod::Get, &status, response(200, &status,
            if valid { r#"{"code":0,"data":{"name":"Fixture User","schoolid":"TEST-0001","username":"fixture-user"}}"# }
            else { r#"{"code":10600,"data":null}"# })),
    ]);
    if valid {
        steps.push(ExpectedRequest::new(
            HttpMethod::Get,
            &info,
            response(200, &info, auth_fixture("userinfo-success.json").unwrap()),
        ));
    }
    let transport = MockTransport::new(steps);
    let observer = transport.clone();
    let store = MemorySessionStore::new();
    let mut client = RouteClient::with_transport(mode, transport, store.clone()).unwrap();
    let result = client.login(login_input()).await;
    if valid {
        assert_eq!(result.unwrap().school_id.as_deref(), Some("TEST-0001"));
        assert!(store.load().unwrap().is_some());
    } else {
        assert_eq!(result.unwrap_err().code, ErrorCode::AuthenticationRequired);
        assert!(store.load().unwrap().is_none());
    }
    observer.assert_exhausted().unwrap();
    let requests = observer.requests().unwrap();
    assert_auth_requests(&requests, mode, prepared, &sso, &callback, &status);
}

fn assert_auth_requests(
    requests: &[HttpRequest],
    mode: ConnectionMode,
    prepared: bool,
    sso: &str,
    callback: &str,
    status: &str,
) {
    let ticket_request = requests.iter().find(|r| r.url == sso).unwrap();
    assert!(ticket_request.headers["Cookie"].contains("CASTGC=synthetic-cas"));
    let callback_request = requests.iter().find(|r| r.url == callback).unwrap();
    assert!(
        !callback_request
            .headers
            .get("Cookie")
            .is_some_and(|h| h.contains("CASTGC="))
    );
    assert!(
        requests.iter().find(|r| r.url == status).unwrap().headers["Cookie"]
            .contains("JSESSIONID=synthetic-uc")
    );
    let posts: Vec<_> = requests
        .iter()
        .filter(|r| r.method == HttpMethod::Post)
        .collect();
    assert_eq!(posts.len(), usize::from(!prepared));
    if let Some(post) = posts.first() {
        let fields: std::collections::BTreeMap<_, _> = url::form_urlencoded::parse(&post.body)
            .into_owned()
            .collect();
        assert_eq!(fields["type"], "username_password");
        assert_eq!(fields["_eventId"], "submit");
        assert_eq!(
            post.headers["Content-Type"],
            "application/x-www-form-urlencoded"
        );
    }
    for request in requests {
        assert!(!request.url.contains("/fingerprint"));
        assert!(request.url.starts_with("https://"));
        if mode == ConnectionMode::WebVpn {
            assert!(request.url.starts_with("https://d.buaa.edu.cn/"));
            assert!(
                from_webvpn_url(&request.url)
                    .unwrap()
                    .starts_with("https://")
            );
        } else {
            assert!(!request.url.contains("d.buaa.edu.cn"));
        }
    }
}

#[tokio::test]
async fn 直连完整票据链保留编码和安全cookie且兼容预登录() {
    for prepared in [false, true] {
        for wrapped in [false, true] {
            activation(ConnectionMode::Direct, prepared, wrapped, true).await;
        }
    }
}

#[tokio::test]
async fn webvpn完整票据链始终固定网关且上游sso使用https() {
    for prepared in [false, true] {
        for wrapped in [false, true] {
            activation(ConnectionMode::WebVpn, prepared, wrapped, true).await;
        }
    }
}

#[tokio::test]
async fn 门户返回200仍须校验uc状态不能保存未登录会话() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        activation(mode, false, true, false).await;
    }
}

#[tokio::test]
async fn uc激活循环有上限且预登录不提交密码() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let login = routed(mode, LOGIN);
        let activate = routed(mode, ACTIVATE);
        let mut steps = vec![ExpectedRequest::new(
            HttpMethod::Get,
            &login,
            redirect(&login, LANDING),
        )];
        for _ in 0..11 {
            steps.push(ExpectedRequest::new(
                HttpMethod::Get,
                &activate,
                redirect(&activate, &activate),
            ));
        }
        let transport = MockTransport::new(steps);
        let observer = transport.clone();
        let store = MemorySessionStore::new();
        let mut client = RouteClient::with_transport(mode, transport, store.clone()).unwrap();
        assert_eq!(
            client.prepare_login().await.unwrap_err().code,
            ErrorCode::UpstreamChanged
        );
        assert!(
            observer
                .requests()
                .unwrap()
                .iter()
                .all(|r| r.method == HttpMethod::Get)
        );
        assert!(store.load().unwrap().is_none());
        observer.assert_exhausted().unwrap();
    }
}
