use super::*;
use std::collections::BTreeMap;
use std::time::Duration;
use ubaa_core::facade::testing::{
    GatewayProbe, HttpMethod, RouteConfig, from_webvpn_url, with_routing_in_config_directory,
};
use ubaa_core::facade::{
    CaptchaAnswer, DualLoginInput, LoginReadiness, NetworkState, RoutePolicy, SecretValue,
};

pub(super) const PLAIN_PAGE: &str = r#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-plain-execution"><input type="hidden" name="unrelated-hidden" value="synthetic-extra"></form>"#;
pub(super) const ANSWER: &str = "synthetic-answer-7";

pub(super) struct Gate {
    pub(super) started: tokio::sync::Notify,
    pub(super) released: tokio::sync::Notify,
    pub(super) fail: bool,
}

#[derive(Clone)]
pub(super) struct ScenarioTransport {
    pub(super) state: Arc<Mutex<Scenario>>,
    pub(super) requests: Arc<Mutex<Vec<HttpRequest>>>,
    label: &'static str,
}

pub(super) struct Scenario {
    pub(super) page: String,
    pub(super) image: Vec<u8>,
    pub(super) image_final_url: Option<String>,
    pub(super) post_body: String,
    pub(super) username: String,
    pub(super) redirect_with_cookie: bool,
    pub(super) image_gate: Option<Arc<Gate>>,
    pub(super) post_gate: Option<Arc<Gate>>,
}

impl ScenarioTransport {
    fn new(label: &'static str, requests: Arc<Mutex<Vec<HttpRequest>>>) -> Self {
        Self {
            state: Arc::new(Mutex::new(Scenario {
                page: SYNTHETIC_PAGE.into(),
                image: synthetic_image(ImageFormat::Png),
                image_final_url: None,
                post_body: "synthetic-authenticated".into(),
                username: SYNTHETIC_USERNAME.into(),
                redirect_with_cookie: false,
                image_gate: None,
                post_gate: None,
            })),
            requests,
            label,
        }
    }
}

#[async_trait]
impl HttpTransport for ScenarioTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let direct = from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
        let path = url::Url::parse(&direct).unwrap().path().to_owned();
        let (mut response, gate) = {
            let scenario = self.state.lock().unwrap();
            let body = match (request.method, path.as_str()) {
                (HttpMethod::Get, "/login") => scenario.page.as_bytes().to_vec(),
                (HttpMethod::Get, "/captcha") => scenario.image.clone(),
                (HttpMethod::Post, "/login") => scenario.post_body.as_bytes().to_vec(),
                (_, "/api/uc/status" | "/api/uc/userinfo") => format!(
                    r#"{{"code":0,"data":{{"username":"{}","schoolid":"{}","name":"合成用户"}}}}"#,
                    scenario.username, scenario.username
                )
                .into_bytes(),
                (_, "/api/login" | "/logout") => Vec::new(),
                _ => panic!("出现未授权的合成测试路径"),
            };
            let mut response = HttpResponse::new(200, request.url.clone(), body);
            if path == "/login" && request.method == HttpMethod::Get {
                response.headers.insert(
                    "Set-Cookie".into(),
                    vec![format!("SYNTHETIC_ROUTE={}; Path=/; Secure", self.label)],
                );
                if scenario.redirect_with_cookie && request.headers.contains_key("Cookie") {
                    response.status = 302;
                    response.headers.insert(
                        "Location".into(),
                        vec!["/synthetic-existing-session".into()],
                    );
                }
            }
            if path == "/captcha"
                && let Some(final_url) = &scenario.image_final_url
            {
                response.final_url.clone_from(final_url);
            }
            let mut gate = (path == "/captcha")
                .then(|| scenario.image_gate.clone())
                .flatten();
            if request.method == HttpMethod::Post {
                gate.clone_from(&scenario.post_gate);
            }
            (response, gate)
        };
        if let Some(gate) = gate {
            gate.started.notify_one();
            gate.released.notified().await;
            if gate.fail {
                response.status = 503;
            }
        }
        Ok(response)
    }
}

struct SyntheticProbe(NetworkState);
impl GatewayProbe for SyntheticProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        self.0
    }
}

pub(super) struct Fixture {
    pub(super) client: UbaaClient,
    pub(super) direct: ScenarioTransport,
    pub(super) webvpn: ScenarioTransport,
    pub(super) requests: Arc<Mutex<Vec<HttpRequest>>>,
    pub(super) root: std::path::PathBuf,
}

impl Fixture {
    pub(super) fn new(policy: RoutePolicy) -> Self {
        Self::with_network(policy, NetworkState::Campus)
    }

    pub(super) fn with_network(policy: RoutePolicy, network: NetworkState) -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(1000);
        let root = std::env::temp_dir().join(format!(
            "ubaa-interactive-flow-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let mut config = RouteConfig::default();
        config.default = policy;
        config.save(&root).unwrap();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let direct = ScenarioTransport::new("direct", requests.clone());
        let webvpn = ScenarioTransport::new("webvpn", requests.clone());
        let client = with_routing_in_config_directory(
            direct.clone(),
            webvpn.clone(),
            &root,
            SyntheticProbe(network),
        )
        .unwrap();
        Self {
            client,
            direct,
            webvpn,
            requests,
            root,
        }
    }

    pub(super) fn count(&self) -> usize {
        self.requests.lock().unwrap().len()
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

pub(super) fn input() -> DualLoginInput {
    DualLoginInput {
        username: SYNTHETIC_USERNAME.into(),
        password: SecretValue::new("synthetic-password"),
    }
}

pub(super) fn answer(challenge: &ubaa_core::facade::CaptchaChallenge) -> CaptchaAnswer {
    CaptchaAnswer {
        challenge: challenge.clone(),
        answer: SecretValue::new(ANSWER),
    }
}

pub(super) fn run(future: impl std::future::Future<Output = ()>) {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(future);
}

#[test]
fn eight_fields_pre_submit_get_and_route_local_cookies_are_exact() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let direct = prepared.routes[0].challenge.as_ref().unwrap().clone();
        let webvpn = prepared.routes[1].challenge.as_ref().unwrap().clone();
        let partial = fixture
            .client
            .submit_interactive_login(&prepared.login, input(), vec![answer(&direct)])
            .await
            .unwrap();
        assert_eq!(partial.readiness, LoginReadiness::Partial);
        assert_eq!(
            partial.routes[1].state,
            InteractiveRouteState::CaptchaRequired
        );
        let requests = fixture.requests.lock().unwrap().clone();
        let (post_index, post) = requests
            .iter()
            .enumerate()
            .find(|(_, request)| request.method == HttpMethod::Post)
            .unwrap();
        assert_eq!(requests[post_index - 1].method, HttpMethod::Get);
        assert_eq!(
            requests[post_index - 1].url,
            "https://sso.buaa.edu.cn/login"
        );
        assert_exact_captcha_form(post);
        for image in requests
            .iter()
            .filter(|request| request.url.contains("/captcha?"))
        {
            let expected = if image.url.starts_with("https://sso.") {
                "direct"
            } else {
                "webvpn"
            };
            assert_eq!(
                image.headers.get("Cookie").unwrap(),
                &format!("SYNTHETIC_ROUTE={expected}")
            );
            assert_eq!(
                url::Url::parse(&image.url).unwrap().query_pairs().count(),
                1
            );
        }
        let before = fixture.count();
        assert!(
            fixture
                .client
                .submit_interactive_login(&prepared.login, input(), vec![answer(&direct)])
                .await
                .is_err()
        );
        assert_eq!(fixture.count(), before);
        let completed = fixture
            .client
            .submit_interactive_login(&prepared.login, input(), vec![answer(&webvpn)])
            .await
            .unwrap();
        assert_eq!(completed.readiness, LoginReadiness::AllReady);
        let requests = fixture.requests.lock().unwrap();
        let posts: Vec<_> = requests
            .iter()
            .filter(|request| request.method == HttpMethod::Post)
            .collect();
        assert_eq!(posts.len(), 2);
        for post in &posts {
            assert_exact_captcha_form(post);
        }
        assert_eq!(
            posts
                .iter()
                .filter(|request| request.url.starts_with("https://sso."))
                .count(),
            1
        );
    });
}

fn assert_exact_captcha_form(post: &HttpRequest) {
    let pairs: Vec<_> = url::form_urlencoded::parse(&post.body)
        .into_owned()
        .collect();
    assert_eq!(pairs.len(), 8);
    let fields: BTreeMap<_, _> = pairs.into_iter().collect();
    assert_eq!(
        fields,
        BTreeMap::from([
            ("username".into(), SYNTHETIC_USERNAME.into()),
            ("password".into(), "synthetic-password".into()),
            ("captcha".into(), ANSWER.into()),
            ("captchaResponse".into(), ANSWER.into()),
            ("execution".into(), "synthetic-execution-1".into()),
            ("_eventId".into(), "submit".into()),
            ("submit".into(), "登录".into()),
            ("type".into(), "username_password".into()),
        ])
    );
    assert_eq!(
        post.headers.get("Content-Type").unwrap(),
        "application/x-www-form-urlencoded"
    );
    assert!(!post.url.contains(ANSWER));
    assert!(post.headers.values().all(|value| !value.contains(ANSWER)));
}

#[test]
fn rotated_execution_or_id_returns_new_challenge_without_post() {
    run(async {
        for replace in ["execution", "captcha"] {
            let mut fixture = Fixture::new(RoutePolicy::Auto);
            let prepared = fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            let old = prepared.routes[0].challenge.as_ref().unwrap();
            fixture.direct.state.lock().unwrap().page = SYNTHETIC_PAGE.replace(
                &format!("synthetic-{replace}-1"),
                &format!("synthetic-{replace}-2"),
            );
            let rotated = fixture
                .client
                .submit_interactive_login(&prepared.login, input(), vec![answer(old)])
                .await
                .unwrap();
            assert!(
                fixture
                    .requests
                    .lock()
                    .unwrap()
                    .iter()
                    .all(|request| request.method != HttpMethod::Post)
            );
            assert_ne!(
                old.revision(),
                rotated.routes[0].challenge.as_ref().unwrap().revision()
            );
            let before = fixture.count();
            assert!(
                fixture
                    .client
                    .submit_interactive_login(&prepared.login, input(), vec![answer(old)])
                    .await
                    .is_err()
            );
            assert_eq!(fixture.count(), before);
            let result = fixture
                .client
                .submit_interactive_login(
                    &prepared.login,
                    input(),
                    vec![answer(rotated.routes[0].challenge.as_ref().unwrap())],
                )
                .await
                .unwrap();
            assert_eq!(result.routes[0].state, InteractiveRouteState::Ready);
        }
    });
}

#[test]
fn invalid_or_oversized_images_stay_required_and_never_become_plain_login() {
    run(async {
        let mut large = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(RgbaImage::new(1025, 1))
            .write_to(&mut large, ImageFormat::Png)
            .unwrap();
        for bytes in [
            b"<html>synthetic-image-error</html>".to_vec(),
            vec![1, 2, 3, 4],
            vec![0; 512 * 1024 + 1],
            large.into_inner(),
        ] {
            let mut fixture = Fixture::new(RoutePolicy::Auto);
            fixture.direct.state.lock().unwrap().image = bytes;
            let result = fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            assert_eq!(
                result.routes[0].state,
                InteractiveRouteState::CaptchaRequired
            );
            assert!(result.routes[0].frame.is_none());
            assert!(result.routes[0].challenge.is_none());
            let before = fixture.count();
            let still_waiting = fixture
                .client
                .submit_interactive_login(&result.login, input(), Vec::new())
                .await
                .unwrap();
            assert_eq!(fixture.count(), before);
            assert_eq!(
                still_waiting.routes[0].state,
                InteractiveRouteState::CaptchaRequired
            );
        }
    });
}

#[test]
fn jpeg_is_decoded_from_real_bytes_and_unknown_final_host_is_closed() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        let mut jpeg = Cursor::new(Vec::new());
        DynamicImage::new_rgb8(2, 1)
            .write_to(&mut jpeg, ImageFormat::Jpeg)
            .unwrap();
        fixture.direct.state.lock().unwrap().image = jpeg.into_inner();
        fixture.webvpn.state.lock().unwrap().image_final_url =
            Some("https://unknown.invalid/captcha".into());
        let result = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        assert_eq!(result.routes[0].frame.as_ref().unwrap().rgba.len(), 8);
        assert!(result.routes[1].frame.is_none());
        assert_eq!(
            result.routes[1].state,
            InteractiveRouteState::CaptchaRequired
        );
        assert_eq!(fixture.count(), 4);
    });
}

#[test]
fn unknown_interactions_send_neither_images_nor_credentials() {
    run(async {
        for extra in [
            "<input name=otp>",
            "<select name=verification></select>",
            "<script>config.mfa = {}</script>",
        ] {
            let mut fixture = Fixture::new(RoutePolicy::Auto);
            fixture.direct.state.lock().unwrap().page =
                SYNTHETIC_PAGE.replace("</form>", &format!("{extra}</form>"));
            fixture.webvpn.state.lock().unwrap().page =
                "<script>config.captcha = { type: 'slider', id: 'synthetic-id' }</script>".into();
            let result = fixture
                .client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .unwrap();
            assert_eq!(fixture.count(), 2);
            assert!(
                result
                    .routes
                    .iter()
                    .all(|route| route.state == InteractiveRouteState::Failed)
            );
            fixture
                .client
                .submit_interactive_login(&result.login, input(), Vec::new())
                .await
                .unwrap();
            assert_eq!(fixture.count(), 2);
        }
    });
}

#[test]
fn captcha_failure_never_claims_invalid_credentials_or_leaks_material() {
    run(async {
        let mut fixture = Fixture::new(RoutePolicy::Auto);
        fixture.direct.state.lock().unwrap().post_body =
            format!("<div class=tip-text>{ANSWER} synthetic-captcha-1 synthetic-execution-1</div>");
        let prepared = fixture
            .client
            .prepare_interactive_login(SYNTHETIC_USERNAME.into())
            .await
            .unwrap();
        let result = fixture
            .client
            .submit_interactive_login(
                &prepared.login,
                input(),
                vec![answer(prepared.routes[0].challenge.as_ref().unwrap())],
            )
            .await
            .unwrap();
        assert_eq!(
            result.routes[0].state,
            InteractiveRouteState::CaptchaRequired
        );
        assert_ne!(
            result.routes[0].error.as_ref().unwrap().code,
            "invalid_credentials"
        );
        let formatted = format!("{prepared:?} {result:?}");
        for value in [
            ANSWER,
            "synthetic-captcha-1",
            "synthetic-execution-1",
            "synthetic-password",
        ] {
            assert!(!formatted.contains(value));
            assert!(
                !std::fs::read_to_string(fixture.root.join("config.toml"))
                    .unwrap()
                    .contains(value)
            );
            if let Ok(session) = std::fs::read_to_string(fixture.root.join("session.json")) {
                assert!(!session.contains(value));
            }
        }
        assert_eq!(
            result.routes[0].error.as_ref().unwrap().code,
            "upstream_changed"
        );
        assert!(result.routes[0].frame.is_none());
    });
}
