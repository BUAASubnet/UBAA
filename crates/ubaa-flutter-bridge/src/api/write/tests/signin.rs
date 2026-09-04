use super::*;
use crate::api::write::BridgeSigninPerformRequest;

const USER_ID: &str = "user-safe";
const SCHEDULE_ID: &str = "schedule-safe";
const SESSION_ID: &str = "session-safe";

#[tokio::test]
async fn signin_prepare_reads_typed_authority_and_builds_safe_target_summary() {
    let root = test_root("prepare-signin");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        signin_entry_request(),
        signin_login_request(),
        signin_today_request(SCHEDULE_ID, Some(0)),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let intent = client
        .prepare_signin_perform(BridgeSigninPerformRequest {
            course_id: SCHEDULE_ID.into(),
        })
        .await
        .expect("允许目标应签发意图");

    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    for expected in ["脱敏课堂", SCHEDULE_ID, "08:00", "09:40", "可签到"] {
        assert!(
            intent.target_summary.contains(expected),
            "摘要缺少 {expected}"
        );
    }
    direct
        .assert_exhausted()
        .expect("prepare 只完成一轮只读复核");
    assert_eq!(direct.requests().expect("读取请求").len(), 3);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn signin_prepare_normalizes_public_target_before_preflight_and_storage() {
    let root = test_root("prepare-signin-normalized");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        signin_entry_request(),
        signin_login_request(),
        signin_today_request(SCHEDULE_ID, Some(0)),
        signin_today_request(SCHEDULE_ID, Some(0)),
        signin_timestamp_request(),
        signin_write_request(r#"{"STATUS":0,"ERRMSG":"ok","result":{"stuSignStatus":1}}"#),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let intent = client
        .prepare_signin_perform(BridgeSigninPerformRequest {
            course_id: format!("  {SCHEDULE_ID}  "),
        })
        .await
        .expect("Bridge 应在权威复核前规范化公开目标");
    let result = client
        .commit_write(intent.intent_id)
        .await
        .expect("规范化目标应原样保存到一次性意图");

    assert!(result.success);
    direct
        .assert_exhausted()
        .expect("不得使用带空白的第二个目标");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn signin_prepare_sanitizes_each_untrusted_summary_field() {
    let root = test_root("prepare-signin-summary");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let schedule_id = "schedule-safe\ncontinued";
    let direct = MockTransport::new([
        signin_entry_request(),
        signin_login_request(),
        signin_today_request_with_fields(schedule_id, Some(0), "脱敏\n课堂", "08:00\r", "09:40\t"),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    let intent = client
        .prepare_signin_perform(BridgeSigninPerformRequest {
            course_id: schedule_id.into(),
        })
        .await
        .expect("控制字符不得破坏安全摘要");

    assert!(intent.target_summary.contains("脱敏课堂"));
    assert!(intent.target_summary.contains("schedule-safecontinued"));
    assert!(intent.target_summary.contains("08:00"));
    assert!(intent.target_summary.contains("09:40"));
    assert!(!intent.target_summary.chars().any(char::is_control));
    direct.assert_exhausted().expect("prepare 只完成只读复核");
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn signin_prepare_rejects_denied_unknown_and_missing_action_without_write() {
    for (label, status) in [("denied", Some(1)), ("unknown", Some(2)), ("missing", None)] {
        let root = test_root(label);
        let _ = std::fs::remove_dir_all(&root);
        let store = seed_sessions(&root, true, false);
        let direct = MockTransport::new([
            signin_entry_request(),
            signin_login_request(),
            signin_today_request(SCHEDULE_ID, status),
        ]);
        let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
        install_core(
            &client,
            store,
            "[route]\ndefault = \"direct\"\n",
            direct.clone(),
            MockTransport::new([]),
        )
        .await;

        let error = client
            .prepare_signin_perform(BridgeSigninPerformRequest {
                course_id: SCHEDULE_ID.into(),
            })
            .await
            .expect_err("非允许资格必须拒绝");
        assert!(matches!(
            error.code,
            BridgeErrorCode::InvalidInput | BridgeErrorCode::UpstreamChanged
        ));
        assert!(client.write_intents.lock().await.is_empty());
        direct.assert_exhausted().expect("不得访问时间戳或写端点");
        assert_eq!(direct.requests().expect("读取请求").len(), 3);
        client.dispose().await.expect("销毁 bridge");
        let _ = std::fs::remove_dir_all(root);
    }
}

#[tokio::test]
async fn signin_commit_rechecks_fresh_authority_and_preserves_business_false() {
    let root = test_root("commit-signin-false");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        signin_entry_request(),
        signin_login_request(),
        signin_today_request(SCHEDULE_ID, Some(0)),
        signin_today_request(SCHEDULE_ID, Some(0)),
        signin_timestamp_request(),
        signin_write_request(
            r#"{"STATUS":0,"ERRMSG":"当前尚不可签到","result":{"stuSignStatus":0}}"#,
        ),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_signin_perform(BridgeSigninPerformRequest {
            course_id: SCHEDULE_ID.into(),
        })
        .await
        .expect("准备签到");

    let result = client
        .commit_write(intent.intent_id.clone())
        .await
        .expect("明确业务 false 应作为确定结果返回");

    assert!(!result.success);
    assert_eq!(result.message, "签到未完成");
    assert!(!result.message.contains("当前尚不可签到"));
    assert!(!result.outcome_unknown);
    direct.assert_exhausted().expect("最终写请求必须恰好一次");
    assert_eq!(direct.requests().expect("读取请求").len(), 6);
    let reused = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("业务拒绝也必须消费一次性意图");
    assert_eq!(reused.code, BridgeErrorCode::IntentExpired);
    assert_eq!(direct.requests().expect("读取请求").len(), 6);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn signin_commit_rejects_eligibility_drift_before_timestamp_or_write() {
    let root = test_root("commit-signin-drift");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        signin_entry_request(),
        signin_login_request(),
        signin_today_request(SCHEDULE_ID, Some(0)),
        signin_today_request(SCHEDULE_ID, Some(1)),
    ]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_signin_perform(BridgeSigninPerformRequest {
            course_id: SCHEDULE_ID.into(),
        })
        .await
        .expect("准备签到");

    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("提交前资格漂移必须拒绝");
    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    direct
        .assert_exhausted()
        .expect("漂移后不得请求时间戳或写端点");
    assert_eq!(direct.requests().expect("读取请求").len(), 4);
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

fn signin_entry_request() -> ExpectedRequest {
    let url = "https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter";
    ExpectedRequest::new(
        HttpMethod::Get,
        url,
        HttpResponse::new(
            200,
            format!("https://iclass.buaa.edu.cn:8346/?loginName={SESSION_ID}"),
            Vec::new(),
        ),
    )
}

fn signin_login_request() -> ExpectedRequest {
    let url = format!(
        "https://iclass.buaa.edu.cn:8346/eschool/app/user/login_buaa.do?password=&phone={SESSION_ID}&userLevel=1&verificationType=2&verificationUrl="
    );
    ExpectedRequest::new(
        HttpMethod::Get,
        &url,
        HttpResponse::new(
            200,
            &url,
            format!(r#"{{"STATUS":"0","result":{{"id":"{USER_ID}"}}}}"#).into_bytes(),
        ),
    )
}

fn signin_today_request(schedule_id: &str, status: Option<i32>) -> ExpectedRequest {
    signin_today_request_with_fields(schedule_id, status, "脱敏课堂", "08:00", "09:40")
}

fn signin_today_request_with_fields(
    schedule_id: &str,
    status: Option<i32>,
    course_name: &str,
    begin: &str,
    end: &str,
) -> ExpectedRequest {
    let url = format!(
        "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action?id={USER_ID}&dateStr={}",
        shanghai_date(),
    );
    let status = status
        .map(|value| format!(r#","signStatus":{value}"#))
        .unwrap_or_default();
    let body = format!(
        r#"{{"STATUS":"0","result":[{{"id":"{}","courseName":"{}","classBeginTime":"{}","classEndTime":"{}"{status}}}]}}"#,
        json_escape(schedule_id),
        json_escape(course_name),
        json_escape(begin),
        json_escape(end),
    );
    ExpectedRequest::new(
        HttpMethod::Get,
        &url,
        HttpResponse::new(200, &url, body.into_bytes()),
    )
}

fn json_escape(value: &str) -> String {
    value
        .replace('\\', r"\\")
        .replace('"', r#"\""#)
        .replace('\n', r"\n")
        .replace('\r', r"\r")
        .replace('\t', r"\t")
}

fn signin_timestamp_request() -> ExpectedRequest {
    let url = "https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action";
    ExpectedRequest::new(
        HttpMethod::Get,
        url,
        HttpResponse::new(200, url, br#"{"timestamp":"1700000000000"}"#.to_vec()),
    )
}

fn signin_write_request(body: &'static str) -> ExpectedRequest {
    let url = format!(
        "https://iclass.buaa.edu.cn:8347/eschool/app/course/stu_scan_sign.action?courseSchedId={SCHEDULE_ID}&timestamp=1700000000000"
    );
    ExpectedRequest::new(
        HttpMethod::Post,
        &url,
        HttpResponse::new(200, &url, body.as_bytes().to_vec()),
    )
}

fn shanghai_date() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |value| value.as_secs())
        + 8 * 60 * 60;
    let days = i64::try_from(seconds / 86_400).unwrap_or(i64::MAX);
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + i64::from(month <= 2);
    format!("{year:04}{month:02}{day:02}")
}
