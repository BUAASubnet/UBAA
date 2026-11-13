use super::ReqwestTransport;
use crate::error::Result;
use crate::ports::{HttpFileRange, HttpRequest, HttpTransferObserver, HttpTransport};
use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
};

#[derive(Default)]
struct Progress {
    bytes: AtomicU64,
    largest: AtomicU64,
}
impl HttpTransferObserver for Progress {
    fn check(&self) -> Result<()> {
        Ok(())
    }
    fn advance(&self, bytes: u64) {
        self.bytes.fetch_add(bytes, Ordering::SeqCst);
        self.largest.fetch_max(bytes, Ordering::SeqCst);
    }
}
fn transport() -> ReqwestTransport {
    ReqwestTransport {
        fast_connect_client: reqwest::Client::builder().no_proxy().build().unwrap(),
        client: reqwest::Client::builder().no_proxy().build().unwrap(),
        object_client: reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .gzip(false)
            .build()
            .unwrap(),
    }
}
fn directory() -> std::path::PathBuf {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/integration/port_tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&path).unwrap();
    path
}
#[tokio::test]
async fn 对象上传流式读取指定区间且只发一个长度头() {
    let root = directory();
    let path = root.join("source");
    let bytes = vec![b'x'; 200_003];
    std::fs::write(&path, &bytes).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut data = Vec::new();
        let mut buffer = vec![0; 64 * 1024];
        loop {
            let size = stream.read(&mut buffer).unwrap();
            assert!(size > 0);
            data.extend_from_slice(&buffer[..size]);
            if let Some(end) = data
                .windows(4)
                .position(|w| w == b"\r\n\r\n")
                .map(|i| i + 4)
                && data.len() >= end + 200_000
            {
                break;
            }
        }
        stream
            .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            .unwrap();
        data
    });
    let mut request = HttpRequest::get(format!("http://{address}/object"));
    request.method = super::HttpMethod::Put;
    request = request
        .with_header("content-length", "200000")
        .with_header("Authorization", "object-only");
    let progress = Arc::new(Progress::default());
    let response = transport()
        .upload(
            request,
            Some(HttpFileRange {
                file: std::fs::File::open(&path).unwrap(),
                offset: 3,
                length: 200_000,
            }),
            progress.clone(),
        )
        .await
        .unwrap();
    assert_eq!(response.status, 200);
    let data = server.join().unwrap();
    let end = data.windows(4).position(|w| w == b"\r\n\r\n").unwrap() + 4;
    let headers = String::from_utf8_lossy(&data[..end]).to_ascii_lowercase();
    assert_eq!(headers.matches("content-length:").count(), 1);
    assert!(headers.contains("authorization: object-only\r\n"));
    assert!(!headers.contains("cookie:"));
    assert_eq!(&data[end..], &bytes[3..]);
    assert_eq!(progress.bytes.load(Ordering::SeqCst), 200_000);
    assert!(progress.largest.load(Ordering::SeqCst) <= 64 * 1024);
    std::fs::remove_dir_all(root).unwrap();
}
#[tokio::test]
async fn 对象下载大于通用响应上限仍有界写文件且不进入响应正文() {
    const SIZE: usize = 8 * 1024 * 1024 + 17;
    let root = directory();
    let path = root.join("download");
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = [0; 4096];
        let _ = stream.read(&mut request).unwrap();
        write!(
            stream,
            "HTTP/1.1 200 OK\r\nContent-Length: {SIZE}\r\nConnection: close\r\n\r\n"
        )
        .unwrap();
        let buffer = vec![b'd'; 64 * 1024];
        let mut left = SIZE;
        while left > 0 {
            let length = left.min(buffer.len());
            stream.write_all(&buffer[..length]).unwrap();
            left -= length;
        }
    });
    let progress = Arc::new(Progress::default());
    let response = transport()
        .download(
            HttpRequest::get(format!("http://{address}/download")),
            std::fs::File::create(&path).unwrap(),
            progress.clone(),
        )
        .await
        .unwrap();
    server.join().unwrap();
    assert_eq!(response.body.len(), 0);
    assert_eq!(std::fs::metadata(&path).unwrap().len(), SIZE as u64);
    assert_eq!(progress.bytes.load(Ordering::SeqCst), SIZE as u64);
    assert!(progress.largest.load(Ordering::SeqCst) <= 64 * 1024);
    let mut file = std::fs::File::open(path).unwrap();
    let mut buffer = vec![0; 64 * 1024];
    loop {
        let size = file.read(&mut buffer).unwrap();
        if size == 0 {
            break;
        }
        assert!(buffer[..size].iter().all(|byte| *byte == b'd'));
    }
    drop(file);
    std::fs::remove_dir_all(root).unwrap();
}
