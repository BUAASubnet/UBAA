use super::*;
use ubaa_core::facade::{LoginInput, SecretValue};

fn kcid() -> String {
    fixture!("course-list")["content"][0]["kcid"]
        .as_str()
        .unwrap()
        .into()
}

#[tokio::test]
async fn 仅学生样本可发签名请求() {
    for role in [
        json!("1"),
        json!("3"),
        json!("6"),
        json!("0"),
        json!(""),
        json!(2),
        json!(null),
    ] {
        let mut steps = super::super::files::login(false, "fixture");
        let mut map = mapping(false, false);
        map[0].1.body = json!({"code":200,"content":role}).to_string().into_bytes();
        steps.push(map.remove(0));
        let (mut client, script, _root) = setup(false, steps);
        let error = client
            .spoc_classroom_catalog(&kcid())
            .await
            .unwrap_err()
            .error;
        assert_eq!(error.code, ErrorCode::Unsupported);
        assert_eq!(
            error.message,
            if matches!(role.as_str(), Some("1" | "3" | "6")) {
                "暂不支持教师身份"
            } else {
                "暂不支持当前身份"
            }
        );
        assert!(script.0.lock().unwrap().is_empty());
    }
}

#[tokio::test]
async fn 课堂标识校验长度字符并去除课程首尾空白() {
    let (mut client, _, _root) = setup(false, vec![]);
    for invalid in [" ", "a\u{1f}z", &"x".repeat(129)] {
        assert_eq!(
            client
                .spoc_classroom_catalog(invalid)
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::InvalidInput
        );
    }
    for (course, sub) in [
        ("12a", "2"),
        ("１２", "2"),
        (&"1".repeat(21), "2"),
        ("1", &"2".repeat(21)),
    ] {
        assert_eq!(
            client
                .spoc_classroom_session(course, sub)
                .await
                .unwrap_err()
                .error
                .code,
            ErrorCode::InvalidInput
        );
    }
    let mut steps = super::super::files::login(false, "fixture");
    let mut map = mapping(false, false);
    map[0].1.body = br#"{"code":200,"content":"1"}"#.to_vec();
    steps.push(map.remove(0));
    let (mut client, script, _root) = setup(false, steps);
    assert_eq!(
        client
            .spoc_classroom_catalog(&format!("  {}  ", kcid()))
            .await
            .unwrap_err()
            .error
            .code,
        ErrorCode::Unsupported
    );
    assert!(script.0.lock().unwrap().is_empty());
}

#[tokio::test]
async fn 映射拒绝篡改入口和不安全签名字段() {
    for (key, value) in [
        ("ktsl_url", "https://example.invalid/?"),
        (
            "ktsl_url",
            "https://yjapi.msa.buaa.edu.cn/coursescheduleapi/v2/bh-university/get-bh-course-url",
        ),
        ("ktsl_url", "https://yjapi.msa.buaa.edu.cn/other?"),
        ("signature", "sig&extra=1"),
        ("username", "a b"),
    ] {
        let mut steps = super::super::files::login(false, "fixture");
        let mut map = mapping(false, false);
        let mut signature = fixture!("signature-a");
        signature["content"][key] = json!(value);
        map[1].1.body = signature.to_string().into_bytes();
        steps.extend(map.into_iter().take(2));
        let (mut client, script, _root) = setup(false, steps);
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
}

#[tokio::test]
async fn 映射只对姓名按前端规则编码并隔离主会话() {
    for vpn in [false, true] {
        let mut steps = super::super::files::login(vpn, "fixture");
        let mut map = mapping(vpn, false);
        let mut signature = fixture!("signature-a");
        signature["content"]["realname"] = json!("A 中-_.!~*'()+");
        map[1].1.body = signature.to_string().into_bytes();
        map[2].0 = map[2].0.replace(
            "%E6%B5%8B%E8%AF%95%E5%AD%A6%E7%94%9F",
            "A%20%E4%B8%AD-_.!~*'()%2B",
        );
        steps.extend(map);
        steps.extend(auth(vpn));
        steps.push(business(
            vpn,
            format!(
                "{YJ}/courseapi/v3/multi-search/get-course-detail?course_id=100001&student=91024683"
            ),
            &fixture!("course-detail"),
        ));
        let mut cookie =
            StoredCookie::fixture(if vpn { "_token" } else { "MAIN_ONLY" }, "fixture-parent");
        cookie.domain = if vpn { "d.buaa.edu.cn" } else { "buaa.edu.cn" }.into();
        cookie.host_only = vpn;
        let (mut client, script, _root) = setup_with_cookies(vpn, steps, &[cookie]);
        client.spoc_classroom_catalog(&kcid()).await.unwrap();
        assert!(script.0.lock().unwrap().is_empty());
    }
}

#[tokio::test]
async fn 映射拒绝重复课程号异常权限段和跨路线包装() {
    let good = format!("{CLASS}/coursedetail?course_id=1");
    for vpn in [false, true] {
        let mut targets = vec![
            format!("{good}&course_id=2"),
            good.replace("https://", "https://user@"),
            good.replace(".cn/", ".cn:8443/"),
            route(true, &good).replace("/https/", "/http/"),
        ];
        if !vpn {
            targets.push(route(true, &good));
        }
        for target in targets {
            let mut steps = super::super::files::login(vpn, "fixture");
            let mut map = mapping(vpn, false);
            map[2].1.headers.insert("location".into(), vec![target]);
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
    }
}

#[tokio::test]
async fn 课堂认证逐跳拒绝非允许主机和空票据() {
    for vpn in [false, true] {
        for (hop, target) in [
            (0, "https://other.invalid/login".into()),
            (
                1,
                LOGIN.replace("yjapi.msa.buaa.edu.cn", "other.invalid") + "&ticket=ST-fixture",
            ),
            (1, format!("{LOGIN}&ticket=")),
            (2, LOGIN.replace("yjapi.msa.buaa.edu.cn", "other.invalid")),
            (3, "https://other.invalid/".into()),
            (0, route(true, "http://classroom.msa.buaa.edu.cn/")),
        ] {
            let mut steps = auth(vpn);
            steps[hop]
                .1
                .headers
                .insert("location".into(), vec![route(vpn, &target)]);
            steps.truncate(hop + 1);
            let (mut client, script, _root) = setup(vpn, steps);
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
}

#[tokio::test]
async fn 课堂业务重定向不跟随也不转发授权头() {
    for vpn in [false, true] {
        let mut steps = auth(vpn);
        let mut response = transcript(vpn, &Value::Null);
        response.1.status = 302;
        response
            .1
            .headers
            .insert("Location".into(), vec!["https://other.invalid/".into()]);
        steps.push(response);
        let (mut client, script, _root) = setup(vpn, steps);
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

fn auth_with(vpn: bool, jwt: &str) -> Vec<Step> {
    assert_eq!(jwt.len(), 8);
    let mut steps = auth(vpn);
    if vpn {
        steps[4].1.body = String::from_utf8(steps[4].1.body.clone())
            .unwrap()
            .replace("TEST_JWT", jwt)
            .into_bytes();
    } else {
        let cookie = &mut steps[2].1.headers.get_mut("set-cookie").unwrap()[0];
        *cookie = cookie.replace("TEST_JWT", jwt);
    }
    steps
}
fn with_bearer(mut step: Step, jwt: &str) -> Step {
    step.1
        .headers
        .insert("fixture-bearer".into(), vec![format!("Bearer {jwt}")]);
    step
}

#[tokio::test]
async fn 两个并发读取遇到5002只重新认证一次() {
    for vpn in [false, true] {
        let ok = transcript(vpn, &fixture!("transcript"));
        let rejected = transcript(vpn, &fixture!("missing-token"));
        let mut steps = auth(vpn);
        steps.extend([ok.clone(), rejected.clone(), rejected]);
        steps.extend(auth_with(vpn, "NEXT_JWT"));
        steps.extend([
            with_bearer(ok.clone(), "NEXT_JWT"),
            with_bearer(ok, "NEXT_JWT"),
        ]);
        let (mut client, script, _root) = setup(vpn, steps);
        client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap();
        let mut first = client.fork_parallel_readonly().unwrap();
        let mut second = client.fork_parallel_readonly().unwrap();
        let (left, right) = tokio::join!(
            first.spoc_classroom_transcript("200001", TEACHER),
            second.spoc_classroom_transcript("200001", TEACHER)
        );
        left.unwrap();
        right.unwrap();
        assert!(script.0.lock().unwrap().is_empty());
    }
}

#[tokio::test]
async fn 同一客户端重新登录与更换账号后使用新课堂令牌() {
    let (mut client, script, _root) = setup(false, vec![]);
    for (index, (account, jwt)) in [
        ("fixture-a", "OLD1_JWT"),
        ("fixture-a", "NEW1_JWT"),
        ("fixture-b", "NEW2_JWT"),
    ]
    .into_iter()
    .enumerate()
    {
        if index == 2 {
            for vpn in [false, true] {
                script.0.lock().unwrap().push_back(reply(
                    &route(vpn, "https://sso.buaa.edu.cn/logout"),
                    &Value::Null,
                ));
            }
            client.logout().await.unwrap();
        }
        let url = "https://sso.buaa.edu.cn/login";
        let login = head(
            url,
            &json!({"status":302,"body":"","headers":{"location":["/ready"],"set-cookie":["NAV=fixture; Path=/; Secure"]}}),
        );
        let mut steps = cases::identity(false, 200);
        steps[1].1.body =
            json!({"user":account,"attributes":{"employeeNumber":[account],"name":["测试"]}})
                .to_string()
                .into_bytes();
        steps.insert(0, login);
        steps.extend(auth_with(false, jwt));
        steps.push(with_bearer(transcript(false, &fixture!("transcript")), jwt));
        script.0.lock().unwrap().extend(steps);
        client
            .login_required_route(
                ConnectionMode::Direct,
                LoginInput {
                    username: account.into(),
                    password: SecretValue::new("fixture"),
                },
            )
            .await
            .unwrap();
        client
            .spoc_classroom_transcript("200001", TEACHER)
            .await
            .unwrap();
        assert!(script.0.lock().unwrap().is_empty());
    }
}
