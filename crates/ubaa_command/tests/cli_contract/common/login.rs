use std::io::Write;
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use ubaa_command::{Cli, CommandControl, PreparedCommand, execute_auth_attempt, prepare_input};
use ubaa_core::facade::testing::{
    FileSessionStore, HttpMethod, HttpRequest, HttpResponse, HttpTransport, sso_fixture_ticket,
};
use ubaa_core::facade::{ErrorCode, ErrorKind, Result, UbaaClient, UbaaError};

#[derive(Clone)]
struct LoginTransport {
    username: &'static str,
    posts: Arc<AtomicUsize>,
}

#[async_trait::async_trait]
impl HttpTransport for LoginTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = &request.url;
        if let Some(response) = sso_fixture_ticket(&request) {
            return Ok(response);
        }
        if url.starts_with("https://sso.buaa.edu.cn/serviceValidate?") {
            let body = serde_json::json!({
                "user": self.username,
                "attributes": {"employeeNumber": ["TEST-0001"], "name": ["Fixture User"]},
            });
            return Ok(HttpResponse::new(200, url, body.to_string().into_bytes()));
        }
        if url == "https://sso.buaa.edu.cn/login" {
            if request.method == HttpMethod::Post {
                assert!(String::from_utf8_lossy(&request.body).contains(self.username));
                self.posts.fetch_add(1, Ordering::SeqCst);
                let mut response = HttpResponse::new(302, url, Vec::new());
                response
                    .headers
                    .insert("Location".into(), vec!["https://uc.buaa.edu.cn/".into()]);
                return Ok(response);
            }
            return Ok(HttpResponse::new(200, url, br#"<form action="login"><input type="hidden" name="execution" value="fixture-execution"></form>"#.to_vec()));
        }
        if url == "https://uc.buaa.edu.cn/" {
            return Err(UbaaError::new(
                ErrorCode::NetworkError,
                ErrorKind::Network,
                true,
                "合成用户中心不可达",
            ));
        }
        panic!("未安排的合成登录请求");
    }
}

pub(crate) struct LoginFixture {
    client: UbaaClient,
    posts: Arc<AtomicUsize>,
    _temp: ubaa_test_support::TestTempDir,
}

impl LoginFixture {
    pub(crate) fn new(username: &'static str) -> Self {
        let temp = ubaa_test_support::test_temp_dir("ubaa_command_login").unwrap();
        let posts = Arc::new(AtomicUsize::new(0));
        let transport = LoginTransport {
            username,
            posts: posts.clone(),
        };
        let client = UbaaClient::with_transports(
            transport,
            ubaa_test_support::MockTransport::new([]),
            FileSessionStore::new(temp.path()).unwrap(),
        )
        .unwrap();
        Self {
            client,
            posts,
            _temp: temp,
        }
    }

    pub(crate) fn posts(&self) -> usize {
        self.posts.load(Ordering::SeqCst)
    }

    pub(crate) async fn run(
        &mut self,
        cli: Cli,
        mut input: &[u8],
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        let control = CommandControl::default();
        let prepared = prepare_input(cli.into(), &mut input, &control).unwrap();
        self.execute(&prepared, &control, stdout, stderr).await
    }

    pub(crate) async fn execute(
        &mut self,
        prepared: &PreparedCommand,
        control: &CommandControl,
        stdout: &mut impl Write,
        stderr: &mut impl Write,
    ) -> i32 {
        execute_auth_attempt(prepared, &mut self.client, control)
            .await
            .into_result()
            .render(control, stdout, stderr)
    }
}
