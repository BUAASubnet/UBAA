use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::Duration,
};
use ubaa_core::facade::{ClassroomStatus, NetworkState, UbaaClient};
use ubaa_test_support::{
    ConnectionMode, DualSessionSnapshot, ErrorCode, FileSessionStore, GatewayProbe, HttpMethod,
    HttpRequest, HttpResponse, HttpTransport, RouteConfig, RouteSessionSnapshot, SessionSnapshot,
    StoredCookie, TestTempDir, from_webvpn_url, test_temp_dir, to_webvpn_url,
};
use url::Url;

const LOGIN: &str = "https://yjapi.msa.buaa.edu.cn/casapi/index.php?r=auth/login&tenant_code=21&forward=https://classroom.msa.buaa.edu.cn/";
const TEACHER: &str = "fedcba9876543210fedcba9876543210";
const PPT: &str = "abcdef0123456789abcdef0123456789";
const YJ: &str = "https://yjapi.msa.buaa.edu.cn";
const CLASS: &str = "https://classroom.msa.buaa.edu.cn";
const SPOC: &str = "https://spoc.buaa.edu.cn/spocnewht";
const SNAP: &str = "https://d.buaa.edu.cn/wengine-vpn/cookie?method=get&host=classroom.msa.buaa.edu.cn&scheme=https&path=%2Fcoursedetail&vpn_timestamp=";

macro_rules! fixture {
    ($name:literal) => {
        serde_json::from_str::<Value>(include_str!(concat!(
            "../../../../../fixtures/readonly/spoc_classroom/",
            $name,
            ".json"
        )))
        .unwrap()
    };
}
type Step = (String, HttpResponse);
#[path = "classroom_boundaries.rs"]
mod boundaries;
#[path = "classroom_cases.rs"]
mod cases;
fn reply(url: &str, body: &Value) -> Step {
    (
        url.into(),
        HttpResponse::new(200, url, body.to_string().into_bytes()),
    )
}
fn head(url: &str, fixture: &Value) -> Step {
    let mut res = HttpResponse::new(
        fixture["status"].as_u64().unwrap().try_into().unwrap(),
        url,
        fixture["body"].as_str().unwrap().as_bytes().to_vec(),
    );
    res.headers = serde_json::from_value(fixture["headers"].clone()).unwrap();
    (url.into(), res)
}
fn route(vpn: bool, url: &str) -> String {
    if vpn && !url.starts_with("https://d.buaa.edu.cn/") {
        to_webvpn_url(url).unwrap()
    } else {
        url.into()
    }
}
fn auth(vpn: bool) -> Vec<Step> {
    let hops = if vpn {
        fixture!("casapi-webvpn")
    } else {
        fixture!("casapi-direct")
    };
    let mut url = route(vpn, LOGIN);
    hops.as_array()
        .unwrap()
        .iter()
        .enumerate()
        .map(|(index, hop)| {
            let step = head(if index == 4 { SNAP } else { &url }, hop);
            url = hop["headers"]["location"][0].as_str().unwrap_or("").into();
            step
        })
        .collect()
}
fn mapping(vpn: bool, second: bool) -> Vec<Step> {
    let course_list = fixture!("course-list");
    let kcid = course_list["content"][usize::from(second)]["kcid"]
        .as_str()
        .unwrap();
    let sig = if second {
        fixture!("signature-b")
    } else {
        fixture!("signature-a")
    };
    let mut location = if second {
        fixture!("course-url-b")
    } else {
        fixture!("course-url-a")
    };
    let params = &sig["content"];
    let mut map_url = Url::parse(params["ktsl_url"].as_str().unwrap()).unwrap();
    for key in [
        "bind_id",
        "username",
        "realname",
        "tenant_code",
        "timestamp",
        "signature",
        "allow_live",
    ] {
        let scalar = &params[key];
        map_url.query_pairs_mut().append_pair(
            key,
            &scalar
                .as_str()
                .map_or_else(|| scalar.to_string(), str::to_owned),
        );
    }
    location["headers"]["location"][0] = json!(route(
        vpn,
        location["headers"]["location"][0].as_str().unwrap()
    ));
    vec![
        reply(
            &route(vpn, &format!("{SPOC}/kc/queryYhSflx?kcid={kcid}")),
            &fixture!("identity"),
        ),
        reply(
            &route(
                vpn,
                &format!("{SPOC}/yun/getHxyTimestampAndSignature2?kcid={kcid}&type=&isxs=1"),
            ),
            &sig,
        ),
        head(&route(vpn, map_url.as_str()), &location),
    ]
}
fn business(vpn: bool, url: String, body: &Value) -> Step {
    let routed = if vpn { route(true, &url) } else { url };
    reply(&routed, body)
}
fn transcript(vpn: bool, body: &Value) -> Step {
    business(
        vpn,
        format!(
            "{YJ}/courseapi/v3/web-socket/search-trans-result?sub_id=200001&format=json&resource_guid={TEACHER}"
        ),
        body,
    )
}
fn session(vpn: bool, course: &str, sub: &str, body: &Value) -> Step {
    business(
        vpn,
        format!(
            "{CLASS}/courseapi/v3/portal-home-setting/get-sub-info?course_id={course}&sub_id={sub}"
        ),
        body,
    )
}
#[derive(Clone, Default)]
struct Script(Arc<Mutex<VecDeque<Step>>>);
#[async_trait::async_trait]
impl HttpTransport for Script {
    async fn execute(&self, req: HttpRequest) -> ubaa_test_support::Result<HttpResponse> {
        let (expected, mut res) = self.0.lock().unwrap().pop_front().expect("出现脚本外请求");
        if expected == SNAP {
            assert!(req.url.strip_prefix(SNAP).unwrap().parse::<u64>().is_ok());
        } else {
            assert_eq!(req.url, expected);
        }
        let direct = from_webvpn_url(&req.url).unwrap();
        if direct.ends_with("/sys/casLogin") {
            assert_eq!(req.method, HttpMethod::Post);
        } else {
            assert_eq!(req.method, HttpMethod::Get);
            assert_eq!(req.body.len(), 0);
        }
        if direct.contains("/courseapi/") || direct.contains("/pptnote/") {
            let expected = res
                .headers
                .remove("fixture-bearer")
                .unwrap_or_else(|| vec!["Bearer TEST_JWT".into()]);
            assert_eq!(req.headers["Authorization"], expected[0]);
            if direct == req.url {
                assert!(!req.headers.contains_key("Cookie"));
            } else {
                assert!(req.headers["Cookie"].contains("NAV="));
                assert!(!req.headers["Cookie"].contains("_token="));
            }
        } else {
            assert!(!req.headers.contains_key("Authorization"));
        }
        if direct.contains("/kc/queryYhSflx") || direct.contains("/yun/getHxy") {
            assert_eq!(req.headers["RoleCode"], "01");
            assert!(req.headers["Token"].starts_with("Inco-"));
        }
        if !direct.contains("/spocnewht/") {
            assert!(!req.headers.contains_key("Token"));
            assert!(!req.headers.contains_key("RoleCode"));
        }
        if direct == req.url
            && (direct.contains("/casapi/") || direct.contains("/get-bh-course-url"))
        {
            assert!(
                !req.headers
                    .get("Cookie")
                    .is_some_and(|value| value.contains("MAIN_ONLY="))
            );
        }
        if direct.starts_with("https://sso.buaa.edu.cn/login?") {
            assert!(req.headers.contains_key("Cookie"));
            assert!(!req.headers["Cookie"].contains("MSA_ONLY"));
        }
        res.final_url = Url::parse(&req.url).unwrap().into();
        tokio::task::yield_now().await;
        if res.status == 0 {
            return Err(ubaa_test_support::UbaaError::new(
                ErrorCode::Timeout,
                ubaa_test_support::ErrorKind::Network,
                true,
                "合成网络超时",
            ));
        }
        Ok(res)
    }
}
struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: Duration) -> NetworkState {
        NetworkState::Unknown
    }
}
fn setup(vpn: bool, steps: Vec<Step>) -> (UbaaClient, Script, TestTempDir) {
    setup_with_cookies(vpn, steps, &[])
}
fn setup_with_cookies(
    vpn: bool,
    steps: Vec<Step>,
    extra: &[StoredCookie],
) -> (UbaaClient, Script, TestTempDir) {
    let root = test_temp_dir("msa_read").unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    let slot = |route_vpn| {
        let mut cookie = StoredCookie::fixture("NAV", "fixture-navigation");
        cookie.domain = if route_vpn {
            "d.buaa.edu.cn"
        } else {
            "sso.buaa.edu.cn"
        }
        .into();
        RouteSessionSnapshot::from_legacy(&SessionSnapshot {
            mode: if route_vpn {
                ConnectionMode::WebVpn
            } else {
                ConnectionMode::Direct
            },
            cookies: [vec![cookie], extra.to_vec()].concat(),
            authenticated_at: 1,
            last_activity: 2,
        })
    };
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(slot(false)),
            Some(slot(true)),
        ))
        .unwrap();
    let script = Script(Arc::new(Mutex::new(steps.into())));
    let config = RouteConfig::parse(if vpn {
        "[route]\ndefault='webvpn'"
    } else {
        "[route]\ndefault='direct'"
    })
    .unwrap();
    (
        UbaaClient::with_routing(script.clone(), script.clone(), store, config, NoProbe).unwrap(),
        script,
        root,
    )
}
fn account_verification_steps(vpn: bool) -> Vec<Step> {
    let route_url = |url: &str| {
        if vpn {
            ubaa_test_support::to_webvpn_url(url).unwrap()
        } else {
            url.to_owned()
        }
    };
    let ticket_url = route_url(
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp",
    );
    let validate_url = route_url(
        "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON",
    );
    vec![
        (
            ticket_url.clone(),
            ubaa_core::facade::testing::sso_fixture_ticket(&HttpRequest::get(&ticket_url)).unwrap(),
        ),
        (
            validate_url.clone(),
            HttpResponse::new(
                200,
                &validate_url,
                br#"{"user":"fixture-user","attributes":{"employeeNumber":["fixture-user"]}}"#
                    .to_vec(),
            ),
        ),
    ]
}

#[tokio::test]
async fn 两条路线从冷启动读取同名课程与全部课堂数据且导出脱敏() {
    for vpn in [false, true] {
        let mut steps = account_verification_steps(vpn);
        steps.extend(super::files::login(vpn, "fixture-spoc-secret"));
        for (second, id) in [(false, "100001"), (true, "100002")] {
            steps.extend(mapping(vpn, second));
            if !second {
                steps.extend(auth(vpn));
            }
            let mut detail = fixture!("course-detail");
            detail["data"]["id"] = json!(id);
            steps.push(business(vpn,format!("{YJ}/courseapi/v3/multi-search/get-course-detail?course_id={id}&student=91024683"),&detail));
        }
        steps.extend([session(vpn,"100001","200001",&fixture!("sub-recording")),session(vpn,"100002","200003",&fixture!("sub-live")),transcript(vpn,&fixture!("transcript")), business(vpn,format!("{CLASS}/courseapi/v2/intelligent-summary/detail?sub_id=200001&resource_guid={TEACHER}"),&fixture!("summary")),business(vpn,format!("{CLASS}/pptnote/v1/schedule/search-ppt?course_id=100001&sub_id=200001&page=1&per_page=100&resource_guid={PPT}"),&fixture!("ppt"))]);
        let (mut client, script, root) = setup(vpn, steps);
        let diagnostics = client.raw_diagnostics();
        diagnostics.enable();
        client.recover_connection_session().await.unwrap();
        for (index, id) in ["100001", "100002"].into_iter().enumerate() {
            let list = fixture!("course-list");
            let kcid = list["content"][index]["kcid"].as_str().unwrap();
            let catalog = client.spoc_classroom_catalog(kcid).await.unwrap().data;
            assert_eq!(
                (&*catalog.course_id, &*catalog.title, &*catalog.term_name),
                (id, "测试课程", "测试学期")
            );
            assert_eq!(catalog.sessions[0].status, ClassroomStatus::Replay);
            assert_eq!(catalog.sessions[0].week, Some(1));
            assert_eq!(catalog.sessions[1].status, ClassroomStatus::Upcoming);
            assert!(catalog.sessions[1].tencent_meeting);
            assert_eq!(catalog.teachers, ["测试教师"]);
            assert_eq!(catalog.sessions.len(), 2);
            assert_eq!(catalog.sessions[0].week, Some(1));
            assert_eq!(catalog.sessions[0].status, ClassroomStatus::Replay);
            assert!(catalog.sessions[1].tencent_meeting);
        }
        let recording = client
            .spoc_classroom_session("100001", "200001")
            .await
            .unwrap()
            .data;
        assert_eq!(recording.sources.len(), 2);
        assert!(
            recording
                .sources
                .iter()
                .any(|source| source.resource_guid.as_deref() == Some(PPT)
                    && source.time_offset_secs == Some(-120))
        );
        let live = client
            .spoc_classroom_session("100002", "200003")
            .await
            .unwrap()
            .data;
        assert_eq!(live.sources.len(), 2);
        assert!(
            live.sources
                .iter()
                .all(|source| source.url.contains("?auth_key="))
        );
        let text = client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap()
            .data;
        assert_eq!(text.segments[1].begin_ms, 4000);
        let summary = client
            .spoc_classroom_summary("200001", TEACHER)
            .await
            .unwrap()
            .data;
        assert_eq!(summary.qa.len(), 1);
        assert_eq!(summary.qa[0].start_ms, 4000);
        assert_eq!(summary.chapters[0].end_ms, 12000);
        assert_eq!(summary.keywords, ["测试关键词"]);
        let slides = client
            .spoc_classroom_slides("100001", "200001", PPT)
            .await
            .unwrap()
            .data;
        assert_eq!(slides.slides[1].offset_ms, 12000);
        assert!(script.0.lock().unwrap().is_empty());
        assert_private_export(&diagnostics.export_json());
        let stored = FileSessionStore::new(&root).unwrap().load_dual().unwrap();
        let store_text = serde_json::to_string(&stored).unwrap();
        assert!(!store_text.contains("_token"));
        assert!(!store_text.contains("TEST_JWT"));
    }
}
fn assert_private_export(export: &str) {
    assert!(export.contains("get-sub-info"));
    for secret in [
        "TEST_JWT",
        "ST-TEST",
        "fixture-spoc-secret",
        "测试学生",
        "测试教师",
        "190019011T000000001001",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "cccccccccccccccccccccccccccccccc",
        "dddddddddddddddddddddddddddddddd",
        "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "ffffffffffffffffffffffffffffffff",
        "91024683",
        "92024683",
        "%E6%B5%8B%E8%AF%95%E5%AD%A6%E7%94%9F",
        "1000000001",
        "1000000002",
    ] {
        assert!(!export.contains(secret), "导出包含敏感夹具值：{secret}");
    }
}
#[tokio::test]
async fn 两个并发读取只认证一次并拒绝不合法输入() {
    for vpn in [false, true] {
        let empty = json!({"code":0,"list":[]});
        let mut steps = auth(vpn);
        steps.extend([transcript(vpn, &empty), transcript(vpn, &empty)]);
        let (mut parent, script, _root) = setup(vpn, steps);
        let mut first = parent.fork_parallel_readonly().unwrap();
        let mut second = parent.fork_parallel_readonly().unwrap();
        let (left, right) = tokio::join!(
            first.spoc_classroom_transcript("200001", TEACHER),
            second.spoc_classroom_transcript("200001", TEACHER)
        );
        assert!(left.unwrap().data.segments.is_empty());
        assert!(right.unwrap().data.segments.is_empty());
        assert!(script.0.lock().unwrap().is_empty());
        for guid in ["", "坏", "a-b", &"a".repeat(65)] {
            assert_eq!(
                parent
                    .spoc_classroom_transcript("200001", guid)
                    .await
                    .unwrap_err()
                    .error
                    .code,
                ErrorCode::InvalidInput
            );
        }
        assert_eq!(
            parent
                .spoc_classroom_session("1", "１")
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::InvalidInput
        );
    }
}
