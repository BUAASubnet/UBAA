use super::*;
use crate::domain::RoutePolicy;
use crate::domain::bhpan::{
    BhpanItem, BhpanItemKind, BhpanPermission, BhpanShareSettings, BhpanTransferPhase,
    BhpanWriteIntent,
};
use crate::error::ErrorCode;
use crate::facade::NetworkState;
use crate::facade::testing::{
    FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport, RouteConfig,
};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

pub(super) struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不能探测网关")
    }
}
#[derive(Clone, Default)]
pub(super) struct Script {
    steps: Arc<Mutex<VecDeque<Step>>>,
}
struct Step {
    method: HttpMethod,
    path: &'static str,
    body: Option<serde_json::Value>,
    token: Option<&'static str>,
    secondary: Option<&'static str>,
    response: Result<HttpResponse>,
}
#[async_trait::async_trait]
impl HttpTransport for Script {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let step = self
            .steps
            .lock()
            .unwrap()
            .pop_front()
            .expect("不得额外发送请求或自动重试");
        assert_eq!(request.method, step.method);
        if step.path == "/api/efast/v1/entry-item" {
            let cookie = request
                .headers
                .get("Cookie")
                .map(String::as_str)
                .unwrap_or_default();
            assert!(cookie.contains("link_token:synthetic-share=share-fixture"));
            assert!(!cookie.contains("personal-cookie"));
        } else {
            assert!(
                !request.headers.contains_key("Cookie"),
                "Bearer API 不得携带个人或其他分享 Cookie"
            );
        }
        assert_eq!(
            request.url,
            format!("{}{path}", wire::ORIGIN, path = step.path)
        );
        assert_eq!(
            request.headers.get("Authorization").map(String::as_str),
            step.token
        );
        assert_eq!(
            request
                .headers
                .get("x-as-authorization")
                .map(String::as_str),
            step.secondary
        );
        if let Some(body) = step.body {
            let mut actual = serde_json::from_slice::<serde_json::Value>(&request.body).unwrap();
            if step.path.ends_with("/dupload") || step.path.ends_with("/osbeginupload") {
                assert!(
                    actual
                        .get("client_mtime")
                        .and_then(serde_json::Value::as_u64)
                        .is_some()
                );
                actual.as_object_mut().unwrap().remove("client_mtime");
            }
            assert_eq!(actual, body);
        }
        step.response
    }
}
impl Script {
    pub(super) fn add(
        &self,
        method: HttpMethod,
        path: &'static str,
        body: Option<serde_json::Value>,
        response: &[u8],
    ) {
        self.steps.lock().unwrap().push_back(Step {
            method,
            path,
            body,
            token: Some("Bearer personal-fixture"),
            secondary: None,
            response: Ok(HttpResponse::new(
                200,
                format!("{}{path}", wire::ORIGIN),
                response.to_vec(),
            )),
        });
    }
    pub(super) fn status(&self, status: u16) {
        self.steps
            .lock()
            .unwrap()
            .back_mut()
            .unwrap()
            .response
            .as_mut()
            .unwrap()
            .status = status;
    }
    pub(super) fn done(&self) {
        assert!(self.steps.lock().unwrap().is_empty());
    }
}
fn executor() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn client(script: Script) -> (UbaaClient, std::path::PathBuf) {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/bhpan_delivery/tests")
        .join(uuid::Uuid::new_v4().to_string());
    let mut config = RouteConfig::default();
    config.replace_default_policy(RoutePolicy::Direct);
    let mut client = UbaaClient::with_routing(
        script,
        Script::default(),
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
    (client, root)
}
pub(super) fn item(client: &mut UbaaClient, scope: BhpanScope) -> BhpanItem {
    item_with_root(
        client,
        scope,
        if scope == BhpanScope::Personal {
            crate::domain::bhpan::BhpanRootKind::Personal
        } else {
            crate::domain::bhpan::BhpanRootKind::All
        },
    )
}
fn item_with_root(
    client: &mut UbaaClient,
    scope: BhpanScope,
    root_kind: crate::domain::bhpan::BhpanRootKind,
) -> BhpanItem {
    client.bhpan.publish(Authority {
        item: parse::Item {
            id: "gns://fixture/target".into(),
            name: "目录".into(),
            kind: BhpanItemKind::Folder,
            bytes: None,
            created: None,
            modified: None,
        },
        scope,
        root_kind,
        root_id: "gns://fixture/target".into(),
        token: None,
        context: String::new(),
    })
}
#[test]
fn 目录请求与字段解析保持来源语义() {
    executor().block_on(async {
        let script = Script::default();
        script.add(HttpMethod::Get,"/api/efast/v1/owned-doc-lib",None,r#"[{"id":"gns://fixture/target","name":"个人"}]"#.as_bytes());
        script.add(HttpMethod::Post,"/api/efast/v1/dir/list",Some(json!({"by":"name","docid":"gns://fixture/target","sort":"asc"})),
            br#"{"dirs":[],"files":[{"docid":"gns://fixture/file","name":"notes.txt","size":12,"modified":1700000000123456}]}"#);
        let (mut client,root) = client(script.clone());
        let personal = client.bhpan_personal_root().await.unwrap();
        let page = client.bhpan_list(&personal.items[0].handle).await.unwrap();
        assert_eq!(page.range,BhpanListRange::Unknown);
        assert_eq!(page.items[0].bytes,Some(12));
        assert_eq!(page.items[0].modified_at,Some(1_700_000_000));
        assert_eq!(page.items[0].created_at,None);
        assert!(!serde_json::to_string(&page).unwrap().contains("gns://"));
        script.done(); drop(client); std::fs::remove_dir_all(root).unwrap();
    });
}
#[test]
fn 写确认消费一次且网络响应丢失保持结果未知() {
    executor().block_on(async {
        let script = Script::default();
        script.steps.lock().unwrap().push_back(Step {
            method: HttpMethod::Post,
            path: "/api/efast/v1/file/delete",
            body: Some(json!({"docid":"gns://fixture/target"})),
            token: Some("Bearer personal-fixture"),
            secondary: None,
            response: Err(UbaaError::new(
                ErrorCode::NetworkError,
                crate::error::ErrorKind::Network,
                true,
                "synthetic",
            )),
        });
        let (mut client, root) = client(script.clone());
        let item = item(&mut client, BhpanScope::Personal);
        let prepared = client
            .bhpan_prepare_write(BhpanWriteIntent::Recycle { item: item.handle })
            .await
            .unwrap();
        let error = client
            .bhpan_commit_write(&prepared.handle)
            .await
            .unwrap_err();
        assert_eq!(error.code, ErrorCode::OutcomeUnknown);
        assert!(!error.retryable);
        assert_eq!(
            client
                .bhpan_commit_write(&prepared.handle)
                .await
                .unwrap_err()
                .code,
            ErrorCode::InvalidInput
        );
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}
#[test]
fn 写入成功响应缺少身份不能报告成功() {
    executor().block_on(async {
        let script = Script::default();
        script.add(
            HttpMethod::Post,
            "/api/efast/v1/dir/create",
            Some(json!({"docid":"gns://fixture/target","name":"新目录","ondup":1})),
            b"{}",
        );
        let (mut client, root) = client(script.clone());
        let parent = item(&mut client, BhpanScope::Personal);
        let prepared = client
            .bhpan_prepare_write(BhpanWriteIntent::CreateFolder {
                parent: parent.handle,
                name: "新目录".into(),
            })
            .await
            .unwrap();
        assert_eq!(
            client
                .bhpan_commit_write(&prepared.handle)
                .await
                .unwrap_err()
                .code,
            ErrorCode::OutcomeUnknown
        );
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}
#[test]
fn 退出或路线变化后旧句柄不能发出业务请求() {
    executor().block_on(async {
        let script = Script::default();
        let (mut client, root) = client(script.clone());
        let target = item(&mut client, BhpanScope::Personal);
        let p = client
            .bhpan_prepare_write(BhpanWriteIntent::Recycle {
                item: target.handle.clone(),
            })
            .await
            .unwrap();
        client.route_generation += 1;
        // 路线代次变化时旧确认须在认证请求前拒绝。
        assert!(client.bhpan_commit_write(&p.handle).await.is_err());
        client.clear_all_memory();
        assert_eq!(
            client.bhpan_list(&target.handle).await.unwrap_err().code,
            ErrorCode::AuthenticationRequired
        );
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}
#[test]
fn 接收分享不能取得个人文件管理权限() {
    executor().block_on(async {
        let script = Script::default();
        let (mut client, root) = client(script.clone());
        let target = item(&mut client, BhpanScope::ReceivedShare);
        assert!(
            client
                .bhpan_prepare_write(BhpanWriteIntent::Recycle {
                    item: target.handle.clone()
                })
                .await
                .is_err()
        );
        assert!(
            client
                .bhpan_prepare_write(BhpanWriteIntent::Rename {
                    item: target.handle,
                    name: "x".into()
                })
                .await
                .is_err()
        );
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[test]
fn 同客户端账号变化后旧确认不能提交() {
    executor().block_on(async {
        let script = Script::default();
        let (mut client, root) = client(script.clone());
        let target = item(&mut client, BhpanScope::Personal);
        let p = client
            .bhpan_prepare_write(BhpanWriteIntent::Recycle {
                item: target.handle,
            })
            .await
            .unwrap();
        client
            .direct_runtime
            .remember_account_name(Some("different-fixture-account"));
        assert!(client.bhpan_commit_write(&p.handle).await.is_err());
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[test]
fn 显式授权请求不会附带个人会话cookie() {
    executor().block_on(async {
        let script = Script::default();
        script.add(
            HttpMethod::Get,
            "/api/efast/v1/entry-doc-lib?sort=doc_lib_name&direction=asc",
            None,
            b"[]",
        );
        let (mut client, root) = client(script.clone());
        client
            .direct_runtime
            .set_scoped_cookie(
                "client.oauth2_token=personal-cookie; Path=/; Secure",
                wire::ORIGIN,
            )
            .unwrap();
        client.bhpan_roots(BhpanRootKind::All).await.unwrap();
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[test]
fn 秒传使用协议摘要且本机文件变化后不提交() {
    executor().block_on(async {
        let script = Script::default();
        script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/predupload",
            Some(json!({"length":5,"slice_md5":"5d41402abc4b2a76b9719d911017c592"})),
            br#"{"match":true}"#,
        );
        let (mut client, root) = client(script.clone());
        let parent = item(&mut client, BhpanScope::Personal);
        let path = root.join("upload.fixture");
        std::fs::write(&path, b"hello").unwrap();
        let transfer = super::BhpanTransfer::new();
        let p = client
            .bhpan_prepare_fast_upload(&parent.handle, path.clone(), "notes.txt", transfer.clone())
            .await
            .unwrap();
        assert_eq!(
            transfer.progress().phase,
            BhpanTransferPhase::AwaitingConfirmation
        );
        std::fs::write(&path, b"changed").unwrap();
        assert!(client.bhpan_commit_write(&p.handle).await.is_err());
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}
#[test]
fn 任务取消与重复使用不能继续准备或发出写入() {
    executor().block_on(async {
        let script = Script::default();
        script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/predupload",
            Some(json!({"length":5,"slice_md5":"5d41402abc4b2a76b9719d911017c592"})),
            br#"{"match":true}"#,
        );
        let (mut client, root) = client(script.clone());
        let parent = item(&mut client, BhpanScope::Personal);
        let path = root.join("upload.fixture");
        std::fs::write(&path, b"hello").unwrap();
        let transfer = super::BhpanTransfer::new();
        let p = client
            .bhpan_prepare_fast_upload(&parent.handle, path.clone(), "notes.txt", transfer.clone())
            .await
            .unwrap();
        assert!(
            client
                .bhpan_prepare_fast_upload(&parent.handle, path, "notes.txt", transfer.clone())
                .await
                .is_err()
        );
        transfer.cancel();
        assert!(client.bhpan_commit_write(&p.handle).await.is_err());
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[test]
fn 秒传成功与响应丢失分别记账且不重放() {
    executor().block_on(async {
        for lost in [false,true] {
            let script=Script::default();
            script.add(HttpMethod::Post,"/api/efast/v1/file/predupload",Some(json!({"length":5,"slice_md5":"5d41402abc4b2a76b9719d911017c592"})),br#"{"match":true}"#);
            let step=Step {method:HttpMethod::Post,path:"/api/efast/v1/file/dupload",body:Some(json!({"crc32":"3610a686","docid":"gns://fixture/target","length":5,"md5":"5d41402abc4b2a76b9719d911017c592","name":"notes.txt","ondup":1})),token:Some("Bearer personal-fixture"),secondary:None,
                response:if lost {Err(UbaaError::new(ErrorCode::NetworkError,crate::error::ErrorKind::Network,true,"synthetic"))}else{Ok(HttpResponse::new(200,format!("{}/api/efast/v1/file/dupload",wire::ORIGIN),br#"{"success":true}"#.to_vec()))}};
            script.steps.lock().unwrap().push_back(step);
            let (mut client,root)=client(script.clone());let parent=item(&mut client,BhpanScope::Personal);let path=root.join("upload.fixture");std::fs::write(&path,b"hello").unwrap();let transfer=super::BhpanTransfer::new();
            let p=client.bhpan_prepare_fast_upload(&parent.handle,path,"notes.txt",transfer.clone()).await.unwrap();
            let result=client.bhpan_commit_write(&p.handle).await;
            if lost {assert_eq!(result.unwrap_err().code,ErrorCode::OutcomeUnknown);assert_eq!(transfer.progress().phase,BhpanTransferPhase::OutcomeUnknown);}
            else {assert!(result.is_ok());assert_eq!(transfer.progress().phase,BhpanTransferPhase::Completed);}
            assert!(client.bhpan_commit_write(&p.handle).await.is_err());script.done();drop(client);std::fs::remove_dir_all(root).unwrap();
        }
    });
}
#[test]
fn 秒传未匹配不自动创建普通上传或分片会话() {
    executor().block_on(async {
        let script = Script::default();
        script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/predupload",
            Some(json!({"length":5,"slice_md5":"5d41402abc4b2a76b9719d911017c592"})),
            br#"{"match":false}"#,
        );
        let (mut client, root) = client(script.clone());
        let parent = item(&mut client, BhpanScope::Personal);
        let path = root.join("upload.fixture");
        std::fs::write(&path, b"hello").unwrap();
        let transfer = super::BhpanTransfer::new();
        assert!(
            client
                .bhpan_prepare_fast_upload(&parent.handle, path, "notes.txt", transfer.clone())
                .await
                .is_err()
        );
        assert_eq!(transfer.progress().phase, BhpanTransferPhase::Blocked);
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[test]
fn 共享文档库拒绝秒传且不发送探测请求() {
    executor().block_on(async {
        for root_kind in [
            crate::domain::bhpan::BhpanRootKind::Shared,
            crate::domain::bhpan::BhpanRootKind::Department,
            crate::domain::bhpan::BhpanRootKind::Group,
        ] {
            let script = Script::default();
            let (mut client, root) = client(script.clone());
            let parent = item_with_root(&mut client, BhpanScope::Personal, root_kind);
            let path = root.join("upload.fixture");
            std::fs::write(&path, b"hello").unwrap();
            let transfer = super::BhpanTransfer::new();
            let error = client
                .bhpan_prepare_fast_upload(&parent.handle, path, "notes.txt", transfer)
                .await
                .unwrap_err();
            assert_eq!(error.code, ErrorCode::InvalidInput);
            assert_eq!(error.message, "秒传只支持个人文档库");
            script.done();
            drop(client);
            std::fs::remove_dir_all(root).unwrap();
        }
    });
}

#[test]
fn All入口核实个人根后允许秒传() {
    executor().block_on(async {
        let script = Script::default();
        script.add(
            HttpMethod::Get,
            "/api/efast/v1/owned-doc-lib",
            None,
            br#"[{"id":"gns://fixture/target","name":"personal"}]"#,
        );
        script.add(
            HttpMethod::Post,
            "/api/efast/v1/file/predupload",
            Some(json!({
                "length": 5,
                "slice_md5": "5d41402abc4b2a76b9719d911017c592"
            })),
            br#"{"match":false}"#,
        );
        let (mut client, root) = client(script.clone());
        let parent = item_with_root(
            &mut client,
            BhpanScope::Personal,
            crate::domain::bhpan::BhpanRootKind::All,
        );
        let path = root.join("upload.fixture");
        std::fs::write(&path, b"hello").unwrap();
        let transfer = super::BhpanTransfer::new();
        let error = client
            .bhpan_prepare_fast_upload(&parent.handle, path, "notes.txt", transfer)
            .await
            .unwrap_err();
        assert_eq!(error.message, "该文件不支持秒传，请改用普通上传");
        script.done();
        drop(client);
        std::fs::remove_dir_all(root).unwrap();
    });
}

#[path = "operation_tests.rs"]
mod operations;

#[test]
fn 重复刷新同一对象不会累积旧目标或旧分享() {
    let (mut client, root) = client(Script::default());
    let first = item(&mut client, BhpanScope::Personal);
    for _ in 0..100 {
        item(&mut client, BhpanScope::Personal);
    }
    assert_eq!(client.bhpan.items.len(), 1);
    assert_eq!(client.bhpan.item(&first.handle).unwrap().item.name, "目录");
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 当次动态授权允许_direct对象传输且保留_web_vpn未验证() {
    let (client, root) = client(Script::default());
    let capabilities = client.bhpan_capabilities();
    assert_eq!(
        capabilities.object_transfer,
        crate::domain::bhpan::BhpanCapability::Available
    );
    assert_eq!(
        capabilities.webvpn,
        crate::domain::bhpan::BhpanCapability::Unverified
    );
    drop(client);
    std::fs::remove_dir_all(root).unwrap();
}

#[path = "pagination_tests.rs"]
mod pagination;
