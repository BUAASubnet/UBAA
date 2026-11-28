use super::*;

#[tokio::test]
async fn 课堂异常正文和授权头在入缓冲前脱敏() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let transport = RecordingTransport {
        inner: Fixture,
        diagnostics: diagnostics.clone(),
        route: ConnectionMode::Direct,
    };
    let endpoint =
        "https://classroom.msa.buaa.edu.cn/courseapi/v3/portal-home-setting/get-sub-info";
    let mut response = HttpResponse::new(
        502,
        endpoint,
        b"upstream failure: ?auth_key=fixture-media-secret".to_vec(),
    );
    response.headers.insert(
        "aUtHoRiZaTiOn".into(),
        vec!["Bearer fixture-token-secret".into()],
    );
    response.headers.insert(
        "Cookie".into(),
        vec!["mode=1; _token=fixture-cookie-secret".into()],
    );
    transport
        .capture(
            super::super::HttpMethod::Get,
            endpoint.into(),
            false,
            async { Ok(response) },
        )
        .await
        .unwrap();
    let text = diagnostics.export_json();
    for secret in [
        "fixture-media-secret",
        "fixture-token-secret",
        "fixture-cookie-secret",
    ] {
        assert!(!text.contains(secret));
    }
    assert!(text.contains("mode=[已隐藏]"));
}

#[test]
fn 课堂诊断递归处理字符串化对象数组和混合大小写地址() {
    let inner = json!([{"auth_key":"inner-secret","link":"  HtTpS://example.test/x?auth_key=url-secret","other":7}]);
    let body = json!({"content":json!({"items":inner.to_string()}).to_string(),"link":"\tHTTP://example.test/x?ticket=outer-secret"});
    let masked = redact::body("https://example.test/", body.to_string().as_bytes()).unwrap();
    assert!(!masked.contains("-secret"));
    let outer: Value = serde_json::from_str(&masked).unwrap();
    let middle: Value = serde_json::from_str(outer["content"].as_str().unwrap()).unwrap();
    let items: Value = serde_json::from_str(middle["items"].as_str().unwrap()).unwrap();
    assert_eq!(items[0]["auth_key"], "[已隐藏]");
    assert_eq!(items[0]["other"], 7);
}

#[test]
fn 课堂诊断遮盖跳转片段中的敏感键() {
    for target in [
        "/x#Ticket=fragment-secret&keep=ok",
        "/x?username=query-secret#/player?auth_key=fragment-secret&keep=ok",
    ] {
        let mut response = HttpResponse::new(302, "https://example.test/start", vec![]);
        response
            .headers
            .insert("Location".into(), vec![target.into()]);
        let safe = &redact::headers(&response.final_url, &response)["Location"][0];
        assert!(!safe.contains("-secret"));
        assert!(safe.contains("keep=ok"));
    }
}

#[tokio::test]
async fn 课堂两主机及网关快照按请求或响应地址遮盖全部cookie值() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let transport = RecordingTransport {
        inner: Fixture,
        diagnostics: diagnostics.clone(),
        route: ConnectionMode::WebVpn,
    };
    let other = "https://example.test/";
    for target in [
        "https://yjapi.msa.buaa.edu.cn/other",
        "https://classroom.msa.buaa.edu.cn/other",
        "https://yjapi.msa.buaa.edu.cn/casapi/index.php",
        "https://d.buaa.edu.cn/wengine-vpn/cookie?method=get",
    ] {
        for url in [
            target.to_owned(),
            crate::connection::to_webvpn_url(target).unwrap(),
        ] {
            for (request_url, response_url) in [(url.as_str(), other), (other, url.as_str())] {
                let mut response = HttpResponse::new(200, response_url, vec![]);
                response.headers.insert(
                    "Cookie".into(),
                    vec!["mode=mode-secret; SID=sid-secret".into()],
                );
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec![
                        "other=cookie-secret; Path=/x; Secure".into(),
                        "another=another-secret".into(),
                    ],
                );
                transport
                    .capture(
                        super::super::HttpMethod::Get,
                        request_url.into(),
                        false,
                        async { Ok(response) },
                    )
                    .await
                    .unwrap();
            }
        }
    }
    let report: Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
    for record in report["records"].as_array().unwrap() {
        let headers = &record["response"]["headers"];
        assert_eq!(headers["Cookie"], json!(["mode=[已隐藏]; SID=[已隐藏]"]));
        assert_eq!(
            headers["Set-Cookie"],
            json!(["other=[已隐藏]; Path=/x; Secure", "another=[已隐藏]"])
        );
    }
}

struct Fixture;
#[async_trait]
impl HttpTransport for Fixture {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let mut response = HttpResponse::new(
            401,
            request.url,
            br#"{"STATUS":"401","message":"fixture","token":"fixture-secret"}"#.to_vec(),
        );
        response.headers.insert(
            "Set-Cookie".into(),
            vec!["fixture=one".into(), "fixture=two".into()],
        );
        Ok(response)
    }
}

#[tokio::test]
async fn 原始响应保留未知字段重复响应头和重试顺序() {
    let diagnostics = RawDiagnostics::default();
    let transport = RecordingTransport {
        inner: Fixture,
        diagnostics: diagnostics.clone(),
        route: ConnectionMode::WebVpn,
    };
    transport
        .execute(HttpRequest::get("https://example.test/disabled"))
        .await
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&diagnostics.export_json()).unwrap()["records"],
        json!([])
    );
    diagnostics.enable();
    for _ in 0..2 {
        let response = transport
            .execute(HttpRequest::get("https://example.test/today"))
            .await
            .unwrap();
        assert_eq!(response.status, 401);
    }
    let report: Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
    assert_eq!(report["records"].as_array().unwrap().len(), 2);
    assert_eq!(report["records"][1]["request_id"], 2);
    assert_eq!(
        report["records"][0]["response"]["headers"]["Set-Cookie"],
        json!(["fixture=one", "fixture=two"])
    );
    assert!(
        report["records"][0]["response"]["body"]
            .as_str()
            .unwrap()
            .contains("fixture-secret")
    );
}

#[tokio::test]
async fn 研讨室诊断遮蔽凭据并保留普通字段() {
    use super::super::HttpMethod::{Get, Post};

    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let diagnostics = RawDiagnostics::default();
        diagnostics.enable();
        let transport = RecordingTransport {
            inner: Fixture,
            diagnostics: diagnostics.clone(),
            route,
        };
        for (method, path, body) in [
            (Get, "/sso/manageLogin", "合成认证响应"),
            (
                Post,
                "/api/login",
                r#"{"code":200,"data":{"token":{"access_token":"fixture-cgyy-access"}},"message":"合成业务登录"}"#,
            ),
            (
                Get,
                "/api/captcha/get",
                r#"{"code":200,"data":{"success":true,"repData":{"secretKey":"fixture-cgyy-key","token":"fixture-cgyy-challenge"}}}"#,
            ),
        ] {
            let endpoint = format!("https://cgyy.buaa.edu.cn/venue-zhjs-server{path}");
            let endpoint = match route {
                ConnectionMode::Direct => endpoint,
                ConnectionMode::WebVpn => crate::connection::to_webvpn_url(&endpoint).unwrap(),
            };
            let mut response = HttpResponse::new(200, &endpoint, body.as_bytes().to_vec());
            if path == "/sso/manageLogin" {
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec![
                        "sso_buaa_zhjs_token=fixture-cgyy-sso; Path=/venue-zhjs-server/; Secure"
                            .into(),
                        "view=compact; Path=/".into(),
                    ],
                );
            }
            transport
                .capture(method, endpoint, false, async { Ok(response) })
                .await
                .unwrap();
        }

        let text = diagnostics.export_json();
        for secret in [
            "fixture-cgyy-sso",
            "fixture-cgyy-access",
            "fixture-cgyy-key",
            "fixture-cgyy-challenge",
        ] {
            assert!(!text.contains(secret), "{route:?} 的研讨室凭据进入了诊断");
        }
        let report: Value = serde_json::from_str(&text).unwrap();
        let records = report["records"].as_array().unwrap();
        let sso = &records[0]["response"];
        assert_eq!(sso["body"], "合成认证响应");
        assert_eq!(
            sso["headers"]["Set-Cookie"],
            json!([
                "sso_buaa_zhjs_token=[已隐藏]; Path=/venue-zhjs-server/; Secure",
                "view=compact; Path=/"
            ])
        );
        let login: Value =
            serde_json::from_str(records[1]["response"]["body"].as_str().unwrap()).unwrap();
        assert_eq!(login["message"], "合成业务登录");
        assert_eq!(login["data"]["token"]["access_token"], "[已隐藏]");
        let captcha: Value =
            serde_json::from_str(records[2]["response"]["body"].as_str().unwrap()).unwrap();
        assert_eq!(captcha["data"]["success"], true);
        assert_eq!(captcha["data"]["repData"]["secretKey"], "[已隐藏]");
        assert_eq!(captcha["data"]["repData"]["token"], "[已隐藏]");
    }
}

#[test]
fn 容量淘汰明确报告且保留完整记录() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    for id in 1..=257 {
        diagnostics.push(id, &json!({"request_id": id}));
    }
    let report: Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
    assert_eq!(report["dropped_records"], 1);
    assert_eq!(report["records"].as_array().unwrap().len(), 256);
    assert_eq!(report["records"][0]["request_id"], 2);
}

#[tokio::test]
async fn 非文本响应无损导出且传输失败不伪造响应() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let transport = RecordingTransport {
        inner: Fixture,
        diagnostics: diagnostics.clone(),
        route: ConnectionMode::Direct,
    };
    let bytes = vec![0, 255, 128, 10];
    transport
        .capture(
            super::super::HttpMethod::Get,
            "https://example.test/binary".into(),
            false,
            async {
                Ok(HttpResponse::new(
                    200,
                    "https://example.test/binary",
                    bytes.clone(),
                ))
            },
        )
        .await
        .unwrap();
    let error = crate::error::UbaaError::upstream_changed("合成错误");
    transport
        .capture(
            super::super::HttpMethod::Get,
            "https://example.test/failure".into(),
            false,
            async { Err(error) },
        )
        .await
        .unwrap_err();
    let report: Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
    let response = &report["records"][0]["response"];
    assert_eq!(response["body_encoding"], "base64");
    assert_eq!(
        base64::engine::general_purpose::STANDARD
            .decode(response["body"].as_str().unwrap())
            .unwrap(),
        bytes
    );
    assert!(report["records"][1].get("response").is_none());
    assert!(report["records"][1].get("transport_error").is_some());
    assert_eq!(report["unfinished_requests"], 0);
}
