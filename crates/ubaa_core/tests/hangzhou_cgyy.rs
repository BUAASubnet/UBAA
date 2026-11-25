//! 杭州校区空间预约（hzsm）经杭州统一认证（hzsso）北航 CAS 插件登录的脱敏 Mock 测试。
//!
//! 所有令牌、票据、编号均为合成值；协议依据见 `docs/protocol/parity/cgyy.md` 杭州专项记录。

use async_trait::async_trait;
use std::sync::{Arc, Mutex};
use ubaa_core::facade::testing::{
    FileSessionStore, HttpMethod, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot,
    SessionStore,
};
use ubaa_core::facade::{ConnectionMode, ErrorCode, Result, RouteClient};

const CAS_LOGIN: &str = "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fhzsso.buaa.edu.cn%2Fpublic%2Fapi%2Fauthenticate%2Fplugin_cas%2Fstatic%2Fcallback.html%3FenterpriseAuthId%3Didaasplugin_cas";

fn client(
    mode: ConnectionMode,
    transport: HzTransport,
    name: &str,
) -> (RouteClient, std::path::PathBuf) {
    let root = std::env::temp_dir().join(format!("ubaa-hz-cgyy-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    (
        RouteClient::with_transport(mode, transport, store).unwrap(),
        root,
    )
}

fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn json_body(request: &HttpRequest) -> serde_json::Value {
    serde_json::from_slice(&request.body).expect("hzsso 请求体应为 JSON")
}

fn path_of(request: &HttpRequest) -> String {
    let url = url::Url::parse(&request.url).unwrap();
    format!("{}{}", url.host_str().unwrap(), url.path())
}

#[test]
fn 杭州场馆首次读取先经北航cas登录hzsso再取站点() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, root) = client(
        ConnectionMode::Direct,
        HzTransport::new(Arc::clone(&requests), false),
        "first",
    );

    let sites = runtime()
        .block_on(client.hangzhou_cgyy_sites())
        .unwrap()
        .data;

    assert_eq!(sites.len(), 1);
    assert_eq!(sites[0].id, 701);
    assert_eq!(sites[0].venue_name, "合成场馆");
    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests.iter().map(path_of).collect();
    assert_eq!(
        paths,
        vec![
            "hzsso.buaa.edu.cn/enduser/sp/sso/idaasplugin_jwt38",
            "hzsso.buaa.edu.cn/frontend/login/",
            "hzsso.buaa.edu.cn/api/public/bff/v1.2/frontend/login_data",
            "hzsso.buaa.edu.cn/api/public/bff/v1.2/authenticate/plugin/generate_trace_id",
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/login",
            "sso.buaa.edu.cn/login",
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html",
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/valid_ticket",
            "hzsso.buaa.edu.cn/api/public/bff/v1.2/authenticate/plugin/validate_trace_id",
            "hzsso.buaa.edu.cn/api/bff/v1.2/commons/session/save",
            "hzsso.buaa.edu.cn/enduser/sp/sso/idaasplugin_jwt38",
            "hzsm.buaa.edu.cn/venue-server/loginto",
            "hzsm.buaa.edu.cn/venue/login",
            "hzsm.buaa.edu.cn/venue-server/api/login",
            "hzsm.buaa.edu.cn/venue-server/api/front/website/venues",
        ]
    );

    let trace = &requests[3];
    assert_eq!(trace.method, HttpMethod::Post);
    assert_eq!(
        json_body(trace),
        serde_json::json!({
            "enterpriseAuthId": "idaasplugin_cas",
            "enterpriseId": "idaas",
            "clientId": "client-fixture",
        })
    );
    assert_eq!(
        json_body(&requests[4]),
        serde_json::json!({"enterpriseAuthId": "idaasplugin_cas", "traceId": "trace-fixture"})
    );
    assert_eq!(
        json_body(&requests[7]),
        serde_json::json!({
            "enterpriseAuthId": "idaasplugin_cas",
            "traceId": "trace-fixture",
            "ticket": "ST-fixture",
        })
    );
    assert_eq!(
        json_body(&requests[8]),
        serde_json::json!({"traceId": "trace-fixture"})
    );
    let save = &requests[9];
    assert_eq!(
        json_body(save),
        serde_json::json!({"access_token": "idaas-fixture"})
    );
    assert_eq!(
        save.headers.get("Authorization").map(String::as_str),
        Some("Bearer idaas-fixture")
    );

    let login = &requests[13];
    assert_eq!(login.method, HttpMethod::Post);
    assert_eq!(
        login.headers.get("Sso-Token").map(String::as_str),
        Some("h3i-sso-fixture")
    );
    assert_eq!(
        login.headers.get("app-key").map(String::as_str),
        Some("8fceb735082b5a529312040b58ea780b")
    );

    let venues = url::Url::parse(&requests[14].url).unwrap();
    assert_eq!(venues.scheme(), "https");
    let query: std::collections::BTreeMap<_, _> = venues.query_pairs().into_owned().collect();
    assert_eq!(query.get("page").map(String::as_str), Some("-1"));
    assert_eq!(query.get("size").map(String::as_str), Some("-1"));
    assert!(!query.contains_key("reservationRoleId"));
    assert_eq!(
        requests[14]
            .headers
            .get("cgAuthorization")
            .map(String::as_str),
        Some("hz-access-fixture")
    );
    drop(requests);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 杭州统一认证已登录时直接进入场馆且连续读取复用业务令牌() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, root) = client(
        ConnectionMode::Direct,
        HzTransport::new(Arc::clone(&requests), true),
        "reuse",
    );
    let rt = runtime();

    rt.block_on(client.hangzhou_cgyy_sites()).unwrap();
    rt.block_on(client.hangzhou_cgyy_sites()).unwrap();

    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests.iter().map(path_of).collect();
    assert!(!paths.iter().any(|path| path.contains("plugin_cas")));
    assert_eq!(
        paths
            .iter()
            .filter(|path| path.ends_with("/venue-server/api/login"))
            .count(),
        1
    );
    assert_eq!(
        paths
            .iter()
            .filter(|path| path.ends_with("/api/front/website/venues"))
            .count(),
        2
    );
    drop(requests);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 杭州场馆我的预约使用hzsm订单接口() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, root) = client(
        ConnectionMode::Direct,
        HzTransport::new(Arc::clone(&requests), true),
        "orders",
    );

    let page = runtime()
        .block_on(client.hangzhou_cgyy_orders(0, 10))
        .unwrap()
        .data;

    assert_eq!(page.total_elements, 1);
    assert_eq!(page.content[0].id, 9001);
    let requests = requests.lock().unwrap();
    let orders = requests
        .iter()
        .find(|request| request.url.contains("/venue-server/api/orders/mine"))
        .expect("应读取杭州我的预约");
    let query: std::collections::BTreeMap<_, _> = url::Url::parse(&orders.url)
        .unwrap()
        .query_pairs()
        .into_owned()
        .collect();
    assert_eq!(query.get("page").map(String::as_str), Some("0"));
    assert_eq!(query.get("size").map(String::as_str), Some("10"));
    drop(requests);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 杭州场馆在webvpn路线明确不支持且不发请求() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, root) = client(
        ConnectionMode::WebVpn,
        HzTransport::new(Arc::clone(&requests), true),
        "webvpn",
    );

    let error = runtime()
        .block_on(client.hangzhou_cgyy_sites())
        .unwrap_err();

    assert_eq!(error.code, ErrorCode::Unsupported);
    assert!(requests.lock().unwrap().is_empty());
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 北航cas未签发票据时报认证失败而非成功() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut transport = HzTransport::new(Arc::clone(&requests), false);
    transport.cas_without_ticket = true;
    let (mut client, root) = client(ConnectionMode::Direct, transport, "noticket");

    let error = runtime()
        .block_on(client.hangzhou_cgyy_sites())
        .unwrap_err();

    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert!(
        !requests
            .lock()
            .unwrap()
            .iter()
            .any(|request| request.url.contains("valid_ticket"))
    );
    let _ = std::fs::remove_dir_all(root);
}

struct HzTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    hzsso_logged_in: Arc<Mutex<bool>>,
    cas_without_ticket: bool,
}

impl HzTransport {
    fn new(requests: Arc<Mutex<Vec<HttpRequest>>>, hzsso_logged_in: bool) -> Self {
        Self {
            requests,
            hzsso_logged_in: Arc::new(Mutex::new(hzsso_logged_in)),
            cas_without_ticket: false,
        }
    }
}

fn ok(url: &str, body: &str) -> HttpResponse {
    HttpResponse::new(200, url, body.as_bytes().to_vec())
}

fn redirect(url: &str, location: &str) -> HttpResponse {
    let mut response = HttpResponse::new(302, url, Vec::new());
    response
        .headers
        .insert("location".into(), vec![location.into()]);
    response
}

#[async_trait]
impl HttpTransport for HzTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let parsed = url::Url::parse(&request.url).unwrap();
        let key = format!("{}{}", parsed.host_str().unwrap(), parsed.path());
        let url = request.url.as_str();
        let response = match key.as_str() {
            "hzsso.buaa.edu.cn/enduser/sp/sso/idaasplugin_jwt38" => {
                if *self.hzsso_logged_in.lock().unwrap() {
                    redirect(
                        url,
                        "https://hzsm.buaa.edu.cn/venue-server/loginto?id_token=jwt-fixture",
                    )
                } else {
                    redirect(url, "/frontend/login/#/login?sp_code=sp-fixture")
                }
            }
            "hzsso.buaa.edu.cn/frontend/login/" => ok(url, "<html>login</html>"),
            "hzsso.buaa.edu.cn/api/public/bff/v1.2/frontend/login_data" => ok(
                url,
                r#"{"success":true,"code":"200","data":{"clientId":"client-fixture"}}"#,
            ),
            "hzsso.buaa.edu.cn/api/public/bff/v1.2/authenticate/plugin/generate_trace_id" => ok(
                url,
                r#"{"success":true,"code":"200","data":{"traceId":"trace-fixture","locationURL":"http://hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/index.html"}}"#,
            ),
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/login" => ok(
                url,
                &serde_json::json!({"success": true, "loginUrl": CAS_LOGIN}).to_string(),
            ),
            "sso.buaa.edu.cn/login" => {
                if self.cas_without_ticket {
                    ok(url, "<form name=\"execution\">username_password</form>")
                } else {
                    redirect(
                        url,
                        "http://hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html?enterpriseAuthId=idaasplugin_cas&ticket=ST-fixture",
                    )
                }
            }
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html" => {
                ok(url, "<html>callback</html>")
            }
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/valid_ticket" => ok(
                url,
                r#"{"success":true,"frontendAdapterAddress":"http://hzsso.buaa.edu.cn/frontend/login/#/pluginAdapter"}"#,
            ),
            "hzsso.buaa.edu.cn/api/public/bff/v1.2/authenticate/plugin/validate_trace_id" => ok(
                url,
                r#"{"success":true,"code":"200","data":{"accessToken":"idaas-fixture","portalBound":true}}"#,
            ),
            "hzsso.buaa.edu.cn/api/bff/v1.2/commons/session/save" => {
                *self.hzsso_logged_in.lock().unwrap() = true;
                ok(
                    url,
                    r#"{"success":true,"code":"200","data":{"result":true}}"#,
                )
            }
            "hzsm.buaa.edu.cn/venue-server/loginto" => {
                let mut response = redirect(url, "https://hzsm.buaa.edu.cn/venue/login");
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec!["sso_buaa_h3i_token=h3i-sso-fixture; Path=/".into()],
                );
                response
            }
            "hzsm.buaa.edu.cn/venue/login" => ok(url, "<html>venue</html>"),
            "hzsm.buaa.edu.cn/venue-server/api/login" => ok(
                url,
                r#"{"code":200,"data":{"token":{"access_token":"hz-access-fixture"}}}"#,
            ),
            "hzsm.buaa.edu.cn/venue-server/api/front/website/venues" => ok(
                url,
                r#"{"code":200,"data":{"totalElements":1,"content":[{"id":701,"siteName":"合成楼","venueName":"合成场馆","campusName":"合成校区"}]}}"#,
            ),
            "hzsm.buaa.edu.cn/venue-server/api/orders/mine" => ok(
                url,
                r#"{"code":200,"data":{"content":[{"id":9001,"tradeNo":"synthetic-trade","venueSiteId":701,"orderStatus":1}],"totalElements":1,"totalPages":1,"size":10,"number":0}}"#,
            ),
            _ => panic!("未预期的杭州场馆请求: {key}"),
        };
        Ok(response)
    }
}
