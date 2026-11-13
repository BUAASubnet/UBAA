use super::*;
use std::collections::VecDeque;
use ubaa_core::facade::testing::{HttpMethod, with_routing_in_config_directory};
use ubaa_core::facade::{
    DualLoginInput, ErrorKind, InteractiveLoginCancellation, InteractiveRouteState, RouteLoginState,
};

#[derive(Clone)]
enum Failure {
    Credentials(&'static str),
    Network,
    Unavailable,
}

#[derive(Clone)]
struct RetryTransport {
    inner: IdentityTransport,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    failures: Arc<Mutex<VecDeque<Failure>>>,
    pages: Arc<AtomicUsize>,
    cancellation: Arc<Mutex<Option<InteractiveLoginCancellation>>>,
}

#[async_trait]
impl HttpTransport for RetryTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        if from_webvpn_url(&request.url).unwrap() == "https://sso.buaa.edu.cn/login" {
            if request.method == HttpMethod::Get {
                let number = self.pages.fetch_add(1, Ordering::SeqCst) + 1;
                return Ok(HttpResponse::new(200, request.url, format!(
                    "<form id=\"fm1\"><input type=\"hidden\" name=\"execution\" value=\"synthetic-execution-{number}\"></form>"
                ).into_bytes()));
            }
            if let Some(failure) = self.failures.lock().unwrap().pop_front() {
                if let Some(cancellation) = &*self.cancellation.lock().unwrap() {
                    cancellation.cancel();
                }
                return match failure {
                    Failure::Credentials(message) => Ok(HttpResponse::new(
                        401,
                        request.url,
                        format!("<div id=\"errorDiv\"><p>{message}</p></div>").into_bytes(),
                    )),
                    Failure::Network => Err(UbaaError::new(
                        ErrorCode::NetworkError,
                        ErrorKind::Network,
                        true,
                        "合成连接中断",
                    )),
                    Failure::Unavailable => Ok(HttpResponse::new(503, request.url, Vec::new())),
                };
            }
        }
        self.inner.execute(request).await
    }
}

struct Fixture {
    client: UbaaClient,
    transport: RetryTransport,
    root: std::path::PathBuf,
}

impl Fixture {
    fn new(failures: Vec<Failure>) -> Self {
        let root = test_root("webvpn-login-retry");
        let transport = RetryTransport {
            inner: IdentityTransport {
                requests: Arc::default(),
                invalid: false,
            },
            requests: Arc::default(),
            failures: Arc::new(Mutex::new(failures.into())),
            pages: Arc::default(),
            cancellation: Arc::default(),
        };
        let client = with_routing_in_config_directory(
            transport.clone(),
            transport.clone(),
            &root,
            NeverProbe,
        )
        .unwrap();
        Self {
            client,
            transport,
            root,
        }
    }

    fn posts(&self) -> Vec<HttpRequest> {
        self.transport
            .requests
            .lock()
            .unwrap()
            .iter()
            .filter(|request| request.method == HttpMethod::Post)
            .cloned()
            .collect()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn credentials() -> LoginInput {
    LoginInput {
        username: "fixture-account".into(),
        password: SecretValue::new("fixture-password"),
    }
}

fn dual_credentials() -> DualLoginInput {
    let input = credentials();
    DualLoginInput {
        username: input.username,
        password: input.password,
    }
}

#[tokio::test]
async fn webvpn普通登录首次失败后使用新页面和相同凭据重试一次() {
    for failure in [
        Failure::Credentials("合成凭据拒绝"),
        Failure::Network,
        Failure::Unavailable,
    ] {
        let mut fixture = Fixture::new(vec![failure]);
        let result = fixture
            .client
            .login_required_route(ConnectionMode::WebVpn, credentials())
            .await;
        assert!(result.is_ok(), "首次失败后第二次普通登录应成功");
        assert_eq!(fixture.client.active_routes(), vec![ConnectionMode::WebVpn]);
        let posts = fixture.posts();
        assert_eq!(posts.len(), 2);
        for (index, post) in posts.iter().enumerate() {
            assert!(post.url.starts_with("https://d.buaa.edu.cn/"));
            let form: std::collections::BTreeMap<_, _> = url::form_urlencoded::parse(&post.body)
                .into_owned()
                .collect();
            assert_eq!(form["username"], "fixture-account");
            assert_eq!(form["password"], "fixture-password");
            assert_eq!(
                form["execution"],
                format!("synthetic-execution-{}", index + 1)
            );
        }
    }
}

#[tokio::test]
async fn webvpn两次凭据拒绝后停止并返回第二次错误() {
    let mut fixture = Fixture::new(vec![
        Failure::Credentials("第一次合成拒绝"),
        Failure::Credentials("第二次合成拒绝"),
    ]);
    let error = fixture
        .client
        .login_required_route(ConnectionMode::WebVpn, credentials())
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidCredentials);
    assert_eq!(error.message, "第二次合成拒绝");
    assert_eq!(fixture.posts().len(), 2);
    assert_eq!(
        fixture.client.active_routes(),
        [] as [ubaa_core::facade::ConnectionMode; 0]
    );
}

#[tokio::test]
async fn direct普通登录失败只提交一次() {
    let mut fixture = Fixture::new(vec![Failure::Credentials("合成凭据拒绝")]);
    let error = fixture
        .client
        .login_required_route(ConnectionMode::Direct, credentials())
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidCredentials);
    assert_eq!(fixture.posts().len(), 1);
}

#[tokio::test]
async fn webvpn首次成功只提交一次() {
    let mut fixture = Fixture::new(vec![]);
    fixture
        .client
        .login_required_route(ConnectionMode::WebVpn, credentials())
        .await
        .unwrap();
    assert_eq!(fixture.posts().len(), 1);
}

#[tokio::test]
async fn 应用普通页面登录共用webvpn一次重试() {
    for quiet in [false, true] {
        let mut fixture = Fixture::new(vec![]);
        fixture
            .client
            .set_default_route_policy(RoutePolicy::WebVpn)
            .unwrap();
        let login = fixture
            .client
            .interactive_login_cancellation()
            .begin("fixture-account")
            .unwrap();
        fixture
            .client
            .prepare_quiet_login_for(&login)
            .await
            .unwrap();
        fixture
            .transport
            .failures
            .lock()
            .unwrap()
            .push_back(Failure::Credentials("合成凭据拒绝"));
        let before = fixture.posts().len();
        let outcome = if quiet {
            fixture
                .client
                .submit_quiet_login(&login, dual_credentials())
                .await
                .unwrap()
        } else {
            fixture
                .client
                .submit_interactive_login(&login, dual_credentials(), vec![])
                .await
                .unwrap()
        };
        assert_eq!(outcome.routes[1].state, InteractiveRouteState::Ready);
        assert_eq!(fixture.posts().len() - before, 2);
    }
}

#[tokio::test]
async fn webvpn首次失败时取消登录不再重试() {
    let mut fixture = Fixture::new(vec![Failure::Network]);
    fixture
        .client
        .set_default_route_policy(RoutePolicy::WebVpn)
        .unwrap();
    let cancellation = fixture.client.interactive_login_cancellation();
    let login = cancellation.begin("fixture-account").unwrap();
    fixture
        .client
        .prepare_quiet_login_for(&login)
        .await
        .unwrap();
    *fixture.transport.cancellation.lock().unwrap() = Some(cancellation);
    assert!(
        fixture
            .client
            .submit_quiet_login(&login, dual_credentials())
            .await
            .is_err()
    );
    assert_eq!(fixture.posts().len(), 1);
}

#[tokio::test]
async fn 聚合登录仅重试失败的webvpn路线() {
    let mut fixture = Fixture::new(vec![
        Failure::Credentials("Direct 合成拒绝"),
        Failure::Credentials("WebVPN 合成拒绝"),
    ]);
    let outcome = fixture.client.login(dual_credentials()).await.unwrap();
    assert_eq!(outcome.routes[0].state, RouteLoginState::Failed);
    assert_eq!(outcome.routes[1].state, RouteLoginState::Ready);
    assert_eq!(fixture.posts().len(), 3);
}
