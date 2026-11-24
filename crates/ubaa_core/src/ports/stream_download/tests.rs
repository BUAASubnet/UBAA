use super::*;
use futures_util::{StreamExt, stream};

fn head(length: Option<u64>) -> HttpResponse {
    let mut head = HttpResponse::new(200, "https://example.test/", vec![]);
    if let Some(length) = length {
        head.headers
            .insert("Content-Length".into(), vec![length.to_string()]);
    }
    head
}

#[tokio::test]
async fn 长度超限截断与取消均保留原文件并删除临时文件() {
    let root = crate::test_tmp::test_temp_dir("spoc_stream").unwrap();
    let dest = root.join("chosen");
    std::fs::write(&dest, b"original").unwrap();
    for (length, chunks) in [
        (Some(5), vec![]),
        (None, vec![b"abc".as_slice(), b"de"]),
        (Some(4), vec![b"abc".as_slice()]),
    ] {
        let mut sink = StreamSink::new(&dest, 4).unwrap();
        assert!(
            sink.receive(head(length), stream::iter(chunks.into_iter().map(Ok)))
                .await
                .is_err()
        );
        assert_eq!(std::fs::read(&dest).unwrap(), b"original");
        assert_eq!(root.read_dir().unwrap().count(), 1);
    }
    let mut sink = StreamSink::new(&dest, 4).unwrap();
    let (sent, waiting) = tokio::sync::oneshot::channel();
    let chunks = stream::iter([Ok(b"abc".as_slice())]).chain(stream::once(async move {
        sent.send(()).unwrap();
        std::future::pending().await
    }));
    let mut future = Box::pin(sink.receive(head(None), chunks));
    tokio::select! {_ = waiting=>{},_ = &mut future=>panic!("应等待下一块")};
    assert_eq!(root.read_dir().unwrap().count(), 2);
    drop(future);
    assert_eq!(root.read_dir().unwrap().count(), 1);
    assert_eq!(std::fs::read(&dest).unwrap(), b"original");
}

#[tokio::test]
async fn 分类返回有界正文不写文件() {
    let root = crate::test_tmp::test_temp_dir("spoc_stream_body").unwrap();
    let dest = root.join("chosen");
    for (status, kind) in [
        (302, ""),
        (403, "application/octet-stream"),
        (200, "APPLICATION/JSON"),
        (200, "text/html;charset=UTF-8"),
        (200, "text/plain"),
    ] {
        let mut head = head(None);
        head.status = status;
        head.headers
            .insert("Content-Type".into(), vec![kind.into()]);
        let mut sink = StreamSink::new(&dest, 2).unwrap();
        let head = sink
            .receive(head, stream::iter([Ok(vec![1; BODY_LIMIT]), Ok(vec![2])]))
            .await
            .unwrap();
        let StreamDownload::Body {
            response,
            truncated,
        } = sink.deliver(head).unwrap()
        else {
            panic!("应返回正文")
        };
        assert!(truncated);
        assert_eq!(response.body.len(), BODY_LIMIT);
        assert!(!dest.exists());
    }
}
