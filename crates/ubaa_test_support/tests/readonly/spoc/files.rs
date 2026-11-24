use crate::common::{SpocTransport, redirect_from, response};
use serde_json::{Value, json};
use ubaa_core::facade::{NetworkState, SpocDownloadTarget, UbaaClient};
use ubaa_test_support::{
    ConnectionMode, DualSessionSnapshot, ErrorCode, FileSessionStore, GatewayProbe, HttpMethod,
    HttpResponse, RouteConfig, RouteSessionSnapshot, SessionSnapshot, StoredCookie, TestTempDir,
    test_temp_dir, to_webvpn_url,
};

struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不应探测")
    }
}
pub(super) type Step = (String, HttpResponse);

fn url(path: &str, vpn: bool) -> String {
    let url = format!("https://spoc.buaa.edu.cn/{path}");
    if vpn {
        to_webvpn_url(&url).unwrap()
    } else {
        url
    }
}
pub(super) fn login(vpn: bool, token: &str) -> Vec<Step> {
    let cas = url("spocnewht/cas", vpn);
    let token = url(&format!("spocnew/cas?token={token}"), vpn);
    vec![
        (cas.clone(), redirect_from(&cas, &token)),
        step(
            "spocnewht/sys/casLogin",
            vpn,
            200,
            "application/json",
            r#"{"code":200,"content":{"jsdm":"01"}}"#,
        ),
    ]
}
pub(super) fn step(path: &str, vpn: bool, status: u16, kind: &str, body: &str) -> Step {
    let url = url(path, vpn);
    let mut res = response(status, &url, body);
    res.headers.insert("Content-Type".into(), vec![kind.into()]);
    (url, res)
}
pub(super) fn client(script: Vec<Step>, vpn: bool) -> (UbaaClient, SpocTransport, TestTempDir) {
    let root = test_temp_dir("spoc_files").unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    let mode = if vpn {
        ConnectionMode::WebVpn
    } else {
        ConnectionMode::Direct
    };
    let mut navigation = StoredCookie::fixture("NAV", "fixture");
    navigation.domain = if vpn {
        "d.buaa.edu.cn"
    } else {
        "spoc.buaa.edu.cn"
    }
    .into();
    let slot = RouteSessionSnapshot::from_legacy(&SessionSnapshot {
        mode,
        cookies: vec![StoredCookie::fixture("SID", "fixture"), navigation],
        authenticated_at: 1,
        last_activity: 2,
    });
    let (direct, webvpn) = if vpn {
        (None, Some(slot))
    } else {
        (Some(slot), None)
    };
    store
        .save_dual(&DualSessionSnapshot::new(direct, webvpn))
        .unwrap();
    let transport = SpocTransport::new(script);
    let empty = SpocTransport::new([]);
    let (direct, webvpn) = if vpn {
        (empty, transport.clone())
    } else {
        (transport.clone(), empty)
    };
    let config = RouteConfig::parse(if vpn {
        "[route]\ndefault='webvpn'"
    } else {
        "[route]\ndefault='direct'"
    })
    .unwrap();
    (
        UbaaClient::with_routing(direct, webvpn, store, config, NoProbe).unwrap(),
        transport,
        root,
    )
}
fn page(vpn: bool, folder: Option<&str>, number: u32, pages: u32, items: &Value) -> Step {
    let endpoint = if folder.is_some() {
        "grwj1/queryKcwjListgr"
    } else {
        "kcwj/queryListPageXs"
    };
    let pid = folder.unwrap_or("0");
    step(
        &format!(
            "spocnewht/{endpoint}?pageNum={number}&pageSize=50&pid={pid}&mcTab=&kcid=course&lmlxdm=&wjlx="
        ),
        vpn,
        200,
        "application/json",
        &json!({"code":200,"content":{"pages":pages,"hasNextPage":number<pages,"list":items}})
            .to_string(),
    )
}

#[tokio::test]
async fn 课程来源与两条路线目录分页及下载权限() {
    for vpn in [false, true] {
        let mut script = login(vpn, "fixture");
        let first = json!([
            {"id":"folder","wjmc":"练习","sfwjj":"1","sfkxz":"folder"},
            {"id":"denied","wjmc":"不可下载","sfwjj":"0","sfkxz":"0"}
        ]);
        let child = json!([{"id":"inner","wjmc":"课件.pdf","sfwjj":"0","sfkxz":"1","wjhzm":"pdf","wjsize":"1MB","czsj":"2026-09-22"}]);
        script.extend([
            step(
                "spocnewht/inco/ht/queryOne",
                vpn,
                200,
                "application/json",
                r#"{"code":200,"content":{"mrxq":"term"}}"#,
            ),
            step(
                "spocnewht/jxkj/queryKclb?kcmc=&xnxq=term",
                vpn,
                200,
                "application/json",
                r#"{"code":200,"content":[{"kcid":"course","kcmc":"合成课","skjs":"合成教师"}]}"#,
            ),
            page(vpn, None, 1, 2, &first),
            page(
                vpn,
                None,
                2,
                2,
                &json!([{"id":"other","wjmc":"a/b","sfwjj":"0","sfkxz":null}]),
            ),
            page(vpn, Some("folder"), 1, 1, &child),
            page(vpn, None, 1, 0, &json!([])),
        ]);
        let (mut client, transport, _root) = client(script, vpn);
        let courses = client.spoc_courses().await.unwrap().data;
        assert_eq!(courses[0].course_id, "course");
        assert_eq!(courses[0].teacher.as_deref(), Some("合成教师"));
        let items = client.spoc_course_files("course", None).await.unwrap().data;
        assert_eq!(items.len(), 3);
        assert!(items[0].is_folder && items[0].download_allowed);
        assert!(!items[1].download_allowed);
        assert_eq!(items[2].name, "a_b");
        assert!(items[2].download_allowed);
        let inner = client
            .spoc_course_files("course", Some("folder"))
            .await
            .unwrap()
            .data;
        assert!(inner[0].download_allowed);
        assert_eq!(inner[0].uploaded_at_text.as_deref(), Some("2026-09-22"));
        assert_eq!(
            client
                .spoc_course_files("course", None)
                .await
                .unwrap()
                .data
                .len(),
            0
        );
        for request in transport.requests().iter().skip(4) {
            assert_eq!(request.method, HttpMethod::Post);
            assert_eq!(request.body.len(), 0);
            assert_eq!(request.headers["RoleCode"], "01");
        }
        assert_eq!(
            client
                .spoc_course_files("course", Some(" "))
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::InvalidInput
        );
        transport.assert_exhausted();
    }
}
#[tokio::test]
async fn 超出页数上限不交付不完整目录() {
    let mut script = login(false, "fixture");
    script.extend((1..=100).map(|number| page(false, None, number, 101, &json!([]))));
    let (mut client, transport, _root) = client(script, false);
    assert_eq!(
        client
            .spoc_course_files("course", None)
            .await
            .unwrap_err()
            .error
            .code,
        ErrorCode::UpstreamChanged
    );
    transport.assert_exhausted();
}

#[tokio::test]
async fn 文件服务仅刷新一次并安全交付两类文件() {
    for vpn in [false, true] {
        let file = "inco-filesystem/fileManagerSystem/downLoadFile?scjlid=attachment";
        let course = "spocnewht/grwj1/downLoadFile?id=listed";
        let mut script = login(vpn, "old");
        script.push(step(
            file,
            vpn,
            403,
            "application/json",
            r#"{"code":0,"content":null}"#,
        ));
        script.extend(login(vpn, "fresh"));
        let mut binary = step(file, vpn, 200, "application/octet-stream", "binary");
        binary.1.headers.insert(
            "Content-Disposition".into(),
            vec!["attachment; filename=\"..%2F%E8%AF%BE+32.png\"".into()],
        );
        script.extend([
            binary,
            step(
                file,
                vpn,
                200,
                "application/json",
                r#"{"code":0,"content":null}"#,
            ),
            step(
                course,
                vpn,
                200,
                "application/json",
                r#"{"code":0,"msg":"异常错误","content":"fixture"}"#,
            ),
            step(course, vpn, 200, "application/octet-stream", "%PDF-"),
            step(file, vpn, 200, "application/octet-stream", "fallback"),
        ]);
        let (mut client, transport, root) = client(script, vpn);
        let dest = root.join("selected");
        let attachment = SpocDownloadTarget::AssignmentFile {
            file_id: "attachment".into(),
            file_name: Some("名称.zip".into()),
        };
        let item = SpocDownloadTarget::CourseFile {
            id: "listed".into(),
            name: "目录/合成.pdf".into(),
        };
        let receipt = client.spoc_download(&attachment, &dest).await.unwrap().data;
        assert_eq!(receipt.file_name, "__课 32.png");
        assert_eq!(receipt.byte_len, 6);
        assert_eq!(std::fs::read(&dest).unwrap(), b"binary");
        for target in [&attachment, &item] {
            assert_eq!(
                client
                    .spoc_download(target, &dest)
                    .await
                    .unwrap_err()
                    .error
                    .code,
                ErrorCode::BusinessRejected
            );
            assert_eq!(std::fs::read(&dest).unwrap(), b"binary");
        }
        let receipt = client.spoc_download(&item, &dest).await.unwrap().data;
        assert_eq!(receipt.file_name, "目录_合成.pdf");
        assert_eq!(std::fs::read(&dest).unwrap(), b"%PDF-");
        assert_eq!(
            client
                .spoc_download(&attachment, &dest)
                .await
                .unwrap()
                .data
                .file_name,
            "名称.zip"
        );
        for request in transport
            .requests()
            .iter()
            .filter(|r| r.url.contains("downLoadFile"))
        {
            assert!(!request.url.contains("token="));
            assert_eq!(request.body.len(), 0);
            if request.url.contains("inco-filesystem") {
                assert_eq!(request.method, HttpMethod::Get);
                assert_eq!(request.headers.contains_key("Cookie"), vpn);
                assert!(!request.headers.contains_key("RoleCode"));
            } else {
                assert_eq!(request.method, HttpMethod::Post);
                assert_eq!(request.headers["RoleCode"], "01");
            }
        }
        let requests = transport.requests();
        assert_eq!(requests[2].headers["Token"], "Inco-old");
        assert_eq!(requests[5].headers["Token"], "Inco-fresh");
        transport.assert_exhausted();
    }
}

#[tokio::test]
async fn 缺名时读取元数据且超大文件不覆盖已保存文件() {
    let file = "inco-filesystem/fileManagerSystem/downLoadFile?scjlid=fixture";
    let mut script = login(false, "fixture");
    let mut oversized = step(file, false, 200, "application/octet-stream", "");
    oversized.1.headers.insert(
        "Content-Length".into(),
        vec![(512_u64 * 1024 * 1024 + 1).to_string()],
    );
    script.extend([
        step(
            "inco-filesystem/fileManagerSystem/queryFileById?wjid=fixture",
            false,
            200,
            "application/json",
            r#"{"wjysmc":"目录/讲义.pdf"}"#,
        ),
        step(file, false, 200, "application/octet-stream", "saved"),
        oversized,
    ]);
    let (mut client, transport, root) = client(script, false);
    let path = root.join("chosen");
    let target = |name| SpocDownloadTarget::AssignmentFile {
        file_id: "fixture".into(),
        file_name: name,
    };
    let receipt = client
        .spoc_download(&target(None), &path)
        .await
        .unwrap()
        .data;
    assert_eq!(receipt.file_name, "目录_讲义.pdf");
    assert_eq!(
        client
            .spoc_download(&target(Some(receipt.file_name)), &path)
            .await
            .unwrap_err()
            .error
            .code,
        ErrorCode::InvalidInput
    );
    assert_eq!(std::fs::read(&path).unwrap(), b"saved");
    for request in transport.requests().iter().skip(2) {
        assert!(!request.headers.contains_key("Cookie"));
    }
    transport.assert_exhausted();
}
