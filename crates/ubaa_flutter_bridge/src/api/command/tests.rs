use super::*;
#[test]
fn 配置路径为文件时在请求密码前拒绝() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/input_tests");
    std::fs::create_dir_all(&root).unwrap();
    let file = root.join(uuid::Uuid::new_v4().to_string());
    std::fs::write(&file, "合成普通文件").unwrap();
    let command = BridgeCommand::parse(
        vec![
            "ubaa-cli".into(),
            "--config-dir".into(),
            file.to_string_lossy().into(),
            "auth".into(),
            "login".into(),
            "--username".into(),
            "synthetic".into(),
        ],
        120_000,
    );
    let input = command.input_request(vec![], false).unwrap();
    assert_eq!(
        input.kind,
        BridgeCommandInputKind::Ready,
        "无法使用的配置目录不得触发密码输入"
    );
    assert!(command.early_result().is_some());
    std::fs::remove_file(file).unwrap();
}
#[test]
fn 无效用户名立即拒绝且不再请求密码() {
    for input in [vec![0xff, b'\n'], b" \n".to_vec(), b"\n".to_vec()] {
        let command = BridgeCommand::parse(
            [
                "ubaa-cli",
                "--json",
                "auth",
                "login",
                "--username-stdin",
                "--password-stdin",
            ]
            .into_iter()
            .map(str::to_owned)
            .collect(),
            120_000,
        );
        assert_eq!(
            command.input_request(input, false).unwrap().kind,
            BridgeCommandInputKind::Ready
        );
        assert!(command.early_result().is_some());
    }
}

#[tokio::test]
async fn 无效登录参数在材料初始化前形成最终错误() {
    for args in [
        vec![
            "ubaa-cli",
            "--json",
            "auth",
            "login",
            "--username",
            "",
            "--password-stdin",
        ],
        vec![
            "ubaa-cli",
            "--json",
            "auth",
            "login",
            "--username",
            "synthetic",
        ],
        vec!["ubaa-cli", "--json", "auth", "login", "--password-stdin"],
        vec![
            "ubaa-cli",
            "auth",
            "login",
            "--username",
            "synthetic",
            "--username-stdin",
        ],
    ] {
        let command = BridgeCommand::parse(args.into_iter().map(str::to_owned).collect(), 120_000);
        assert_eq!(
            command.input_request(vec![], false).unwrap().kind,
            BridgeCommandInputKind::Ready
        );
        command.prepare(vec![]).await;
        assert!(
            command.early_result().is_some(),
            "参数错误不得等到建立材料或客户端后处理"
        );
    }
}

#[tokio::test]
async fn 无效本机参数与输入在打开材料前拒绝() {
    for (arguments, input) in [
        (
            vec![
                "agenda",
                "delete",
                "--id",
                "11111111-1111-4111-8111-111111111111",
                "--scope",
                "this",
                "--confirm-local-write",
            ],
            "",
        ),
        (
            vec![
                "agenda",
                "complete",
                "--id",
                "11111111-1111-4111-8111-111111111111",
                "--at",
                "not-time",
                "--confirm-local-write",
            ],
            "",
        ),
        (
            vec![
                "agenda",
                "list",
                "--from",
                "2026-12-02",
                "--to",
                "2026-12-01",
            ],
            "",
        ),
        (
            vec!["agenda", "create", "--input", "-", "--confirm-local-write"],
            "{invalid",
        ),
    ] {
        let command = BridgeCommand::parse(
            [vec!["ubaa-cli", "--json"], arguments]
                .concat()
                .into_iter()
                .map(str::to_owned)
                .collect(),
            120_000,
        );
        command.prepare(input.as_bytes().to_vec()).await;
        assert!(
            command.early_result().is_some(),
            "本机无效输入不能触发材料初始化"
        );
    }
}

#[tokio::test]
async fn 写入结果在交付前到期时保留核对提示() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/command_delivery/output_tests")
        .join(uuid::Uuid::new_v4().to_string());
    std::fs::create_dir_all(&root).unwrap();
    let cache = crate::api::offline::BridgeOfflineCache::open(
        root.to_string_lossy().into(),
        "0123456789abcdef0123456789abcdef".into(),
        "synthetic".into(),
        vec![8; 32],
    )
    .await
    .unwrap();
    let ticket = cache
        .cache
        .begin_write_readback(
            core::WriteReadbackOperation::BykcSelectCourse,
            core::ConnectionMode::Direct,
            100,
        )
        .unwrap();
    let prepared = command::prepare_input(
        command::parse([
            "ubaa-cli",
            "--json",
            "bykc",
            "select",
            "--course-id",
            "42",
            "--confirm-write",
        ])
        .unwrap(),
        &mut Cursor::new([]),
        &command::CommandControl::default(),
    )
    .unwrap();
    let result = BridgeCommandResult {
        body: Arc::new(Mutex::new(Some(Body::Result(
            command::runtime::preflight_failure(
                &prepared,
                core::RoutedError {
                    error: UbaaError::new(
                        ErrorCode::PermissionDenied,
                        ErrorKind::Authentication,
                        false,
                        "合成拒绝结果",
                    ),
                    resolution: None,
                },
            )
            .into_result(),
        )))),
        control: command::CommandControl::new(Instant::now(), Duration::ZERO),
        scope: None,
        hints: Arc::new(Mutex::new(vec![(
            cache.cache.clone(),
            ticket.id().to_owned(),
        )])),
    };
    let delivery = result.deliver().await;
    tokio::join!(
        async {
            while delivery.next_stdout().await.unwrap().is_some() {
                delivery.acknowledge_stdout().unwrap();
            }
        },
        async {
            while delivery.next_stderr().await.unwrap().is_some() {
                delivery.acknowledge_stderr().unwrap();
            }
        }
    );
    assert_eq!(delivery.finish().await, 5);
    assert_eq!(
        cache.cache.write_readback_hints().unwrap().len(),
        1,
        "收尾错误并未交付原写入结果，核对提示必须保留"
    );
    cache.close().await.unwrap();
    drop((delivery, result, cache));
    std::fs::remove_dir_all(root).unwrap();
}

#[tokio::test]
async fn 密码与阳光请求在材料初始化前完整校验() {
    for (arguments, input) in [
        (
            vec![
                "auth",
                "login",
                "--username",
                "synthetic",
                "--password-stdin",
            ],
            vec![b'\n'],
        ),
        (
            vec![
                "auth",
                "login",
                "--username",
                "synthetic",
                "--password-stdin",
            ],
            vec![],
        ),
        (
            vec![
                "auth",
                "login",
                "--username",
                "synthetic",
                "--password-stdin",
            ],
            vec![0xff, b'\n'],
        ),
        (
            vec![
                "ygdk",
                "submit",
                "--classify-id",
                "1",
                "--item-id",
                "1",
                "--start-time",
                "bad-time",
                "--end-time",
                "bad-time",
                "--photo",
                ".ubaa_local/command_delivery/missing.jpg",
                "--confirm-write",
            ],
            vec![],
        ),
        (
            vec![
                "ygdk",
                "submit",
                "--classify-id",
                "1",
                "--item-id",
                "1",
                "--start-time",
                "2026-11-05 08:00",
                "--end-time",
                "2026-11-05 09:00",
                "--photo",
                ".ubaa_local/command_delivery/missing.jpg",
                "--confirm-write",
            ],
            vec![],
        ),
    ] {
        let command = BridgeCommand::parse(
            [vec!["ubaa-cli", "--json"], arguments]
                .concat()
                .into_iter()
                .map(str::to_owned)
                .collect(),
            120_000,
        );
        command.prepare(input).await;
        assert!(
            command.early_result().is_some(),
            "无效密码或阳光输入不能推进材料与账号状态"
        );
    }
}
