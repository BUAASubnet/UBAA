use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::domain::ConnectionMode;
use ubaa_core::error::Result;
use ubaa_core::facade::RouteClient;
use ubaa_core::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use ubaa_test_support::readonly_fixture;

use crate::common::{response, session_store_with};

#[derive(Clone, Default)]
struct CgyyTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for CgyyTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let index = self.requests.lock().expect("场馆请求锁").len();
        let response = match index {
            0 => {
                assert_eq!(request.method, HttpMethod::Get);
                assert_eq!(
                    request.url,
                    "https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin"
                );
                let mut response = response(200, &request.url, "场馆入口");
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec!["sso_buaa_zhjs_token=已脱敏; Path=/venue-zhjs-server/; Secure".into()],
                );
                response
            }
            1 => {
                assert_eq!(request.method, HttpMethod::Post);
                assert_eq!(
                    request.url,
                    "https://cgyy.buaa.edu.cn/venue-zhjs-server/api/login"
                );
                assert_eq!(
                    request.headers.get("Sso-Token").map(String::as_str),
                    Some("已脱敏")
                );
                response(
                    200,
                    &request.url,
                    r#"{"code":200,"data":{"token":{"access_token":"访问令牌已脱敏"}}}"#,
                )
            }
            2 => {
                assert_eq!(request.method, HttpMethod::Get);
                let url = url::Url::parse(&request.url).expect("场馆站点 URL");
                assert_eq!(url.path(), "/venue-zhjs-server/api/front/website/venues");
                let query = url.query_pairs().collect::<HashMap<_, _>>();
                assert_eq!(query.get("page").map(AsRef::as_ref), Some("-1"));
                assert_eq!(query.get("size").map(AsRef::as_ref), Some("-1"));
                assert_eq!(query.get("reservationRoleId").map(AsRef::as_ref), Some("3"));
                assert!(query.contains_key("nocache"));
                assert_eq!(
                    request.headers.get("cgAuthorization").map(String::as_str),
                    Some("访问令牌已脱敏")
                );
                assert_eq!(
                    request.headers.get("app-key").map(String::as_str),
                    Some("8fceb735082b5a529312040b58ea780b")
                );
                assert!(request.headers.contains_key("timestamp"));
                assert!(request.headers.contains_key("sign"));
                response(
                    200,
                    &request.url,
                    readonly_fixture("cgyy-sites.json").unwrap(),
                )
            }
            _ => panic!("场馆请求超出脚本"),
        };
        self.requests.lock().expect("场馆请求锁").push(request);
        Ok(response)
    }
}

#[tokio::test]
async fn 场馆站点查询先换取业务令牌并发送签名请求() {
    let transport = CgyyTransport::default();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("场馆主会话已脱敏"),
    )
    .unwrap();

    let result = client.cgyy_sites().await.unwrap();

    assert_eq!(result.data[0].id, 4);
    assert_eq!(observed.requests.lock().expect("场馆请求锁").len(), 3);
}
