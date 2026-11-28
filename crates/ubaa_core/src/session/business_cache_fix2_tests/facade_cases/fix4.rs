use super::*;
use crate::facade::RouteClient;

pub(super) fn prepared(path: &Path) -> (FileSessionStore, BusinessSessionCache) {
    let store = signed_in(path);
    let observer = cache(path);
    observer.invalidate(Invalidation::RevokeAll).unwrap();
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        write_route(&observer, route);
    }
    (store, observer)
}

#[test]
fn 修复四_同一路线两个读组分别拒绝不同范围() {
    let path = root("two-rejections");
    let (_, owner) = prepared(&path);
    let route = ConnectionMode::Direct;
    let (spoc_stamp, spoc) = owner.seeds(ACCOUNT, route, NOW);
    let (ygdk_stamp, ygdk) = owner.seeds(ACCOUNT, route, NOW);
    for (stamp, seeds, scope) in [
        (spoc_stamp, spoc, BusinessScope::Spoc),
        (ygdk_stamp, ygdk, BusinessScope::Ygdk),
    ] {
        owner.reject(
            ACCOUNT,
            stamp,
            route,
            scope,
            seeds[scope as usize].material.clone().unwrap(),
            true,
        );
        owner.lock().writer.drain();
    }
    let seeds = owner.seeds(ACCOUNT, route, NOW).1;
    assert!(seeds[BusinessScope::Spoc as usize].material.is_none());
    assert!(seeds[BusinessScope::Ygdk as usize].material.is_none());
    let disk = document(&path);
    assert!(disk["routes"]["direct"]["spoc"].is_null());
    assert!(disk["routes"]["direct"]["ygdk"].is_null());
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复四_拒绝不阻止同路线上另一范围已排队的写回() {
    let path = root("reject-and-write");
    let (_, owner) = prepared(&path);
    let route = ConnectionMode::Direct;
    let (stamp, seeds) = owner.seeds(ACCOUNT, route, NOW);
    let old = seeds[BusinessScope::Spoc as usize]
        .material
        .clone()
        .unwrap();
    let (wait, resume) = pause_file_job(&owner);
    owner.reject(ACCOUNT, stamp, route, BusinessScope::Spoc, old, true);
    wait_for_file_job(&wait);
    let updated = BusinessMaterial::Ygdk(YgdkCredential {
        uid: 43,
        token: "fixture-ygdk-next".into(),
    });
    let accepted = owner.write(
        ACCOUNT,
        stamp,
        route,
        vec![(BusinessScope::Ygdk, Some(updated.clone()))],
        NOW,
        || true,
    );
    drop(resume);
    owner.lock().writer.drain();
    assert!(accepted.is_some());
    let disk = document(&path);
    assert!(disk["routes"]["direct"]["spoc"].is_null());
    let reopened = cache(&path);
    let seeds = reopened.seeds(ACCOUNT, route, NOW).1;
    assert!(
        seeds[BusinessScope::Ygdk as usize]
            .material
            .as_ref()
            .is_some_and(|material| material.matches(&updated))
    );
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复四_跨实例拒绝重载时保留本地未提交条目() {
    let path = root("reload-with-pending-write");
    let (_, b) = prepared(&path);
    let a = cache(&path);
    let route = ConnectionMode::Direct;
    let (stamp, _) = a.seeds(ACCOUNT, route, NOW);
    let (wait, resume) = pause_file_job(&a);
    let pending = BusinessMaterial::Identity(StudentKind::Undergraduate);
    a.write(
        ACCOUNT,
        stamp,
        route,
        vec![(BusinessScope::Identity, Some(pending.clone()))],
        NOW,
        || true,
    )
    .unwrap();
    wait_for_file_job(&wait);
    let (stamp, seeds) = b.seeds(ACCOUNT, route, NOW);
    let spoc = BusinessScope::Spoc;
    b.reject(
        ACCOUNT,
        stamp,
        route,
        spoc,
        seeds[spoc as usize].material.clone().unwrap(),
        true,
    );
    b.lock().writer.drain();
    let seeds = a.seeds(ACCOUNT, route, NOW).1;
    drop(resume);
    a.lock().writer.drain();
    assert!(seeds[spoc as usize].material.is_none());
    assert!(crate::session::business_cache::same_material(
        seeds[BusinessScope::Identity as usize].material.as_ref(),
        Some(&pending)
    ));
    std::fs::remove_dir_all(path).unwrap();
}

pub(super) fn block_sidecar_write(path: &Path) {
    let lock = path.join(".business_session.lock");
    std::fs::remove_file(&lock).unwrap();
    std::fs::create_dir(lock).unwrap();
}

fn assert_untrusted_then_recovers(path: &Path, owner: &BusinessSessionCache) {
    std::fs::remove_dir(path.join(".business_session.lock")).unwrap();
    let route = ConnectionMode::Direct;
    let before = document(path);
    let old = material(&cache(path), route).unwrap();
    let (stamp, seeds) = owner.seeds(ACCOUNT, route, NOW);
    let attempted_write = owner.write(
        ACCOUNT,
        stamp,
        route,
        vec![(BusinessScope::Ygdk, None)],
        NOW,
        || true,
    );
    owner.reject(ACCOUNT, stamp, route, BusinessScope::Spoc, old, true);
    owner.lock().writer.drain();
    assert!(
        seeds.iter().all(|seed| seed.material.is_none()),
        "撤销失败后仍播种磁盘材料"
    );
    assert!(attempted_write.is_none());
    assert_eq!(document(path), before);
    // 恢复必须由同一缓存的下一次成功撤销触发。
    owner.invalidate(Invalidation::RevokeAll).unwrap();
    write_route(&cache(path), route);
    assert!(material(owner, route).is_some());
}

#[tokio::test]
async fn 修复四_聚合注销墓碑失败后正常注销并停止使用旁车() {
    let path = root("failed-logout-revocation");
    let (store, _) = prepared(&path);
    let mut client = client(&store, transport(ACCOUNT));
    let owner = client.business_cache_for_test();
    block_sidecar_write(&path);
    client.logout().await.unwrap();
    assert!(store.load_dual_versioned().unwrap().snapshot.is_none());
    assert_untrusted_then_recovers(&path, &owner);
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复四_sso单槽撤销失败后正常清槽并停止使用旁车() {
    let path = root("failed-slot-revocation");
    let (store, owner) = prepared(&path);
    let owner = Arc::new(owner);
    let sessions = DualSessionCoordinator::new(store.clone())
        .unwrap()
        .with_business_cache(&owner);
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        Sso {
            session_expired: true,
            ..transport(ACCOUNT)
        },
        sessions.route_store(ConnectionMode::Direct),
    )
    .unwrap();
    runtime.business_sessions = Some(Arc::clone(&owner));
    block_sidecar_write(&path);
    let error = crate::auth::sso_identity::validate_status(&mut runtime, &mut || {})
        .await
        .unwrap_err();
    assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
    let saved = store.load_dual_versioned().unwrap().snapshot.unwrap();
    assert!(saved.sessions.direct.is_none() && saved.sessions.webvpn.is_some());
    assert_untrusted_then_recovers(&path, &owner);
    std::fs::remove_dir_all(path).unwrap();
}

fn input() -> LoginInput {
    LoginInput {
        username: ACCOUNT.into(),
        password: SecretValue::new("fixture-password"),
    }
}

#[tokio::test]
async fn 修复四_登录轮换失败后正常登录并停止使用旁车() {
    let path = root("failed-login-revocation");
    let (store, owner) = prepared(&path);
    let owner = Arc::new(owner);
    let mut runtime = main_runtime_with_cache(&store, ACCOUNT, Arc::clone(&owner));
    runtime.remember_account_name(Some(ACCOUNT));
    let before = store.load_dual_versioned().unwrap().revision;
    block_sidecar_write(&path);
    let profile = AuthWorkflow::default()
        .login(&mut runtime, input())
        .await
        .unwrap();
    assert_eq!(profile.school_id.as_deref(), Some(ACCOUNT));
    assert!(store.load_dual_versioned().unwrap().revision > before);
    assert_untrusted_then_recovers(&path, &owner);
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复四_固定路线远端注销取消前已撤销目标路线() {
    let path = root("route-logout-cancel");
    let (store, _) = prepared(&path);
    let before = document(&path);
    let entered = Arc::new(tokio::sync::Notify::new());
    let mut client = RouteClient::with_coordinated_transport_for_test(
        ConnectionMode::Direct,
        Sso {
            logout_entered: Some(Arc::clone(&entered)),
            ..transport(ACCOUNT)
        },
        store,
    )
    .unwrap();
    {
        let request = std::pin::pin!(client.logout());
        tokio::select! {
            result = request => panic!("注销不应先结束：{result:?}"),
            result = tokio::time::timeout(crate::test_timeout::TEST_HANG_TIMEOUT, entered.notified()) => result.unwrap(),
        }
    }
    let after = document(&path);
    assert!(
        after["routes"]["direct"]
            .as_object()
            .is_none_or(serde_json::Map::is_empty)
    );
    assert_ne!(
        after["clear_nonces"]["direct"],
        before["clear_nonces"]["direct"]
    );
    assert_eq!(after["routes"]["webvpn"], before["routes"]["webvpn"]);
    assert_eq!(
        after["clear_nonces"]["webvpn"],
        before["clear_nonces"]["webvpn"]
    );
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复四_固定路线登录轮换未知和同账号的撤销令牌() {
    for same_account in [false, true] {
        let path = root("route-login-revocation");
        let (store, _) = prepared(&path);
        let before = document(&path);
        let mut client = RouteClient::with_coordinated_transport_for_test(
            ConnectionMode::Direct,
            transport(ACCOUNT),
            store,
        )
        .unwrap();
        if same_account {
            assert_eq!(
                client
                    .auth_status()
                    .await
                    .unwrap()
                    .user
                    .school_id
                    .as_deref(),
                Some(ACCOUNT)
            );
        }
        client.login(input()).await.unwrap();
        let after = document(&path);
        assert!(
            after["routes"]["direct"]
                .as_object()
                .is_none_or(serde_json::Map::is_empty)
        );
        assert_ne!(
            after["clear_nonces"]["direct"],
            before["clear_nonces"]["direct"]
        );
        assert!(material(&cache(&path), ConnectionMode::Direct).is_none());
        assert_eq!(
            material(&cache(&path), ConnectionMode::WebVpn).is_some(),
            same_account
        );
        assert_eq!(
            after["clear_nonces"]["webvpn"] == before["clear_nonces"]["webvpn"],
            same_account
        );
        std::fs::remove_dir_all(path).unwrap();
    }
}

#[tokio::test]
async fn 修复四_登录准备已保存核验结果时即轮换令牌() {
    let path = root("prepare-login-revocation");
    let (store, owner) = prepared(&path);
    let mut runtime = main_runtime_with_cache(&store, ACCOUNT, Arc::new(owner));
    runtime.remember_account_name(Some(ACCOUNT));
    let mut auth = AuthWorkflow::default();
    let before = document(&path);
    auth.prepare_login(&mut runtime).await.unwrap();
    let after = document(&path);
    assert_ne!(
        after["clear_nonces"]["direct"],
        before["clear_nonces"]["direct"]
    );
    assert_eq!(
        after["clear_nonces"]["webvpn"],
        before["clear_nonces"]["webvpn"]
    );
    auth.login(&mut runtime, input()).await.unwrap();
    assert_eq!(after, document(&path));
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复四_路线策略重开保留旁车不可信状态() {
    let path = root("reopen-untrusted-sidecar");
    let (_store, _) = prepared(&path);
    let mut client = crate::facade::UbaaClient::open(&path).unwrap();
    block_sidecar_write(&path);
    client
        .set_default_route_policy(crate::domain::RoutePolicy::Direct)
        .unwrap();
    std::fs::remove_dir(path.join(".business_session.lock")).unwrap();
    let reopened = client.reopen_for_route_policy().unwrap();
    let cache = reopened.business_cache_for_test();
    assert!(material(&cache, ConnectionMode::Direct).is_none());
    std::fs::remove_dir_all(path).unwrap();
}
