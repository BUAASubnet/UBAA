use super::*;

fn bind(diagnostics: &RawDiagnostics) -> ConfirmedOwner {
    diagnostics
        .pending(diagnostics.generation())
        .confirm(
            &UserProfile {
                school_id: Some("fixture-user".into()),
                ..UserProfile::default()
            },
            || true,
        )
        .unwrap()
}

#[tokio::test]
async fn 课堂异常正文和授权头在入缓冲前脱敏() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let owner = bind(&diagnostics);
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
    diagnostics
        .capture_for(
            owner,
            transport.capture(
                super::super::HttpMethod::Get,
                endpoint.into(),
                false,
                async { Ok(response) },
            ),
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
    let owner = bind(&diagnostics);
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
                diagnostics
                    .capture_for(
                        owner,
                        transport.capture(
                            super::super::HttpMethod::Get,
                            request_url.into(),
                            false,
                            async { Ok(response) },
                        ),
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
    let owner = bind(&diagnostics);
    for _ in 0..2 {
        let response = diagnostics
            .capture_for(
                owner,
                transport.execute(HttpRequest::get("https://example.test/today")),
            )
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

struct CgyyDiagnosticTransport(Mutex<VecDeque<(HttpRequest, HttpResponse)>>);

#[async_trait]
impl HttpTransport for CgyyDiagnosticTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let (expected, response) = self.0.lock().unwrap().pop_front().unwrap();
        assert_eq!(request, expected);
        Ok(response)
    }
}

const CGYY_MOBILE_RESERVATION: &str = "https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation";

fn cgyy_diagnostic_exchanges(route: ConnectionMode) -> Vec<(HttpRequest, HttpResponse)> {
    let endpoint = |path: &str| {
        let direct = format!("https://cgyy.buaa.edu.cn{path}");
        match route {
            ConnectionMode::Direct => direct,
            ConnectionMode::WebVpn => crate::connection::to_webvpn_url(&direct).unwrap(),
        }
    };
    let auth = endpoint("/venue-zhjs-server/sso/manageLogin");
    let mut exchanges = Vec::new();
    let sso_token = match route {
        ConnectionMode::Direct => {
            let mut redirect = HttpResponse::new(302, &auth, Vec::new());
            redirect
                .headers
                .insert("Location".into(), vec![CGYY_MOBILE_RESERVATION.into()]);
            redirect.headers.insert(
                "Set-Cookie".into(),
                vec![
                    "sso_buaa_zhjs_token=fixture-cgyy-sso; Path=/venue-zhjs-server/; Secure".into(),
                    "view=compact; Path=/".into(),
                ],
            );
            exchanges.push((HttpRequest::get(&auth), redirect));
            exchanges.push((
                HttpRequest::get(CGYY_MOBILE_RESERVATION),
                HttpResponse::new(
                    200,
                    CGYY_MOBILE_RESERVATION,
                    "合成认证响应".as_bytes().to_vec(),
                ),
            ));
            "fixture-cgyy-sso"
        }
        ConnectionMode::WebVpn => {
            exchanges.push((
                HttpRequest::get(&auth),
                HttpResponse::new(200, &auth, "合成认证响应".as_bytes().to_vec()),
            ));
            let snapshot = "https://d.buaa.edu.cn/wengine-vpn/cookie?method=get&host=cgyy.buaa.edu.cn&scheme=https&path=%2Fvenue-zhjs&vpn_timestamp=1000";
            exchanges.push((
                HttpRequest::get(snapshot),
                HttpResponse::new(
                    200,
                    snapshot,
                    b"sso_buaa_zhjs_token=fixture-cgyy-gateway-sso; _zte_fp_=fixture-cgyy-gateway-fingerprint;".to_vec(),
                ),
            ));
            "fixture-cgyy-gateway-sso"
        }
    };

    let login = endpoint("/venue-zhjs-server/api/login");
    let challenge = endpoint("/venue-zhjs-server/api/captcha/get");
    let check = endpoint("/venue-zhjs-server/api/captcha/check");
    for (request, body) in [
        (
            HttpRequest::post(&login, Vec::new())
                .with_header("Sso-Token", sso_token)
                .with_header("sign", "fixture-cgyy-signature"),
            r#"{"code":200,"data":{"token":{"access_token":"fixture-cgyy-access"}},"message":"合成业务登录"}"#,
        ),
        (
            HttpRequest::get(&challenge).with_header("cgAuthorization", "fixture-cgyy-access"),
            r#"{"code":200,"data":{"success":true,"repData":{"secretKey":"fixture-cgyy-key","token":"fixture-cgyy-challenge"}}}"#,
        ),
        (
            HttpRequest::post(
                &check,
                b"token=fixture-cgyy-challenge&pointJson=fixture-cgyy-form".to_vec(),
            )
            .with_header("Content-Type", "application/x-www-form-urlencoded")
            .with_header("cgAuthorization", "fixture-cgyy-access"),
            r#"{"code":200,"data":{"success":true}}"#,
        ),
    ] {
        let response = HttpResponse::new(200, &request.url, body.as_bytes().to_vec());
        exchanges.push((request, response));
    }

    exchanges
}

#[tokio::test]
async fn 研讨室诊断遮蔽凭据并保留普通字段() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let diagnostics = RawDiagnostics::default();
        diagnostics.enable();
        let owner = bind(&diagnostics);
        let exchanges = cgyy_diagnostic_exchanges(route);
        let transport = RecordingTransport {
            inner: CgyyDiagnosticTransport(Mutex::new(exchanges.iter().cloned().collect())),
            diagnostics: diagnostics.clone(),
            route,
        };
        for (request, response) in exchanges {
            assert_eq!(
                diagnostics
                    .capture_for(owner, transport.execute(request))
                    .await
                    .unwrap(),
                response
            );
        }

        let text = diagnostics.export_json();
        for secret in [
            "fixture-cgyy-sso",
            "fixture-cgyy-gateway-sso",
            "fixture-cgyy-gateway-fingerprint",
            "fixture-cgyy-access",
            "fixture-cgyy-key",
            "fixture-cgyy-challenge",
            "fixture-cgyy-signature",
            "fixture-cgyy-form",
        ] {
            assert!(!text.contains(secret), "{route:?} 的研讨室凭据进入了诊断");
        }
        let report: Value = serde_json::from_str(&text).unwrap();
        let records = report["records"].as_array().unwrap();
        assert_eq!(records.len(), 5);
        if route == ConnectionMode::Direct {
            let sso = &records[0]["response"];
            assert_eq!(sso["status"], 302);
            assert_eq!(sso["headers"]["Location"], json!([CGYY_MOBILE_RESERVATION]));
            assert_eq!(
                sso["headers"]["Set-Cookie"],
                json!([
                    "sso_buaa_zhjs_token=[已隐藏]; Path=/venue-zhjs-server/; Secure",
                    "view=compact; Path=/"
                ])
            );
            assert_eq!(records[1]["response"]["body"], "合成认证响应");
        } else {
            assert_eq!(records[0]["response"]["body"], "合成认证响应");
            assert_eq!(records[1]["response"]["status"], 200);
            assert_eq!(records[1]["response"]["body_capture"], "redacted");
        }
        let body = |index: usize| -> Value {
            serde_json::from_str(records[index]["response"]["body"].as_str().unwrap()).unwrap()
        };
        let login = body(2);
        assert_eq!(login["message"], "合成业务登录");
        assert_eq!(login["data"]["token"]["access_token"], "[已隐藏]");
        let captcha = body(3);
        assert_eq!(captcha["data"]["success"], true);
        assert_eq!(captcha["data"]["repData"]["secretKey"], "[已隐藏]");
        assert_eq!(captcha["data"]["repData"]["token"], "[已隐藏]");
        assert_eq!(body(4), json!({"code": 200, "data": {"success": true}}));
    }
}

#[tokio::test]
async fn 容量淘汰明确报告且保留完整记录() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let owner = bind(&diagnostics);
    for id in 1..=257 {
        diagnostics.push(
            &diagnostics
                .capture_for(owner, async { diagnostics.begin().unwrap() })
                .await,
            &json!({"request_id": id}),
        );
    }
    let report: Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
    assert_eq!(report["dropped_records"], 1);
    assert_eq!(report["records"].as_array().unwrap().len(), 256);
    assert_eq!(report["records"][0]["request_id"], 2);
}

#[tokio::test]
async fn 清空诊断后忽略上一轮请求的迟到响应() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let owner = bind(&diagnostics);
    let previous = diagnostics
        .capture_for(owner, async { diagnostics.begin().unwrap() })
        .await;
    diagnostics.begin_explicit(diagnostics.generation(), || true);
    let owner = bind(&diagnostics);
    let current = diagnostics
        .capture_for(owner, async { diagnostics.begin().unwrap() })
        .await;
    diagnostics.push(&previous, &json!({"message": "合成旧响应"}));
    diagnostics.push(&current, &json!({"message": "合成新响应"}));

    let report: Value = serde_json::from_str(&diagnostics.export_json()).unwrap();
    assert_eq!(report["records"], json!([{"message": "合成新响应"}]));
    assert_eq!(report["started_requests"], 1);
    assert_eq!(report["completed_requests"], 1);
    assert_eq!(report["unfinished_requests"], 0);
}

#[tokio::test]
async fn 非文本响应无损导出且传输失败不伪造响应() {
    let diagnostics = RawDiagnostics::default();
    diagnostics.enable();
    let owner = bind(&diagnostics);
    let transport = RecordingTransport {
        inner: Fixture,
        diagnostics: diagnostics.clone(),
        route: ConnectionMode::Direct,
    };
    let bytes = vec![0, 255, 128, 10];
    diagnostics
        .capture_for(
            owner,
            transport.capture(
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
            ),
        )
        .await
        .unwrap();
    let error = crate::error::UbaaError::upstream_changed("合成错误");
    diagnostics
        .capture_for(
            owner,
            transport.capture(
                super::super::HttpMethod::Get,
                "https://example.test/failure".into(),
                false,
                async { Err(error) },
            ),
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
