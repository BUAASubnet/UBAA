use super::*;
use std::sync::atomic::AtomicUsize;
use ubaa_core::facade::testing::{HttpMethod, from_webvpn_url, set_captcha_recognizer};
use ubaa_core::facade::{ErrorCode, LoginInput, SecretValue};

#[derive(Clone)]
struct AutomaticTransport {
    posts: Arc<AtomicUsize>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    refusals: usize,
    failure_status: u16,
}

fn page(generation: usize, rejected: bool) -> String {
    format!(
        r#"<form id="loginForm" action="login"><input name="execution" value="synthetic-execution-{generation}"><input name="type" value="username_password"><input name="_eventId" value="submit"></form>{}<script>config.captcha = {{ type: 'image', id: 'synthetic-captcha-{generation}' }}; function captchaUrl() {{ return 'captcha?captchaId=' + config.captcha.id; }}</script>"#,
        if rejected {
            "<div id=\"errorDiv\"><p>用户名或密码错误。</p></div>"
        } else {
            ""
        }
    )
}

#[async_trait]
impl HttpTransport for AutomaticTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let direct = from_webvpn_url(&request.url).unwrap();
        let url = url::Url::parse(&direct).unwrap();
        let mut status = 200;
        let body = match (request.method, url.path()) {
            (HttpMethod::Get, "/login") => {
                page(self.posts.load(Ordering::SeqCst), false).into_bytes()
            }
            (HttpMethod::Get, "/captcha") => synthetic_image(ImageFormat::Png),
            (HttpMethod::Post, "/login") => {
                let count = self.posts.fetch_add(1, Ordering::SeqCst) + 1;
                if count <= self.refusals {
                    status = self.failure_status;
                    page(count, true).into_bytes()
                } else {
                    b"synthetic-authenticated".to_vec()
                }
            }
            (_, "/api/login") => Vec::new(),
            (_, "/api/uc/status" | "/api/uc/userinfo") => format!(
                r#"{{"code":0,"data":{{"username":"{SYNTHETIC_USERNAME}","schoolid":"{SYNTHETIC_USERNAME}","name":"合成用户"}}}}"#
            )
            .into_bytes(),
            _ => panic!("出现未授权的合成测试路径"),
        };
        Ok(HttpResponse::new(status, request.url, body))
    }
}

async fn run(
    route: ConnectionMode,
    refusals: usize,
    status: u16,
) -> (Result<()>, Vec<HttpRequest>) {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = std::env::temp_dir().join(format!(
        "ubaa-automatic-captcha-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let transport = AutomaticTransport {
        posts: Arc::new(AtomicUsize::new(0)),
        requests: requests.clone(),
        refusals,
        failure_status: status,
    };
    let mut client = UbaaClient::with_transports(
        transport.clone(),
        transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    set_captcha_recognizer(&mut client, |_| Some("a2b3c4".into()));
    let result = client
        .login_required_route(
            route,
            LoginInput {
                username: SYNTHETIC_USERNAME.into(),
                password: SecretValue::new("synthetic-password"),
            },
        )
        .await
        .map(|_| ());
    let requests = requests.lock().unwrap().clone();
    let _ = std::fs::remove_dir_all(root);
    (result, requests)
}

#[tokio::test]
async fn 统一拒绝后只在原路线换图并最多提交三次() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let (result, requests) = run(route, 2, 401).await;
        assert!(result.is_ok(), "第三次有效验证码应完成认证：{result:?}");
        let posts: Vec<_> = requests
            .iter()
            .filter(|r| r.method == HttpMethod::Post)
            .collect();
        assert_eq!(posts.len(), 3);
        for (index, post) in posts.iter().enumerate() {
            let form: std::collections::BTreeMap<_, _> =
                url::form_urlencoded::parse(&post.body).collect();
            assert_eq!(form["captcha"], "a2b3c4");
            assert_eq!(form["execution"], format!("synthetic-execution-{index}"));
        }
        assert!(requests.iter().all(|request| {
            (url::Url::parse(&request.url).unwrap().host_str() == Some("d.buaa.edu.cn"))
                == (route == ConnectionMode::WebVpn)
        }));
    }
}

#[tokio::test]
async fn 三次统一拒绝后保留人工处理状态且不判定密码无效() {
    let (result, requests) = run(ConnectionMode::Direct, 10, 401).await;
    assert_eq!(result.unwrap_err().code, ErrorCode::AuthenticationRequired);
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.method == HttpMethod::Post)
            .count(),
        3
    );
}

#[tokio::test]
async fn 服务异常不重放验证码登录提交() {
    let (result, requests) = run(ConnectionMode::WebVpn, 10, 503).await;
    assert_eq!(result.unwrap_err().code, ErrorCode::UpstreamUnavailable);
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.method == HttpMethod::Post)
            .count(),
        1
    );
}

#[derive(Clone)]
struct RotatingPages {
    inner: AutomaticTransport,
    gets: Arc<AtomicUsize>,
}

#[async_trait]
impl HttpTransport for RotatingPages {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let is_login_get = request.method == HttpMethod::Get
            && url::Url::parse(&from_webvpn_url(&request.url).unwrap())
                .unwrap()
                .path()
                == "/login";
        let mut response = self.inner.execute(request).await?;
        if is_login_get {
            response.body = page(self.gets.fetch_add(1, Ordering::SeqCst), false).into_bytes();
        }
        Ok(response)
    }
}

#[tokio::test]
async fn 每次读取都会轮换的真实页面形态仍能提交当前图片答案() {
    let root = std::env::temp_dir().join(format!("ubaa-rotating-captcha-{}", std::process::id()));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let transport = RotatingPages {
        inner: AutomaticTransport {
            posts: Arc::new(AtomicUsize::new(0)),
            requests: requests.clone(),
            refusals: 0,
            failure_status: 401,
        },
        gets: Arc::new(AtomicUsize::new(0)),
    };
    let mut client = UbaaClient::with_transports(
        transport.clone(),
        transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    set_captcha_recognizer(&mut client, |_| Some("a2b3c4".into()));
    let result = client
        .login_required_route(
            ConnectionMode::WebVpn,
            LoginInput {
                username: SYNTHETIC_USERNAME.into(),
                password: SecretValue::new("synthetic-password"),
            },
        )
        .await;
    assert!(result.is_ok(), "有效的当前图片答案必须能够提交：{result:?}");
    assert_eq!(
        requests
            .lock()
            .unwrap()
            .iter()
            .filter(|r| r.method == HttpMethod::Post)
            .count(),
        1
    );
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct LostResponse(AutomaticTransport);

#[async_trait]
impl HttpTransport for LostResponse {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let posted = request.method == HttpMethod::Post;
        let response = self.0.execute(request).await?;
        if posted {
            return Err(ubaa_core::facade::UbaaError::new(
                ErrorCode::Timeout,
                ubaa_core::facade::ErrorKind::Network,
                true,
                "合成超时",
            ));
        }
        Ok(response)
    }
}

#[tokio::test]
async fn 登录响应丢失时停止且不重放已发送答案() {
    let root = std::env::temp_dir().join(format!("ubaa-captcha-timeout-{}", std::process::id()));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let transport = LostResponse(AutomaticTransport {
        posts: Arc::new(AtomicUsize::new(0)),
        requests: requests.clone(),
        refusals: 0,
        failure_status: 401,
    });
    let mut client = UbaaClient::with_transports(
        transport.clone(),
        transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    set_captcha_recognizer(&mut client, |_| Some("a2b3c4".into()));
    let result = client
        .login_required_route(
            ConnectionMode::WebVpn,
            LoginInput {
                username: SYNTHETIC_USERNAME.into(),
                password: SecretValue::new("synthetic-password"),
            },
        )
        .await;
    assert_eq!(result.unwrap_err().code, ErrorCode::Timeout);
    assert_eq!(
        requests
            .lock()
            .unwrap()
            .iter()
            .filter(|r| r.method == HttpMethod::Post)
            .count(),
        1
    );
    let _ = std::fs::remove_dir_all(root);
}
