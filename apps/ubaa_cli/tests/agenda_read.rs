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
    use super::*;
    use crate::support::*;
    use serde_json::{Value, json};
    use sha2::{Digest, Sha256};
    use std::process::Command;
    use ubaa_cli::local_agenda::AgendaAccess;
    use ubaa_core::facade::{
        AgendaStore, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope, ConnectionMode,
    };
    const SERVICE: &str = "cn.edu.ubaa.cli.local-accounts.v1";
    fn scope(root: &std::path::Path) -> String {
        format!("{:x}", Sha256::digest(root.as_os_str().as_encoded_bytes()))
    }
    fn native_read(scope: &str) -> Vec<u8> {
        let output = Command::new("/usr/bin/security")
            .args(["find-generic-password", "-s", SERVICE, "-a", scope, "-w"])
            .output()
            .unwrap();
        assert!(output.status.success());
        let mut data = output.stdout;
        if data.last() == Some(&b'\n') {
            data.pop();
        }
        data
    }
    fn native_write(scope: &str, data: &[u8]) {
        use std::io::Write;
        let command = format!(
            "add-generic-password -U -s '{}' -a '{}' -w '{}'\n",
            SERVICE,
            scope,
            std::str::from_utf8(data).unwrap().replace('\'', "'\\''")
        );
        let mut child = Command::new("/usr/bin/security")
            .args(["-q", "-i"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(command.as_bytes())
            .unwrap();
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
    }
    async fn seed() -> Fixture {
        let root = root();
        let scope = scope(&root);

        let mut access = AgendaAccess::open(&root).unwrap();
        access.revoke().unwrap();
        let (mut c, calls) = client(&root, Some("fixture-a"), Some("fixture-a"));
        assert!(c.take_verified_login_identity().is_err());
        let _ = login(&mut c, "fixture-a").await;
        let cli = Cli::try_parse_from([
            "ubaa",
            "--json",
            "auth",
            "login",
            "--username",
            "fixture-a",
            "--password-stdin",
        ])
        .unwrap();
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        assert_eq!(
            ubaa_cli::run_dual_login_with_agenda(
                cli,
                &mut c,
                &mut std::io::Cursor::new(b"synthetic-only\n"),
                &mut stdout,
                &mut stderr,
                &mut access
            )
            .await,
            0
        );
        let output: Value = serde_json::from_slice(&stdout).unwrap();
        assert_eq!(output["agendaRegistration"]["state"], "ready");
        let schema: Value =
            serde_json::from_str(include_str!("../../../docs/contracts/cli-json.schema.json"))
                .unwrap();
        assert!(
            jsonschema::validator_for(&schema)
                .unwrap()
                .is_valid(&output)
        );
        let current = native_read(&scope);
        let before = calls.load(std::sync::atomic::Ordering::SeqCst);
        // 仅检查本测试刚创建的隔离命名空间，不读取用户历史材料。
        let index: Value = serde_json::from_slice(&current).unwrap();
        let alias = index["accounts"]["fixture-a"]["alias"]
            .as_str()
            .unwrap()
            .to_owned();
        let store = AgendaStore::open(&root, &alias).unwrap();
        let item = item("合成本机待办");
        let id = item.id;
        store.create(item).unwrap();
        drop(store);
        drop(access);
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
        let mut access = AgendaAccess::open(&root).unwrap();
        access.revoke().unwrap();
        drop(access);
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
