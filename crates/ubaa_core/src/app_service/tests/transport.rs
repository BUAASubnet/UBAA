use super::AppServiceTransport;
use crate::{
    app_service::{AppServiceConfig, Platform},
    error::ErrorCode,
    ports::{HttpRequest, HttpTransport},
};
use std::{net::Ipv4Addr, time::Duration};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    time::timeout,
};
use url::Url;

const IO_BUDGET: Duration = Duration::from_secs(3);

fn request(url: &Url) -> HttpRequest {
    HttpRequest::post(url.as_str(), b"{}".to_vec()).with_header("content-type", "application/json")
}

async fn capture_http(listener: &TcpListener, response: &str) -> String {
    let (mut stream, _) = listener.accept().await.unwrap();
    let mut request = Vec::new();
    while !request.ends_with(b"\r\n\r\n{}") {
        assert!(stream.read_buf(&mut request).await.unwrap() > 0);
    }
    stream.write_all(response.as_bytes()).await.unwrap();
    String::from_utf8(request).unwrap()
}

#[tokio::test]
async fn 不跟随跨主机跳转也不重用服务端设置的_cookie() {
    let source = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
    let target = std::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    target.set_nonblocking(true).unwrap();
    let source_url = Url::parse(&format!(
        "http://{}/v1/telemetry",
        source.local_addr().unwrap()
    ))
    .unwrap();
    let target_url = Url::parse(&format!(
        "http://localhost:{}/v1/telemetry",
        target.local_addr().unwrap().port()
    ))
    .unwrap();
    let transport = AppServiceTransport::new(&source_url).unwrap();
    let redirect = format!(
        "HTTP/1.1 307 Temporary Redirect\r\nLocation: {target_url}\r\nSet-Cookie: sample=1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    );
    let (result, received) = timeout(IO_BUDGET, async {
        tokio::join!(
            transport.execute(request(&source_url)),
            capture_http(&source, &redirect)
        )
    })
    .await
    .unwrap();
    assert_eq!(result.unwrap().status, 307);

    let (second, received_again) = timeout(IO_BUDGET, async {
        tokio::join!(
            transport.execute(request(&source_url)),
            capture_http(
                &source,
                "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
            )
        )
    })
    .await
    .unwrap();
    assert_eq!(second.unwrap().status, 204);
    for captured in [received, received_again] {
        let headers = captured.to_ascii_lowercase();
        assert!(headers.starts_with("post /v1/telemetry http/1.1\r\n"));
        assert!(headers.contains("\r\ncontent-type: application/json\r\n"));
        assert!(!headers.contains("\r\ncookie:"));
        assert!(!headers.contains("\r\nauthorization:"));
    }
    assert_eq!(
        transport
            .execute(request(&target_url))
            .await
            .unwrap_err()
            .code,
        ErrorCode::InvalidInput
    );
    assert!(
        matches!(target.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
    );
}

#[tokio::test]
async fn 回环_https_执行握手而不向明文监听器交付正文() {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
    let address = listener.local_addr().unwrap();
    let endpoint = format!("https://localhost:{}", address.port());
    let make_config = |release| {
        AppServiceConfig::from_build(
            Some(&endpoint),
            Some("github"),
            Some("2.0.0"),
            Platform::Macos,
            release,
        )
    };
    assert!(make_config(true).available().is_none());
    let config = make_config(false);
    let url = &config.available().unwrap().url;
    let transport = AppServiceTransport::new(url).unwrap();
    let (result, ()) = timeout(IO_BUDGET, async {
        tokio::join!(transport.execute(request(url)), async {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut tls_header = [0_u8; 3];
            stream.read_exact(&mut tls_header).await.unwrap();
            assert_eq!(tls_header[..2], [0x16, 0x03]);
        })
    })
    .await
    .unwrap();
    assert_eq!(result.unwrap_err().code, ErrorCode::NetworkError);
}
