use super::*;
use crate::auth::AuthWorkflow;
use crate::domain::{LoginInput, SecretValue};
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::{DualSessionCoordinator, SessionStore};
use std::sync::Arc;

#[derive(Clone)]
struct Sso {
    account: &'static str,
    replace_on_logout: Option<FileSessionStore>,
    interactive_pending: bool,
}

#[async_trait::async_trait]
impl HttpTransport for Sso {
    async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
        let url = crate::connection::from_webvpn_url(&request.url).unwrap();
        if url.ends_with("/logout") {
            if let Some(store) = &self.replace_on_logout {
                let saved = store.load_dual_versioned()?;
                assert!(matches!(
                    store.compare_exchange_dual(saved.revision, saved.snapshot.as_ref())?,
                    crate::session::types::DualSessionMutation::Applied { .. }
                ));
            }
            return Ok(HttpResponse::new(200, request.url, Vec::new()));
        }
        if url == "https://d.buaa.edu.cn/" {
            return Ok(HttpResponse::new(200, request.url, Vec::new()));
        }
        if self.interactive_pending && url == crate::upstream::SSO_LOGIN_URL {
            return Ok(HttpResponse::new(
                200,
                request.url,
                br#"<input name="execution" value="fixture-flow">"#.to_vec(),
            ));
        }
        if url == crate::upstream::SSO_LOGIN_URL || url.contains("/login?") {
            let mut response = HttpResponse::new(302, &request.url, Vec::new());
            let target = if url.contains("cas_login%3Dtrue") {
                "https://d.buaa.edu.cn/".into()
            } else {
                let target = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-fixture";
                if url == request.url {
                    target.into()
                } else {
                    crate::connection::to_webvpn_url(target).unwrap()
                }
            };
            response.headers.insert("Location".into(), vec![target]);
            return Ok(response);
        }
        assert!(url.contains("/serviceValidate?"), "收到未登记的合成请求");
        let account = self.account;
        let body =
            format!(r#"{{"user":"{account}","attributes":{{"employeeNumber":["{account}"]}}}}"#);
        let mut response = HttpResponse::new(200, request.url, body.into_bytes());
        response.headers.insert(
            "Set-Cookie".into(),
            vec!["fixture_sso=refreshed; Path=/; Secure".into()],
        );
        Ok(response)
    }
}

fn transport(account: &'static str) -> Sso {
    Sso {
        account,
        replace_on_logout: None,
        interactive_pending: false,
    }
}

fn main_runtime(store: &FileSessionStore, account: &'static str) -> ClientRuntime {
    let sessions = DualSessionCoordinator::new(store.clone()).unwrap();
    ClientRuntime::new(
        ConnectionMode::Direct,
        transport(account),
        sessions.route_store(ConnectionMode::Direct),
    )
    .unwrap()
}

fn document(path: &Path) -> serde_json::Value {
    serde_json::from_slice(&std::fs::read(path.join("business_session.json")).unwrap()).unwrap()
}

fn material(cache: &BusinessSessionCache, route: ConnectionMode) -> Option<BusinessMaterial> {
    cache.seeds(ACCOUNT, route, NOW).1[BusinessScope::Spoc as usize]
        .material
        .clone()
}

fn write_route(cache: &BusinessSessionCache, route: ConnectionMode) {
    let (stamp, _) = cache.seeds(ACCOUNT, route, NOW);
    cache
        .write(ACCOUNT, stamp, route, materials(), NOW, || true)
        .unwrap();
    cache.lock().writer.drain();
}

#[derive(Clone, Copy, Debug)]
enum Event {
    Save,
    Login,
    ChangeAccount,
    Revoke,
}

async fn after_precheck(event: Event, route: ConnectionMode, tombstone: bool, accepted: bool) {
    let path = root("after-precheck");
    let store = FileSessionStore::new(&path).unwrap();
    let mut first = main_runtime(&store, ACCOUNT);
    first.refresh_authentication(&mut || {}).unwrap();
    let sessions = DualSessionCoordinator::new(store.clone()).unwrap();
    let revision = store.load_dual_versioned().unwrap().revision;
    let route_store = sessions.route_store(route);
    let a = cache(&path);
    let b = Arc::new(cache(&path));
    if tombstone {
        b.invalidate(Invalidation::RevokeAll);
        assert!(document(&path)["account"].is_null());
    } else {
        assert!(!path.join("business_session.json").exists());
    }
    let (stamp, _) = a.seeds(ACCOUNT, route, NOW);
    let (wait, resume) = pause_file_job(&a);
    a.write_after_revision_check(
        ACCOUNT,
        stamp,
        route,
        materials(),
        NOW,
        (
            move || route_store.revision_matches_for_cache(revision).unwrap(),
            || true,
            None,
        ),
    )
    .unwrap();
    wait_for_file_job(&wait);

    let account = if matches!(event, Event::ChangeAccount) {
        "fixture-other"
    } else {
        ACCOUNT
    };
    let mut second = main_runtime(&store, account);
    second.business_sessions = Some(Arc::clone(&b));
    if !matches!(event, Event::ChangeAccount) {
        second.remember_account_name(Some(ACCOUNT));
    }
    match event {
        Event::Save => {
            crate::auth::sso_identity::validate_status(&mut second, &mut || {})
                .await
                .unwrap();
        }
        Event::Login | Event::ChangeAccount => {
            let mut auth = AuthWorkflow::default();
            assert_eq!(
                auth.login_automatically(
                    &mut second,
                    LoginInput {
                        username: account.into(),
                        password: SecretValue::new("fixture-input")
                    }
                )
                .await
                .unwrap()
                .school_id
                .as_deref(),
                Some(account)
            );
        }
        Event::Revoke => b.invalidate(Invalidation::RevokeAll),
    }
    if !matches!(event, Event::Revoke) {
        assert!(store.load_dual_versioned().unwrap().revision > revision);
    }
    drop(resume);
    a.lock().writer.drain();
    assert_eq!(
        material(&cache(&path), route).is_some(),
        accepted,
        "{event:?}/{route:?}：清理前的任务处理错误"
    );
    assert!(!sessions.is_conflicted());
    std::fs::remove_dir_all(path).unwrap();
}

#[tokio::test]
async fn 修复二_f1_外部同账号核验只保存主会话不阻止已预检写回() {
    after_precheck(Event::Save, ConnectionMode::Direct, false, true).await;
}

#[tokio::test]
async fn 修复二_f2_同账号单路线登录只拦目标路线的在途写回() {
    after_precheck(Event::Login, ConnectionMode::Direct, true, false).await;
    after_precheck(Event::Login, ConnectionMode::WebVpn, true, true).await;
}

#[tokio::test]
async fn 修复二_f2_先前账号未知时换号拦两条路线含无文件及墓碑() {
    for tombstone in [false, true] {
        for route in [ConnectionMode::WebVpn, ConnectionMode::Direct] {
            after_precheck(Event::ChangeAccount, route, tombstone, false).await;
        }
    }
}

#[tokio::test]
async fn 修复二_f2_全量清理拦两条路线的在途写回() {
    for route in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        after_precheck(Event::Revoke, route, false, false).await;
    }
}

#[test]
fn 修复二_f2_迟到拒绝不删除清理后写入的同值条目() {
    let path = root("old-rejection");
    let a = cache(&path);
    let b = cache(&path);
    write_route(&b, ConnectionMode::Direct);
    let (stamp, seeds) = a.seeds(ACCOUNT, ConnectionMode::Direct, NOW);
    let old = seeds[BusinessScope::Spoc as usize]
        .material
        .clone()
        .unwrap();
    let (wait, resume) = pause_file_job(&a);
    a.reject(
        ACCOUNT,
        stamp,
        ConnectionMode::Direct,
        BusinessScope::Spoc,
        old.clone(),
    );
    wait_for_file_job(&wait);
    b.invalidate(Invalidation::RevokeAll);
    write_route(&b, ConnectionMode::Direct);
    drop(resume);
    a.lock().writer.drain();
    assert!(super::super::same_material(
        material(&cache(&path), ConnectionMode::Direct).as_ref(),
        Some(&old)
    ));
    std::fs::remove_dir_all(path).unwrap();
}

#[cfg(feature = "test-contract")]
#[path = "business_cache_fix2_tests/facade_cases.rs"]
mod facade_cases;
