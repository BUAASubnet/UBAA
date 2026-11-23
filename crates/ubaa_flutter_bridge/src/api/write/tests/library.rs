use super::*;
use crate::api::write::BridgeLibraryLoanRenewRequest;

const LIST: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/loans?page=1&pageSize=20";
const MAX: &str =
    "https://space.lib.buaa.edu.cn/meta-local/opac/users/loan_max_renew_times?page=1&pageSize=20";
const RENEW: &str = "https://space.lib.buaa.edu.cn/meta-local/opac/users/batch_renew";

fn list_request(renew: u32) -> ExpectedRequest {
    let body = format!(
        r#"{{"code":0,"msg":null,"data":{{"currentPage":1,"pageSize":20,"total":1,"totalPage":1,"items":[{{"loanId":"loan-1","title":"合成书目","author":"合成作者","item":{{"barCode":"bar-1"}},"location":"合成馆藏地","loanDate":"2026-11-01","dueDate":"2026-12-01","renewTimes":{renew},"loanStatus":"soon"}}]}}}}"#
    );
    ExpectedRequest::new(
        HttpMethod::Get,
        LIST,
        HttpResponse::new(200, LIST, body.into_bytes()),
    )
}

fn max_request(max: u32) -> ExpectedRequest {
    let body =
        format!(r#"{{"code":0,"data":{{"items":[{{"barCode":"bar-1","maxRenewTimes":{max}}}]}}}}"#);
    ExpectedRequest::new(
        HttpMethod::Get,
        MAX,
        HttpResponse::new(200, MAX, body.into_bytes()),
    )
}

#[tokio::test]
async fn 借阅续借准备与提交使用单个记录标识且不自动重试() {
    let root = test_root("library-renew");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        list_request(1),
        max_request(3),
        ExpectedRequest::new(
            HttpMethod::Post,
            RENEW,
            HttpResponse::new(
                200,
                RENEW,
                r#"{"code":0,"msg":"外层说明","data":null}"#.as_bytes().to_vec(),
            ),
        ),
    ]);
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_library_loan_renew(BridgeLibraryLoanRenewRequest {
            loan_id: " loan-1 ".into(),
        })
        .await
        .expect("唯一可续借目标应签发意图");
    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::LibraryLoanRenew
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert!(intent.target_summary.contains("合成书目"));
    assert!(intent.target_summary.contains("2026-12-01"));
    assert!(!intent.target_summary.chars().any(char::is_control));
    let target = intent
        .library_loan_renew_target
        .expect("预检记录用于写后核对");
    assert_eq!(target.loan_id, "loan-1");
    assert_eq!(target.due_date.as_deref(), Some("2026-12-01"));
    assert_eq!(target.renew_times, Some(1));

    let result = client
        .commit_write(intent.intent_id)
        .await
        .expect("学校接受续借");
    assert!(result.success);
    assert!(!result.outcome_unknown);
    assert_eq!(result.message, "续借成功");

    direct
        .assert_exhausted()
        .expect("续借必须完成一次复核读取和一次提交");
    let requests = direct.requests().expect("读取 Direct 请求");
    assert_eq!(requests.len(), 3);
    assert_eq!(webvpn.requests().expect("读取 WebVPN 请求").len(), 0);
    let request = requests
        .iter()
        .find(|request| request.url.ends_with("/batch_renew"))
        .expect("缺少续借请求");
    assert_eq!(
        String::from_utf8(request.body.clone()).unwrap(),
        r#"{"loanIds":["loan-1"],"source":1}"#
    );
    assert_eq!(
        request.headers.get("Content-Type").map(String::as_str),
        Some("application/json")
    );
    assert_eq!(
        request.headers.get("X-Hw-Lang").map(String::as_str),
        Some("chi")
    );
    assert_eq!(
        request.headers.get("X-Hw-explorer").map(String::as_str),
        Some("m")
    );
    assert_eq!(
        request.headers.get("X-CSRF-TOKEN").map(String::as_str),
        Some("")
    );
    client.dispose().await.expect("销毁 bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 借阅续借拒绝已用尽的目标且不发送写请求() {
    let root = test_root("library-renew-exhausted");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([list_request(3), max_request(3)]);
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
        .prepare_library_loan_renew(BridgeLibraryLoanRenewRequest {
            loan_id: "loan-1".into(),
        })
        .await
        .expect_err("已用尽续借次数不得签发写意图");
    assert_eq!(error.code, BridgeErrorCode::InvalidInput);
    direct.assert_exhausted().unwrap();
    let requests = direct.requests().unwrap();
    assert!(
        requests
            .iter()
            .all(|request| request.method == HttpMethod::Get)
    );
    client.dispose().await.unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 借阅续借业务拒绝仅返回目标的学校原因() {
    let root = test_root("library-renew-rejected");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let direct = MockTransport::new([
        list_request(0),
        max_request(3),
        ExpectedRequest::new(
            HttpMethod::Post,
            RENEW,
            HttpResponse::new(
                200,
                RENEW,
                r#"{"code":0,"msg":"外层说明","data":{"loan-2":"另一记录原因","loan-1":"META-403060: 不允许续借,未达到到期前续借天数"}}"#
                    .as_bytes()
                    .to_vec(),
            ),
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
        .prepare_library_loan_renew(BridgeLibraryLoanRenewRequest {
            loan_id: "loan-1".into(),
        })
        .await
        .unwrap();
    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("学校拒绝续借");
    assert_eq!(error.code, BridgeErrorCode::BusinessRejected);
    assert_eq!(
        error.message,
        "META-403060: 不允许续借,未达到到期前续借天数"
    );
    let diagnostic = error.diagnostic_json.as_deref().unwrap();
    assert!(!diagnostic.contains("META-403060"));
    assert!(!diagnostic.contains("到期前"));
    assert!(!format!("{error:?} {error}").contains("到期前"));
    assert!(!error.retryable);
    direct.assert_exhausted().unwrap();
    client.dispose().await.unwrap();
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 借阅核对固定调用方路线且不重新选择_auto() {
    use ubaa_core::facade::testing::to_webvpn_url;
    let root = test_root("library-pinned-readback");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, false, true);
    let list = to_webvpn_url(LIST).unwrap();
    let max = to_webvpn_url(MAX).unwrap();
    let webvpn = MockTransport::new([
        ExpectedRequest::new(
            HttpMethod::Get,
            list.clone(),
            HttpResponse::new(
                200,
                &list,
                r#"{"code":0,"data":{"currentPage":1,"pageSize":20,"total":1,"totalPage":1,"items":[{"loanId":"loan-1","title":"合成书目","item":{"barCode":"bar-1"},"dueDate":"2027-01-05","renewTimes":2}]}}"#
                    .as_bytes()
                    .to_vec(),
            ),
        ),
        ExpectedRequest::new(
            HttpMethod::Get,
            max.clone(),
            HttpResponse::new(
                200,
                &max,
                br#"{"code":0,"data":{"items":[{"barCode":"bar-1","maxRenewTimes":3}]}}"#.to_vec(),
            ),
        ),
    ]);
    let direct = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let result = client
        .current_library_loans_on_route(BridgeConnectionMode::WebVpn)
        .await
        .expect("固定 WebVPN 读取借阅");
    assert_eq!(result.pinned_route, BridgeConnectionMode::WebVpn);
    assert_eq!(result.data.entries.len(), 1);
    assert_eq!(result.data.entries[0].can_renew_times, Some(1));
    assert_eq!(direct.requests().unwrap().len(), 0);
    webvpn.assert_exhausted().unwrap();
    client.dispose().await.unwrap();
    let _ = std::fs::remove_dir_all(root);
}
