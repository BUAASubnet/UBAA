use super::*;
use std::sync::Mutex;
use ubaa_core::facade::testing::from_webvpn_url;
use ubaa_core::facade::{LoginInput, SecretValue, UbaaError};

#[path = "login_retry.rs"]
mod login_retry;

#[derive(Clone)]
struct IdentityTransport {
    requests: Arc<Mutex<Vec<String>>>,
    invalid: bool,
}

#[async_trait]
impl HttpTransport for IdentityTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let direct = from_webvpn_url(&request.url).unwrap();
        let url = url::Url::parse(&direct).unwrap();
        self.requests.lock().unwrap().push(direct.clone());
        if url.host_str() == Some("uc.buaa.edu.cn") {
            return Err(UbaaError::new(
                ErrorCode::NetworkError,
                ubaa_core::facade::ErrorKind::Network,
                true,
                "用户中心不可达",
            ));
        }
        let mut response = HttpResponse::new(200, request.url.clone(), Vec::new());
        if url.path() == "/serviceValidate" {
            response.body = if self.invalid {
                br#"{"serviceResponse":{"authenticationFailure":{"code":"INVALID_TICKET"}}}"#
                    .to_vec()
            } else {
                br#"{"user":"fixture-account","attributes":{"employeeNumber":["fixture-account"],"name":["Fixture"]}}"#.to_vec()
            };
        } else if url.query_pairs().any(|(key, value)| {
            key == "service" && value == "https://d.buaa.edu.cn/login?cas_login=true"
        }) {
            response.status = 302;
            response.headers.insert("Location".into(), vec!["https://d.buaa.edu.cn/https/77726476706e69737468656265737421f4b94389263126557a1dc7af96/login?cas_login=true&ticket=ST-fixture".into()]);
        } else if url.host_str() == Some("d.buaa.edu.cn") && url.path() == "/login" {
            assert!(
                request.url.contains("/https/"),
                "网关自指回调需要保留原包装路径"
            );
            response.status = 302;
            response.headers.insert(
                "Location".into(),
                vec!["https://d.buaa.edu.cn/token-login?token=fixture".into()],
            );
        } else if url.host_str() == Some("d.buaa.edu.cn") && url.path() == "/token-login" {
            response.status = 302;
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["GATEWAY=fixture; Path=/; Secure".into()],
            );
            response
                .headers
                .insert("Location".into(), vec!["https://uc.buaa.edu.cn/".into()]);
        } else if url.host_str() == Some("d.buaa.edu.cn") && url.path() == "/" {
            assert!(
                request
                    .headers
                    .get("Cookie")
                    .is_some_and(|cookie| cookie.contains("GATEWAY=fixture"))
            );
            response.body = b"gateway ready".to_vec();
        } else if url.query_pairs().any(|(key, _)| key == "service") {
            response.status = 302;
            response.headers.insert("Location".into(), vec!["https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-fixture".into()]);
        } else if format!("{:?}", request.method) == "Post" {
            response.status = 302;
            response
                .headers
                .insert("Location".into(), vec!["https://uc.buaa.edu.cn/".into()]);
        } else {
            response.body = br#"<form action="login"><input type="hidden" name="execution" value="fixture-execution"></form>"#.to_vec();
        }
        Ok(response)
    }
}

#[tokio::test]
async fn uc不可达时两路线仍能登录并通过独立sso身份检查() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = test_root("sso-independent");
        let requests = Arc::new(Mutex::new(Vec::new()));
        let transport = IdentityTransport {
            requests: requests.clone(),
            invalid: false,
        };
        let mut client = UbaaClient::with_transports(
            transport.clone(),
            transport,
            FileSessionStore::new(&root).unwrap(),
        )
        .unwrap();
        let result = client
            .login_required_route(
                route,
                LoginInput {
                    username: "fixture-account".into(),
                    password: SecretValue::new("fixture-password"),
                },
            )
            .await
            .unwrap();
        assert_eq!(result.data.school_id.as_deref(), Some("fixture-account"));
        assert_eq!(client.active_routes(), vec![route]);
        if route == ConnectionMode::WebVpn {
            assert!(
                requests
                    .lock()
                    .unwrap()
                    .iter()
                    .any(|url| url.contains("cas_login%3Dtrue")),
                "WebVPN 必须建立网关自己的登录会话"
            );
        }
        assert!(
            requests
                .lock()
                .unwrap()
                .iter()
                .all(|url| !url.contains("uc.buaa.edu.cn"))
        );
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn 票据校验失败不能保存已认证会话() {
    let root = test_root("sso-invalid-ticket");
    let transport = IdentityTransport {
        requests: Arc::default(),
        invalid: true,
    };
    let mut client = UbaaClient::with_transports(
        transport.clone(),
        transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    assert!(
        client
            .login_required_route(
                ConnectionMode::Direct,
                LoginInput {
                    username: "fixture-account".into(),
                    password: SecretValue::new("fixture-password")
                }
            )
            .await
            .is_err()
    );
    assert!(client.active_routes().is_empty());
    let _ = std::fs::remove_dir_all(root);
}
