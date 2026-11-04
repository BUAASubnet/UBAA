use super::tests::{NeverProbe, Script};
use super::*;
use crate::{
    domain::{
        RoutePolicy,
        bhpan::{BhpanItem, BhpanItemKind, BhpanTransferPhase},
    },
    facade::testing::{FileSessionStore, RouteConfig},
    ports::{HttpFileRange, HttpRequest, HttpResponse, HttpTransferObserver, HttpTransport},
};
use serde_json::json;
use std::{
    collections::VecDeque,
    io::{Read, Seek, Write},
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};
mod download;
mod upload;

const OBJECT: &str = "https://dynamic.synthetic.invalid/object?signature=synthetic-secret";
#[derive(Clone)]
struct ObjectStep {
    status: u16,
    etag: Option<String>,
    bytes: Vec<u8>,
    length: Option<u64>,
}
impl ObjectStep {
    fn ok(length: u64) -> Self {
        Self {
            status: 200,
            etag: Some("\"part-etag\"".into()),
            bytes: vec![],
            length: Some(length),
        }
    }
}
#[derive(Clone, Default)]
struct Transport {
    script: Script,
    objects: Arc<Mutex<VecDeque<ObjectStep>>>,
    object_calls: Arc<AtomicUsize>,
    stop: Arc<Mutex<Option<BhpanTransfer>>>,
    change_file: Arc<Mutex<Option<PathBuf>>>,
    business_calls: Arc<AtomicUsize>,
    business_gate: Option<Arc<tokio::sync::Notify>>,
    skip_upload_body: bool,
}
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.business_calls.fetch_add(1, Ordering::SeqCst);
        let response = self.script.execute(request).await;
        if let Some(gate) = &self.business_gate {
            gate.notified().await;
        }
        response
    }
    async fn upload(
        &self,
        request: HttpRequest,
        source: Option<HttpFileRange>,
        observer: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.object_calls.fetch_add(1, Ordering::SeqCst);
        assert_eq!(request.url, OBJECT);
        assert!(
            request
                .headers
                .keys()
                .all(|key| !key.eq_ignore_ascii_case("cookie"))
        );
        assert_eq!(
            request.headers.get("authorization").map(String::as_str),
            Some("object-only")
        );
        let step = self
            .objects
            .lock()
            .unwrap()
            .pop_front()
            .expect("未安排对象请求");
        if let Some(mut source) = source.filter(|_| !self.skip_upload_body) {
            assert_eq!(Some(source.length), step.length);
            assert_eq!(request.method, HttpMethod::Put);
            source
                .file
                .seek(std::io::SeekFrom::Start(source.offset))
                .unwrap();
            let mut remaining = source.length;
            let mut buffer = vec![0u8; 64 * 1024];
            while remaining > 0 {
                observer.check()?;
                let n = usize::try_from(remaining.min(buffer.len() as u64)).unwrap();
                source.file.read_exact(&mut buffer[..n]).unwrap();
                observer.advance(n as u64);
                remaining -= n as u64;
            }
        } else if !self.skip_upload_body {
            assert_eq!(request.method, HttpMethod::Post);
            assert!(request.body.starts_with(b"<Complete"));
        }
        if let Some(transfer) = self.stop.lock().unwrap().take() {
            transfer.cancel();
            observer.check()?;
        }
        if let Some(path) = self.change_file.lock().unwrap().take() {
            std::fs::OpenOptions::new()
                .append(true)
                .open(path)
                .unwrap()
                .write_all(b"changed")
                .unwrap();
        }
        let mut response = HttpResponse::new(step.status, request.url, step.bytes);
        if let Some(etag) = step.etag {
            response.headers.insert("ETag".into(), vec![etag]);
        }
        Ok(response)
    }
    async fn download(
        &self,
        request: HttpRequest,
        mut destination: std::fs::File,
        observer: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.object_calls.fetch_add(1, Ordering::SeqCst);
        assert_eq!(request.url, OBJECT);
        assert_eq!(request.method, HttpMethod::Get);
        let step = self
            .objects
            .lock()
            .unwrap()
            .pop_front()
            .expect("未安排对象下载");
        if step.length == Some(0) {
            assert!(request.headers.is_empty());
        } else {
            assert_eq!(request.headers.len(), 1);
            assert_eq!(request.headers["authorization"], "object-only");
        }
        if step.status == 200 {
            observer.set_total(step.bytes.len() as u64);
            for block in step.bytes.chunks(64 * 1024) {
                observer.check()?;
                destination.write_all(block).unwrap();
                observer.advance(block.len() as u64);
                if let Some(transfer) = self.stop.lock().unwrap().take() {
                    transfer.cancel();
                }
                observer.check()?;
            }
        }
        Ok(HttpResponse::new(step.status, request.url, vec![]))
    }
}
struct Fixture {
    client: UbaaClient,
    transport: Transport,
    root: PathBuf,
    parent: BhpanItem,
}
impl Fixture {
    fn new() -> Self {
        let transport = Transport::default();
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/bhpan_delivery/integration/transfer_tests")
            .join(uuid::Uuid::new_v4().to_string());
        let mut config = RouteConfig::default();
        config.replace_default_policy(RoutePolicy::Direct);
        let mut client = UbaaClient::with_routing(
            transport.clone(),
            transport.clone(),
            FileSessionStore::new(&root).unwrap(),
            config,
            NeverProbe,
        )
        .unwrap();
        client
            .direct_runtime
            .refresh_authentication(&mut || {})
            .unwrap();
        client.bhpan.binding = Some(client.bhpan_binding());
        client.bhpan.token = Some(SecretValue::new("personal-fixture"));
        let parent = super::tests::item(&mut client, BhpanScope::Personal);
        Self {
            client,
            transport,
            root,
            parent,
        }
    }
    fn source(&self, length: u64) -> PathBuf {
        let path = self.root.join("upload.fixture");
        std::fs::File::create(&path)
            .unwrap()
            .set_len(length)
            .unwrap();
        path
    }
    fn begin(&self, length: u64) {
        self.transport.script.add(HttpMethod::Post,"/api/efast/v1/file/osbeginupload",Some(json!({"docid":"gns://fixture/target","length":length,"name":"notes.txt","ondup":1})),serde_json::to_vec(&json!({"docid":"gns://fixture/created","rev":"upload-revision","authrequest":["PUT",OBJECT,"Authorization: object-only"]})).unwrap().as_slice());
    }
    fn end(&self, response: &[u8]) {
        self.transport.script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/osendupload",
            Some(json!({"docid":"gns://fixture/created","rev":"upload-revision"})),
            response,
        );
    }
    fn file(&mut self, length: u64) -> BhpanItem {
        let mut authority = self.client.bhpan.item(&self.parent.handle).unwrap();
        authority.item.kind = BhpanItemKind::File;
        authority.item.bytes = Some(length);
        authority.item.id = "gns://fixture/file".into();
        self.client.bhpan.publish(authority)
    }
    fn download_auth(&self, bytes: Vec<u8>) {
        self.transport.script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/osdownload",
            Some(json!({"docid":"gns://fixture/file","authtype":"QUERY_STRING"})),
            serde_json::to_vec(&json!({"authrequest":["GET",OBJECT,"Authorization: object-only"]}))
                .unwrap()
                .as_slice(),
        );
        self.transport
            .objects
            .lock()
            .unwrap()
            .push_back(ObjectStep {
                status: 200,
                etag: None,
                length: None,
                bytes,
            });
    }
    fn finish(self) {
        self.transport.script.done();
        assert!(self.transport.objects.lock().unwrap().is_empty());
        let root = self.root.clone();
        drop(self);
        std::fs::remove_dir_all(root).unwrap();
    }
}
mod versions;
