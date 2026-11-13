use super::*;
use ubaa_core::facade::testing::{StoredCookie, from_webvpn_url};

const PDF: &[u8] = b"%PDF-1.7\n%%EOF\n";

#[derive(Clone, Copy)]
struct PrintTransport(ConnectionMode);

#[async_trait]
impl HttpTransport for PrintTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let actual = url::Url::parse(&request.url).unwrap();
        let upstream = url::Url::parse(&from_webvpn_url(&request.url).unwrap()).unwrap();
        assert_eq!(upstream.host_str(), Some("print.lib.buaa.edu.cn"));
        let cookie = request.headers.get("Cookie").map_or("", String::as_str);
        match self.0 {
            ConnectionMode::Direct => {
                assert_eq!(actual, upstream);
                assert_eq!(cookie, "");
            }
            ConnectionMode::WebVpn => {
                assert_eq!(actual.host_str(), Some("d.buaa.edu.cn"));
                assert_eq!(cookie, "fixture-gateway=fixture-webvpn");
            }
        }
        let body = match upstream.path() {
            "/client/new/cprintPc/cprint.html" => Vec::new(),
            "/api/client/Auth/Check" => {
                br#"{"code":0,"result":{"szLogonName":"fixture-user"}}"#.to_vec()
            }
            "/api/client/Scan/Get" => serde_json::json!({
                "code": 0, "result": [{
                    "dwJobId": 15, "szDisplayName": "fixture.pdf", "dwFileSize": PDF.len(),
                    "dwSubmitDate": "20261113", "dwSubmitTime": "123456", "dwStatus": 0
                }]
            })
            .to_string()
            .into_bytes(),
            "/api/client/Scan/Download" => {
                assert_eq!(upstream.query(), Some("dwJobId=15"));
                PDF.to_vec()
            }
            other => panic!("未预期的云打印请求: {other}"),
        };
        Ok(HttpResponse::new(200, request.url, body))
    }
}

#[tokio::test]
async fn cloud_print_uses_the_selected_route_and_its_existing_session() {
    let root = test_root("cloud-print-routes");
    let store = FileSessionStore::new(&root).unwrap();
    let direct = RouteSessionSnapshot {
        cookies: Vec::new(),
        authenticated_at: 1,
        last_activity: 1,
    };
    let vpn = RouteSessionSnapshot {
        cookies: vec![StoredCookie {
            name: "fixture-gateway".into(),
            value: "fixture-webvpn".into(),
            domain: "d.buaa.edu.cn".into(),
            host_only: true,
            path: "/".into(),
            secure: true,
            expires_at: None,
            created_at: 1,
            max_age: None,
        }],
        ..direct.clone()
    };
    store
        .save_dual(&DualSessionSnapshot::new(Some(direct), Some(vpn)))
        .unwrap();
    for default in [RoutePolicy::WebVpn, RoutePolicy::Direct] {
        let mut config = RouteConfig::default();
        config.default = default;
        let mut client = UbaaClient::with_routing(
            PrintTransport(ConnectionMode::Direct),
            PrintTransport(ConnectionMode::WebVpn),
            store.clone(),
            config,
            NeverProbe,
        )
        .unwrap();
        let result = client.cloud_print_scan("15").await.unwrap();
        assert_eq!(result.data, PDF);
        assert_eq!(
            result.resolution.mode,
            if default == RoutePolicy::WebVpn {
                ConnectionMode::WebVpn
            } else {
                ConnectionMode::Direct
            }
        );
    }
    let _ = std::fs::remove_dir_all(root);
}
