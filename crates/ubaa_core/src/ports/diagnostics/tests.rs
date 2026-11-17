use super::*;

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
