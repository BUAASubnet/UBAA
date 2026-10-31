#[path = "agenda_read/support.rs"]
#[cfg(target_os = "macos")]
mod support;
use clap::Parser;
use ubaa_cli::Cli;

#[test]
fn 本机日程命令独立于学校会话() {
    for arguments in [
        vec![
            "ubaa",
            "agenda",
            "list",
            "--from",
            "2026-11-01",
            "--to",
            "2026-11-08",
        ],
        vec![
            "ubaa",
            "agenda",
            "show",
            "--id",
            "00000000-0000-4000-8000-000000000001",
        ],
        vec!["ubaa", "agenda", "unsynced"],
    ] {
        let cli = Cli::try_parse_from(arguments).expect("应提供本机日程命令");
        assert!(!cli.requires_session());
        assert_eq!(cli.feature().as_str(), "agenda");
    }
}

#[cfg(target_os = "macos")]
mod native {
    use crate::support::*;
    use serde_json::{Value, json};
    use sha2::{Digest, Sha256};
    use std::process::Command;

    use ubaa_core::facade::{
        AgendaStore, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope, ConnectionMode,
    };
    const SERVICE: &str = "cn.edu.ubaa.cli.local-accounts.v1";
    fn scope(root: &std::path::Path) -> String {
        format!("{:x}", Sha256::digest(root.as_os_str().as_encoded_bytes()))
    }
    fn native_read(scope: &str) -> Vec<u8> {
        let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
            .args(["--internal-keychain-worker", "read", scope])
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        output.stdout
    }
    fn native_write(scope: &str, data: &[u8]) {
        use std::io::Write;
        let mut child = Command::new(env!("CARGO_BIN_EXE_ubaa"))
            .args(["--internal-keychain-worker", "write", scope])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        child.stdin.take().unwrap().write_all(data).unwrap();
        assert!(child.wait().unwrap().success());
        assert_eq!(native_read(scope), data);
    }
    fn binary(root: &std::path::Path, args: &[&str]) -> std::process::Output {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let output = Command::new(env!("CARGO_BIN_EXE_ubaa"))
            .arg("--config-dir")
            .arg(root)
            .args(args)
            .output()
            .unwrap();
        let mut log = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .mode(0o600)
            .open(root.join("binary.jsonl"))
            .unwrap();
        writeln!(log,"{}",json!({"args":args,"exit":output.status.code(),"stdout":String::from_utf8_lossy(&output.stdout),"stderr":String::from_utf8_lossy(&output.stderr)})).unwrap();
        output
    }
    fn valid(output: &std::process::Output) -> Value {
        assert!(output.stderr.is_empty(), "标准错误应为空");
        let value: Value = serde_json::from_slice(&output.stdout).unwrap();
        let schema: Value =
            serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json"))
                .unwrap();
        let validator = jsonschema::validator_for(&schema).unwrap();
        if let Some(e) = validator.iter_errors(&value).next() {
            panic!("Schema 失败：{e}");
        }
        assert!(value["meta"].get("resolvedRoute").is_none());
        value
    }
    struct Fixture {
        root: std::path::PathBuf,
        scope: String,
        alias: String,
        id: uuid::Uuid,
        index: Value,
        calls: std::sync::Arc<std::sync::atomic::AtomicUsize>,
        before: usize,
        _cleanup: SyntheticMaterial,
    }
    struct SyntheticMaterial(String);
    impl Drop for SyntheticMaterial {
        fn drop(&mut self) {
            let _ = Command::new("/usr/bin/security")
                .args(["delete-generic-password", "-s", SERVICE, "-a", &self.0])
                .output();
        }
    }
    async fn seed() -> Fixture {
        use std::io::Write;
        use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
        let root = root();
        let scope = scope(&root);

        let cleanup = SyntheticMaterial(scope.clone());
        // 创建、更新、重开均由同一真实 CLI 执行，使用系统默认 ACL。
        native_write(&scope, b"\0\r\n\xff\\\"'");
        let anchor = uuid::Uuid::new_v4().simple().to_string();
        let mut lock = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(root.join("cli-accounts.lock"))
            .unwrap();
        lock.write_all(anchor.as_bytes()).unwrap();
        lock.sync_all().unwrap();
        let metadata = std::fs::metadata(&root).unwrap();
        let mut index = json!({"version":1,"anchor":anchor,"directory":format!("{}:{}",metadata.dev(),metadata.ino()),"accounts":{"fixture-a":{"alias":uuid::Uuid::new_v4().simple().to_string(),"cache_key":null}},"active":"fixture-a","epoch":uuid::Uuid::new_v4().simple().to_string()});
        for n in 0..64 {
            index["accounts"][format!("{n:08}")] =
                json!({"alias":uuid::Uuid::new_v4().simple().to_string(),"cache_key":null});
        }
        for id in [
            "fixture\"quote",
            "fixture'quote",
            "fixture\\slash",
            "中文合成账号",
        ] {
            index["accounts"][id] = json!({"alias":uuid::Uuid::new_v4().simple().to_string(),"cache_key":vec![19_u8;32]});
        }
        let encoded = serde_json::to_vec(&index).unwrap();
        assert!(encoded.len() > 4096);
        native_write(&scope, &encoded);
        // 超过既有 1 MiB 读取边界的输入在原生更新前拒绝，旧值完整保留。
        let mut rejected = Command::new(env!("CARGO_BIN_EXE_ubaa"))
            .args(["--internal-keychain-worker", "write", &scope])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        rejected
            .stdin
            .take()
            .unwrap()
            .write_all(&vec![b'x'; 1_048_577])
            .unwrap();
        assert_eq!(rejected.wait().unwrap().code(), Some(7));
        assert_eq!(native_read(&scope), encoded);
        let (mut c, calls) = client(&root, Some("fixture-a"), Some("fixture-a"));
        login(&mut c, "fixture-a").await;
        let before = calls.load(std::sync::atomic::Ordering::SeqCst);
        let alias = index["accounts"]["fixture-a"]["alias"]
            .as_str()
            .unwrap()
            .to_owned();
        let store = AgendaStore::open(&root, &alias).unwrap();
        let item = item("合成本机待办");
        let id = item.id;
        store.create(item).unwrap();
        drop(store);

        std::fs::write(
            root.join("config.toml"),
            b"synthetic invalid school configuration",
        )
        .unwrap();
        std::fs::write(
            root.join("session.json"),
            b"synthetic invalid school session",
        )
        .unwrap();
        Fixture {
            root,
            scope,
            alias,
            id,
            index,
            calls,
            before,
            _cleanup: cleanup,
        }
    }
    fn verify_local(fixture: &Fixture) {
        let root = fixture.root.clone();
        let id = fixture.id;
        let output = binary(&root, &["--json", "agenda", "unsynced"]);
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(valid(&output)["data"]["count"], 1);
        let output = binary(
            &root,
            &["--json", "agenda", "show", "--id", &id.to_string()],
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            valid(&output)["data"]["item"]["content"]["title"],
            "合成本机待办"
        );
        let output = binary(
            &root,
            &[
                "--json",
                "agenda",
                "list",
                "--from",
                "2026-11-01",
                "--to",
                "2026-11-08",
            ],
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            valid(&output)["data"]["entries"].as_array().unwrap().len(),
            1
        );
        let output = binary(&root, &["agenda", "unsynced"]);
        assert!(output.status.success());
        assert!(String::from_utf8(output.stdout).unwrap().contains('1'));
        assert!(output.stderr.is_empty());
    }
    fn verify_cache(fixture: &Fixture) {
        let root = fixture.root.clone();
        let scope = fixture.scope.clone();
        let alias = fixture.alias.clone();
        let mut index = fixture.index.clone();
        let school = [
            "--json",
            "agenda",
            "list",
            "--from",
            "2026-11-01",
            "--to",
            "2026-11-08",
            "--school-cache",
            "--route",
            "direct",
            "--term",
            "fixture-term",
        ];
        let output = binary(&root, &school);
        assert_eq!(output.status.code(), Some(7));
        assert_eq!(valid(&output)["error"]["code"], "cache_key_missing");
        // 只在测试边界添加合成 cacheKey 和已缓存公开载荷，生产没有此写入流水线。
        index["accounts"]["fixture-a"]["cache_key"] = json!(vec![19_u8; 32]);
        native_write(&scope, &serde_json::to_vec(&index).unwrap());
        let output = binary(&root, &school);
        assert_eq!(valid(&output)["error"]["code"], "cache_missing");
        let mut cache = ubaa_core::facade::OfflineRepository::open(
            &root,
            &alias,
            CacheKey::new([19; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        let ticket = cache
            .begin_read(CacheScope {
                route: ConnectionMode::Direct,
                query: CacheQuery::Exams {
                    term: "fixture-term".into(),
                },
            })
            .unwrap();
        cache
            .publish(
                &ticket,
                CachePayload::Exams(ubaa_core::facade::ExamArrangement {
                    arranged: vec![ubaa_core::facade::Exam {
                        course_name: "合成考试".into(),
                        exam_date: Some("2026-11-03".into()),
                        task_id: Some("synthetic-exam".into()),
                        ..Default::default()
                    }],
                    not_arranged: Vec::new(),
                }),
                1,
                ubaa_core::facade::CacheCompleteness::Complete,
            )
            .unwrap();
        drop(cache);
        let output = binary(&root, &school);
        assert_eq!(output.status.code(), Some(0));
        let data = valid(&output);
        assert_eq!(data["data"]["sources"].as_array().unwrap().len(), 8);
        assert!(
            data["data"]["entries"]
                .as_array()
                .unwrap()
                .iter()
                .any(|entry| entry["item"]["origin"] == "school")
        );
        let mut vpn = school.to_vec();
        *vpn.iter_mut().find(|v| **v == "direct").unwrap() = "webvpn";
        let output = binary(&root, &vpn);
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(
            valid(&output)["data"]["entries"].as_array().unwrap().len(),
            1
        );
        assert!(data["data"]["sources"].as_array().unwrap().iter().any(|s| {
            s["observations"]
                .as_array()
                .unwrap()
                .iter()
                .any(|o| o["fresh"] == false)
        }));
        // 坏缓存明确失败，保留已有日程，不降级为本机成功。
        std::fs::write(
            root.join("business-cache").join(format!("{alias}.sqlite")),
            b"broken",
        )
        .unwrap();
        let output = binary(&root, &school);
        assert_eq!(valid(&output)["error"]["code"], "cache_corrupt");
        let output = binary(&root, &["--json", "agenda", "unsynced"]);
        assert_eq!(valid(&output)["data"]["count"], 1);
        assert_eq!(
            fixture.calls.load(std::sync::atomic::Ordering::SeqCst),
            fixture.before
        );
    }
    fn verify_exit(fixture: &Fixture) {
        let root = fixture.root.clone();
        let scope = fixture.scope.clone();
        let mut index = fixture.index.clone();
        index["active"] = Value::Null;
        index["epoch"] = json!(uuid::Uuid::new_v4().simple().to_string());
        native_write(&scope, &serde_json::to_vec(&index).unwrap());
        AgendaStore::open(&root, &fixture.alias)
            .unwrap()
            .deactivate()
            .unwrap();
        let output = binary(&root, &["--json", "agenda", "unsynced"]);
        assert_eq!(output.status.code(), Some(3));
        assert_eq!(valid(&output)["error"]["code"], "registration_required");
        assert!(
            Command::new("/usr/bin/security")
                .args(["delete-generic-password", "-s", SERVICE, "-a", &scope])
                .output()
                .unwrap()
                .status
                .success()
        );
        let output = binary(&root, &["--json", "agenda", "unsynced"]);
        assert_eq!(valid(&output)["error"]["code"], "material_corrupt");
    }
    #[tokio::test]
    async fn 合成_keychain_重开与真实二进制本地只读及缓存路径() {
        let fixture = seed().await;
        verify_local(&fixture);
        verify_cache(&fixture);
        verify_exit(&fixture);
    }
}
