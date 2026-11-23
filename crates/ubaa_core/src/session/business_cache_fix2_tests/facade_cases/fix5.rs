use super::fix4::{block_sidecar_write, prepared};
use super::*;
use crate::session::file_store::try_file_lock;
use std::{fs::OpenOptions, sync::mpsc, time::Duration};

fn assert_main_session_locked(path: &Path) {
    let probe = OpenOptions::new()
        .read(true)
        .write(true)
        .open(path.join(".session.lock"))
        .unwrap();
    assert!(
        !try_file_lock(&probe).expect("无法非阻塞探测主会话锁"),
        "旁车轮换入口未持有主会话锁"
    );
}

fn assert_pending_direct_is_revoked(reopen: bool, retry_fails: bool, final_route: ConnectionMode) {
    let path = root("pending-route-revocation");
    let (_, owner) = prepared(&path);
    let direct = ConnectionMode::Direct;
    let webvpn = ConnectionMode::WebVpn;
    let before = document(&path);
    block_sidecar_write(&path);
    assert!(
        owner
            .invalidate(Invalidation::SameAccountLogin(direct))
            .is_err()
    );
    assert!(material(&owner, direct).is_none());
    let reopened = cache(&path);
    let owner = if reopen {
        reopened.inherit_revocation_failure(&owner);
        &reopened
    } else {
        &owner
    };
    if retry_fails {
        assert!(
            owner
                .invalidate(Invalidation::SameAccountLogin(webvpn))
                .is_err()
        );
        assert_eq!(document(&path), before);
    }
    std::fs::remove_dir(path.join(".business_session.lock")).unwrap();
    if retry_fails {
        assert!(material(owner, direct).is_none());
        assert!(material(owner, webvpn).is_none());
    }
    owner
        .invalidate(Invalidation::SameAccountLogin(final_route))
        .unwrap();
    let after = document(&path);
    assert!(material(owner, direct).is_none(), "Direct 撤销尚未补完");
    assert!(material(&cache(&path), direct).is_none());
    for route in ["direct", "webvpn"] {
        assert_ne!(
            after["clear_nonces"][route], before["clear_nonces"][route],
            "从 {final_route:?} 补撤销后，{route} 撤销令牌未轮换"
        );
    }
    write_route(&cache(&path), direct);
    assert!(material(owner, direct).is_some());
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复五_webvpn撤销成功时补完direct撤销() {
    assert_pending_direct_is_revoked(false, false, ConnectionMode::WebVpn);
}

#[test]
fn 修复五_补撤销失败时重开仍保留待撤销路线() {
    for final_route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        assert_pending_direct_is_revoked(true, true, final_route);
    }
}

#[tokio::test]
async fn 修复五_轮换完成前另一实例看不到新主会话() {
    let path = root("revoke-before-main-session-publish");
    let (store, cache) = prepared(&path);
    let cache = Arc::new(cache);
    let mut runtime = main_runtime_with_cache(&store, ACCOUNT, Arc::clone(&cache));
    let (arrived, wait) = mpsc::channel();
    let (resume, paused) = mpsc::channel();
    cache.lock().before_revocation = Some(Box::new(move || {
        arrived.send(()).unwrap();
        let _ = paused.recv();
    }));
    let session_file = path.join("session.json");
    let before = std::fs::read(&session_file).unwrap();
    let old_revision = store.load_dual_versioned().unwrap().revision;
    let observing_path = path.to_path_buf();
    let observer = std::thread::spawn(move || {
        wait.recv_timeout(Duration::from_secs(5)).unwrap();
        let visible = std::fs::read(&session_file).unwrap();
        assert_main_session_locked(&observing_path);
        resume.send(()).unwrap();
        let other = FileSessionStore::new(observing_path).unwrap();
        (visible, other.load_dual_versioned().unwrap().revision)
    });
    let mut auth = AuthWorkflow::default();
    auth.prepare_login(&mut runtime).await.unwrap();
    let (visible, observed_revision) = observer.join().unwrap();
    assert!(visible == before, "旁车轮换前已发布新主会话");
    assert!(observed_revision > old_revision);
    assert!(material(&cache, ConnectionMode::Direct).is_none());
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复五_无快照登录准备遇到修订冲突时旁车字节不变() {
    let path = root("revoke-without-snapshot-conflict");
    let (store, owner) = prepared(&path);
    let owner = Arc::new(owner);
    let mut runtime = main_runtime_with_cache(&store, ACCOUNT, Arc::clone(&owner));
    AuthWorkflow::default()
        .prepare_login(&mut runtime)
        .await
        .unwrap();
    let other = FileSessionStore::new(&path).unwrap();
    let old_revision = other.load_dual_versioned().unwrap().revision;
    let probe_path = path.to_path_buf();
    let (arrived, wait) = mpsc::channel();
    owner.lock().before_revocation = Some(Box::new(move || {
        assert_main_session_locked(&probe_path);
        arrived.send(()).unwrap();
    }));
    AuthWorkflow::default()
        .prepare_login(&mut runtime)
        .await
        .unwrap();
    wait.try_recv().expect("无快照登录准备未进入旁车轮换");
    assert_eq!(other.load_dual_versioned().unwrap().revision, old_revision);

    let new_owner_path = path.to_path_buf();
    let (published, new_sidecar) = mpsc::channel();
    runtime.before_login_revocation = Some(Box::new(move || {
        let snapshot = other.load_dual_versioned().unwrap().snapshot.unwrap();
        other.save_dual(&snapshot).unwrap();
        let new_owner = cache(&new_owner_path);
        new_owner.invalidate(Invalidation::RevokeAll).unwrap();
        write_route(&new_owner, ConnectionMode::Direct);
        published
            .send(std::fs::read(new_owner_path.join("business_session.json")).unwrap())
            .unwrap();
    }));
    let result = AuthWorkflow::default().prepare_login(&mut runtime).await;
    let expected = new_sidecar.recv_timeout(Duration::from_secs(1)).unwrap();
    assert!(std::fs::read(path.join("business_session.json")).unwrap() == expected);
    assert!(result.unwrap_err().is_session_conflict());
    assert_eq!(
        store.load_dual_versioned().unwrap().revision,
        old_revision + 1
    );
    std::fs::remove_dir_all(path).unwrap();
}
