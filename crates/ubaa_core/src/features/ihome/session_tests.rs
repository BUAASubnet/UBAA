use super::*;

pub(super) fn override_response(
    scenario: &Scenario,
    request: &HttpRequest,
    path: &str,
) -> Option<HttpResponse> {
    let (target, status, location, body) = scenario.response_override?;
    if path != target {
        return None;
    }
    let mut response = empty_response(request);
    response.status = status;
    response.body = body.as_bytes().to_vec();
    if !location.is_empty() {
        response
            .headers
            .insert("Location".into(), vec![location.into()]);
    }
    Some(response)
}

#[tokio::test]
async fn ihome_webvpn登录失效在认证和业务读取中返回需要恢复() {
    for path in [
        "/login",
        "/api/authLogin",
        "/api/appeal",
        "/api/general_set_more",
    ] {
        for location in ["/login", "https://d.buaa.edu.cn/login"] {
            let (mut runtime, state, _root) = fixture(
                ConnectionMode::WebVpn,
                Scenario {
                    response_override: Some((path, 302, location, "")),
                    ..Scenario::default()
                },
            );
            let error = if path == "/api/general_set_more" {
                get_config(&mut runtime).await.unwrap_err()
            } else {
                get_page(&mut runtime, &IhomeQuery::default())
                    .await
                    .unwrap_err()
            };
            assert_eq!(error.code, ErrorCode::AuthenticationRequired, "{path}");
            assert_eq!(error.kind, ErrorKind::Authentication);
            let requests = &state.lock().unwrap().requests;
            assert!(
                requests
                    .iter()
                    .all(|r| url::Url::parse(&r.url).unwrap().path() != "/login")
            );
            assert!(requests.iter().all(|r| r.method == HttpMethod::Get));
        }
    }
}

#[tokio::test]
async fn ihome_sso登录表单需要恢复但普通服务异常不触发认证() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        for (status, body, code) in [
            (
                200,
                "<input name='execution' value='fixture'>",
                ErrorCode::AuthenticationRequired,
            ),
            (401, "", ErrorCode::AuthenticationRequired),
            (200, "<html>维护中</html>", ErrorCode::UpstreamUnavailable),
            (
                503,
                "<input name='execution' value='fixture'>",
                ErrorCode::UpstreamUnavailable,
            ),
        ] {
            let (mut runtime, state, _root) = fixture(
                mode,
                Scenario {
                    response_override: Some(("/login", status, "", body)),
                    ..Scenario::default()
                },
            );
            let error = get_page(&mut runtime, &IhomeQuery::default())
                .await
                .unwrap_err();
            assert_eq!(error.code, code);
            assert_eq!(state.lock().unwrap().requests.len(), 1);
        }
    }
}

#[tokio::test]
async fn ihome_外部跳转和直连网关跳转不误报会话失效() {
    for (mode, location) in [
        (ConnectionMode::WebVpn, "https://example.org/login"),
        (ConnectionMode::WebVpn, "https://d.buaa.edu.cn:8443/login"),
        (ConnectionMode::Direct, "https://d.buaa.edu.cn/login"),
    ] {
        let (mut runtime, state, _root) = fixture(
            mode,
            Scenario {
                response_override: Some(("/login", 302, location, "")),
                ..Scenario::default()
            },
        );
        let error = get_page(&mut runtime, &IhomeQuery::default())
            .await
            .unwrap_err();
        assert_ne!(error.code, ErrorCode::AuthenticationRequired);
        assert_eq!(state.lock().unwrap().requests.len(), 1);
    }
}
