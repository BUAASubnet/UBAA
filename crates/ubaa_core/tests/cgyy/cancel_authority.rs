use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use chrono::NaiveDateTime;
use ubaa_core::facade::testing::HttpMethod;
use ubaa_core::facade::testing::{
    FileSessionStore, SessionMutation, SessionSnapshot, SessionStore, VersionedSession,
};
use ubaa_core::facade::{
    ActionEligibility, CgyyCancelOrderRequest, ConnectionMode, ErrorCode, ErrorKind, Result,
    RouteClient, UbaaError,
};

use super::cancel_support::{
    CANCEL_PATH, CancelReply, DETAIL_PATH, DetailReply, ORDER_ID, Scenario, allowed_order_row,
    cleanup, client_for, client_for_at, detail_response, order_row, request, request_for_path,
    runtime,
};

#[test]
fn 场馆取消在任何网络前拒绝非正订单标识() {
    for (case, order_id) in [("zero", 0), ("negative", -1)] {
        let scenario = Scenario::new([]);
        let (mut client, root) = client_for(&format!("invalid-prepare-{case}"), scenario.clone());
        let error = runtime()
            .block_on(client.preflight_cgyy_cancel(&CgyyCancelOrderRequest { order_id }))
            .expect_err("非正订单标识必须在 prepare 网络前拒绝");
        assert_eq!(
            (error.code, error.kind, error.retryable),
            (ErrorCode::InvalidInput, ErrorKind::Input, false),
            "prepare {case}"
        );
        assert!(scenario.requests().is_empty(), "prepare {case}");
        cleanup(root);

        let scenario = Scenario::new([]);
        let (mut client, root) = client_for(&format!("invalid-commit-{case}"), scenario.clone());
        let error = runtime()
            .block_on(client.cgyy_cancel_order(CgyyCancelOrderRequest { order_id }))
            .expect_err("非正订单标识必须在 commit 网络前拒绝");
        assert_eq!(
            (error.code, error.kind, error.retryable),
            (ErrorCode::InvalidInput, ErrorKind::Input, false),
            "commit {case}"
        );
        assert!(scenario.requests().is_empty(), "commit {case}");
        cleanup(root);
    }
}

#[test]
fn 场馆订单只从_canonical_id_状态和上海时间派生取消_action() {
    let cases = [
        (
            "normal-allowed",
            order_row("77", "1", "1", None, None),
            Some(1),
            Some(1),
            ActionEligibility::Allowed,
            true,
        ),
        (
            "occupy-allowed",
            order_row("77", "3", "6", None, None),
            Some(3),
            Some(6),
            ActionEligibility::Allowed,
            true,
        ),
        (
            "cancelled-denied",
            order_row("77", "2", "1", None, None),
            Some(2),
            Some(1),
            ActionEligibility::Denied,
            false,
        ),
        (
            "rejected-denied",
            order_row("77", "1", "-2", None, None),
            Some(1),
            Some(-2),
            ActionEligibility::Denied,
            false,
        ),
        (
            "zero-check-unknown",
            order_row("77", "1", "0", None, None),
            Some(1),
            Some(0),
            ActionEligibility::Unknown,
            false,
        ),
        (
            "other-order-unknown",
            order_row("77", "4", "1", None, None),
            Some(4),
            Some(1),
            ActionEligibility::Unknown,
            false,
        ),
        (
            "noncanonical-id-unknown",
            order_row(r#""077""#, "1", "1", None, None),
            Some(1),
            Some(1),
            ActionEligibility::Unknown,
            false,
        ),
        (
            "noncanonical-status-unknown",
            order_row("77", r#""01""#, "1", None, None),
            Some(1),
            Some(1),
            ActionEligibility::Unknown,
            false,
        ),
    ];

    for (case, row, order_status, check_status, eligibility, has_target) in cases {
        let scenario = Scenario::new([detail_response(&row)]);
        let (mut client, root) = client_for(case, scenario);
        let order = runtime()
            .block_on(client.cgyy_order_detail(ORDER_ID))
            .expect("普通详情仍应按兼容 DTO 解析")
            .data;
        assert_eq!(order.order_status, order_status, "{case}");
        assert_eq!(order.check_status, check_status, "{case}");
        assert_eq!(order.cancel_eligibility, eligibility, "{case}");
        assert_eq!(order.cancel_target.is_some(), has_target, "{case}");
        if let Some(target) = order.cancel_target {
            assert_eq!(target.order_id, ORDER_ID, "{case}");
        }
        cleanup(root);
    }
}

#[test]
fn 场馆订单取消核对目标只接受_canonical_id_与_canonical_已取消状态() {
    let cases = [
        (
            "canonical-cancelled",
            order_row("77", "2", "1", None, None),
            Some(ORDER_ID),
        ),
        (
            "noncanonical-id",
            order_row(r#""077""#, "2", "1", None, None),
            None,
        ),
        (
            "noncanonical-status",
            order_row("77", r#""02""#, "1", None, None),
            None,
        ),
        ("not-cancelled", order_row("77", "1", "1", None, None), None),
    ];

    for (case, row, expected_order_id) in cases {
        let scenario = Scenario::new([detail_response(&row)]);
        let (mut client, root) = client_for(case, scenario);
        let order = runtime()
            .block_on(client.cgyy_order_detail(ORDER_ID))
            .expect("兼容详情应可读取")
            .data;

        assert_eq!(
            order.cancelled_target.map(|target| target.order_id),
            expected_order_id,
            "{case}"
        );
        cleanup(root);
    }
}

#[test]
fn 场馆取消时间使用可注入上海时钟并保持冻结回退边界() {
    let cases = [
        (
            "before-deadline",
            "2026-04-04T06:29:59Z",
            Some("2026-04-04 18:30:00"),
            Some("2026-04-04 20:05:00"),
            ActionEligibility::Allowed,
        ),
        (
            "at-deadline",
            "2026-04-04T06:30:00Z",
            Some("2026-04-04 18:30:00"),
            Some("2026-04-04 20:05:00"),
            ActionEligibility::Denied,
        ),
        (
            "invalid-start-fallback-future-end",
            "2026-04-04T06:30:00Z",
            Some("invalid-start"),
            Some("2026-04-04 14:30:01"),
            ActionEligibility::Allowed,
        ),
        (
            "invalid-start-fallback-end-boundary",
            "2026-04-04T06:30:00Z",
            Some("invalid-start"),
            Some("2026-04-04 14:30:00"),
            ActionEligibility::Denied,
        ),
        (
            "both-invalid-no-extra-time-rule",
            "2026-04-04T06:30:00Z",
            Some("invalid-start"),
            Some("invalid-end"),
            ActionEligibility::Allowed,
        ),
    ];

    for (case, now, start, end, eligibility) in cases {
        let row = order_row("77", "1", "1", start, end);
        let scenario = Scenario::new([detail_response(&row)]);
        let (mut client, root) = client_for_at(case, scenario, now);
        let order = runtime()
            .block_on(client.cgyy_order_detail(ORDER_ID))
            .expect("场馆详情应可读取")
            .data;
        assert_eq!(order.cancel_eligibility, eligibility, "{case}");
        assert_eq!(
            order.cancel_target.is_some(),
            eligibility == ActionEligibility::Allowed,
            "{case}"
        );
        cleanup(root);
    }
}

#[test]
fn 场馆取消可解析开始时间的四小时下溢必须失败关闭且不能回退结束时间() {
    let start = NaiveDateTime::MIN.format("%Y-%m-%d %H:%M:%S").to_string();
    assert_eq!(
        NaiveDateTime::parse_from_str(&start, "%Y-%m-%d %H:%M:%S").ok(),
        Some(NaiveDateTime::MIN),
        "测试开始时间必须能被生产格式解析"
    );
    let row = order_row("77", "1", "1", Some(&start), Some("2099-04-04 20:05:00"));
    let scenario = Scenario::new([detail_response(&row)]);
    let (mut client, root) = client_for("deadline-underflow", scenario);

    let order = runtime()
        .block_on(client.cgyy_order_detail(ORDER_ID))
        .expect("兼容详情应可读取")
        .data;

    assert_eq!(order.cancel_eligibility, ActionEligibility::Unknown);
    assert!(order.cancel_target.is_none());
    cleanup(root);
}

#[test]
fn 场馆取消预检只读一次详情并返回安全_typed_摘要() {
    let row = order_row(
        "77",
        "3",
        "6",
        Some("2026-04-04T18:30:00"),
        Some("2026-04-04 20:05"),
    );
    let scenario = Scenario::new([detail_response(&row)]);
    let (mut client, root) = client_for_at("preflight", scenario.clone(), "2026-04-04T06:29:59Z");

    let preflight = runtime()
        .block_on(client.preflight_cgyy_cancel(&request()))
        .expect("唯一明确允许的同 ID 订单应通过预检")
        .data;

    assert_eq!(preflight.target.order_id, ORDER_ID);
    assert_eq!(preflight.order_status, 3);
    assert_eq!(preflight.check_status, 6);
    assert_eq!(
        preflight.reservation_start_date.as_deref(),
        Some("2026-04-04 18:30:00")
    );
    assert_eq!(
        preflight.reservation_end_date.as_deref(),
        Some("2026-04-04 20:05:00")
    );
    assert_eq!(scenario.detail_count(), 1);
    assert_eq!(scenario.cancel_count(), 0);
    cleanup(root);
}

#[test]
fn 场馆取消权威拒绝非对象非_canonical_非同_id_与状态不足且不发送() {
    let cases = [
        (
            "null",
            r#"{"code":200,"data":null}"#.to_owned(),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "array",
            r#"{"code":200,"data":[]}"#.to_owned(),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "missing-id",
            detail_response(r#"{"orderStatus":1,"checkStatus":1}"#),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "noncanonical-id",
            detail_response(&order_row(r#""077""#, "1", "1", None, None)),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "zero-id",
            detail_response(&order_row("0", "1", "1", None, None)),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "wrong-id",
            detail_response(&order_row("78", "1", "1", None, None)),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "cancelled",
            detail_response(&order_row("77", "2", "1", None, None)),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "negative-check",
            detail_response(&order_row("77", "1", "-3", None, None)),
            ErrorCode::InvalidInput,
            true,
        ),
        (
            "missing-check",
            detail_response(r#"{"id":77,"orderStatus":1}"#),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "zero-check",
            detail_response(&order_row("77", "1", "0", None, None)),
            ErrorCode::UpstreamChanged,
            false,
        ),
        (
            "unknown-order",
            detail_response(&order_row("77", "9", "1", None, None)),
            ErrorCode::UpstreamChanged,
            false,
        ),
    ];

    for (case, detail, code, retryable) in cases {
        let scenario = Scenario::new([detail]);
        let (mut client, root) = client_for(case, scenario.clone());
        let error = runtime()
            .block_on(client.cgyy_cancel_order(request()))
            .expect_err("资格不足或身份不明必须在最终 POST 前拒绝");
        assert_eq!((error.code, error.retryable), (code, retryable), "{case}");
        assert_eq!(scenario.detail_count(), 1, "{case}");
        assert_eq!(scenario.cancel_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 显式预检通过后提交仍重新读取并拒绝资格漂移() {
    let scenario = Scenario::new([
        detail_response(&allowed_order_row()),
        detail_response(&order_row("77", "2", "1", None, None)),
    ]);
    let (mut client, root) = client_for("fresh-drift", scenario.clone());

    runtime()
        .block_on(client.preflight_cgyy_cancel(&request()))
        .expect("首次预检应允许");
    let error = runtime()
        .block_on(client.cgyy_cancel_order(request()))
        .expect_err("commit 必须 fresh 复核并拒绝漂移");

    assert_eq!(
        (error.code, error.retryable),
        (ErrorCode::InvalidInput, true)
    );
    assert_eq!(scenario.detail_count(), 2);
    assert_eq!(scenario.cancel_count(), 0);
    cleanup(root);
}

#[test]
fn 场馆取消提交经非幂等边界只发送一次空表单并返回固定安全结果() {
    let scenario = Scenario::new([detail_response(&allowed_order_row())]).with_cancel(
        CancelReply::Response(
            200,
            r#"{"code":200,"message":"取消成功 token=secret\n学号=private","data":{"phone":"private"}}"#.into(),
        ),
    );
    let (mut client, root) = client_for("success", scenario.clone());

    let result = runtime()
        .block_on(client.cgyy_cancel_order(request()))
        .expect("canonical code=200 应产生固定安全成功")
        .data;

    assert!(result.success);
    assert_eq!(result.message, "场馆预约订单已取消");
    for fragment in ["secret", "private", "学号", "token", "\n"] {
        assert!(
            !result.message.contains(fragment),
            "结果暴露了 {fragment:?}"
        );
    }
    assert_eq!(scenario.detail_count(), 1);
    assert_eq!(scenario.cancel_count(), 1);
    assert_eq!(scenario.login_count(), 1);
    let requests = scenario.requests();
    let cancel = request_for_path(&requests, CANCEL_PATH);
    assert_eq!(cancel.method, HttpMethod::Post);
    assert!(cancel.body.is_empty());
    assert_eq!(
        cancel.headers.get("Content-Type").map(String::as_str),
        Some("application/x-www-form-urlencoded")
    );
    assert_eq!(
        cancel.headers.get("Accept").map(String::as_str),
        Some("application/json, text/plain, */*")
    );
    assert!(cancel.headers.contains_key("app-key"));
    assert!(cancel.headers.contains_key("timestamp"));
    assert!(cancel.headers.contains_key("sign"));
    assert!(cancel.headers.contains_key("cgAuthorization"));
    cleanup(root);
}

#[test]
fn 场馆取消最终发送前会话修订检查失败保留原错误且不误报结果未知() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-cgyy-cancel-pre-send-revision-{}-{:?}",
        std::process::id(),
        std::thread::current().id(),
    ));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).expect("创建场馆取消测试会话存储");
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .expect("写入初始脱敏会话");
    let scenario = Scenario::new([detail_response(&allowed_order_row())]);
    let revision_checks = Arc::new(AtomicUsize::new(0));
    let guarded_store = ThirdRevisionCheckFails {
        inner: store,
        checks: Arc::clone(&revision_checks),
    };
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, scenario.clone(), guarded_store)
            .expect("创建场馆取消测试客户端");

    let error = runtime()
        .block_on(client.cgyy_cancel_order(request()))
        .expect_err("发送前会话修订检查失败必须保留确定错误");

    assert_eq!(
        (error.code, error.kind, error.retryable),
        (ErrorCode::InternalError, ErrorKind::Internal, true)
    );
    assert_ne!(error.code, ErrorCode::OutcomeUnknown);
    assert_eq!(scenario.detail_count(), 1);
    assert_eq!(scenario.cancel_count(), 0);
    assert_eq!(revision_checks.load(Ordering::SeqCst), 4);
    cleanup(root);
}

#[test]
fn 场馆取消发送后所有歧义统一为不可重试_outcome_unknown_且不重放() {
    let success = r#"{"code":200,"message":"取消成功"}"#.to_owned();
    let cases = [
        ("transport", CancelReply::TransportError),
        ("http-500", CancelReply::Response(500, success.clone())),
        ("http-401", CancelReply::Response(401, success.clone())),
        ("redirect", CancelReply::Response(302, success.clone())),
        (
            "wrong-final-url",
            CancelReply::FinalUrl("https://sso.buaa.edu.cn/login", success.clone()),
        ),
        (
            "invalid-cookie",
            CancelReply::InvalidCookie(success.clone()),
        ),
        ("non-json", CancelReply::Response(200, "not-json".into())),
        ("array", CancelReply::Response(200, "[]".into())),
        (
            "missing-code",
            CancelReply::Response(200, r#"{"message":"取消成功"}"#.into()),
        ),
        (
            "noncanonical-code",
            CancelReply::Response(200, r#"{"code":"0200","message":"取消成功"}"#.into()),
        ),
        (
            "other-code",
            CancelReply::Response(
                200,
                r#"{"code":201,"message":"系统繁忙 token=secret"}"#.into(),
            ),
        ),
    ];

    for (case, reply) in cases {
        let scenario = Scenario::new([detail_response(&allowed_order_row())]).with_cancel(reply);
        let (mut client, root) = client_for(case, scenario.clone());
        let error = runtime()
            .block_on(client.cgyy_cancel_order(request()))
            .expect_err("越过发送边界后的歧义必须归为结果未知");
        assert_eq!(
            (error.code, error.kind, error.retryable),
            (ErrorCode::OutcomeUnknown, ErrorKind::Upstream, false),
            "{case}"
        );
        assert_eq!(
            error.message, "场馆取消请求已发送，结果未知，请刷新订单后再决定是否重试",
            "{case}"
        );
        for fragment in ["secret", "private", "学号", "token", "系统繁忙", "\n"] {
            assert!(
                !error.message.contains(fragment),
                "{case} 暴露了 {fragment:?}"
            );
        }
        assert_eq!(scenario.cancel_count(), 1, "{case}");
        assert_eq!(scenario.login_count(), 1, "{case} 不得重新认证重放");
        cleanup(root);
    }
}

#[test]
fn 场馆取消详情核对错误使用固定安全文案且不越过写边界() {
    let cases = [
        (
            "business-error",
            Scenario::new([r#"{"code":500,"message":"学号=private token=secret\n失败"}"#.into()]),
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            "场馆取消资格核对响应无效",
            1,
            1,
        ),
        (
            "transport-error",
            Scenario::with_detail_replies([DetailReply::TransportError]),
            ErrorCode::NetworkError,
            ErrorKind::Network,
            "场馆取消资格核对暂时不可用",
            1,
            1,
        ),
        (
            "authentication-error",
            Scenario::with_detail_replies([
                DetailReply::Response(401, "认证页 token=secret".into()),
                DetailReply::Response(401, "认证页 token=secret".into()),
            ]),
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            "场馆取消资格核对需要重新认证",
            2,
            2,
        ),
    ];

    for (case, scenario, code, kind, message, detail_count, login_count) in cases {
        let (mut client, root) = client_for(case, scenario.clone());
        let error = runtime()
            .block_on(client.cgyy_cancel_order(request()))
            .expect_err("详情核对失败必须使用稳定错误且不发送");
        assert_eq!(
            (error.code, error.kind, error.retryable),
            (code, kind, false),
            "{case}"
        );
        assert_eq!(error.message, message, "{case}");
        for fragment in ["secret", "private", "学号", "token", "\n"] {
            assert!(
                !error.message.contains(fragment),
                "{case} 暴露了 {fragment:?}"
            );
        }
        assert_eq!(scenario.detail_count(), detail_count, "{case}");
        assert_eq!(scenario.login_count(), login_count, "{case}");
        assert_eq!(scenario.cancel_count(), 0, "{case}");
        cleanup(root);
    }
}

#[test]
fn 场馆取消详情请求只把订单_id_放入路径并保留_get_nocache() {
    let scenario = Scenario::new([detail_response(&allowed_order_row())]);
    let (mut client, root) = client_for("detail-wire", scenario.clone());
    runtime()
        .block_on(client.preflight_cgyy_cancel(&request()))
        .expect("预检应成功");

    let requests = scenario.requests();
    let detail = request_for_path(&requests, DETAIL_PATH);
    assert_eq!(detail.method, HttpMethod::Get);
    assert!(detail.body.is_empty());
    let url = url::Url::parse(&detail.url).expect("详情 URL 有效");
    let query = url.query_pairs().collect::<Vec<_>>();
    assert_eq!(query.len(), 1);
    assert_eq!(query[0].0, "nocache");
    assert!(!query[0].1.is_empty());
    cleanup(root);
}

#[derive(Clone)]
struct ThirdRevisionCheckFails {
    inner: FileSessionStore,
    checks: Arc<AtomicUsize>,
}

impl SessionStore for ThirdRevisionCheckFails {
    fn load_versioned(&self) -> Result<VersionedSession> {
        self.inner.load_versioned()
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        self.inner.compare_exchange(expected_revision, replacement)
    }

    fn is_revision_current(&self, expected_revision: u64) -> Result<bool> {
        let check = self.checks.fetch_add(1, Ordering::SeqCst);
        if check == 2 {
            Err(UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                true,
                "发送前会话修订检查暂时失败",
            ))
        } else {
            self.inner.is_revision_current(expected_revision)
        }
    }
}
