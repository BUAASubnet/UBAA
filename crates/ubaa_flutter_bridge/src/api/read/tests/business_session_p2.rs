//! 第二阶段从合成登录、业务读取到进程重开的回归覆盖。
use super::{Fixture, FixtureRequest, PortalTransport, restored};
use crate::api::client::{BridgeClient, BridgeConnectionMode, BridgeErrorCode};
use crate::api::offline::BridgeOfflineCache;
use crate::api::read::BridgeYgdkSubmitTarget;
use crate::api::write::{BridgePhotoUpload, BridgeYgdkSubmitRequest};
use serde_json::{Value, json};
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst},
};
use ubaa_test_support::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, Result, from_webvpn_url,
};

const ACCOUNT: &str = super::ACCOUNT;
const SPOC_OLD: &str = "fixture-spoc-old";
const SPOC_NEW: &str = "fixture-spoc-new";
const YGDK_OLD: &str = "fixture-ygdk-old";
const YGDK_NEW: &str = "fixture-ygdk-new";
const TASK: &str = "biz_cache_p2";

#[derive(Clone)]
struct LogBuffer(Arc<Mutex<Vec<u8>>>);

impl Write for LogBuffer {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[derive(Clone, Default)]
struct Transport {
    portal: PortalTransport,
    calls: Arc<Calls>,
    renew_spoc: bool,
    renew_ygdk: bool,
    reject_page: Option<u16>,
}

#[derive(Default)]
struct Calls {
    spoc_logins: AtomicUsize,
    spoc_terms: AtomicUsize,
    spoc_old: AtomicUsize,
    ygdk_logins: AtomicUsize,
    ygdk_overviews: AtomicUsize,
    ygdk_pages: AtomicUsize,
    ygdk_old: AtomicUsize,
    ygdk_uploads: AtomicUsize,
    ygdk_submissions: AtomicUsize,
    reject_classify: AtomicBool,
}

impl Transport {
    fn spoc(&self, call: &FixtureRequest, path: &str) -> HttpResponse {
        match path {
            "/spocnewht/cas" => {
                let token = if self.renew_spoc { SPOC_NEW } else { SPOC_OLD };
                call.redirect(
                    &format!("https://spoc.buaa.edu.cn/spocnew/cas?token={token}"),
                    true,
                )
            }
            "/spocnewht/sys/casLogin" => {
                self.calls.spoc_logins.fetch_add(1, SeqCst);
                call.respond(200, r#"{"code":200,"content":{"jsdm":"01"}}"#)
            }
            _ => {
                let header = call
                    .request
                    .headers
                    .get("Token")
                    .and_then(|s| s.strip_prefix("Inco-"));
                assert!(matches!(header, Some(SPOC_OLD | SPOC_NEW)));
                assert!(
                    call.request
                        .headers
                        .get("RoleCode")
                        .is_some_and(|role| role == "01")
                );
                let body = match path {
                    "/spocnewht/inco/ht/queryOne" => {
                        self.calls.spoc_terms.fetch_add(1, SeqCst);
                        if header == Some(SPOC_OLD) {
                            self.calls.spoc_old.fetch_add(1, SeqCst);
                            if self.renew_spoc {
                                return call.respond(401, "");
                            }
                        }
                        r#"{"code":200,"content":{"mrxq":"fixture-term"}}"#
                    }
                    "/spocnewht/jxkj/queryKclb" => r#"{"code":200,"content":[]}"#,
                    "/spocnewht/inco/ht/queryListByPage" => {
                        r#"{"code":200,"content":{"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","zymc":"合成作业"}]}}"#
                    }
                    "/spocnewht/kczy/queryKczyInfoByid" => {
                        r#"{"code":200,"content":{"id":"a1","zymc":"合成作业","zynr":"合成正文"}}"#
                    }
                    "/spocnewht/kczy/queryXsSubmitKczyInfo" => r#"{"code":200,"content":null}"#,
                    _ => panic!("收到未登记的合成 SPOC 请求"),
                };
                call.respond(200, body)
            }
        }
    }

    fn ygdk(&self, call: &FixtureRequest, path: &str) -> HttpResponse {
        match path {
            "/uc/api/oauth/index" => {
                call.redirect("https://ygdk.buaa.edu.cn/#/home?code=fixture-code", true)
            }
            "/api/Front/Clockin/User/campusAppLogin" => {
                self.calls.ygdk_logins.fetch_add(1, SeqCst);
                let token = if self.renew_ygdk { YGDK_NEW } else { YGDK_OLD };
                call.respond(
                    200,
                    &json!({"code":1,"result":{"uid":7,"token":token}}).to_string(),
                )
            }
            "/api/Front/Upload/File/post" => {
                self.calls.ygdk_uploads.fetch_add(1, SeqCst);
                call.respond(200, r#"{"code":1,"result":{"file_name":"fixture.jpg"}}"#)
            }
            _ => {
                let token = std::str::from_utf8(&call.request.body)
                    .unwrap()
                    .split('&')
                    .find_map(|pair| pair.strip_prefix("token="));
                assert!(matches!(token, Some(YGDK_OLD | YGDK_NEW)));
                if token == Some(YGDK_OLD) {
                    self.calls.ygdk_old.fetch_add(1, SeqCst);
                }
                let body = match path {
                    "/api/Front/Clockin/Classify/getList" => {
                        self.calls.ygdk_overviews.fetch_add(1, SeqCst);
                        if self.calls.reject_classify.load(SeqCst)
                            || (self.renew_ygdk && token == Some(YGDK_OLD))
                        {
                            return call.respond(200, r#"{"code":-98}"#);
                        }
                        r#"{"code":1,"result":{"list":[{"classify_id":3,"name":"阳光体育"}]}}"#
                    }
                    "/api/Front/Clockin/Item/getList" => {
                        r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","sort":1}]}}"#
                    }
                    "/api/Front/Clockin/Clockin/getCount" => {
                        r#"{"code":1,"result":{"term_good_count_show":4}}"#
                    }
                    "/api/Front/Clockin/Term/get" => {
                        r#"{"code":1,"result":{"term_id":9,"name":"合成学期"}}"#
                    }
                    "/api/Front/Clockin/Clockin/getList" => {
                        self.calls.ygdk_pages.fetch_add(1, SeqCst);
                        if let Some(status) = self.reject_page {
                            let body = json!({"code":-98,"echo":token});
                            return call.respond(status, &body.to_string());
                        }
                        r#"{"code":1,"result":{"total":0,"list":[]}}"#
                    }
                    "/api/Front/Clockin/Clockin/clockin" => {
                        self.calls.ygdk_submissions.fetch_add(1, SeqCst);
                        r#"{"code":1,"result":{"record_id":77}}"#
                    }
                    _ => panic!("收到未登记的合成阳光打卡请求"),
                };
                call.respond(200, body)
            }
        }
    }
}

#[async_trait::async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let direct = from_webvpn_url(&request.url).unwrap();
        let call = FixtureRequest { request, direct };
        let (host, path) = call
            .direct
            .strip_prefix("https://")
            .unwrap()
            .split_once('/')
            .unwrap();
        let path = path.split('?').next().unwrap();
        let path = format!("/{path}");
        match host {
            "spoc.buaa.edu.cn" => Ok(self.spoc(&call, &path)),
            "app.buaa.edu.cn" | "ygdk.buaa.edu.cn" => Ok(self.ygdk(&call, &path)),
            _ => self.portal.execute(call.request).await,
        }
    }
}

async fn offline(root: &std::path::Path) -> BridgeOfflineCache {
    BridgeOfflineCache::open(
        root.to_string_lossy().into(),
        "0123456789abcdef0123456789abcdef".into(),
        ACCOUNT.into(),
        vec![4; 32],
    )
    .await
    .unwrap()
}

async fn read_basics(bridge: &BridgeClient) {
    bridge.schedule_today().await.unwrap();
    bridge.spoc_assignments().await.unwrap();
    bridge.ygdk_overview().await.unwrap();
}

async fn read_entry(bridge: &BridgeClient, root: &std::path::Path, mode: &str, name: &str) {
    if name == "basic" {
        read_basics(bridge).await;
        return;
    }
    let cache = offline(root).await;
    match name {
        "home-spoc" => {
            bridge.home_spoc_cached(&cache).await.unwrap();
        }
        "home-spoc-detail" => {
            bridge
                .home_spoc_detail_cached(&cache, "a1".into())
                .await
                .unwrap();
        }
        "home-ygdk" => {
            bridge.home_ygdk_cached(&cache).await.unwrap();
        }
        "spoc-pages" => {
            let task = bridge.begin_spoc_scan(&cache).await.unwrap();
            assert!(!bridge.next_spoc_scan(&task).await.unwrap().finished);
        }
        "spoc-detail-pages" => {
            let task = bridge
                .begin_spoc_detail_scan(&cache, "a1".into())
                .await
                .unwrap();
            assert!(!bridge.next_spoc_detail_scan(&task).await.unwrap().finished);
        }
        "ygdk-records" => {
            bridge.ygdk_records_cached(&cache, 1, 10).await.unwrap();
        }
        "ygdk-overview-records" => {
            let route = if mode == "direct" {
                BridgeConnectionMode::Direct
            } else {
                BridgeConnectionMode::WebVpn
            };
            bridge
                .ygdk_records_for_overview_cached(&cache, route, 3, 1, 10)
                .await
                .unwrap();
        }
        _ => unreachable!(),
    }
}

const CHILD: &str = "api::read::tests::business_session::p2::业务会话二阶段合成子进程";

fn restart(name: &str, mode: &str) {
    let fixture = Fixture::in_task(TASK);
    for round in ["cold", "reopen"] {
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--ignored", "--exact", "--nocapture", CHILD])
            .env("UBAA_FIXTURE_CACHE_ROOT", &fixture.0)
            .env("UBAA_FIXTURE_CACHE_ENTRY", name)
            .env("UBAA_FIXTURE_CACHE_MODE", mode)
            .env("UBAA_FIXTURE_CACHE_ROUND", round)
            .output()
            .unwrap();
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(
            output.status.success() && stdout.contains("1 passed; 0 failed"),
            "{name}/{mode}/{round}: {stdout}\n{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

#[test]
#[ignore = "由跨进程回归启动"]
fn 业务会话二阶段合成子进程() {
    let Some(root) = std::env::var_os("UBAA_FIXTURE_CACHE_ROOT").map(PathBuf::from) else {
        return;
    };
    let name = std::env::var("UBAA_FIXTURE_CACHE_ENTRY").unwrap();
    let mode = std::env::var("UBAA_FIXTURE_CACHE_MODE").unwrap();
    let cold = std::env::var("UBAA_FIXTURE_CACHE_ROUND").unwrap() == "cold";
    let transport = Transport::default();
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let store = FileSessionStore::new(&root).unwrap();
            let bridge = restored(store, &mode, &transport).await;
            Box::pin(read_entry(&bridge, &root, &mode, &name)).await;
        });
    let spoc = name == "basic" || name.contains("spoc");
    let ygdk = name == "basic" || name.contains("ygdk");
    if spoc {
        assert_eq!(
            transport.calls.spoc_terms.load(SeqCst),
            1,
            "必须实际读取 SPOC 学期"
        );
        assert_eq!(
            transport.calls.spoc_logins.load(SeqCst),
            usize::from(cold),
            "SPOC 登录次数"
        );
    }
    if ygdk {
        assert_eq!(
            transport.calls.ygdk_overviews.load(SeqCst),
            1,
            "必须实际读取阳光分类"
        );
        assert_eq!(
            transport.calls.ygdk_logins.load(SeqCst),
            usize::from(cold),
            "阳光打卡登录次数"
        );
    }
    if matches!(name.as_str(), "ygdk-records" | "ygdk-overview-records") {
        assert_eq!(transport.calls.ygdk_pages.load(SeqCst), 1);
    }
    if name == "basic" {
        let calls = transport.portal.state.portal_info.load(SeqCst);
        if cold {
            assert!(calls > 0);
        } else {
            assert_eq!(calls, 0, "命中身份时不请求门户资料");
        }
    }
}

#[test]
fn 业务会话_新进程恢复学生身份和两类业务令牌() {
    for mode in ["direct", "webvpn"] {
        restart("basic", mode);
    }
}

#[test]
fn 业务会话_各新增入口写回可供新进程复用() {
    for name in [
        "home-spoc",
        "home-spoc-detail",
        "home-ygdk",
        "spoc-pages",
        "spoc-detail-pages",
        "ygdk-records",
        "ygdk-overview-records",
    ] {
        for mode in ["direct", "webvpn"] {
            restart(name, mode);
        }
    }
}

#[tokio::test]
async fn 业务会话_过期后重新核对身份并登录() {
    let fixture = Fixture::in_task(TASK);
    let first = Transport::default();
    let bridge = restored(fixture.1.clone(), "direct", &first).await;
    read_basics(&bridge).await;
    drop(bridge);
    let mut document: Value = serde_json::from_str(&fixture.contents()).unwrap();
    for scope in ["identity", "spoc", "ygdk"] {
        let entry = &mut document["routes"]["direct"][scope];
        assert!(entry.is_object(), "正常读取应保存该范围");
        entry["saved_at"] = 0.into();
    }
    std::fs::write(fixture.cache(), document.to_string()).unwrap();
    let next = Transport {
        renew_spoc: true,
        renew_ygdk: true,
        ..Transport::default()
    };
    let bridge = restored(fixture.1.clone(), "direct", &next).await;
    read_basics(&bridge).await;
    assert_eq!(next.portal.state.portal_info.load(SeqCst), 1);
    assert_eq!(next.calls.spoc_logins.load(SeqCst), 1);
    assert_eq!(next.calls.ygdk_logins.load(SeqCst), 1);
    assert_eq!(next.calls.spoc_old.load(SeqCst), 0);
    assert_eq!(next.calls.ygdk_old.load(SeqCst), 0);
}

#[tokio::test]
async fn 业务会话_令牌被拒后只重登一次并保存新令牌() {
    let fixture = Fixture::in_task(TASK);
    let bridge = restored(fixture.1.clone(), "direct", &Transport::default()).await;
    read_basics(&bridge).await;
    drop(bridge);
    let next = Transport {
        renew_spoc: true,
        renew_ygdk: true,
        ..Transport::default()
    };
    let bridge = restored(fixture.1.clone(), "direct", &next).await;
    read_basics(&bridge).await;
    drop(bridge);
    assert_eq!(next.calls.spoc_old.load(SeqCst), 1);
    assert_eq!(next.calls.ygdk_old.load(SeqCst), 1);
    assert_eq!(next.calls.spoc_logins.load(SeqCst), 1);
    assert_eq!(next.calls.ygdk_logins.load(SeqCst), 1);
    let content = fixture.contents();
    assert!(content.contains(SPOC_NEW) && content.contains(YGDK_NEW));
    assert!(!content.contains(SPOC_OLD) && !content.contains(YGDK_OLD));
}

#[tokio::test]
async fn 业务会话_阳光记录页被拒后删缓存并原样出错不重试() {
    for status in [200, 401] {
        let fixture = Fixture::in_task(TASK);
        let bridge = restored(fixture.1.clone(), "direct", &Transport::default()).await;
        read_basics(&bridge).await;
        drop(bridge);
        let rejected = Transport {
            reject_page: Some(status),
            ..Transport::default()
        };
        let bridge = restored(fixture.1.clone(), "direct", &rejected).await;
        let cache = offline(&fixture.0).await;
        let error = bridge.ygdk_records_cached(&cache, 1, 10).await.unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::AuthenticationRequired);
        assert_eq!(rejected.calls.ygdk_pages.load(SeqCst), 1);
        drop(bridge);
        let content = fixture.contents();
        assert!(content.contains(SPOC_OLD) && !content.contains(YGDK_OLD));
        assert_eq!(rejected.calls.ygdk_logins.load(SeqCst), 0);
        let next = Transport {
            renew_ygdk: true,
            ..Transport::default()
        };
        let bridge = restored(fixture.1.clone(), "direct", &next).await;
        bridge.ygdk_overview().await.unwrap();
        assert_eq!(next.calls.ygdk_logins.load(SeqCst), 1);
        assert_eq!(next.calls.ygdk_old.load(SeqCst), 0);
    }
}

#[tokio::test]
async fn 业务会话_登录注销换号路线策略与设置均清理新范围() {
    for operation in ["login", "logout", "account", "policy", "settings"] {
        let fixture = Fixture::in_task(TASK);
        for mode in ["direct", "webvpn"] {
            read_basics(&restored(fixture.1.clone(), mode, &Transport::default()).await).await;
        }
        let document: Value = serde_json::from_str(&fixture.contents()).unwrap();
        for mode in ["direct", "webvpn"] {
            for scope in ["identity", "spoc", "ygdk"] {
                assert!(
                    document["routes"][mode][scope].is_object(),
                    "操作前应保存新范围"
                );
            }
        }
        let next = Transport::default();
        let bridge = restored(fixture.1.clone(), "direct", &next).await;
        match operation {
            "login" => {
                bridge
                    .login_required_route(
                        BridgeConnectionMode::Direct,
                        ACCOUNT.into(),
                        "fixture-input".into(),
                    )
                    .await
                    .unwrap();
                let doc: Value = serde_json::from_str(&fixture.contents()).unwrap();
                assert!(doc["routes"]["direct"].as_object().unwrap().is_empty());
                assert!(doc["routes"]["webvpn"]["ygdk"].is_object());
            }
            "logout" => {
                bridge.logout().await.unwrap();
                assert!(!fixture.cache().exists());
            }
            "account" => {
                drop(bridge);
                let other = Transport {
                    portal: PortalTransport {
                        other_account: true,
                        ..PortalTransport::default()
                    },
                    ..Transport::default()
                };
                let bridge = restored(fixture.1.clone(), "direct", &other).await;
                read_basics(&bridge).await;
                drop(bridge);
                assert_eq!(other.calls.spoc_logins.load(SeqCst), 1);
                assert_eq!(other.calls.ygdk_logins.load(SeqCst), 1);
                let doc: Value = serde_json::from_str(&fixture.contents()).unwrap();
                assert_eq!(doc["account"], "fixture-other");
                assert!(doc["routes"]["webvpn"].as_object().unwrap().is_empty());
            }
            "policy" => {
                // open 只读取本机配置；修改策略不请求学校。
                let mut primary = ubaa_core::facade::UbaaClient::open(&fixture.0).unwrap();
                primary
                    .set_default_route_policy(ubaa_core::facade::RoutePolicy::Direct)
                    .unwrap();
                assert!(!fixture.cache().exists());
            }
            "settings" => {
                read_basics(&bridge).await;
                assert_eq!(next.calls.ygdk_logins.load(SeqCst), 0);
                bridge.clear_business_session_cache().await;
                assert!(!fixture.cache().exists());
                read_basics(&bridge).await;
                assert_eq!(next.calls.spoc_logins.load(SeqCst), 1);
                assert_eq!(next.calls.ygdk_logins.load(SeqCst), 1);
            }
            _ => unreachable!(),
        }
    }
}

#[tokio::test]
async fn 业务会话_阳光提交不读写旁车且被拒不重登() {
    for rejected in [false, true] {
        let fixture = Fixture::in_task(TASK);
        let bridge = restored(fixture.1.clone(), "direct", &Transport::default()).await;
        bridge.ygdk_overview().await.unwrap();
        drop(bridge);
        let prior = fixture.contents();
        assert!(prior.contains(YGDK_OLD));
        let write = Transport {
            renew_ygdk: true,
            ..Transport::default()
        };
        let bridge = restored(fixture.1.clone(), "direct", &write).await;
        let intent = bridge
            .prepare_ygdk_submit(BridgeYgdkSubmitRequest {
                target: BridgeYgdkSubmitTarget {
                    classify_id: 3,
                    item_id: 2,
                },
                start_time: "2026-04-01 08:00".into(),
                end_time: "2026-04-01 09:00".into(),
                place: Some("合成操场".into()),
                share_to_square: false,
                photo: BridgePhotoUpload {
                    bytes: vec![0xff, 0xd8, 0xff],
                    file_name: "fixture.jpg".into(),
                    mime_type: "image/jpeg".into(),
                },
            })
            .await
            .unwrap();
        write.calls.reject_classify.store(rejected, SeqCst);
        let result = bridge.commit_write(intent.intent_id).await;
        if rejected {
            assert_eq!(
                result.unwrap_err().code,
                BridgeErrorCode::AuthenticationRequired
            );
        } else {
            assert_eq!(result.unwrap().ygdk_receipt.unwrap().record_id, 77);
        }
        drop(bridge);
        assert_eq!(write.calls.ygdk_logins.load(SeqCst), 1);
        assert_eq!(write.calls.ygdk_overviews.load(SeqCst), 2);
        assert_eq!(write.calls.ygdk_old.load(SeqCst), 0);
        assert_eq!(
            write.calls.ygdk_uploads.load(SeqCst),
            usize::from(!rejected)
        );
        assert_eq!(
            write.calls.ygdk_submissions.load(SeqCst),
            usize::from(!rejected)
        );
        assert!(prior == fixture.contents(), "主客户端不得写回旁车");
    }
}

#[tokio::test]
async fn 业务会话_日志与普通诊断隐藏令牌且完整诊断不收集旁车() {
    use tracing::instrument::WithSubscriber as _;

    let fixture = Fixture::in_task(TASK);
    let bridge = restored(fixture.1.clone(), "direct", &Transport::default()).await;
    bridge.spoc_assignments().await.unwrap();
    bridge.ygdk_overview().await.unwrap();
    drop(bridge);
    let prior = fixture.contents();
    assert!(prior.contains(SPOC_OLD) && prior.contains(YGDK_OLD));
    // 阻止后台淘汰写入，验证真实 I/O 告警和未删除的旁车都不会泄露材料。
    let lock = fixture.0.join(super::LOCK);
    std::fs::remove_file(&lock).unwrap();
    std::fs::create_dir(lock).unwrap();
    let transport = Transport {
        reject_page: Some(200),
        ..Transport::default()
    };
    let logs = Arc::new(Mutex::new(Vec::new()));
    let subscriber = tracing_subscriber::fmt()
        .with_ansi(false)
        .without_time()
        .with_max_level(tracing::Level::TRACE)
        .with_writer({
            let logs = Arc::clone(&logs);
            move || LogBuffer(Arc::clone(&logs))
        })
        .finish();
    let (error, full_report) = Box::pin(async {
        let bridge = restored(fixture.1.clone(), "direct", &transport).await;
        let error = bridge.ygdk_records(1, 10).await.unwrap_err();
        (error, bridge.export_raw_diagnostics())
    })
    .with_subscriber(subscriber)
    .await;
    let logs = logs.lock().unwrap();
    let logs = std::str::from_utf8(&logs).unwrap();
    let report = error.diagnostic_json.as_deref().expect("原安全诊断存在");
    assert_eq!(error.code, BridgeErrorCode::AuthenticationRequired);
    assert!(logs.contains("业务会话缓存失效写回失败"));
    for hidden in [SPOC_OLD, YGDK_OLD] {
        assert!(!report.contains(hidden));
        assert!(!format!("{error:?}").contains(hidden));
        assert!(!logs.contains(hidden));
    }
    assert_eq!(transport.calls.ygdk_logins.load(SeqCst), 0);
    assert!(prior == fixture.contents(), "告警后旁车内容保持不变");
    assert!(full_report.contains("/Clockin/getList"));
    assert!(
        full_report.contains(YGDK_OLD),
        "完整诊断仍保留 HTTP 响应正文"
    );
    assert!(!full_report.contains(SPOC_OLD) && !full_report.contains(super::SIDE_CAR));
}

#[tokio::test]
async fn 业务会话_schema1旁车不播种并在成功读取后覆盖() {
    let fixture = Fixture::in_task(TASK);
    let bridge = restored(fixture.1.clone(), "direct", &Transport::default()).await;
    bridge.schedule_today().await.unwrap();
    drop(bridge);
    let mut old: Value = serde_json::from_str(&fixture.contents()).unwrap();
    old["schema"] = 1.into();
    old["routes"]["direct"]
        .as_object_mut()
        .unwrap()
        .retain(|k, _| matches!(k.as_str(), "byxt" | "portal"));
    std::fs::write(fixture.cache(), old.to_string()).unwrap();
    let next = Transport::default();
    let bridge = restored(fixture.1.clone(), "direct", &next).await;
    bridge.schedule_today().await.unwrap();
    drop(bridge);
    assert_eq!(next.portal.activations(), (1, 1));
    let current: Value = serde_json::from_str(&fixture.contents()).unwrap();
    assert_eq!(current["schema"], 2);
    assert!(current["routes"]["direct"]["identity"].is_object());
}
