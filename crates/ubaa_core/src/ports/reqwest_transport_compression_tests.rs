//! 压缩响应必须保持解析输入和解压后的正文上限。
use super::{HttpRequest, HttpTransport, MAX_RESPONSE_BODY_BYTES, ReqwestTransport};
use crate::error::ErrorCode;
use std::io::{Read, Write};
use std::net::TcpListener;

fn gzip(body: &[u8]) -> Vec<u8> {
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    encoder.write_all(body).unwrap();
    encoder.finish().unwrap()
}

fn serve(body: Vec<u8>) -> (String, std::thread::JoinHandle<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/fixture", listener.local_addr().unwrap());
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = Vec::new();
        let mut buffer = [0; 4096];
        while !request.windows(4).any(|part| part == b"\r\n\r\n") {
            let count = stream.read(&mut buffer).unwrap();
            assert_ne!(count, 0);
            request.extend_from_slice(&buffer[..count]);
        }
        write!(
            stream,
            "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: {}\r\nSet-Cookie: fixture=a; Path=/\r\nSet-Cookie: second=b; Path=/\r\nConnection: close\r\n\r\n",
            body.len(),
        )
        .unwrap();
        // 超限接收端可能提前关闭连接。
        let _ = stream.write_all(&body);
        String::from_utf8(request).unwrap()
    });
    (url, server)
}

fn read(body: Vec<u8>) -> (crate::error::Result<super::HttpResponse>, String, String) {
    let (url, server) = serve(body);
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime.block_on(
        ReqwestTransport::new()
            .unwrap()
            .execute(HttpRequest::get(&url)),
    );
    (result, server.join().unwrap(), url)
}

#[test]
fn gzip正文解压后保留地址状态及多值会话头() {
    let body = "<html>合成作业详情与成绩</html>".as_bytes();
    let (result, request, url) = read(gzip(body));
    let response = result.unwrap();
    assert_eq!(response.body, body);
    assert_eq!(response.status, 200);
    assert_eq!(response.final_url, url);
    assert_eq!(response.headers["set-cookie"].len(), 2);
    assert!(
        request
            .to_ascii_lowercase()
            .contains("accept-encoding: gzip")
    );
    assert!(!response.headers.contains_key("content-encoding"));
    assert!(!response.headers.contains_key("content-length"));
}

#[test]
fn gzip压缩体很小时仍拒绝解压后超限的正文() {
    let compressed = gzip(&vec![b'x'; MAX_RESPONSE_BODY_BYTES + 1]);
    assert!(compressed.len() < MAX_RESPONSE_BODY_BYTES);
    let (result, _, _) = read(compressed);
    let error = result.expect_err("压缩不能绕过正文上限");
    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    assert_eq!(error.message, "上游响应体超过允许大小");
}

#[test]
fn 损坏gzip不作为成功业务正文交付() {
    let mut compressed = gzip(b"fixture");
    compressed.truncate(compressed.len() - 6);
    let (result, _, _) = read(compressed);
    assert_eq!(result.unwrap_err().code, ErrorCode::NetworkError);
}
