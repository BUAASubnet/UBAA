use super::{BusinessMaterial, BusinessScope, BusinessSessionCache};
use crate::domain::ConnectionMode;
use crate::internal::route_state::{SpocCredential, StudentKind, YgdkCredential};
use crate::session::FileSessionStore;
use std::path::{Path, PathBuf};

const ACCOUNT: &str = "fixture-user";
const NOW: i64 = 1_800_000_000;

fn root(name: &str) -> PathBuf {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/biz_cache_p2")
        .join(format!("{name}-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&path).unwrap();
    path
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
        reader.reject(ACCOUNT, generation, ConnectionMode::Direct, scope, rejected);
    }
    let (_, seeds) = reader.seeds(ACCOUNT, ConnectionMode::Direct, NOW + 3);
    assert!(
        seeds[BusinessScope::Spoc as usize]
            .material
            .as_ref()
            .is_some_and(|value| value.matches(&renewed_spoc))
    );
    assert!(seeds[BusinessScope::Ygdk as usize].material.is_none());
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
    cache.clear_login(Some(ACCOUNT), ConnectionMode::Direct);
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
    assert!(!store.path().exists());
    std::fs::remove_dir_all(path).unwrap();
}
