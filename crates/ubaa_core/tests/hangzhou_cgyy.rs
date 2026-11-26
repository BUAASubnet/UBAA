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

/// 首次登录的完整请求顺序（2026-11-25 真机诊断核对过主机与路径）。
const FIRST_LOGIN_PATHS: [&str; 17] = [
    "hzsso.buaa.edu.cn/enduser/sp/sso/idaasplugin_jwt38",
    "hzsso.buaa.edu.cn/login",
    "hzsso.buaa.edu.cn/api/public/bff/v1.2/frontend/login_data",
    "hzsso.buaa.edu.cn/api/public/bff/v1.2/authenticate/plugin/generate_trace_id",
    "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/login",
    "sso.buaa.edu.cn/login",
    "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/idaasplugin_cas/receive_ticket",
    "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html",
    "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/valid_ticket",
    "hzsso.buaa.edu.cn/api/public/bff/v1.2/authenticate/plugin/validate_trace_id",
    "hzsso.buaa.edu.cn/api/bff/v1.2/commons/session/save",
    "hzsso.buaa.edu.cn/enduser/sp/sso/idaasplugin_jwt38",
    "hzsm.buaa.edu.cn/venue-server/loginto",
    "hzsm.buaa.edu.cn/venue/login",
    "hzsm.buaa.edu.cn/venue-server/api/login",
    "hzsm.buaa.edu.cn/venue-server/roleLogin",
    "hzsm.buaa.edu.cn/venue-server/api/front/website/venue_information",
];

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
    assert_eq!(paths, FIRST_LOGIN_PATHS);

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
        json_body(&requests[8]),
        serde_json::json!({
            "enterpriseAuthId": "idaasplugin_cas",
            "traceId": "trace-fixture",
            "ticket": "ST-fixture",
        })
    );
    assert_eq!(
        json_body(&requests[9]),
        serde_json::json!({"traceId": "trace-fixture"})
    );
    let save = &requests[10];
    assert_eq!(
        json_body(save),
        serde_json::json!({"access_token": "idaas-fixture"})
    );
    assert_eq!(
        save.headers.get("Authorization").map(String::as_str),
        Some("Bearer idaas-fixture")
    );

    let login = &requests[14];
    assert_eq!(login.method, HttpMethod::Post);
    assert_eq!(
        login.headers.get("Sso-Token").map(String::as_str),
        Some("h3i-sso-fixture")
    );
    assert_eq!(
        login.headers.get("app-key").map(String::as_str),
        Some("8fceb735082b5a529312040b58ea780b")
    );

    let role = &requests[15];
    assert_eq!(role.method, HttpMethod::Post);
    assert_eq!(
        role.headers.get("cgAuthorization").map(String::as_str),
        Some("hz-access-fixture")
    );
    assert_eq!(String::from_utf8_lossy(&role.body), "roleid=3");

    let venues = url::Url::parse(&requests[16].url).unwrap();
    assert_eq!(venues.scheme(), "https");
    let query: std::collections::BTreeMap<_, _> = venues.query_pairs().into_owned().collect();
    // 杭州前端「场地预约」页：`venue_information`，`isNeedSearchVenue=0`、`resourceType=1`（SITE）。
    assert_eq!(
        query.get("isNeedSearchVenue").map(String::as_str),
        Some("0")
    );
    assert_eq!(query.get("resourceType").map(String::as_str), Some("1"));
    assert!(!query.contains_key("reservationRoleId"));
    assert_eq!(
        requests[16]
            .headers
            .get("cgAuthorization")
            .map(String::as_str),
        Some("hz-role-fixture")
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
            .filter(|path| path.ends_with("/api/front/website/venue_information"))
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
    /// 写入 Mock：`day/info.isFee`、`captcha/check` 结果与订单详情 `payFee`。
    is_fee: i64,
    captcha_ok: bool,
    pay_fee: f64,
}

impl HzTransport {
    fn new(requests: Arc<Mutex<Vec<HttpRequest>>>, hzsso_logged_in: bool) -> Self {
        Self {
            requests,
            hzsso_logged_in: Arc::new(Mutex::new(hzsso_logged_in)),
            cas_without_ticket: false,
            is_fee: 0,
            captcha_ok: true,
            pay_fee: 0.0,
        }
    }
}

/// 结构取自 2026-11-25 杭州实录（键名与类型），值全部为合成值。
fn day_info_body(is_fee: i64) -> String {
    let slot = |status: i32, admin_take: bool| {
        serde_json::json!({
            "adminTake": admin_take, "adminRemark": if admin_take { "教学使用" } else { "" },
            "tradeNo": null, "orderId": null, "reservationStatus": status, "orderFee": null,
            "startDate": "2026-11-26 09:00", "endDate": "2026-11-26 10:00", "useNum": 0,
            "waitNum": 0, "alreadyNum": 0, "takeUp": false, "takeUpExplain": null,
            "spaceName": "合成讨论室"
        })
    };
    serde_json::json!({"code": 200, "message": "OK", "data": {
        "advanceReservationDays": 3, "reservationTotalNum": 1, "isTakeUp": 0,
        "reservationDateList": ["2026-11-26"],
        "spaceTimeInfo": [
            {"id": 331_101, "beginTime": "09:00", "endTime": "10:00", "limitRoles": null},
            {"id": 331_102, "beginTime": "10:00", "endTime": "11:00", "limitRoles": null},
            {"id": 331_103, "beginTime": "11:00", "endTime": "12:00", "limitRoles": null}
        ],
        "reservationDateSpaceInfo": {"2026-11-26": [{
            "331101": slot(1, false), "331102": slot(2, true), "331103": slot(1, false),
            "venueSpaceGroupId": null,
            "spaceName": "合成讨论室", "id": 70, "venueSiteId": 323
        }]},
        "weekDisplay": false, "token": "day-token-fixture", "orderParamView": {}, "siteParam": {},
        "isFee": is_fee, "notReserveType": 0
    }})
    .to_string()
}

fn form_of(request: &HttpRequest) -> std::collections::BTreeMap<String, String> {
    url::form_urlencoded::parse(&request.body)
        .into_owned()
        .collect()
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

impl HzTransport {
    /// 预约、验证码与取消的合成响应。
    fn write_response(&self, key: &str, url: &str) -> Option<HttpResponse> {
        Some(match key {
            "hzsm.buaa.edu.cn/venue-server/api/reservation/day/info" => {
                ok(url, &day_info_body(self.is_fee))
            }
            // 合成 16 字节密钥，图片为非真实的 Base64 片段。
            "hzsm.buaa.edu.cn/venue-server/api/captcha/get" => ok(
                url,
                r#"{"code":200,"data":{"repCode":"0000","repData":{"secretKey":"abcdefghijklmnop","token":"captcha-token-fixture","originalImageBase64":"b3JpZ2luYWw=","jigsawImageBase64":"amlnc2F3","result":false},"success":true},"message":"OK"}"#,
            ),
            "hzsm.buaa.edu.cn/venue-server/api/captcha/check" => ok(
                url,
                &format!(
                    r#"{{"code":200,"data":{{"repCode":"0000","repData":{{"result":{0}}},"success":{0}}},"message":"OK"}}"#,
                    self.captcha_ok
                ),
            ),
            "hzsm.buaa.edu.cn/venue-server/api/reservation/order/submit" => ok(
                url,
                r#"{"code":200,"data":{"id":71425,"tradeNo":"D000000000001","reservationStartDate":"2026-11-26 09:00:00","reservationEndDate":"2026-11-26 10:00:00"},"message":"OK"}"#,
            ),
            "hzsm.buaa.edu.cn/venue-server/api/venue/finances/order/detail" => ok(
                url,
                &format!(
                    r#"{{"code":200,"data":{{"payFee":{:.1},"payStatus":1,"orderStatus":1,"orderId":71425}},"message":"OK"}}"#,
                    self.pay_fee
                ),
            ),
            "hzsm.buaa.edu.cn/venue-server/api/venue/finances/order/pay" => {
                ok(url, r#"{"code":200,"data":{"payFee":0.0},"message":"OK"}"#)
            }
            "hzsm.buaa.edu.cn/venue-server/api/orders/cancel_tip" => ok(
                url,
                r#"{"code":200,"data":{"tip":"合成取消提醒"},"message":"OK"}"#,
            ),
            "hzsm.buaa.edu.cn/venue-server/api/venue/finances/order/cancel" => {
                ok(url, r#"{"code":200,"data":null,"message":"success"}"#)
            }
            _ => return None,
        })
    }
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
                    // 2026-11-25 真实诊断：未登录时 302 到 hzsso 根路径 /login（200 页面）。
                    redirect(url, "http://hzsso.buaa.edu.cn/login")
                }
            }
            "hzsso.buaa.edu.cn/login" => ok(url, "<html>login</html>"),
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
                    // 2026-11-25 真机诊断：CAS 先回到 hzsso receive_ticket，再 302 到 callback.html。
                    redirect(
                        url,
                        "http://hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/idaasplugin_cas/receive_ticket?ticket=ST-fixture",
                    )
                }
            }
            "hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/idaasplugin_cas/receive_ticket" => {
                redirect(
                    url,
                    "http://hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html?enterpriseAuthId=idaasplugin_cas&ticket=ST-fixture",
                )
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
                r#"{"code":200,"data":{"roles":[{"id":3,"roleType":1,"name":"合成角色"}],"token":{"access_token":"hz-access-fixture"}}}"#,
            ),
            // 前端在恰好一个角色时自动 roleLogin，之后改用其返回的令牌。
            "hzsm.buaa.edu.cn/venue-server/roleLogin" => ok(
                url,
                r#"{"code":200,"data":{"token":{"access_token":"hz-role-fixture"}}}"#,
            ),
            // 真机上旧版 `venues` 返回 `data:null`；杭州前端改读 `venue_information.siteList`，场地编号字段是 `siteId`（无 `id`）。
            "hzsm.buaa.edu.cn/venue-server/api/front/website/venues" => {
                ok(url, r#"{"code":200,"data":null,"message":"success"}"#)
            }
            "hzsm.buaa.edu.cn/venue-server/api/front/website/venue_information" => ok(
                url,
                r#"{"code":200,"data":{"venueView":null,"siteList":[{"siteId":701,"siteName":"合成楼","venueName":"合成场馆","campusName":"合成校区"}]}}"#,
            ),
            "hzsm.buaa.edu.cn/venue-server/api/orders/mine" => ok(
                url,
                r#"{"code":200,"data":{"content":[{"id":9001,"tradeNo":"synthetic-trade","venueSiteId":701,"orderStatus":1}],"totalElements":1,"totalPages":1,"size":10,"number":0}}"#,
            ),
            _ => self
                .write_response(&key, url)
                .unwrap_or_else(|| panic!("未预期的杭州场馆请求: {key}")),
        };
        Ok(response)
    }
}

struct NeverProbe;

impl ubaa_core::facade::testing::GatewayProbe for NeverProbe {
    fn probe(&self, _budget: std::time::Duration) -> ubaa_core::facade::NetworkState {
        panic!("固定直连路线不得执行网关探测")
    }
}

#[test]
fn 应用路线客户端在直连策略下读取杭州站点与我的预约() {
    use ubaa_core::facade::testing::{DualSessionSnapshot, RouteConfig, RouteSessionSnapshot};

    let root = std::env::temp_dir().join(format!("ubaa-hz-cgyy-routed-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    FileSessionStore::new(&root)
        .unwrap()
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            None,
        ))
        .unwrap();
    RouteConfig::parse("[route]\ndefault = \"direct\"\n")
        .unwrap()
        .save(&root)
        .unwrap();
    let direct = Arc::new(Mutex::new(Vec::new()));
    let webvpn = Arc::new(Mutex::new(Vec::new()));
    let mut client = ubaa_core::facade::testing::with_routing_in_config_directory(
        HzTransport::new(direct.clone(), true),
        HzTransport::new(webvpn.clone(), true),
        &root,
        NeverProbe,
    )
    .unwrap();
    let runtime = runtime();

    let sites = runtime.block_on(client.hangzhou_cgyy_sites()).unwrap();
    assert_eq!(sites.data.len(), 1);
    assert_eq!(sites.data[0].id, 701);
    assert_eq!(sites.resolution.mode, ConnectionMode::Direct);

    let orders = runtime
        .block_on(client.hangzhou_cgyy_orders(0, 10))
        .unwrap();
    assert_eq!(orders.data.content.len(), 1);
    let invalid = runtime
        .block_on(client.hangzhou_cgyy_orders(-1, 10))
        .unwrap_err();
    assert_eq!(invalid.error.code, ErrorCode::InvalidInput);
    assert!(webvpn.lock().unwrap().is_empty(), "直连策略不得访问 WebVPN");
    let _ = std::fs::remove_dir_all(&root);
}

fn routed_client(
    name: &str,
    direct: HzTransport,
) -> (
    ubaa_core::facade::UbaaClient,
    Arc<Mutex<Vec<HttpRequest>>>,
    std::path::PathBuf,
) {
    use ubaa_core::facade::testing::{DualSessionSnapshot, RouteConfig, RouteSessionSnapshot};

    let root = std::env::temp_dir().join(format!("ubaa-hz-cgyy-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    FileSessionStore::new(&root)
        .unwrap()
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            None,
        ))
        .unwrap();
    RouteConfig::parse("[route]\ndefault = \"direct\"\n")
        .unwrap()
        .save(&root)
        .unwrap();
    let webvpn = Arc::new(Mutex::new(Vec::new()));
    let client = ubaa_core::facade::testing::with_routing_in_config_directory(
        direct,
        HzTransport::new(webvpn.clone(), true),
        &root,
        NeverProbe,
    )
    .unwrap();
    (client, webvpn, root)
}

fn hz_request(
    challenge: &ubaa_core::facade::HangzhouCgyyCaptchaChallenge,
) -> ubaa_core::facade::HangzhouCgyyReservationRequest {
    ubaa_core::facade::HangzhouCgyyReservationRequest {
        venue_site_id: 323,
        reservation_date: "2026-11-26".into(),
        selections: vec![ubaa_core::facade::CgyyReservationSelection {
            space_id: 70,
            time_id: 331_101,
            venue_space_group_id: None,
        }],
        phone: "10000000000".into(),
        user_input: ubaa_core::facade::HangzhouCgyyUserInput {
            captcha_token: challenge.token.clone(),
            captcha_secret_key: challenge.secret_key.clone(),
            slider_offset_x: 123.5,
            tap_x: 612,
            tap_y: 418,
        },
    }
}

fn hz_api_paths(requests: &Arc<Mutex<Vec<HttpRequest>>>) -> Vec<String> {
    requests
        .lock()
        .unwrap()
        .iter()
        .map(path_of)
        .filter(|path| {
            path.starts_with("hzsm.buaa.edu.cn/venue-server/api/") && !path.ends_with("/api/login")
        })
        .collect()
}

fn find_request(requests: &Arc<Mutex<Vec<HttpRequest>>>, suffix: &str) -> HttpRequest {
    requests
        .lock()
        .unwrap()
        .iter()
        .find(|request| request.url.contains(suffix))
        .unwrap_or_else(|| panic!("缺少请求 {suffix}"))
        .clone()
}

#[test]
fn 杭州预约按实录字段提交并完成零元确认() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, webvpn, root) =
        routed_client("submit", HzTransport::new(Arc::clone(&requests), true));
    let rt = runtime();

    let day = rt
        .block_on(client.hangzhou_cgyy_day_info(323, "2026-11-26"))
        .unwrap();
    assert_eq!(day.data.spaces.len(), 1);
    assert_eq!(day.data.spaces[0].slots.len(), 3);
    // 杭州日表只回查询日；可选日期按 advanceReservationDays 从今天起补齐，查询日也保留。
    let today = chrono::Utc::now()
        .with_timezone(&chrono::FixedOffset::east_opt(8 * 3600).unwrap())
        .date_naive();
    for offset in 0..3 {
        let date = (today + chrono::Duration::days(offset))
            .format("%Y-%m-%d")
            .to_string();
        assert!(day.data.available_dates.contains(&date), "缺少 {date}");
    }
    assert!(day.data.available_dates.contains(&"2026-11-26".to_owned()));
    assert_eq!(day.data.spaces[0].slots[0].admin_remark, None);
    assert_eq!(
        day.data.spaces[0].slots[1].admin_remark.as_deref(),
        Some("教学使用")
    );
    let challenge = rt.block_on(client.hangzhou_cgyy_captcha()).unwrap().data;
    assert_eq!(challenge.original_image_base64, "b3JpZ2luYWw=");
    requests.lock().unwrap().clear();

    let receipt = rt
        .block_on(client.hangzhou_cgyy_submit_reservation_if_route_matches(
            hz_request(&challenge),
            ConnectionMode::Direct,
        ))
        .unwrap()
        .data;
    assert_eq!(receipt.trade_no, "D000000000001");
    assert_eq!(receipt.order_id, 71425);

    assert_eq!(
        hz_api_paths(&requests),
        [
            "hzsm.buaa.edu.cn/venue-server/api/reservation/day/info",
            "hzsm.buaa.edu.cn/venue-server/api/captcha/check",
            "hzsm.buaa.edu.cn/venue-server/api/reservation/order/submit",
            "hzsm.buaa.edu.cn/venue-server/api/venue/finances/order/detail",
            "hzsm.buaa.edu.cn/venue-server/api/venue/finances/order/pay",
        ]
    );
    let check = form_of(&find_request(&requests, "/api/captcha/check"));
    assert_eq!(check.keys().collect::<Vec<_>>(), ["pointJson", "token"]);
    assert_eq!(check["token"], "captcha-token-fixture");

    let submit = find_request(&requests, "/api/reservation/order/submit");
    assert_eq!(submit.method, HttpMethod::Post);
    let form = form_of(&submit);
    assert_eq!(
        form.keys().map(String::as_str).collect::<Vec<_>>(),
        [
            "captchaToken",
            "captchaVerification",
            "orderPin",
            "orderPrice",
            "phone",
            "reservationDate",
            "reservationOrderJson",
            "reservationType",
            "venueSiteId",
            "weekStartDate",
        ]
    );
    assert_eq!(
        form["reservationOrderJson"],
        r#"[{"spaceId":"70","timeId":"331101"}]"#
    );
    assert_eq!(form["reservationType"], "-1");
    assert_eq!(form["weekStartDate"], "2026-11-26");
    assert_eq!(form["venueSiteId"], "323");
    assert_eq!(form["orderPin"].len(), 32);
    assert_eq!(
        submit.headers.get("cgAuthorization").map(String::as_str),
        Some("hz-role-fixture")
    );
    let pay = form_of(&find_request(&requests, "/api/venue/finances/order/pay"));
    assert_eq!(pay["venueTradeNo"], "D000000000001");
    assert_eq!(pay["isApp"], "0");
    assert!(webvpn.lock().unwrap().is_empty());
    let _ = std::fs::remove_dir_all(&root);
}

fn submit_error(transport: HzTransport, name: &str) -> ubaa_core::facade::RoutedError {
    let (mut client, _webvpn, root) = routed_client(name, transport);
    let rt = runtime();
    let challenge = rt.block_on(client.hangzhou_cgyy_captcha()).unwrap().data;
    let error = rt
        .block_on(client.hangzhou_cgyy_submit_reservation_if_route_matches(
            hz_request(&challenge),
            ConnectionMode::Direct,
        ))
        .unwrap_err();
    let _ = std::fs::remove_dir_all(&root);
    error
}

#[test]
fn 杭州收费场地在任何写请求前拒绝() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut transport = HzTransport::new(Arc::clone(&requests), true);
    transport.is_fee = 1;

    let error = submit_error(transport, "fee");

    assert_eq!(error.error.code, ErrorCode::InvalidInput);
    assert!(
        !hz_api_paths(&requests)
            .iter()
            .any(|path| path.contains("captcha/check")
                || path.contains("order/submit")
                || path.contains("finances"))
    );
}

#[test]
fn 杭州滑块校验失败不提交预约() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut transport = HzTransport::new(Arc::clone(&requests), true);
    transport.captcha_ok = false;

    let error = submit_error(transport, "captcha");

    assert_eq!(error.error.code, ErrorCode::InvalidInput);
    assert!(
        !hz_api_paths(&requests)
            .iter()
            .any(|path| path.contains("order/submit"))
    );
}

#[test]
fn 杭州提交后发现需付费时不代为支付() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut transport = HzTransport::new(Arc::clone(&requests), true);
    transport.pay_fee = 5.0;

    let error = submit_error(transport, "payfee");

    assert_eq!(error.error.code, ErrorCode::BusinessRejected);
    assert!(error.error.message.contains("D000000000001"));
    assert!(
        !hz_api_paths(&requests)
            .iter()
            .any(|path| path.ends_with("finances/order/pay"))
    );
}

#[test]
fn 杭州预约路线已变化时不发任何请求() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, webvpn, root) =
        routed_client("route", HzTransport::new(Arc::clone(&requests), true));
    let challenge = ubaa_core::facade::HangzhouCgyyCaptchaChallenge {
        token: "t".into(),
        secret_key: "abcdefghijklmnop".into(),
        ..Default::default()
    };

    let error = runtime()
        .block_on(client.hangzhou_cgyy_submit_reservation_if_route_matches(
            hz_request(&challenge),
            ConnectionMode::WebVpn,
        ))
        .unwrap_err();

    assert_eq!(error.error.code, ErrorCode::InvalidInput);
    assert!(requests.lock().unwrap().is_empty());
    assert!(webvpn.lock().unwrap().is_empty());
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn 杭州取消先读提醒再按订单号和原因只发送一次() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, _webvpn, root) =
        routed_client("cancel", HzTransport::new(Arc::clone(&requests), true));
    let rt = runtime();
    let request = ubaa_core::facade::HangzhouCgyyCancelRequest {
        trade_no: "D000000000001".into(),
        reason: "临时有事".into(),
    };

    let preflight = rt
        .block_on(client.preflight_hangzhou_cgyy_cancel(&request))
        .unwrap()
        .data;
    assert_eq!(preflight.tip.as_deref(), Some("合成取消提醒"));
    requests.lock().unwrap().clear();
    let result = rt
        .block_on(
            client.hangzhou_cgyy_cancel_order_if_route_matches(request, ConnectionMode::Direct),
        )
        .unwrap()
        .data;
    assert!(result.success);

    assert_eq!(
        hz_api_paths(&requests),
        [
            "hzsm.buaa.edu.cn/venue-server/api/orders/cancel_tip",
            "hzsm.buaa.edu.cn/venue-server/api/venue/finances/order/cancel",
        ]
    );
    let form = form_of(&find_request(&requests, "finances/order/cancel"));
    assert_eq!(form["venueTradeNo"], "D000000000001");
    assert_eq!(form["handleReason"], "临时有事");
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn 杭州同一房间可一次预约多个不相邻时段() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let (mut client, _webvpn, root) =
        routed_client("multi", HzTransport::new(Arc::clone(&requests), true));
    let rt = runtime();
    let challenge = rt.block_on(client.hangzhou_cgyy_captcha()).unwrap().data;
    let mut request = hz_request(&challenge);
    // 官网杭州站点不要求相邻，也不限两段；中间的 331102 为“教学使用”。
    request
        .selections
        .push(ubaa_core::facade::CgyyReservationSelection {
            space_id: 70,
            time_id: 331_103,
            venue_space_group_id: None,
        });
    rt.block_on(
        client.hangzhou_cgyy_submit_reservation_if_route_matches(request, ConnectionMode::Direct),
    )
    .unwrap();
    let form = form_of(&find_request(&requests, "/api/reservation/order/submit"));
    let orders: serde_json::Value = serde_json::from_str(&form["reservationOrderJson"]).unwrap();
    let times: Vec<_> = orders
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item["timeId"].as_str().unwrap().to_owned())
        .collect();
    assert_eq!(times, ["331101", "331103"]);
    let _ = std::fs::remove_dir_all(&root);
}
