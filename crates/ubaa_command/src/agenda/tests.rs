use super::*;
use crate::{CommandControl, parse, prepare_input};
use std::{io::Cursor, path::PathBuf};
use ubaa_core::facade::{AgendaStore, SharedAccountGuard};

struct Fixture {
    root: PathBuf,
    store: AgendaStore,
    scope: SharedAccountGuard,
}
impl Fixture {
    fn new() -> Self {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/command_delivery/tests")
            .join(uuid::Uuid::new_v4().to_string());
        std::fs::create_dir_all(root.join("data")).unwrap();
        for (name, value) in [
            ("materials.lock", ""),
            ("transaction.v1", "UBAA1:C"),
            ("account-generation.v1", "UBAA1:1"),
        ] {
            std::fs::write(root.join(name), value).unwrap();
        }
        let scope = SharedAccountGuard::new(&root, 1).unwrap();
        let store = AgendaStore::open_shared(
            &root.join("data"),
            "0123456789abcdef0123456789abcdef",
            scope.clone(),
        )
        .unwrap();
        Self { root, store, scope }
    }
    fn run(&self, args: &[&str], input: &str) -> (i32, serde_json::Value, String) {
        let mut command_line = vec!["ubaa", "--json", "agenda"];
        command_line.extend(args);
        let control = CommandControl::default();
        let prepared = prepare_input(
            parse(command_line).unwrap(),
            &mut Cursor::new(input.as_bytes()),
            &control,
        )
        .unwrap();
        let result =
            execute_shared_agenda(&prepared, &self.store, None, self.scope.clone(), &control);
        let (mut out, mut err) = (vec![], vec![]);
        let code = result.render(true, &control, &mut out, &mut err);
        (
            code,
            serde_json::from_slice(&out).unwrap(),
            String::from_utf8(err).unwrap(),
        )
    }
}
impl Fixture {
    fn finish(self) {
        let Self { root, store, scope } = self;
        drop((store, scope));
        std::fs::remove_dir_all(root).unwrap();
    }
}
const DRAFT: &str = r#"{"kind":"event","title":"合成重复事项","start":"2026-12-01T09:00:00+08:00","end":"2026-12-01T10:00:00+08:00","rrule":"FREQ=DAILY;COUNT=3"}"#;

#[test]
fn 默认清除先交付当前未同步数量并拒绝修改() {
    let fixture = Fixture::new();
    assert_eq!(
        fixture
            .run(&["create", "--input", "-", "--confirm-local-write"], DRAFT)
            .0,
        0
    );
    let (code, value, diagnostic) = fixture.run(&["clear"], "");
    assert_eq!(code, 2);
    assert_eq!(value["ok"], false);
    assert!(diagnostic.contains("1 条"));
    assert_eq!(fixture.store.unsynced_count().unwrap(), 1);
    fixture.finish();
}

#[test]
fn 共享日程重复编辑完成覆盖与数量比较清除() {
    let fixture = Fixture::new();
    let (code, value, _) = fixture.run(&["create", "--input", "-", "--confirm-local-write"], DRAFT);
    assert_eq!(code, 0);
    let id = value["data"]["item"]["id"].as_str().unwrap();
    let modified = DRAFT.replace("合成重复事项", "后续事项");
    let (code, value, _) = fixture.run(
        &[
            "edit",
            "--id",
            id,
            "--scope",
            "this-and-future",
            "--at",
            "2026-12-02T09:00:00+08:00",
            "--input",
            "-",
            "--confirm-local-write",
        ],
        &modified,
    );
    assert_eq!(code, 0);
    assert!(value["data"]["successorId"].is_string());
    let (code, _, _) = fixture.run(
        &[
            "complete",
            "--id",
            id,
            "--at",
            "2026-12-01T09:00:00+08:00",
            "--confirm-local-write",
        ],
        "",
    );
    assert_eq!(code, 0);
    let (code, _, _) = fixture.run(
        &[
            "reopen",
            "--id",
            id,
            "--at",
            "2026-12-01T09:00:00+08:00",
            "--confirm-local-write",
        ],
        "",
    );
    assert_eq!(code, 0);
    let (code, _, _) = fixture.run(
        &[
            "overlay",
            "set",
            "--source",
            "exam",
            "--upstream-id",
            "synthetic-1",
            "--completion",
            "reopen",
            "--hidden",
            "true",
            "--confirm-local-write",
        ],
        "",
    );
    assert_eq!(code, 0);
    assert_eq!(fixture.store.unsynced_count().unwrap(), 3);
    let (code, _, _) = fixture.run(
        &["clear", "--expected-unsynced", "2", "--confirm-local-write"],
        "",
    );
    assert_eq!(code, 2);
    assert_eq!(fixture.store.unsynced_count().unwrap(), 3);
    let (code, value, _) = fixture.run(
        &["clear", "--expected-unsynced", "3", "--confirm-local-write"],
        "",
    );
    assert_eq!(code, 0);
    assert_eq!(value["data"]["clearedUnsynced"], 3);
    fixture.finish();
}

#[test]
fn 导出文件默认保留原件且明确覆盖才交付_ics() {
    let fixture = Fixture::new();
    assert_eq!(
        fixture
            .run(&["create", "--input", "-", "--confirm-local-write"], DRAFT)
            .0,
        0
    );
    let path = fixture.root.join("范围.ics");
    std::fs::write(&path, "原文件").unwrap();
    let args = [
        "export",
        "--from",
        "2026-12-01",
        "--to",
        "2026-12-04",
        "--output",
        path.to_str().unwrap(),
    ];
    assert_eq!(fixture.run(&args, "").0, 7);
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "原文件");
    let mut overwrite = args.to_vec();
    overwrite.push("--overwrite");
    let (code, value, _) = fixture.run(&overwrite, "");
    assert_eq!(code, 0);
    assert_eq!(value["data"]["delivery"], "file");
    assert_eq!(value["data"]["exportedCount"], 3);
    let text = std::fs::read_to_string(&path).unwrap();
    assert!(text.starts_with("BEGIN:VCALENDAR\r\n"));
    assert!(
        parse([
            "ubaa",
            "--json",
            "agenda",
            "export",
            "--from",
            "2026-12-01",
            "--to",
            "2026-12-04",
            "--stdout"
        ])
        .is_err()
    );
    fixture.finish();
}

#[test]
fn 编辑拒绝内部例外映射且撤销后不交付旧正文() {
    let fixture = Fixture::new();
    let (_, created, _) = fixture.run(&["create", "--input", "-", "--confirm-local-write"], DRAFT);
    let id = created["data"]["item"]["id"].as_str().unwrap();
    let with_internal = DRAFT.trim_end_matches('}').to_owned() + ",\"overrides\":{}}";
    assert!(
        prepare_input(
            parse([
                "ubaa",
                "--json",
                "agenda",
                "edit",
                "--id",
                id,
                "--scope",
                "all",
                "--input",
                "-",
                "--confirm-local-write"
            ])
            .unwrap(),
            &mut Cursor::new(with_internal.as_bytes()),
            &CommandControl::default(),
        )
        .is_err()
    );
    let control = CommandControl::default();
    let prepared = prepare_input(
        parse(["ubaa", "--json", "agenda", "show", "--id", id]).unwrap(),
        &mut Cursor::new([]),
        &control,
    )
    .unwrap();
    let result = execute_shared_agenda(
        &prepared,
        &fixture.store,
        None,
        fixture.scope.clone(),
        &control,
    );
    std::fs::write(fixture.root.join("account-generation.v1"), "UBAA1:2").unwrap();
    let (mut out, mut err) = (vec![], vec![]);
    assert_eq!(result.render(true, &control, &mut out, &mut err), 3);
    let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(value["ok"], false);
    assert!(value.get("data").is_none());
    assert!(value["meta"].get("resolvedRoute").is_none());
    fixture.finish();
}

#[test]
fn 本机取消与期限均保留_v13_storage退出码() {
    let fixture = Fixture::new();
    for deadline in [false, true] {
        let active = CommandControl::default();
        let input = prepare_input(
            parse(["ubaa", "--json", "agenda", "unsynced"]).unwrap(),
            &mut Cursor::new([]),
            &active,
        )
        .unwrap();
        let control = CommandControl::new(
            std::time::Instant::now(),
            if deadline {
                std::time::Duration::ZERO
            } else {
                std::time::Duration::from_mins(2)
            },
        );
        if !deadline {
            control.cancel();
        }
        let result = execute_shared_agenda(
            &input,
            &fixture.store,
            None,
            fixture.scope.clone(),
            &control,
        );
        let (mut out, mut err) = (vec![], vec![]);
        assert_eq!(result.render(true, &control, &mut out, &mut err), 7);
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["error"]["code"], "storage");
        assert_eq!(value["schemaVersion"], 13);
    }
    fixture.finish();
}

#[test]
fn 命令编辑复用完整草稿并平移未改排除日期() {
    let fixture = Fixture::new();
    let original = DRAFT.replace("}", ",\"exdates\":[\"2026-12-02T09:00:00+08:00\"]}");
    let (_, value, _) = fixture.run(
        &["create", "--input", "-", "--confirm-local-write"],
        &original,
    );
    let id = value["data"]["item"]["id"].as_str().unwrap();
    let changed = original
        .replace("2026-12-01T09", "2026-12-01T11")
        .replace("2026-12-01T10", "2026-12-01T12");
    let (code, value, _) = fixture.run(
        &[
            "edit",
            "--id",
            id,
            "--scope",
            "all",
            "--input",
            "-",
            "--confirm-local-write",
        ],
        &changed,
    );
    assert_eq!(code, 0);
    assert_eq!(
        value["data"]["item"]["exdates"][0]["datetime"],
        "2026-12-02T11:00:00+08:00"
    );
    fixture.finish();
}

#[test]
fn 云盘写入缺少确认时不读取密码或账号材料() {
    let plan = parse([
        "ubaa",
        "bhpan",
        "share",
        "save",
        "synthetic-share",
        "/",
        "/",
        "--password-stdin",
    ])
    .unwrap();
    let mut input = Cursor::new(b"fixture-password\n");
    assert!(prepare_input(plan, &mut input, &CommandControl::default()).is_err());
    assert_eq!(input.position(), 0);
}
