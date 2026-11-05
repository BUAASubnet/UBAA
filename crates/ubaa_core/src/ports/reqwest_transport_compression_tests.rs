//! 压缩响应必须保持解析输入和解压后的正文上限。
use super::{HttpMethod, HttpRequest, HttpTransport, MAX_RESPONSE_BODY_BYTES, ReqwestTransport};
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

fn read_at(
    body: Vec<u8>,
    host: &str,
    path: &str,
    method: HttpMethod,
) -> crate::error::Result<super::HttpResponse> {
    let (local_url, server) = serve(body);
    let local_url = url::Url::parse(&local_url).unwrap();
    let address = local_url.socket_addrs(|| None).unwrap()[0];
    let client = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .gzip(true)
        .resolve(host, address)
        .build()
        .unwrap();
    let transport = ReqwestTransport {
        object_client: client.clone(),
        client,
    };
    let mut request = HttpRequest::get(format!("http://{host}:{}{path}", address.port()));
    request.method = method;
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime.block_on(transport.execute(request));
    server.join().unwrap();
    result
}

fn code_detail(bytes: usize) -> Vec<u8> {
    let mut body = b"<html><body><pre>".to_vec();
    body.resize(bytes - b"</pre></body></html>".len(), b'x');
    body.extend_from_slice(b"</pre></body></html>");
    body
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
fn 希冀详情允许超过通用上限的大段代码正文() {
    let body = code_detail(10_875_793);
    assert!(body.len() > MAX_RESPONSE_BODY_BYTES);
    let response = read_at(
        gzip(&body),
        "judge.buaa.edu.cn",
        "/assignment/index.jsp?assignID=101",
        HttpMethod::Get,
    )
    .expect("受支持的作业详情必须完整交付");
    assert!(response.body == body);
}

#[test]
fn 希冀详情仍拒绝解压后超过独立预算的正文() {
    let error = read_at(
        gzip(&code_detail(16 * 1024 * 1024 + 1)),
        "judge.buaa.edu.cn",
        "/assignment/index.jsp?assignID=101",
        HttpMethod::Get,
    )
    .expect_err("独立详情预算仍须在解压过程中执行");
    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    assert_eq!(error.message, "上游响应体超过允许大小");
}

#[test]
fn 普通响应和希冀索引及非读取请求保留通用正文上限() {
    let body = gzip(&code_detail(MAX_RESPONSE_BODY_BYTES + 1));
    for (host, path, method) in [
        ("uc.buaa.edu.cn", "/api/uc/status", HttpMethod::Get),
        (
            "judge.buaa.edu.cn",
            "/assignment/index.jsp",
            HttpMethod::Get,
        ),
        (
            "judge.buaa.edu.cn",
            "/assignment/index.jsp?assignID=101",
            HttpMethod::Post,
        ),
    ] {
        let error =
            read_at(body.clone(), host, path, method).expect_err("其余操作继续使用通用正文预算");
        assert_eq!(error.code, ErrorCode::UpstreamChanged);
        assert_eq!(error.message, "上游响应体超过允许大小");
    }
}

#[test]
fn 两条路线只为希冀作业详情选择独立正文预算() {
    for (method, direct_url, expected) in [
        (
            HttpMethod::Get,
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101",
            16 * 1024 * 1024,
        ),
        (
            HttpMethod::Get,
            "https://judge.buaa.edu.cn/assignment/index.jsp",
            MAX_RESPONSE_BODY_BYTES,
        ),
        (
            HttpMethod::Get,
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=101",
            MAX_RESPONSE_BODY_BYTES,
        ),
        (
            HttpMethod::Get,
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=",
            MAX_RESPONSE_BODY_BYTES,
        ),
        (
            HttpMethod::Get,
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=abc",
            MAX_RESPONSE_BODY_BYTES,
        ),
        (
            HttpMethod::Get,
            "https://uc.buaa.edu.cn/assignment/index.jsp?assignID=101",
            MAX_RESPONSE_BODY_BYTES,
        ),
        (
            HttpMethod::Post,
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101",
            MAX_RESPONSE_BODY_BYTES,
        ),
    ] {
        for url in [
            direct_url.to_owned(),
            crate::connection::to_webvpn_url(direct_url).unwrap(),
        ] {
            assert_eq!(super::response_body_limit(method, &url), expected);
        }
    }
}

#[test]
fn 损坏gzip不作为成功业务正文交付() {
    let mut compressed = gzip(b"fixture");
    compressed.truncate(compressed.len() - 6);
    let (result, _, _) = read(compressed);
    assert_eq!(result.unwrap_err().code, ErrorCode::NetworkError);
}
