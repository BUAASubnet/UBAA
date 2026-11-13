use super::*;
use crate::api::{
    agenda::models::{BridgeAgendaContent, BridgeAgendaDraft, BridgeAgendaKind},
    client::BridgeErrorCode,
    command::BridgeCommand,
    shared_account::BridgeSharedAccount,
};
use async_trait::async_trait;
use std::{
    path::{Path, PathBuf},
    sync::{RwLock, atomic::AtomicBool},
};
use ubaa_core::facade::testing::{
    FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport, RouteConfig,
};
struct NeverNetwork;
#[async_trait]
impl HttpTransport for NeverNetwork {
    async fn execute(&self, _: HttpRequest) -> core::Result<HttpResponse> {
        panic!("缺少学校会话时不得请求云盘");
    }
}
struct NeverProbe;
impl GatewayProbe for NeverProbe {
    fn probe(&self, _: std::time::Duration) -> core::NetworkState {
        panic!("固定路线不得探测");
    }
}
fn now() -> BridgeAgendaTime {
    BridgeAgendaTime {
        rfc3339: "2026-03-01T00:00:00+08:00".into(),
        timezone: "Asia/Shanghai".into(),
    }
}
fn root() -> PathBuf {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/agenda_sync_dev/bridge")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    root
}
fn bridge_client(directory: &Path, policy: core::RoutePolicy) -> BridgeClient {
    let mut config = RouteConfig::default();
    config.default = policy;
    let client = core::UbaaClient::with_routing(
        NeverNetwork,
        NeverNetwork,
        FileSessionStore::new(directory).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    BridgeClient {
        network_control: client.network_control(),
        close_control: client.close_control(),
        auth_control: RwLock::new(client.interactive_login_cancellation()),
        is_disposed: AtomicBool::new(false),
        bhpan_transfers: std::sync::Mutex::new(Vec::new()),
        inner: crate::api::read_pool::ClientPool::new(client),
        write_intents: tokio::sync::Mutex::new(std::collections::HashMap::new()),
    }
}
fn shared_owner(root: &Path) -> BridgeSharedAccount {
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    BridgeSharedAccount::capture(root.to_string_lossy().into(), 1).unwrap()
}

#[tokio::test]
async fn gui与命令未登录时保留日程并返回认证错误() {
    let root = root();
    let directory = root.join("core");
    let bridge = bridge_client(&directory, core::RoutePolicy::Direct);
    let owner = shared_owner(&root);
    bridge.bind_shared_account(&owner).await.unwrap();
    let agenda = BridgeAgendaStore::open_shared(
        directory.to_string_lossy().into(),
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
        &owner,
    )
    .await
    .unwrap();
    agenda
        .create(
            BridgeAgendaDraft {
                content: BridgeAgendaContent {
                    kind: BridgeAgendaKind::Task,
                    title: "合成待同步事项".into(),
                    location: None,
                    notes: None,
                    color: None,
                    start: None,
                    end: None,
                    all_day: false,
                    due: None,
                },
                rrule: None,
                exdates: vec![],
            },
            now(),
        )
        .await
        .unwrap();
    let service = BridgeAgendaSyncService::open(&agenda, directory.to_string_lossy().into());
    let report = bridge
        .sync_agenda(&service, BridgeAgendaSyncAction::Pull, now())
        .await
        .unwrap_err();
    assert_eq!(
        report.remote.unwrap().code,
        BridgeErrorCode::AuthenticationRequired
    );
    assert_eq!(agenda.unsynced_count().await.unwrap(), 1);
    assert!(!agenda.sync_enabled().await.unwrap());
    let command = BridgeCommand::parse(
        ["ubaa-cli", "--json", "agenda", "sync", "--confirm-write"]
            .into_iter()
            .map(str::to_owned)
            .collect(),
        120_000,
    );
    command.prepare(vec![]).await;
    let result = command
        .execute_agenda_sync(&bridge, &agenda, &owner, directory.to_string_lossy().into())
        .await
        .unwrap();
    assert!(
        command.sent.lock().unwrap().is_some(),
        "新快照作业应记录写入边界以供取消时核对"
    );
    let delivery = result.deliver().await;
    let mut bytes = vec![];
    while let Some(chunk) = delivery.next_stdout().await.unwrap() {
        bytes.extend(chunk);
        delivery.acknowledge_stdout().unwrap();
    }
    while delivery.next_stderr().await.unwrap().is_some() {
        delivery.acknowledge_stderr().unwrap();
    }
    assert_eq!(delivery.finish().await, 3);
    let output = String::from_utf8(bytes).unwrap();
    assert!(output.contains("\"code\":\"authentication_required\""));
    assert!(!agenda.sync_enabled().await.unwrap());
    assert!(
        command
            .execute_agenda_sync(&bridge, &agenda, &owner, directory.to_string_lossy().into())
            .await
            .is_err()
    );
    bridge.dispose().await.unwrap();
    let closed = bridge
        .sync_agenda(&service, BridgeAgendaSyncAction::Push, now())
        .await
        .unwrap_err();
    assert_eq!(closed.remote.unwrap().code, BridgeErrorCode::ClientDisposed);
    assert_eq!(agenda.unsynced_count().await.unwrap(), 1);
    drop((service, agenda, bridge));
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 旧创建作用域在客户端锁后拒绝换路线和同路线重开() {
    for policy in [core::RoutePolicy::WebVpn, core::RoutePolicy::Direct] {
        let root = root();
        let directory = root.join("core");
        let owner = shared_owner(&root);
        let bridge = bridge_client(&directory, core::RoutePolicy::Direct);
        bridge.bind_shared_account(&owner).await.unwrap();
        let agenda = BridgeAgendaStore::open_shared(
            directory.to_string_lossy().into(),
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
            &owner,
        )
        .await
        .unwrap();
        let service = BridgeAgendaSyncService::open(&agenda, directory.to_string_lossy().into());
        let scope = bridge.capture_agenda_sync_scope().unwrap();
        let replacement = bridge_client(&root.join("replacement"), policy);
        replacement.bind_shared_account(&owner).await.unwrap();
        let reopened = replacement.inner.lock().await.take().unwrap();
        {
            let mut held = bridge.inner.lock().await;
            assert!(matches!(
                bridge.capture_agenda_sync_scope(),
                Err(BridgeAgendaSyncError {
                    local: Some(BridgeAgendaFailure::Unavailable),
                    ..
                })
            ));
            let waiting = bridge.create_agenda_sync_confirmed(&service, now(), &scope);
            tokio::pin!(waiting);
            tokio::select! {
                biased;
                _ = &mut waiting => panic!("创建必须等待实际执行客户端锁"),
                () = std::future::ready(()) => {}
            }
            *held = Some(reopened);
            drop(held);
            let rejected = waiting.await.unwrap_err();
            assert_eq!(rejected.local, Some(BridgeAgendaFailure::Superseded));
        }
        let missing = bridge
            .sync_agenda(&service, BridgeAgendaSyncAction::CreateConfirmed, now())
            .await
            .unwrap_err();
        assert_eq!(missing.local, Some(BridgeAgendaFailure::Superseded));
        if policy == core::RoutePolicy::Direct {
            let fresh = bridge.capture_agenda_sync_scope().unwrap();
            let result = bridge
                .create_agenda_sync_confirmed(&service, now(), &fresh)
                .await
                .unwrap_err();
            assert_eq!(
                result.remote.unwrap().code,
                BridgeErrorCode::AuthenticationRequired
            );
            assert!(agenda.sync_enabled().await.unwrap());
        } else {
            assert!(matches!(
                bridge.capture_agenda_sync_scope(),
                Err(BridgeAgendaSyncError {
                    local: Some(BridgeAgendaFailure::Superseded),
                    ..
                })
            ));
        }
        drop((service, agenda, bridge, replacement));
        std::fs::remove_dir_all(root).unwrap();
    }
}
