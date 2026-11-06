#[cfg(test)]
mod tests {
    use async_trait::async_trait;
    use std::sync::{Arc, Mutex};
    use ubaa_core::facade::{DualLoginInput, SecretValue, UbaaClient};
    use ubaa_test_support::{
        FileSessionStore, HttpRequest, HttpResponse, HttpTransport, from_webvpn_url,
    };

    #[derive(Clone)]
    struct 合成传输(Arc<Mutex<Option<&'static str>>>);
    struct 禁止探测;
    impl ubaa_test_support::GatewayProbe for 禁止探测 {
        fn probe(&self, _: std::time::Duration) -> ubaa_core::facade::NetworkState {
            panic!("固定路线不得调用真实探测");
        }
    }
    #[async_trait]
    impl HttpTransport for 合成传输 {
        async fn execute(&self, req: HttpRequest) -> ubaa_core::facade::Result<HttpResponse> {
            if let Some(response) = ubaa_core::facade::testing::sso_fixture_ticket(&req) {
                return Ok(response);
            }
            let url = from_webvpn_url(&req.url).unwrap_or_else(|_| req.url.clone());
            let mode = *self.0.lock().unwrap();
            if url.contains("/captcha?") {
                return Ok(ubaa_core::facade::testing::sso_fixture_response(
                    200,
                    req.url,
                    vec![
                        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2,
                        0, 0, 0, 1, 8, 6, 0, 0, 0, 244, 34, 127, 138, 0, 0, 0, 14, 73, 68, 65, 84,
                        120, 156, 99, 16, 12, 158, 250, 31, 132, 1, 14, 181, 3, 241, 180, 57, 214,
                        207, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
                    ],
                ));
            }
            if url.ends_with("/login") && url.contains("sso.buaa.edu.cn") {
                if mode == Some("challenge") {
                    return Ok(ubaa_core::facade::testing::sso_fixture_response(200, req.url, br#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-execution-1"></form><script>config.captcha = { type: 'image', id: 'synthetic-captcha-1' }</script>"#.to_vec()));
                }
                if mode == Some("failure") {
                    return Ok(ubaa_core::facade::testing::sso_fixture_response(
                        503,
                        req.url,
                        Vec::new(),
                    ));
                }
                return Ok(ubaa_core::facade::testing::sso_fixture_response(
                    302,
                    req.url,
                    Vec::new(),
                ));
            }
            if url.contains("/serviceValidate?") || url.contains("/api/uc/userinfo") {
                return Ok(match *self.0.lock().unwrap() {
                    Some("transient") => ubaa_core::facade::testing::sso_fixture_response(503, req.url, Vec::new()),
                    Some(id) => ubaa_core::facade::testing::sso_fixture_response(200, req.url, serde_json::to_vec(&serde_json::json!({"code":0,"data":{"schoolid":id,"username":id,"name":"合成账号"}})).unwrap()),
                    None => ubaa_core::facade::testing::sso_fixture_response(401, req.url, Vec::new()),
                });
            }
            if url.contains("/api/login")
                || url.contains("/wengine-vpn/cookie")
                || url.ends_with("/logout")
            {
                return Ok(ubaa_core::facade::testing::sso_fixture_response(
                    200,
                    req.url,
                    Vec::new(),
                ));
            }
            panic!("合成传输收到未登记路径");
        }
    }
    async fn 客户端() -> (UbaaClient, 合成传输) {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/agenda_cli_a_fix/identity")
            .join(uuid::Uuid::new_v4().simple().to_string());
        std::fs::create_dir_all(&root).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
        }
        let transport = 合成传输(Arc::new(Mutex::new(Some("fixture-a"))));
        let mut client = UbaaClient::with_routing(
            transport.clone(),
            transport.clone(),
            FileSessionStore::new(&root).unwrap(),
            ubaa_test_support::RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
            禁止探测,
        )
        .unwrap();
        let result = client
            .login(DualLoginInput {
                username: "fixture-a".into(),
                password: SecretValue::new("synthetic-only"),
            })
            .await
            .unwrap();
        assert_eq!(
            result.readiness,
            ubaa_core::facade::LoginReadiness::AllReady
        );
        (client, transport)
    }
    #[tokio::test]
    async fn 交互式换号必须撤销旧能力() {
        let (mut client, transport) = 客户端().await;
        let old = client.take_verified_login_identity().unwrap();
        *transport.0.lock().unwrap() = Some("fixture-b");
        let prepared = client
            .prepare_interactive_login("fixture-b".into())
            .await
            .unwrap();
        assert!(
            prepared
                .routes
                .iter()
                .all(|r| r.state == ubaa_core::facade::InteractiveRouteState::Ready)
        );
        assert!(
            client.validate_login_identity(&old).is_err(),
            "交互式换号成功后，A 的票据仍可核实"
        );
    }
    #[tokio::test]
    async fn 交互式换号不得取出旧身份() {
        let (mut client, transport) = 客户端().await;
        *transport.0.lock().unwrap() = Some("fixture-b");
        client
            .prepare_interactive_login("fixture-b".into())
            .await
            .unwrap();
        assert!(
            client.take_verified_login_identity().is_err(),
            "交互式登录后仍可取出普通旧登录 A 的能力"
        );
    }
    #[tokio::test]
    async fn 准备失败与等待验证码均撤销已取出和未取出的旧能力() {
        for mode in ["failure", "challenge"] {
            for taken in [false, true] {
                let (mut client, transport) = 客户端().await;
                let old = taken.then(|| client.take_verified_login_identity().unwrap());
                *transport.0.lock().unwrap() = Some(mode);
                let prepared = client
                    .prepare_interactive_login("fixture-b".into())
                    .await
                    .unwrap();
                let expected = if mode == "challenge" {
                    ubaa_core::facade::InteractiveRouteState::CaptchaRequired
                } else {
                    ubaa_core::facade::InteractiveRouteState::Failed
                };
                assert!(prepared.routes.iter().all(|r| r.state == expected));
                assert!(client.take_verified_login_identity().is_err());
                if let Some(old) = old {
                    assert!(client.validate_login_identity(&old).is_err());
                }
                if mode == "challenge" {
                    assert!(prepared.login.is_active());
                    assert!(
                        client
                            .refresh_interactive_captcha(
                                &prepared.login,
                                ubaa_core::facade::ConnectionMode::Direct
                            )
                            .await
                            .is_ok()
                    );
                }
            }
        }
    }
    #[tokio::test]
    async fn 普通活动刷新与临时错误保留同身份能力() {
        for taken in [false, true] {
            let (mut client, transport) = 客户端().await;
            let old = taken.then(|| client.take_verified_login_identity().unwrap());
            client
                .recover_required_session(ubaa_core::facade::ReadonlyFeature::Schedule)
                .await
                .unwrap();
            *transport.0.lock().unwrap() = Some("transient");
            assert!(
                client
                    .recover_required_session(ubaa_core::facade::ReadonlyFeature::Schedule)
                    .await
                    .is_err()
            );
            assert_eq!(client.active_routes().len(), 2);
            let token = old.unwrap_or_else(|| client.take_verified_login_identity().unwrap());
            assert!(client.validate_login_identity(&token).is_ok());
        }
    }
    #[tokio::test]
    async fn 资料读取确认失效也撤销未取出的能力() {
        let (mut client, transport) = 客户端().await;
        *transport.0.lock().unwrap() = None;
        assert!(client.get_user_info().await.is_err());
        assert!(client.take_verified_login_identity().is_err());
    }
    #[tokio::test]
    async fn 单路线恢复确认失效必须撤销旧能力() {
        let (mut client, transport) = 客户端().await;
        let old = client.take_verified_login_identity().unwrap();
        *transport.0.lock().unwrap() = None;
        assert!(
            client
                .recover_required_session(ubaa_core::facade::ReadonlyFeature::Schedule)
                .await
                .is_err()
        );
        assert!(
            client.validate_login_identity(&old).is_err(),
            "确认认证失效后，旧票据仍可核实"
        );
    }
}
