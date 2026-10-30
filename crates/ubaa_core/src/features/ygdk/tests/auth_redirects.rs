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
                location,
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
    location: String,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for RedirectTransport {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        let mut requests = self.requests.lock().unwrap();
        let count = requests.len();
        requests.push(request.clone());
        match count {
            0 => {
                let mut response = HttpResponse::new(302, request.url, vec![]);
                response
                    .headers
                    .insert("location".into(), vec![self.location.clone()]);
                Ok(response)
            }
            1 => Ok(HttpResponse::new(
                200,
                request.url,
                br#"{"code":1,"result":{"uid":7,"token":"token+part&tail%252B"}}"#.to_vec(),
            )),
            _ => panic!("授权码回调不能额外访问或重试"),
        }
    }
}
