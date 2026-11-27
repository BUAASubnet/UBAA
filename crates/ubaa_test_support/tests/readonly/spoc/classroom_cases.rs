use super::*;

fn kcid() -> String {
    fixture!("course-list")["content"][0]["kcid"]
        .as_str()
        .unwrap()
        .into()
}
#[tokio::test]
async fn 教师和未开通课程不进入后续请求() {
    for vpn in [false, true] {
        for (role, reason) in [
            (json!("1"), "role_teacher_unsupported"),
            (json!("3"), "role_teacher_unsupported"),
            (json!("6"), "role_teacher_unsupported"),
            (json!("2"), "bind_id_missing"),
            (json!("0"), "role_unsupported"),
            (json!(2), "role_shape"),
        ] {
            let mut steps = super::super::files::login(vpn, "fixture");
            let mut map = mapping(vpn, false);
            map[0].1.body = json!({"code":200,"content":role}).to_string().into_bytes();
            if role == "2" {
                map[1].1.body = br#"{"code":200,"content":{}}"#.to_vec();
                map.truncate(2);
            } else {
                map.truncate(1);
            }
            steps.extend(map);
            let (mut client, script, _root) = setup(vpn, steps);
            let error = client
                .spoc_classroom_catalog(&kcid())
                .await
                .unwrap_err()
                .error;
            assert_eq!(
                error.code,
                if role == "2" {
                    ErrorCode::BusinessUnavailable
                } else {
                    ErrorCode::Unsupported
                }
            );
            assert_eq!(error.diagnostic().reason.as_deref(), Some(reason));
            assert!(script.0.lock().unwrap().is_empty());
        }
    }
}
#[tokio::test]
async fn 两条路线仅将返回200的课堂映射网页判为未开通() {
    let unbound = fixture!("course-url-unbound");
    assert_eq!(unbound["body"].as_str().unwrap().len(), 1337);
    for vpn in [false, true] {
        for (status, content_type, unavailable) in [
            (200, None, true),
            (200, Some("Text/HTML"), true),
            (200, Some("application/json"), false),
            (200, Some("text/html-extra"), false),
            (404, None, false),
        ] {
            let mut steps = super::super::files::login(vpn, "fixture");
            let mut map = mapping(vpn, false);
            let mut fixture = unbound.clone();
            fixture["status"] = json!(status);
            if let Some(content_type) = content_type {
                fixture["headers"]["content-type"] = json!([content_type]);
            }
            map[2] = head(&map[2].0, &fixture);
            steps.extend(map);
            let (mut client, script, _root) = setup(vpn, steps);
            let error = client
                .spoc_classroom_catalog(&kcid())
                .await
                .unwrap_err()
                .error;
            let (code, reason) = if unavailable {
                (ErrorCode::BusinessUnavailable, "mapping_unbound_page")
            } else {
                (ErrorCode::UpstreamChanged, "mapping_status")
            };
            assert_eq!(error.code, code, "WebVPN={vpn}, HTTP {status}");
            if unavailable {
                assert_eq!(error.message, "该课程暂未在智学北航开通课堂");
            }
            assert_eq!(error.diagnostic().stage.as_deref(), Some("spoc_mapping"));
            assert_eq!(error.diagnostic().reason.as_deref(), Some(reason));
            assert!(script.0.lock().unwrap().is_empty());
        }
    }
}
#[tokio::test]
async fn 拒绝映射错误落点和认证链明文而不跟随() {
    for vpn in [false, true] {
        for target in [
            "http://classroom.msa.buaa.edu.cn/coursedetail?course_id=1",
            "https://classroom.msa.buaa.edu.cn.invalid/coursedetail?course_id=1",
            "https://classroom.msa.buaa.edu.cn/play?course_id=1",
            "https://classroom.msa.buaa.edu.cn/coursedetail?course_id=a1",
        ] {
            let mut steps = super::super::files::login(vpn, "fixture");
            let mut map = mapping(vpn, false);
            map[2]
                .1
                .headers
                .insert("location".into(), vec![route(vpn, target)]);
            steps.extend(map);
            let (mut client, script, _root) = setup(vpn, steps);
            assert_eq!(
                client
                    .spoc_classroom_catalog(&kcid())
                    .await
                    .unwrap_err()
                    .error
                    .code,
                ErrorCode::UpstreamChanged
            );
            assert!(script.0.lock().unwrap().is_empty());
        }
        let current = route(vpn, LOGIN);
        let (mut client, script, _root) =
            setup(vpn, vec![head(&current, &fixture!("casapi-http-redirect"))]);
        assert_eq!(
            client
                .spoc_classroom_transcript("200001", TEACHER)
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::UpstreamChanged
        );
        assert!(script.0.lock().unwrap().is_empty());
    }
}
#[tokio::test]
async fn 令牌带前缀可解析而缺失只报业务认证错误() {
    for vpn in [false, true] {
        for missing in [false, true] {
            let mut steps = auth(vpn);
            let old = "a%3A2";
            let prefix = "arbitrary-prefix-a%3A2";
            if vpn {
                let body = String::from_utf8(steps[4].1.body.clone()).unwrap();
                steps[4].1.body = if missing {
                    "other=no-token".into()
                } else {
                    body.replace(old, prefix)
                }
                .into_bytes();
            } else {
                let headers = &mut steps[2].1.headers;
                if missing {
                    headers.remove("set-cookie");
                } else {
                    let value = &mut headers.get_mut("set-cookie").unwrap()[0];
                    *value = value.replace(old, prefix);
                }
            }
            if !missing {
                steps.push(transcript(vpn, &fixture!("transcript")));
            }
            let (mut client, script, _root) = setup(vpn, steps);
            let result = client.spoc_classroom_transcript("200001", TEACHER).await;
            if missing {
                let error = result.unwrap_err().error;
                assert_eq!(error.kind, ubaa_test_support::ErrorKind::Authentication);
                assert_eq!(client.active_routes().len(), 2);
            } else {
                assert_eq!(result.unwrap().data.segments.len(), 2);
            }
            assert!(script.0.lock().unwrap().is_empty());
        }
    }
}
const IDENTITY: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp";
#[tokio::test]
async fn 自动路线重新认证且登出后不复用旧会话() {
    let body = fixture!("transcript");
    let mut steps = auth(false);
    steps.push(transcript(false, &body));
    let mut timeout = transcript(false, &body);
    timeout.1.status = 0;
    steps.push(timeout);
    steps.extend(identity(false, 200));
    steps.extend(identity(true, 200));
    steps.extend(auth(true));
    steps.push(transcript(true, &body));
    for vpn in [false, true] {
        steps.push(reply(
            &route(vpn, "https://sso.buaa.edu.cn/logout"),
            &Value::Null,
        ));
    }
    let (initial, script, root) = setup(false, steps);
    drop(initial);
    let store = FileSessionStore::new(&root).unwrap();
    let seeded = store.load_dual().unwrap().unwrap();
    let mut client = UbaaClient::with_routing(
        script.clone(),
        script.clone(),
        store.clone(),
        RouteConfig::default(),
        NoProbe,
    )
    .unwrap();
    assert_eq!(
        client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap()
            .resolution
            .mode,
        ConnectionMode::Direct
    );
    assert_eq!(
        client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap()
            .resolution
            .mode,
        ConnectionMode::WebVpn
    );
    let mut old_group = client.fork_parallel_readonly().unwrap();
    client.logout().await.unwrap();
    assert_eq!(client.active_routes().len(), 0);
    assert!(
        old_group
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .is_err()
    );
    assert_eq!(
        client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap_err()
            .error
            .code,
        ErrorCode::AuthenticationRequired
    );
    store.save_dual(&seeded).unwrap();
    let mut next = UbaaClient::with_routing(
        script.clone(),
        script.clone(),
        store,
        RouteConfig::parse("[route]\ndefault='direct'").unwrap(),
        NoProbe,
    )
    .unwrap();
    {
        let mut pending = script.0.lock().unwrap();
        pending.extend(auth(false));
        pending.push_back(transcript(false, &body));
    }
    next.spoc_classroom_transcript("200001", TEACHER)
        .await
        .unwrap();
    assert!(script.0.lock().unwrap().is_empty());
}
pub(super) fn identity(vpn: bool, status: u16) -> Vec<Step> {
    let url = route(vpn, IDENTITY);
    if status != 200 {
        return vec![(url.clone(), HttpResponse::new(status, url, vec![]))];
    }
    let ticket = ubaa_core::facade::testing::sso_fixture_ticket(&HttpRequest::get(&url)).unwrap();
    vec![(url,ticket),business(vpn,"https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON".into(),&json!({"user":"fixture","attributes":{"employeeNumber":["fixture"],"name":["测试"]}}))]
}
#[tokio::test]
async fn 认证失效只重试原读取一次并按主会话核验结果收尾() {
    for vpn in [false, true] {
        for (uc, http_unauthorized) in [
            (0, true),
            (0, false),
            (200, false),
            (503, false),
            (401, false),
        ] {
            let mut steps = auth(vpn);
            let mut rejected = transcript(vpn, &fixture!("missing-token"));
            if !vpn {
                steps[2].1.headers.get_mut("set-cookie").unwrap().push(
                    "MSA_ONLY=fixture-msa-cookie; Domain=.buaa.edu.cn; Path=/; Secure".into(),
                );
            }
            if http_unauthorized {
                rejected.1.status = 401;
            }
            steps.push(rejected);
            steps.extend(auth(vpn));
            steps.push(transcript(
                vpn,
                &if uc == 0 {
                    fixture!("transcript")
                } else {
                    fixture!("missing-token")
                },
            ));
            if uc != 0 {
                steps.extend(identity(vpn, uc));
            }
            let (mut client, script, root) = setup(vpn, steps);
            let result = client.spoc_classroom_transcript("200001", TEACHER).await;
            if uc == 0 {
                assert_eq!(result.unwrap().data.segments.len(), 2);
            } else {
                assert_eq!(
                    result.unwrap_err().error.code,
                    if uc == 401 {
                        ErrorCode::AuthenticationRequired
                    } else {
                        ErrorCode::UpstreamUnavailable
                    }
                );
                assert_eq!(client.active_routes().len(), if uc == 401 { 1 } else { 2 });
            }
            assert!(script.0.lock().unwrap().is_empty());
            if !vpn && uc == 200 {
                let stored = FileSessionStore::new(&root)
                    .unwrap()
                    .load_dual()
                    .unwrap()
                    .unwrap();
                let cookies = stored.sessions.direct.unwrap().cookies;
                assert!(
                    !cookies
                        .iter()
                        .any(|cookie| matches!(cookie.name.as_str(), "_token" | "MSA_ONLY"))
                );
            }
        }
    }
}

#[tokio::test]
async fn 状态拒绝不被响应文案改判为主会话失效() {
    for vpn in [false, true] {
        let mut steps = auth(vpn);
        let mut forbidden = transcript(vpn, &Value::Null);
        forbidden.1.status = 403;
        forbidden.1.body = "统一身份认证".as_bytes().to_vec();
        steps.push(forbidden);
        steps.push(transcript(
            vpn,
            &json!({"code":5077,"msg":"fixture-private-message"}),
        ));
        let (mut client, script, _root) = setup(vpn, steps);
        let forbidden = client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap_err()
            .error;
        assert_eq!(forbidden.code, ErrorCode::PermissionDenied);
        let unavailable = client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap_err()
            .error;
        assert_eq!(unavailable.code, ErrorCode::UpstreamUnavailable);
        assert_eq!(unavailable.diagnostic().upstream_code, Some(5077));
        assert!(!unavailable.message.contains("fixture-private-message"));
        assert!(script.0.lock().unwrap().is_empty());
    }
}
#[tokio::test]
async fn 媒体主机协议和端口必须匹配且网关还原原查询() {
    for vpn in [false, true] {
        let mut steps = auth(vpn);
        let mut live = fixture!("sub-live");
        let original = live["data"]["live_url"]["output"]["m3u8"]
            .as_str()
            .unwrap()
            .replace(":443/", "/");
        live["data"]["live_url"]["output"]["m3u8"] = json!(route(vpn, &original));
        live["data"]["live_url"]["output_student"]["m3u8"] =
            json!("https://lmt9.buaa.edu.cn:8443/test");
        steps.push(session(vpn, "100002", "200003", &live));
        let mut bad = fixture!("sub-recording");
        bad["data"]["video_list"]["0"]["preview_url"] =
            json!("https://resource.msa.buaa.edu.cn.invalid/test");
        bad["data"]["video_list"]["1"]["preview_url"] =
            json!(route(vpn, "http://resource.msa.buaa.edu.cn/test"));
        bad["data"]["playurl"]["0"] = json!("");
        steps.push(session(vpn, "100001", "200001", &bad));
        let (mut client, script, _root) = setup(vpn, steps);
        let media = client
            .spoc_classroom_session("100002", "200003")
            .await
            .unwrap()
            .data
            .sources;
        assert_eq!(media.len(), 1);
        assert_eq!(media[0].url, original);
        assert_eq!(
            client
                .spoc_classroom_session("100001", "200001")
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::UpstreamChanged
        );
        assert!(script.0.lock().unwrap().is_empty());
    }
}
