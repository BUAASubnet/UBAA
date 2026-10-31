use super::*;

#[test]
fn 双路线只从回调取一次授权码并编码后交换() {
    for (case, mode, location, success) in [
        (
            "direct",
            ConnectionMode::Direct,
            "https://ygdk.buaa.edu.cn/#/home?code=code+part%26tail%252B".to_owned(),
            true,
        ),
        (
            "vpn",
            ConnectionMode::WebVpn,
            to_webvpn_url("https://ygdk.buaa.edu.cn/#/home?code=code+part%26tail%252B")
                .unwrap()
                .strip_prefix("https://d.buaa.edu.cn")
                .unwrap()
                .to_owned(),
            true,
        ),
        (
            "unknown",
            ConnectionMode::Direct,
            "https://evil.example.invalid/#/home?code=fixture".to_owned(),
            false,
        ),
        (
            "wrapped-unknown",
            ConnectionMode::WebVpn,
            to_webvpn_url("https://evil.example.invalid/#/home?code=fixture").unwrap(),
            false,
        ),
    ] {
        let root =
            std::env::temp_dir().join(format!("ubaa-ygdk-redirect-{case}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).unwrap();
        save_session(
            &store,
            &SessionSnapshot {
                mode,
                cookies: vec![],
                authenticated_at: 1_000,
                last_activity: 1_001,
            },
        )
        .unwrap();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let mut runtime = ClientRuntime::new(
            mode,
            RedirectTransport {
                locations: vec![location],
                requests: Arc::clone(&requests),
            },
            store,
        )
        .unwrap();
        let result = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(ensure_login(&mut runtime));
        if success {
            let credential = result.unwrap();
            assert_eq!(credential.token, "token+part&tail%2B");
        } else {
            assert!(result.is_err(), "未知主机必须在发送前拒绝");
            assert!(runtime.feature_state().ygdk.credential().is_none());
        }
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), if success { 2 } else { 1 });
        for request in requests.iter() {
            assert_eq!(
                url::Url::parse(&request.url).unwrap().host_str() == Some("d.buaa.edu.cn"),
                mode == ConnectionMode::WebVpn
            );
        }
        if success {
            let direct = crate::connection::from_webvpn_url(&requests[1].url).unwrap();
            let parsed = url::Url::parse(&direct).unwrap();
            assert_eq!(parsed.path(), "/api/Front/Clockin/User/campusAppLogin");
            assert_eq!(
                parsed
                    .query_pairs()
                    .find(|(key, _)| key == "code")
                    .unwrap()
                    .1,
                "code+part&tail%2B"
            );
        }
        let _ = std::fs::remove_dir_all(root);
    }
}

struct RedirectTransport {
    locations: Vec<String>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for RedirectTransport {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        let mut requests = self.requests.lock().unwrap();
        let count = requests.len();
        requests.push(request.clone());
        if let Some(location) = self.locations.get(count) {
            let mut response = HttpResponse::new(302, request.url, vec![]);
            response
                .headers
                .insert("location".into(), vec![location.clone()]);
            Ok(response)
        } else if count == self.locations.len() {
            Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":1,"result":{"uid":7,"token":"token+part&tail%252B"}}"#.to_vec(),
            ))
        } else {
            panic!("授权码回调不能额外访问或重试")
        }
    }
}

#[test]
fn 双路线阳光登录经过_sso_后才交换回调授权码() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/ygdk_diagnosis")
            .join(format!("mock-{mode:?}-{}", std::process::id()));
        let store = FileSessionStore::new(&root).unwrap();
        save_session(
            &store,
            &SessionSnapshot {
                mode,
                cookies: vec![],
                authenticated_at: 1_000,
                last_activity: 1_001,
            },
        )
        .unwrap();
        let direct_locations = [
            "https://app.buaa.edu.cn/uc/wap/login",
            "https://app.buaa.edu.cn/a_buaa/api/cas/index",
            "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn%2Fa_buaa%2Fapi%2Fcas%2Findex&code=不能提取",
            "https://app.buaa.edu.cn/a_buaa/api/cas/index?ticket=fixture",
            "https://app.buaa.edu.cn/uc/api/oauth/index",
            "https://ygdk.buaa.edu.cn/#/home?code=callback-fixture",
        ];
        let locations = direct_locations
            .iter()
            .map(|url| {
                if mode == ConnectionMode::WebVpn {
                    to_webvpn_url(url).unwrap()
                } else {
                    (*url).to_owned()
                }
            })
            .collect();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let mut runtime = ClientRuntime::new(
            mode,
            RedirectTransport {
                locations,
                requests: Arc::clone(&requests),
            },
            store,
        )
        .unwrap();
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(ensure_login(&mut runtime))
            .expect("完整 SSO 链应成功");
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 7);
        for request in requests.iter() {
            assert_eq!(
                url::Url::parse(&request.url).unwrap().host_str() == Some("d.buaa.edu.cn"),
                mode == ConnectionMode::WebVpn
            );
        }
        let last = crate::connection::from_webvpn_url(&requests[6].url).unwrap();
        let last = url::Url::parse(&last).unwrap();
        assert_eq!(last.path(), "/api/Front/Clockin/User/campusAppLogin");
        assert_eq!(
            last.query_pairs().find(|(k, _)| k == "code").unwrap().1,
            "callback-fixture"
        );
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn 阳光_sso_仅允许安全登录路径且不能提取授权码() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        for target in [
            "http://sso.buaa.edu.cn/login",
            "https://sso.buaa.edu.cn:8443/login",
            "https://user:pass@sso.buaa.edu.cn/login",
            "https://sso.buaa.edu.cn/logout",
            "https://sso.buaa.edu.cn/login/other",
            "https://sso.buaa.edu.cn.evil.example/login",
        ] {
            let target = if mode == ConnectionMode::WebVpn {
                let Ok(wrapped) = to_webvpn_url(target) else {
                    // codec 提前拒绝带用户信息的地址，同样不能进入请求。
                    continue;
                };
                wrapped
            } else {
                target.into()
            };
            assert!(validate_oauth_target(&target, mode).is_err(), "{target}");
        }
        assert!(code_from_url("https://sso.buaa.edu.cn/login?code=fixture").is_none());
    }
}
