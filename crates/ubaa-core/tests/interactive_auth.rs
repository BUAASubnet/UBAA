//! 所有图片、账号、execution、id 和答案均为本测试生成的合成哨兵。

use std::io::Cursor;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use image::{DynamicImage, ImageFormat, Rgba, RgbaImage};
use ubaa_core::facade::testing::{FileSessionStore, HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::facade::{ConnectionMode, InteractiveRouteState, Result, UbaaClient};

const SYNTHETIC_USERNAME: &str = "synthetic-interactive-account";
const SYNTHETIC_PAGE: &str = r#"<form id="fm1"><input type="hidden" name="execution" value="synthetic-execution-1"></form><script>config.captcha = { type: 'image', id: 'synthetic-captcha-1' }</script>"#;

#[path = "interactive_auth/flows.rs"]
mod flows;
#[path = "interactive_auth/lifecycle.rs"]
mod lifecycle;

#[derive(Clone)]
struct SyntheticTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

#[async_trait]
impl HttpTransport for SyntheticTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let parsed = url::Url::parse(&request.url).unwrap();
        let body = if parsed.path().ends_with("/captcha") {
            synthetic_image(ImageFormat::Png)
        } else {
            SYNTHETIC_PAGE.as_bytes().to_vec()
        };
        Ok(HttpResponse::new(200, request.url, body))
    }
}

fn synthetic_image(format: ImageFormat) -> Vec<u8> {
    let image = DynamicImage::ImageRgba8(RgbaImage::from_pixel(2, 1, Rgba([17, 83, 149, 255])));
    let mut buffer = Cursor::new(Vec::new());
    image.write_to(&mut buffer, format).unwrap();
    buffer.into_inner()
}

fn test_client() -> (UbaaClient, Arc<Mutex<Vec<HttpRequest>>>, std::path::PathBuf) {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let root = std::env::temp_dir().join(format!(
        "ubaa-interactive-synthetic-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let requests = Arc::new(Mutex::new(Vec::new()));
    let transport = SyntheticTransport {
        requests: requests.clone(),
    };
    let client = UbaaClient::with_transports(
        transport.clone(),
        transport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    (client, requests, root)
}

#[test]
fn old_api_still_rejects_captcha_without_images_or_submissions() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let (mut client, requests, root) = test_client();
            let result = client.prepare_login().await;
            assert!(
                result
                    .routes
                    .iter()
                    .all(|route| route.error.as_ref().unwrap().code == "upstream_changed")
            );
            let sent = requests.lock().unwrap();
            assert_eq!(sent.len(), 2);
            assert!(
                sent.iter()
                    .all(|request| request.url.ends_with("/login") && request.body.is_empty())
            );
            let _ = std::fs::remove_dir_all(root);
        });
}

#[test]
fn interactive_prepare_returns_two_same_route_synthetic_frames() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let (mut client, requests, root) = test_client();
            let result = client
                .prepare_interactive_login(SYNTHETIC_USERNAME.into())
                .await
                .expect("来源支持的 image 页面必须返回专用挑战");
            for (index, route) in [ConnectionMode::Direct, ConnectionMode::WebVpn]
                .into_iter()
                .enumerate()
            {
                assert_eq!(result.routes[index].route, route);
                assert_eq!(
                    result.routes[index].state,
                    InteractiveRouteState::CaptchaRequired
                );
                let frame = result.routes[index]
                    .frame
                    .as_ref()
                    .expect("合成有效 PNG 必须解码");
                assert_eq!((frame.width, frame.height), (2, 1));
                assert_eq!(frame.rgba, [17, 83, 149, 255, 17, 83, 149, 255]);
            }
            let sent = requests.lock().unwrap();
            assert_eq!(sent.len(), 4);
            assert_eq!(
                sent[1].url,
                "https://sso.buaa.edu.cn/captcha?captchaId=synthetic-captcha-1"
            );
            assert!(sent[3].url.starts_with("https://d.buaa.edu.cn/https/"));
            assert!(
                sent[3]
                    .url
                    .ends_with("/captcha?captchaId=synthetic-captcha-1")
            );
            let _ = std::fs::remove_dir_all(root);
        });
}
