use std::sync::{Arc, Mutex};
use tracing::{
    Event, Metadata, Subscriber,
    field::{Field, Visit},
    span::{Attributes, Id, Record},
};
#[derive(Default)]
struct Capture(Arc<Mutex<Vec<String>>>);
impl Visit for Capture {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        self.0
            .lock()
            .unwrap()
            .push(format!("{}={value:?}", field.name()));
    }
}
impl Subscriber for Capture {
    fn enabled(&self, _: &Metadata<'_>) -> bool {
        true
    }
    fn new_span(&self, _: &Attributes<'_>) -> Id {
        Id::from_u64(1)
    }
    fn record(&self, _: &Id, _: &Record<'_>) {}
    fn record_follows_from(&self, _: &Id, _: &Id) {}
    fn event(&self, event: &Event<'_>) {
        event.record(&mut Capture(self.0.clone()));
    }
    fn enter(&self, _: &Id) {}
    fn exit(&self, _: &Id) {}
}
#[test]
fn 门锁响应不记录整包指纹或低熵密码() {
    let root = std::env::temp_dir().join(format!("ubaa-lock-log-{}", std::process::id()));
    let runtime = crate::runtime::ClientRuntime::new(
        crate::domain::ConnectionMode::WebVpn,
        super::tests::NoNetworkTransport,
        crate::session::FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let response = crate::ports::HttpResponse::new(
        200,
        "https://cgyy.buaa.edu.cn/venue-zhjs-server/api/orders/lock/code",
        br#"{"code":200,"data":{"qrCode":"001234"}}"#.to_vec(),
    );
    let capture = Capture::default();
    let events = capture.0.clone();
    tracing::subscriber::with_default(capture, || {
        super::http::log_response(&runtime, "orders.lock_code", &response);
    });
    let rendered = events.lock().unwrap().join(" ");
    assert!(rendered.contains("status"));
    assert!(!rendered.contains("body_sha1"));
    assert!(!rendered.contains("001234"));
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 登录订单与写入响应日志不派生敏感正文摘要() {
    use sha1::{Digest, Sha1};

    let root = std::env::temp_dir().join(format!("ubaa-sensitive-log-{}", std::process::id()));
    let runtime = crate::runtime::ClientRuntime::new(
        crate::domain::ConnectionMode::Direct,
        super::tests::NoNetworkTransport,
        crate::session::FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    for operation in [
        "business_login.api",
        "orders.list",
        "orders.detail_or_cancel",
        "orders.cancel",
        "reservation.submit",
    ] {
        let body =
            br#"{"code":200,"data":{"access_token":"synthetic-secret","phone":"synthetic-phone"}}"#;
        let digest = format!("{:x}", Sha1::digest(body));
        let response = crate::ports::HttpResponse::new(
            200,
            "https://cgyy.buaa.edu.cn/venue-zhjs-server/api/login",
            body.to_vec(),
        );
        let capture = Capture::default();
        let events = capture.0.clone();
        tracing::subscriber::with_default(capture, || {
            super::http::log_response(&runtime, operation, &response);
        });
        let rendered = events.lock().unwrap().join(" ");
        assert!(rendered.contains("status"), "{operation} 缺少安全状态");
        assert!(!rendered.contains("synthetic-secret"));
        assert!(!rendered.contains("synthetic-phone"));
        assert!(
            !rendered.contains(&digest),
            "{operation} 泄露了敏感正文摘要"
        );
    }
    let _ = std::fs::remove_dir_all(root);
}
