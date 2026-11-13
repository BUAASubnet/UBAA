//! 合成上游通过实际 live 登录入口，检查自动验证码、路线和会话结果。
use super::*;
use async_trait::async_trait;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
use ubaa_core::facade::testing::{
    set_captcha_recognizer, sso_fixture_response, sso_fixture_ticket,
    with_routing_in_config_directory,
};
use ubaa_core::facade::{NetworkState, Result, SecretValue};
use ubaa_test_support::{
    GatewayProbe, HttpMethod, HttpRequest, HttpResponse, HttpTransport, from_webvpn_url,
};

const USER: &str = "synthetic-live-user";
const PLAIN: &str =
    r#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-execution"></form>"#;
const CAPTCHA: &str = "<script>config.captcha = { type: 'image', id: 'synthetic-id' }</script>";

#[derive(Clone, Copy)]
struct Scenario {
    captcha: bool,
    refusals: usize,
    status: u16,
    wrong_identity: bool,
    unsupported: bool,
}
impl Default for Scenario {
    fn default() -> Self {
        Self {
            captcha: true,
            refusals: 0,
            status: 401,
            wrong_identity: false,
            unsupported: false,
        }
    }
}
#[derive(Clone)]
struct Transport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    scenario: Scenario,
}
struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不能进行 Auto 网络探测")
    }
}
#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        if let Some(response) = sso_fixture_ticket(&request) {
            return Ok(response);
        }
        let direct = from_webvpn_url(&request.url).unwrap();
        let url = url::Url::parse(&direct).unwrap();
        let page = format!(
            "{PLAIN}{}",
            if self.scenario.unsupported {
                "<script>config.captcha = { type: 'slider', id: 'synthetic-id' }</script>"
            } else if self.scenario.captcha {
                CAPTCHA
            } else {
                ""
            }
        );
        let mut status = 200;
        let body = match (request.method, url.path()) {
            (HttpMethod::Get, "/login") => page.into_bytes(),
            (HttpMethod::Get, "/captcha") => {
                include_bytes!("../../../../fixtures/auth/captcha_synthetic.png").to_vec()
            }
            (HttpMethod::Post, "/login") => {
                let posts = self
                    .requests
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|r| r.method == HttpMethod::Post)
                    .count();
                if posts <= self.scenario.refusals {
                    status = self.scenario.status;
                    format!("{page}<div id=\"errorDiv\"><p>用户名或密码错误。</p></div>")
                        .into_bytes()
                } else {
                    b"synthetic-authenticated".to_vec()
                }
            }
            (_, "/api/login") => Vec::new(),
            (_, "/serviceValidate" | "/api/uc/userinfo") => {
                let username = if self.scenario.wrong_identity {
                    "synthetic-other-user"
                } else {
                    USER
                };
                format!(r#"{{"code":0,"data":{{"username":"{username}","schoolid":"{username}","name":"合成用户"}}}}"#).into_bytes()
            }
            _ => panic!("出现预期外的学校请求"),
        };
        Ok(sso_fixture_response(status, request.url, body))
    }
}

async fn exercise(
    mode: ConnectionMode,
    scenario: Scenario,
    expected_ready: bool,
    expected_posts: usize,
) {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(format!(
        "../../.ubaa_local/live_auth_parity/test-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let transport = Transport {
        requests: requests.clone(),
        scenario,
    };
    let mut client =
        with_routing_in_config_directory(transport.clone(), transport, &root, NoProbe).unwrap();
    set_captcha_recognizer(&mut client, |_| Some("a2b3c4".into()));
    let mut evidence = Evidence::new("synthetic");
    let ready = login(
        &mut client,
        mode,
        LoginInput {
            username: USER.into(),
            password: SecretValue::new("synthetic-password"),
        },
        &mut evidence,
    )
    .await;
    assert_eq!(
        ready, expected_ready,
        "live 登录结果必须反映当前路线的实际状态"
    );
    assert_eq!(evidence.failed(), !expected_ready);
    if ready {
        let user = client.get_user_info().await.unwrap();
        assert_eq!(user.resolution.mode, mode);
        assert_eq!(user.data.username.as_deref(), Some(USER));
    } else {
        assert!(client.active_routes().is_empty());
    }
    let requests = requests.lock().unwrap();
    let posts: Vec<_> = requests
        .iter()
        .filter(|r| r.method == HttpMethod::Post)
        .collect();
    assert_eq!(posts.len(), expected_posts);
    if scenario.captcha {
        for post in &posts {
            let form: std::collections::BTreeMap<_, _> =
                url::form_urlencoded::parse(&post.body).collect();
            assert_eq!(form["captcha"], "a2b3c4");
            assert_eq!(form["captchaResponse"], "a2b3c4");
        }
    } else {
        assert!(!requests.iter().any(|r| r.url.contains("/captcha")));
    }
    assert!(
        requests.iter().all(
            |r| r.url.starts_with("https://d.buaa.edu.cn/") == (mode == ConnectionMode::WebVpn)
        )
    );
    drop(requests);
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 两条固定路线的验证登录都自动提交验证码并读取同一会话() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(mode, Scenario::default(), true, 1).await;
    }
}
#[tokio::test]
async fn 两次验证码拒绝后第三次成功() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(
            mode,
            Scenario {
                refusals: 2,
                ..Scenario::default()
            },
            true,
            3,
        )
        .await;
    }
}
#[tokio::test]
async fn 自动识别耗尽后验证失败且停止登录提交() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(
            mode,
            Scenario {
                refusals: 10,
                ..Scenario::default()
            },
            false,
            3,
        )
        .await;
    }
}
#[tokio::test]
async fn 验证码服务异常不重放凭据() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(
            mode,
            Scenario {
                refusals: 10,
                status: 503,
                ..Scenario::default()
            },
            false,
            1,
        )
        .await;
    }
}
#[tokio::test]
async fn 普通登录不请求验证码() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(
            mode,
            Scenario {
                captcha: false,
                ..Scenario::default()
            },
            true,
            1,
        )
        .await;
    }
}
#[tokio::test]
async fn 不支持的验证类型在提交密码前停止() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(
            mode,
            Scenario {
                unsupported: true,
                ..Scenario::default()
            },
            false,
            0,
        )
        .await;
    }
}
#[tokio::test]
async fn 返回其他账号的身份不能通过登录验证() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        exercise(
            mode,
            Scenario {
                wrong_identity: true,
                ..Scenario::default()
            },
            false,
            1,
        )
        .await;
    }
}
