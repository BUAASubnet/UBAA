use ubaa_command::{CommandClass, parse};

#[test]
fn 云盘命令由唯一命令树分派且写操作不进入只读重跑器() {
    for arguments in [
        vec!["list"],
        vec!["stat", "/notes.txt"],
        vec!["share", "history"],
        vec!["download-prepare", "/notes.txt"],
    ] {
        let mut argv = vec!["ubaa", "bhpan"];
        argv.extend(arguments);
        assert_eq!(
            parse(argv).unwrap().requirements().class,
            CommandClass::Readonly
        );
    }
    let plan = parse(["ubaa", "bhpan", "mkdir", "/", "notes", "--confirm-write"]).unwrap();
    assert_eq!(plan.requirements().class, CommandClass::SchoolWrite);
}

use serde_json::{Value, json};
use std::{
    io::Cursor,
    sync::{Arc, Mutex},
};
use ubaa_command::{CommandControl, execute_attempt, prepare_input};
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot,
};
use ubaa_core::facade::{ErrorCode, ErrorKind, NetworkState, UbaaClient, UbaaError};
struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不探测")
    }
}
#[derive(Clone, Default)]
struct Transport {
    calls: Arc<Mutex<Vec<HttpRequest>>>,
    duplicate: bool,
    lost: bool,
}
#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn upload(
        &self,
        request: HttpRequest,
        source: Option<ubaa_core::facade::testing::HttpFileRange>,
        observer: Arc<dyn ubaa_core::facade::testing::HttpTransferObserver>,
    ) -> ubaa_core::facade::Result<HttpResponse> {
        use std::io::{Read, Seek};
        assert!(!request.headers.contains_key("Cookie"));
        assert_eq!(
            request.headers.get("authorization").map(String::as_str),
            Some("object-only")
        );
        self.calls.lock().unwrap().push(request.clone());
        if let Some(mut source) = source {
            source
                .file
                .seek(std::io::SeekFrom::Start(source.offset))
                .unwrap();
            let mut remaining = source.length;
            let mut buffer = vec![0; 64 * 1024];
            while remaining > 0 {
                observer.check()?;
                let length = usize::try_from(remaining.min(buffer.len() as u64)).unwrap();
                source.file.read_exact(&mut buffer[..length]).unwrap();
                observer.advance(length as u64);
                remaining -= length as u64;
            }
        }
        Ok(HttpResponse::new(200, request.url, vec![]))
    }
    async fn download(
        &self,
        request: HttpRequest,
        mut destination: std::fs::File,
        observer: Arc<dyn ubaa_core::facade::testing::HttpTransferObserver>,
    ) -> ubaa_core::facade::Result<HttpResponse> {
        use std::io::Write;
        assert!(!request.headers.contains_key("Cookie"));
        assert!(
            request.headers.is_empty()
                || request
                    .headers
                    .values()
                    .all(|value| value != "Bearer synthetic")
        );
        self.calls.lock().unwrap().push(request.clone());
        observer.check()?;
        destination.write_all(b"hello").unwrap();
        observer.advance(5);
        Ok(HttpResponse::new(200, request.url, vec![]))
    }
    async fn execute(&self, r: HttpRequest) -> ubaa_core::facade::Result<HttpResponse> {
        let url = r.url.clone();
        self.calls.lock().unwrap().push(r.clone());
        let mut response = HttpResponse::new(200, url.clone(), vec![]);
        if url.contains("/oauth2/login?") {
            response.status = 302;
            response.headers.insert(
                "Location".into(),
                vec!["/anyshare/oauth2/login/callback".into()],
            );
        } else if url.ends_with("/anyshare/oauth2/login/callback") {
        } else if url.ends_with("/refreshToken") {
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["client.oauth2_token=synthetic; Path=/; Secure".into()],
            );
        } else if url.ends_with("/owned-doc-lib") || url.contains("/entry-doc-lib?") {
            response.body = br#"[{"id":"gns://fixture/root","name":"root"}]"#.to_vec();
        } else if url.ends_with("/dir/list") || url.ends_with("/recycle/list") {
            let file =
                json!({"docid":"gns://fixture/file","name":"notes.txt","size":5,"modified":0});
            response.body=serde_json::to_vec(&json!({"dirs":[{"docid":"gns://fixture/docs","name":"docs","size":-1,"modified":0}],"files":if self.duplicate {vec![file.clone(),file]}else{vec![file]}})).unwrap();
        } else if url.ends_with("/getsize") {
            response.body = br#"{"dirnum":0,"filenum":1,"totalsize":5}"#.to_vec();
        } else if url.ends_with("/getsuggestname") {
            response.body = br#"{"name":"new (1).txt"}"#.to_vec();
        } else if url.ends_with("/osdownload") {
            response.body=br#"{"authrequest":["GET","https://object.synthetic.invalid/file?signature=private","Authorization: private"]}"#.to_vec();
        } else if url.ends_with("/osbeginupload") {
            response.body=br#"{"docid":"gns://fixture/uploaded","rev":"u","authrequest":["PUT","https://object.synthetic.invalid/upload?signature=private","Authorization: object-only"]}"#.to_vec();
        } else if url.ends_with("/osendupload") {
            response.body = b"{}".to_vec();
        } else if url.ends_with("/file/delete") {
            assert_eq!(
                serde_json::from_slice::<Value>(&r.body).unwrap(),
                json!({"docid":"gns://fixture/file"})
            );
            if self.lost {
                return Err(UbaaError::new(
                    ErrorCode::NetworkError,
                    ErrorKind::Network,
                    true,
                    "合成响应丢失",
                ));
            }
        } else {
            panic!("未安排的合成请求：{url}");
        }
        Ok(response)
    }
}
struct Fixture {
    root: std::path::PathBuf,
    client: UbaaClient,
    transport: Transport,
}
impl Fixture {
    fn new(transport: Transport, route: &str) -> Self {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/bhpan_delivery/integration/command_tests")
            .join(uuid::Uuid::new_v4().to_string());
        let store = FileSessionStore::new(&root).unwrap();
        let session = RouteSessionSnapshot {
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1001,
        };
        store
            .save_dual(&DualSessionSnapshot::new(
                Some(session.clone()),
                Some(session),
            ))
            .unwrap();
        let client = UbaaClient::with_routing(
            transport.clone(),
            transport.clone(),
            store,
            RouteConfig::parse(&format!("[route]\ndefault = \"{route}\"\n")).unwrap(),
            NeverProbe,
        )
        .unwrap();
        Self {
            root,
            client,
            transport,
        }
    }
    async fn run(&mut self, arguments: &[&str]) -> (i32, Value) {
        let mut argv = vec!["ubaa", "--json", "bhpan"];
        argv.extend(arguments);
        let control = CommandControl::default();
        let prepared = prepare_input(parse(argv).unwrap(), &mut Cursor::new([]), &control).unwrap();
        let result = execute_attempt(&prepared, &mut self.client, &control)
            .await
            .into_result();
        let (mut out, mut err) = (vec![], vec![]);
        let code = result.render(&control, &mut out, &mut err);
        let value: Value = serde_json::from_slice(&out).unwrap();
        let schema: Value =
            serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json"))
                .unwrap();
        jsonschema::validator_for(&schema)
            .unwrap()
            .validate(&value)
            .unwrap();
        (code, value)
    }
    fn finish(self) {
        let root = self.root.clone();
        drop(self);
        std::fs::remove_dir_all(root).unwrap();
    }
}
#[tokio::test]
async fn 云盘列表与写入只使用本次读取目标并保持公共信封() {
    let mut fixture = Fixture::new(Transport::default(), "direct");
    let (code, value) = fixture.run(&["list"]).await;
    assert_eq!(code, 0);
    assert_eq!(value["meta"]["feature"], "bhpan");
    assert_eq!(value["data"]["items"][1]["locator"], "gns://fixture/file");
    assert!(value["data"]["items"][1].get("handle").is_none());
    assert_eq!(
        fixture
            .run(&["delete", "/notes.txt", "--confirm-write"])
            .await
            .0,
        0
    );
    let calls = fixture.transport.calls.lock().unwrap();
    let write = calls
        .iter()
        .position(|r| r.url.ends_with("/file/delete"))
        .unwrap();
    assert!(calls[..write].iter().any(|r| r.url.ends_with("/dir/list")));
    assert!(
        calls
            .iter()
            .filter(|r| r.url.contains("/api/efast/"))
            .all(|r| !r.headers.contains_key("Cookie"))
    );
    drop(calls);
    fixture.finish();
}
#[tokio::test]
async fn 云盘同名歧义与未支持路线在写入或恢复业务网络前拒绝() {
    let mut duplicate = Fixture::new(
        Transport {
            duplicate: true,
            ..Transport::default()
        },
        "direct",
    );
    assert_eq!(
        duplicate
            .run(&["delete", "/notes.txt", "--confirm-write"])
            .await
            .0,
        2
    );
    assert!(
        !duplicate
            .transport
            .calls
            .lock()
            .unwrap()
            .iter()
            .any(|r| r.url.ends_with("/file/delete"))
    );
    duplicate.finish();
    let mut unsupported = Fixture::new(Transport::default(), "webvpn");
    assert_ne!(unsupported.run(&["list"]).await.0, 0);
    let operation =
        ubaa_core::facade::RequiredRecoveryControl::new(std::time::Duration::from_secs(2))
            .unwrap()
            .claim()
            .unwrap();
    assert!(
        unsupported
            .client
            .recover_bhpan_session_controlled(operation)
            .await
            .is_err()
    );
    assert!(unsupported.transport.calls.lock().unwrap().is_empty());
    unsupported.finish();
}
#[tokio::test]
async fn 云盘发送后响应丢失只执行一次且下载准备不泄露签名值() {
    let mut fixture = Fixture::new(
        Transport {
            lost: true,
            ..Transport::default()
        },
        "direct",
    );
    let (code, value) = fixture
        .run(&["delete", "/notes.txt", "--confirm-write"])
        .await;
    assert_eq!(code, 5);
    assert_eq!(value["error"]["code"], "outcome_unknown");
    assert_eq!(value["error"]["retryable"], false);
    assert_eq!(
        fixture
            .transport
            .calls
            .lock()
            .unwrap()
            .iter()
            .filter(|r| r.url.ends_with("/file/delete"))
            .count(),
        1
    );
    let (code, value) = fixture.run(&["download-prepare", "/notes.txt"]).await;
    assert_eq!(code, 0);
    assert_eq!(value["data"]["preparation"]["destination_verified"], false);
    assert!(!value.to_string().contains("signature"));
    assert!(!value.to_string().contains("private"));
    fixture.finish();
}
#[tokio::test]
async fn 秒传文件自输入准备后变化时不发起业务网络() {
    let mut fixture = Fixture::new(Transport::default(), "direct");
    let file = fixture.root.join("input.txt");
    std::fs::write(&file, b"first").unwrap();
    let control = CommandControl::default();
    let prepared = prepare_input(
        parse([
            "ubaa",
            "--json",
            "bhpan",
            "upload-fast",
            "/",
            file.to_str().unwrap(),
            "notes.txt",
            "--confirm-write",
        ])
        .unwrap(),
        &mut Cursor::new([]),
        &control,
    )
    .unwrap();
    std::fs::write(&file, b"changed file").unwrap();
    let result = execute_attempt(&prepared, &mut fixture.client, &control)
        .await
        .into_result();
    assert_eq!(result.render(&control, &mut vec![], &mut vec![]), 2);
    assert!(fixture.transport.calls.lock().unwrap().is_empty());
    fixture.finish();
}

#[tokio::test]
async fn 公开聚合执行入口同样拒绝未确认云盘写入() {
    let mut fixture = Fixture::new(Transport::default(), "direct");
    let cli = ubaa_command::parse(["ubaa", "--json", "bhpan", "delete", "/notes.txt"])
        .unwrap()
        .into_cli();
    let code =
        ubaa_command::run_with_routed_backend(cli, &mut fixture.client, &mut vec![], &mut vec![])
            .await;
    assert_eq!(code, 2);
    assert!(fixture.transport.calls.lock().unwrap().is_empty());
    fixture.finish();
}

#[tokio::test]
async fn 公共上传下载命令交付实际文件且不输出对象授权() {
    let mut fixture = Fixture::new(Transport::default(), "direct");
    let source = fixture.root.join("input.txt");
    std::fs::write(&source, b"hello").unwrap();
    let (code, value) = fixture
        .run(&[
            "upload",
            "/",
            source.to_str().unwrap(),
            "notes.txt",
            "--confirm-write",
        ])
        .await;
    assert_eq!(code, 0);
    assert!(!value.to_string().contains("private"));
    let output = fixture.root.join("downloaded.txt");
    let (code, value) = fixture
        .run(&[
            "download",
            "/notes.txt",
            "--output",
            output.to_str().unwrap(),
        ])
        .await;
    assert_eq!(code, 0);
    assert_eq!(std::fs::read(output).unwrap(), b"hello");
    assert_eq!(value["data"]["operation"], "downloaded");
    assert!(!value.to_string().contains("signature"));
    fixture.finish();
}

#[tokio::test]
async fn 命令等待材料锁跨过绝对期限后不发送云盘写入() {
    use std::time::{Duration, Instant};
    let mut f = Fixture::new(Transport::default(), "direct");
    let parent = f
        .client
        .bhpan_personal_root()
        .await
        .unwrap()
        .items
        .remove(0);
    let file = f
        .client
        .bhpan_list(&parent.handle)
        .await
        .unwrap()
        .items
        .into_iter()
        .find(|item| item.name == "notes.txt")
        .unwrap();
    let prepared = f
        .client
        .bhpan_prepare_write(ubaa_core::facade::BhpanWriteIntent::Recycle { item: file.handle })
        .await
        .unwrap();
    let materials = f.root.join("materials");
    std::fs::create_dir_all(&materials).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(materials.join(name), value).unwrap();
    }
    f.client.bind_shared_account(Some(
        ubaa_core::facade::SharedAccountGuard::new(&materials, 1).unwrap(),
    ));
    let control = CommandControl::new(Instant::now(), Duration::from_secs(1));
    let wait = control.clone();
    let (locked, ready) = std::sync::mpsc::sync_channel(0);
    let worker = std::thread::spawn(move || {
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(materials.join("materials.lock"))
            .unwrap();
        file.lock().unwrap();
        locked.send(()).unwrap();
        while !wait.remaining().is_zero() {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(wait.check().is_err());
        drop(file);
    });
    ready.recv().unwrap();
    // 锁释放前期限一定已到达，取消不能仅依赖异步定时器抢占本次轮询。
    let result = control
        .run(f.client.bhpan_commit_write(&prepared.handle))
        .await;
    worker.join().unwrap();
    assert!(result.is_err());
    assert!(
        !f.transport
            .calls
            .lock()
            .unwrap()
            .iter()
            .any(|request| request.url.ends_with("/file/delete"))
    );
    f.finish();
}
