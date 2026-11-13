use super::{pending::SyncAttempt, tests::root};
use crate::{
    agenda::{
        AgendaStore,
        tests::{ACCOUNT, event},
    },
    cache::CacheError,
};
use std::{
    io::{BufRead, BufReader, Read, Write},
    process::{Child, ChildStdout, Command, Stdio},
};

#[test]
fn publication_child() {
    let Some(root) = std::env::var_os("UBAA_AGENDA_PUBLICATION_ROOT") else {
        return;
    };
    let store = AgendaStore::open(std::path::Path::new(&root), ACCOUNT).unwrap();
    let mut snapshot = store.sync_snapshot().unwrap();
    println!("准备竞争");
    std::io::stdout().flush().unwrap();
    let mut release = String::new();
    std::io::stdin().read_line(&mut release).unwrap();
    assert_eq!(release.trim(), "发送");
    match store.begin_sync_attempt(&mut snapshot, SyncAttempt::Publication) {
        Ok(_) => println!(
            "分配:{}:{}",
            snapshot.device_id,
            snapshot.publication.unwrap()
        ),
        Err(CacheError::Superseded) => println!("已有在途"),
        result => panic!("意外的分配结果：{result:?}"),
    }
}

struct Consumer {
    child: Child,
    output: BufReader<ChildStdout>,
}
fn start(root: &std::path::Path) -> Consumer {
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "agenda::sync::process_tests::publication_child",
            "--nocapture",
        ])
        .env("UBAA_AGENDA_PUBLICATION_ROOT", root)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut output = BufReader::new(child.stdout.take().unwrap());
    loop {
        let mut line = String::new();
        assert!(
            output.read_line(&mut line).unwrap() > 0,
            "子进程未到达竞争屏障"
        );
        if line.trim_end().ends_with("准备竞争") {
            break;
        }
    }
    Consumer { child, output }
}

#[test]
fn two_processes_allocate_only_one_durable_publication_and_clear_keeps_the_limit() {
    let root = root();
    let store = AgendaStore::open(&root, ACCOUNT).unwrap();
    store.create(event()).unwrap();
    let device = store.sync_snapshot().unwrap().device_id;
    let mut first = start(&root);
    let mut second = start(&root);
    for consumer in [&mut first, &mut second] {
        consumer
            .child
            .stdin
            .as_mut()
            .unwrap()
            .write_all("发送\n".as_bytes())
            .unwrap();
        consumer.child.stdin.as_mut().unwrap().flush().unwrap();
    }
    let mut outputs = String::new();
    for consumer in [&mut first, &mut second] {
        consumer.output.read_to_string(&mut outputs).unwrap();
        assert!(consumer.child.wait().unwrap().success());
    }
    assert_eq!(outputs.matches(&format!("分配:{device}:1")).count(), 1);
    assert_eq!(outputs.matches("已有在途").count(), 1);
    store.clear_local_data().unwrap();
    let reopened = AgendaStore::open(&root, ACCOUNT).unwrap();
    let restored = reopened.restore_sync_attempt().unwrap().unwrap();
    assert_eq!(restored.snapshot.device_id, device);
    assert_eq!(restored.snapshot.publication, Some(1));
    assert!(!restored.retains_body());
    let mut next = reopened.sync_snapshot().unwrap();
    assert!(matches!(
        reopened.begin_sync_attempt(&mut next, SyncAttempt::Publication),
        Err(CacheError::Superseded)
    ));
    let db =
        rusqlite::Connection::open(root.join("agenda").join(format!("{ACCOUNT}.sqlite"))).unwrap();
    assert_eq!(
        db.query_row::<i64, _, _>("SELECT next_publication FROM agenda_sync_meta", [], |r| r
            .get(0))
            .unwrap(),
        2
    );
}

#[test]
fn delayed_process_publication_preserves_another_process_completed_deletion() {
    let path = root();
    let store = AgendaStore::open(&path, ACCOUNT).unwrap();
    let item = event();
    let id = item.id;
    store.create(item).unwrap();
    let mut held = start(&path);
    store
        .delete(
            id,
            crate::domain::agenda::AgendaEditScope::All,
            None,
            crate::agenda::tests::t("2026-03-01T00:00:00+08:00"),
        )
        .unwrap();
    let mut newer = store.sync_snapshot().unwrap();
    store
        .begin_sync_attempt(&mut newer, SyncAttempt::Publication)
        .unwrap();
    store.confirm_sync(&newer, newer.document()).unwrap();
    held.child
        .stdin
        .as_mut()
        .unwrap()
        .write_all("发送\n".as_bytes())
        .unwrap();
    held.child.stdin.as_mut().unwrap().flush().unwrap();
    let mut output = String::new();
    held.output.read_to_string(&mut output).unwrap();
    assert!(held.child.wait().unwrap().success());
    let accepted = store.restore_sync_attempt().unwrap().unwrap();
    assert!(accepted.snapshot.publication > newer.publication);
    let document = accepted.snapshot.document();
    assert!(
        document.item_deletions.iter().any(|v| v.id == id),
        "较高发布序号须包含另一进程已确认的删除"
    );
    assert!(document.items.iter().all(|v| v.item.id != id));
    let replica = AgendaStore::open(&root(), ACCOUNT).unwrap();
    let scope = replica.sync_snapshot().unwrap();
    replica.merge_sync(&scope, document).unwrap();
    assert_eq!(replica.sync_snapshot().unwrap().document().items.len(), 0);
    assert!(
        replica
            .sync_snapshot()
            .unwrap()
            .document()
            .item_deletions
            .iter()
            .any(|v| v.id == id)
    );
}
