use super::{BusinessMaterial, BusinessScope, BusinessSessionCache, Invalidation};
use crate::domain::ConnectionMode;
use crate::internal::route_state::{SpocCredential, StudentKind, YgdkCredential};
use crate::session::FileSessionStore;
use std::path::Path;

const ACCOUNT: &str = "fixture-user";
const NOW: i64 = 1_700_000_000;

#[path = "business_cache_fix2_tests.rs"]
mod fix2;

fn pause_file_job(
    cache: &BusinessSessionCache,
) -> (std::sync::mpsc::Receiver<()>, std::sync::mpsc::Sender<()>) {
    let (arrived, wait) = std::sync::mpsc::channel();
    let (resume, paused) = std::sync::mpsc::channel();
    cache.lock().before_file_job = Some(Box::new(move || {
        arrived.send(()).unwrap();
        let _ = paused.recv();
    }));
    (wait, resume)
}

fn wait_for_file_job(wait: &std::sync::mpsc::Receiver<()>) {
    wait.recv_timeout(std::time::Duration::from_secs(5))
        .expect("任务必须在取得旁车锁之前到达同步点");
}

fn root(_name: &str) -> crate::test_tmp::TestTempDir {
    crate::test_tmp::test_temp_dir("ubaa_core_business_cache").unwrap()
}

fn cache(path: &Path) -> BusinessSessionCache {
    BusinessSessionCache::new(&FileSessionStore::new(path).unwrap())
}

fn materials() -> Vec<(BusinessScope, Option<BusinessMaterial>)> {
    vec![
        (
            BusinessScope::Identity,
            Some(BusinessMaterial::Identity(StudentKind::Graduate)),
        ),
        (
            BusinessScope::Spoc,
            Some(BusinessMaterial::Spoc(SpocCredential::new(
                "fixture-spoc".into(),
                "01".into(),
            ))),
        ),
        (
            BusinessScope::Ygdk,
            Some(BusinessMaterial::Ygdk(YgdkCredential {
                uid: 42,
                token: "fixture-ygdk".into(),
            })),
        ),
    ]
}

fn write_materials(path: &Path, saved_at: i64) {
    let cache = cache(path);
    let (generation, _) = cache.seeds(ACCOUNT, ConnectionMode::Direct, saved_at);
    cache
        .write(
            ACCOUNT,
            generation,
            ConnectionMode::Direct,
            materials(),
            saved_at,
            || true,
        )
        .unwrap();
    drop(cache);
}

#[test]
fn 重开旁车按账号和路线恢复对应材料() {
    let path = root("restore");
    write_materials(&path, NOW);
    let reopened = cache(&path);
    let (_, seeds) = reopened.seeds(ACCOUNT, ConnectionMode::Direct, NOW + 1);
    assert!(matches!(
        seeds[BusinessScope::Identity as usize].material,
        Some(BusinessMaterial::Identity(StudentKind::Graduate))
    ));
    assert!(matches!(
        seeds[BusinessScope::Spoc as usize].material,
        Some(BusinessMaterial::Spoc(ref value)) if value.role == "01"
    ));
    assert!(matches!(
        seeds[BusinessScope::Ygdk as usize].material,
        Some(BusinessMaterial::Ygdk(ref value)) if value.uid == 42
    ));
    let (_, other_route) = reopened.seeds(ACCOUNT, ConnectionMode::WebVpn, NOW + 1);
    assert!(other_route.iter().all(|seed| seed.material.is_none()));
    let (_, other_account) = reopened.seeds("fixture-other", ConnectionMode::Direct, NOW + 1);
    assert!(other_account.iter().all(|seed| seed.material.is_none()));
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 三种材料按各自期限读取() {
    let path = root("ttl");
    write_materials(&path, NOW);
    let reopened = cache(&path);
    for (scope, ttl) in [
        (BusinessScope::Spoc, 3 * 60 * 60),
        (BusinessScope::Ygdk, 12 * 60 * 60),
        (BusinessScope::Identity, 7 * 24 * 60 * 60),
    ] {
        let (_, seeds) = reopened.seeds(ACCOUNT, ConnectionMode::Direct, NOW + ttl);
        assert!(seeds[scope as usize].material.is_some());
        let (_, seeds) = reopened.seeds(ACCOUNT, ConnectionMode::Direct, NOW + ttl + 1);
        assert!(seeds[scope as usize].material.is_none());
    }
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 迟到拒绝只删除仍匹配的材料() {
    let path = root("reject");
    write_materials(&path, NOW);
    let reader = cache(&path);
    let (generation, seeds) = reader.seeds(ACCOUNT, ConnectionMode::Direct, NOW);
    let old_spoc = seeds[BusinessScope::Spoc as usize]
        .material
        .clone()
        .unwrap();
    let old_ygdk = seeds[BusinessScope::Ygdk as usize]
        .material
        .clone()
        .unwrap();
    let renewed_spoc = BusinessMaterial::Spoc(SpocCredential::new(
        "fixture-spoc-renewed".into(),
        "01".into(),
    ));
    let renewed_ygdk = BusinessMaterial::Ygdk(YgdkCredential {
        uid: 42,
        token: "fixture-ygdk-renewed".into(),
    });

    // 另一读组更新同进程的 SPOC 条目；独立缓存实例更新磁盘上的阳光打卡条目。
    reader
        .write(
            ACCOUNT,
            generation,
            ConnectionMode::Direct,
            vec![(BusinessScope::Spoc, Some(renewed_spoc.clone()))],
            NOW + 1,
            || true,
        )
        .unwrap();
    reader.lock().writer.drain();
    let peer = cache(&path);
    let (peer_generation, _) = peer.seeds(ACCOUNT, ConnectionMode::Direct, NOW + 1);
    peer.write(
        ACCOUNT,
        peer_generation,
        ConnectionMode::Direct,
        vec![(BusinessScope::Ygdk, Some(renewed_ygdk.clone()))],
        NOW + 2,
        || true,
    )
    .unwrap();
    drop(peer);

    for (scope, rejected) in [
        (BusinessScope::Spoc, old_spoc),
        (BusinessScope::Ygdk, old_ygdk),
    ] {
        assert!(reader.reject(
            ACCOUNT,
            generation,
            ConnectionMode::Direct,
            scope,
            rejected,
            true
        ));
    }
    let (_, seeds) = reader.seeds(ACCOUNT, ConnectionMode::Direct, NOW + 3);
    assert!(
        seeds[BusinessScope::Spoc as usize]
            .material
            .as_ref()
            .is_some_and(|value| value.matches(&renewed_spoc))
    );
    assert!(
        seeds[BusinessScope::Ygdk as usize]
            .material
            .as_ref()
            .is_some_and(|material| material.matches(&renewed_ygdk))
    );
    drop(reader);

    let (_, seeds) = cache(&path).seeds(ACCOUNT, ConnectionMode::Direct, NOW + 3);
    for (scope, renewed) in [
        (BusinessScope::Spoc, renewed_spoc),
        (BusinessScope::Ygdk, renewed_ygdk),
    ] {
        assert!(
            seeds[scope as usize]
                .material
                .as_ref()
                .is_some_and(|value| value.matches(&renewed))
        );
    }
    assert!(seeds[BusinessScope::Identity as usize].material.is_some());
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 第二阶段整体清理删除新业务范围() {
    let path = root("clear");
    write_materials(&path, NOW);
    let cache = cache(&path);
    cache
        .invalidate(Invalidation::SameAccountLogin(ConnectionMode::Direct))
        .unwrap();
    let (_, seeds) = cache.seeds(ACCOUNT, ConnectionMode::Direct, NOW + 1);
    assert!(seeds.iter().all(|seed| seed.material.is_none()));
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 业务令牌调试输出隐藏() {
    let value =
        BusinessMaterial::Spoc(SpocCredential::new("spoc-debug-secret".into(), "01".into()));
    let ygdk = BusinessMaterial::Ygdk(YgdkCredential {
        uid: 42,
        token: "ygdk-debug-secret".into(),
    });
    let output = format!("{value:?} {ygdk:?}");
    assert!(!output.contains("spoc-debug-secret"));
    assert!(!output.contains("ygdk-debug-secret"));
}

#[test]
fn schema1按空缓存处理并由schema2写入覆盖() {
    let path = root("schema1");
    std::fs::write(
        path.join("business_session.json"),
        r#"{"schema":1,"account":"fixture-user","routes":{"direct":{},"webvpn":{}}}"#,
    )
    .unwrap();
    let cache = cache(&path);
    let (_, seeds) = cache.seeds(ACCOUNT, ConnectionMode::Direct, NOW);
    assert!(seeds.iter().all(|seed| seed.material.is_none()));
    let (generation, _) = cache.seeds(ACCOUNT, ConnectionMode::Direct, NOW);
    cache
        .write(
            ACCOUNT,
            generation,
            ConnectionMode::Direct,
            vec![(
                BusinessScope::Identity,
                Some(BusinessMaterial::Identity(StudentKind::Undergraduate)),
            )],
            NOW,
            || true,
        )
        .unwrap();
    drop(cache);
    let content = std::fs::read_to_string(path.join("business_session.json")).unwrap();
    assert!(content.contains(r#""schema":2"#));
    assert!(!content.contains(r#""schema":1"#));
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 签到与博雅读组凭据不进入旁车或主会话() {
    use crate::internal::route_state::{BykcCredential, SigninCredential};
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::runtime::ClientRuntime;
    use std::sync::Arc;

    struct NoRequests;
    #[async_trait::async_trait]
    impl HttpTransport for NoRequests {
        async fn execute(&self, _: HttpRequest) -> crate::error::Result<HttpResponse> {
            panic!("业务缓存写回不需要学校请求");
        }
    }

    let path = root("excluded");
    let store = FileSessionStore::new(&path).unwrap();
    let mut main = ClientRuntime::new(ConnectionMode::Direct, NoRequests, store.clone()).unwrap();
    main.refresh_authentication(&mut || {}).unwrap();
    let saved_session = std::fs::read(store.path()).unwrap();
    main.remember_account_name(Some(ACCOUNT));
    main.business_sessions = Some(Arc::new(BusinessSessionCache::new(&store)));
    let mut worker = main.fork_parallel_readonly();
    let state = worker.feature_state();
    state.bykc.set(BykcCredential {
        token: "fixture-by-kc".into(),
    });
    assert!(state.signin.store_credential(
        state.signin.generation(),
        SigninCredential {
            user_id: "fixture-i-class-user".into(),
            session_id: "fixture-i-class-session".into()
        },
    ));
    state.seed_academic_identity(Some(StudentKind::Undergraduate));
    worker.persist_business_session();
    drop(worker);
    drop(main);

    let content = std::fs::read_to_string(path.join("business_session.json")).unwrap();
    let document: serde_json::Value = serde_json::from_str(&content).unwrap();
    let entries = document["routes"]["direct"].as_object().unwrap();
    assert_eq!(entries.len(), 1);
    assert!(entries.contains_key("identity"));
    for excluded in [
        "fixture-by-kc",
        "fixture-i-class-user",
        "fixture-i-class-session",
    ] {
        assert!(!content.contains(excluded));
    }
    assert_eq!(std::fs::read(store.path()).unwrap(), saved_session);
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn 修复_f2_跨实例清理阻止旧材料回填() {
    for (operation, existing) in [("clear", true), ("login", true), ("clear", false)] {
        let path = root("clear-fence");
        if existing {
            write_materials(&path, NOW);
        }
        let first = cache(&path);
        let (generation, _) = first.seeds(ACCOUNT, ConnectionMode::Direct, NOW);
        let (wait, resume) = pause_file_job(&first);
        first
            .write(
                ACCOUNT,
                generation,
                ConnectionMode::Direct,
                materials(),
                NOW,
                || true,
            )
            .unwrap();
        wait_for_file_job(&wait);
        let second = cache(&path);
        if operation == "login" {
            second
                .invalidate(Invalidation::SameAccountLogin(ConnectionMode::Direct))
                .unwrap();
        } else {
            second.invalidate(Invalidation::RevokeAll).unwrap();
        }
        drop(resume);
        drop(first);
        let (_, seeds) = cache(&path).seeds(ACCOUNT, ConnectionMode::Direct, NOW);
        assert!(
            seeds.iter().all(|seed| seed.material.is_none()),
            "{operation}/{existing} 回填了旧材料"
        );
        std::fs::remove_dir_all(path).unwrap();
    }
}

#[test]
fn 修复_f6_未来时间戳使内存种子失效() {
    let path = root("future");
    write_materials(&path, NOW);
    let reader = cache(&path);
    assert!(
        reader.seeds(ACCOUNT, ConnectionMode::Direct, NOW).1[BusinessScope::Spoc as usize]
            .material
            .is_some()
    );
    for now in [NOW - 1, NOW] {
        let (_, seeds) = reader.seeds(ACCOUNT, ConnectionMode::Direct, now);
        assert!(seeds.iter().all(|seed| seed.material.is_none()));
    }
    std::fs::remove_dir_all(path).unwrap();
}

#[cfg(unix)]
mod queued {
    use super::*;
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::runtime::ClientRuntime;
    use crate::session::DualSessionCoordinator;
    use std::sync::Arc;

    struct Sso;
    #[async_trait::async_trait]
    impl HttpTransport for Sso {
        async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
            if request.url.contains("/login?") {
                let mut response = HttpResponse::new(302, request.url, Vec::new());
                response.headers.insert("Location".into(), vec!["https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-fixture".into()]);
                return Ok(response);
            }
            assert!(request.url.contains("/serviceValidate?"));
            let mut response = HttpResponse::new(
                200,
                request.url,
                br#"{"user":"fixture-user","attributes":{"employeeNumber":["fixture-user"]}}"#
                    .to_vec(),
            );
            response.headers.insert(
                "Set-Cookie".into(),
                vec!["fixture_sso=refreshed; Path=/; Secure".into()],
            );
            Ok(response)
        }
    }

    fn setup(
        path: &Path,
    ) -> (
        FileSessionStore,
        DualSessionCoordinator,
        ClientRuntime,
        Arc<BusinessSessionCache>,
    ) {
        let store = FileSessionStore::new(path).unwrap();
        let coordinator = DualSessionCoordinator::new(store.clone()).unwrap();
        let mut parent = ClientRuntime::new(
            ConnectionMode::Direct,
            Sso,
            coordinator.route_store(ConnectionMode::Direct),
        )
        .unwrap();
        parent.refresh_authentication(&mut || {}).unwrap();
        parent.remember_account_name(Some(ACCOUNT));
        let cache = Arc::new(BusinessSessionCache::new(&store));
        parent.business_sessions = Some(Arc::clone(&cache));
        (store, coordinator, parent, cache)
    }

    fn queue(
        parent: &mut ClientRuntime,
        cache: &BusinessSessionCache,
    ) -> (std::sync::mpsc::Sender<()>, ClientRuntime) {
        let (wait, resume) = pause_file_job(cache);
        let mut worker = parent.fork_parallel_readonly();
        worker
            .feature_state()
            .seed_academic_identity(Some(StudentKind::Graduate));
        worker.persist_business_session();
        wait_for_file_job(&wait);
        (resume, worker)
    }

    #[tokio::test]
    async fn 修复_f1_预检后正常核验保存仍可写回且不污染协调器() {
        let path = root("queued-refresh");
        let (store, coordinator, mut parent, cache) = setup(&path);
        parent.refresh_authentication(&mut || {}).unwrap();
        let revision = store.load_dual_versioned().unwrap().revision;
        let (held, _worker) = queue(&mut parent, &cache);
        crate::auth::sso_identity::validate_status(&mut parent, &mut || {})
            .await
            .unwrap();
        assert!(store.load_dual_versioned().unwrap().revision > revision);
        drop(held);
        cache.lock().writer.drain();
        assert!(path.join("business_session.json").exists());
        assert!(!coordinator.is_conflicted());
        parent.ensure_session_revision().unwrap();
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn 修复_f1_注销推进修订时旧写回不污染协调器() {
        let path = root("queued-logout");
        let (_, coordinator, mut parent, cache) = setup(&path);
        parent.refresh_authentication(&mut || {}).unwrap();
        let (held, _worker) = queue(&mut parent, &cache);
        parent.clear_memory();
        let revisions = coordinator.clear_both().unwrap();
        drop(held);
        cache.invalidate(Invalidation::RevokeAll).unwrap();
        parent.set_session_revision(revisions.direct);
        assert!(!coordinator.is_conflicted());
        parent.refresh_authentication(&mut || {}).unwrap();
        assert!(
            cache
                .seeds(ACCOUNT, ConnectionMode::Direct, NOW)
                .1
                .iter()
                .all(|seed| seed.material.is_none())
        );
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn 修复_f3_路线生命周期变化丢弃排队写回且新读组不播种() {
        let path = root("queued-lifecycle");
        let (store, _, mut parent, cache) = setup(&path);
        let (held, _worker) = queue(&mut parent, &cache);
        let revision = store.load_dual_versioned().unwrap().revision;
        let mut rejected_group = parent.fork_parallel_readonly();
        rejected_group.clear_with(|| {}).unwrap();
        assert_eq!(store.load_dual_versioned().unwrap().revision, revision);
        let fresh_group = parent.fork_parallel_readonly();
        drop(held);
        cache.lock().writer.drain();
        assert!(!path.join("business_session.json").exists());
        assert!(
            fresh_group
                .feature_state()
                .cached_academic_identity()
                .is_none()
        );
        std::fs::remove_dir_all(path).unwrap();
    }
}
