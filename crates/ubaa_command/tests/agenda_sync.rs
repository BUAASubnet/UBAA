use ubaa_command::{agenda::sync::AgendaSyncCommandResult, parse};
use ubaa_core::facade::UbaaError;

#[tokio::test]
async fn 固定webvpn首次创建通过同步服务输出未验证且不启用同步() {
    use ubaa_core::facade::{
        AgendaStore, AgendaSyncAction, AgendaSyncService, AgendaTime, NetworkState, RoutePolicy,
        SharedAccountGuard, UbaaClient,
        testing::{
            FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport, RouteConfig,
        },
    };

    struct NeverNetwork;
    #[async_trait::async_trait]
    impl HttpTransport for NeverNetwork {
        async fn execute(&self, _: HttpRequest) -> Result<HttpResponse, UbaaError> {
            panic!("未验证的同步路线不得发送请求")
        }
    }
    struct NeverProbe;
    impl GatewayProbe for NeverProbe {
        fn probe(&self, _: std::time::Duration) -> NetworkState {
            panic!("固定路线不得探测")
        }
    }

    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    for (name, value) in [
        ("materials.lock", ""),
        ("transaction.v1", "UBAA1:C"),
        ("account-generation.v1", "UBAA1:1"),
    ] {
        std::fs::write(root.join(name), value).unwrap();
    }
    let owner = SharedAccountGuard::new(&root, 1).unwrap();
    let store =
        AgendaStore::open_shared(&root, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", owner.clone()).unwrap();
    let mut config = RouteConfig::default();
    config.default = RoutePolicy::WebVpn;
    let mut client = UbaaClient::with_routing(
        NeverNetwork,
        NeverNetwork,
        FileSessionStore::new(&root).unwrap(),
        config,
        NeverProbe,
    )
    .unwrap();
    client.bind_shared_account(Some(owner));
    let plan = parse([
        "ubaa-cli",
        "--json",
        "agenda",
        "sync",
        "--create",
        "--confirm-write",
    ])
    .unwrap();
    plan.validate_local_arguments().unwrap();
    assert!(matches!(
        &plan.cli().command,
        ubaa_command::Command::Agenda(ubaa_command::AgendaArgs {
            command: ubaa_command::AgendaCommand::Sync {
                create: true,
                confirm_write: true,
                ..
            }
        })
    ));
    let scratch = root.join("scratch");
    let mut service = AgendaSyncService::new(store.clone(), scratch.clone());
    let result = service
        .run(
            &mut client,
            AgendaSyncAction::CreateConfirmed,
            AgendaTime::new(
                chrono::DateTime::parse_from_rfc3339("2026-11-05T00:00:00+08:00").unwrap(),
            ),
        )
        .await;
    let (mut out, mut err) = (vec![], vec![]);
    let exit = AgendaSyncCommandResult(result).render(
        true,
        &ubaa_command::CommandControl::default(),
        &mut out,
        &mut err,
    );
    let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
    assert!(!store.sync_enabled().unwrap());
    assert!(!scratch.exists());
    assert_eq!(exit, 6);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "sync_unverified");
    assert_eq!(value["data"]["status"], "unverified");
    drop((service, store, client));
    std::fs::remove_dir_all(root).unwrap();
}
