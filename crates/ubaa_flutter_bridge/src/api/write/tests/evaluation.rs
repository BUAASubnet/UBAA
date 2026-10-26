use super::*;
use crate::api::read::BridgeEvaluationSubmitTarget;
use crate::api::write::commit::evaluation_commit_message;
use crate::api::write::support::{map_commit_error, map_evaluation_preflight_error};
use crate::api::write::support::{map_evaluation_batch, map_evaluation_request};
use crate::api::write::{
    BridgeEvaluationCourseOutcome, BridgeEvaluationSubmitCoursesRequest, PendingWrite,
};
use ubaa_core::facade as domain;

const CAS_URL: &str = "https://spoc.buaa.edu.cn/pjxt/cas";
const TASKS_URL: &str = "https://spoc.buaa.edu.cn/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks?yhdm=&pageNum=1&pageSize=10";
const FORMS_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireListToTask?rwid=task-1";
const COURSES_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getRequiredReviewsData?wjid=form-1";
const REVISE_URL: &str =
    "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/reviseQuestionnairePattern";
const SUBMIT_URL: &str = "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/submitSaveEvaluation";

fn target(label: &str, bpdm: Option<&str>) -> BridgeEvaluationSubmitTarget {
    BridgeEvaluationSubmitTarget {
        rwid: format!("rw-{label}"),
        wjid: format!("wj-{label}"),
        kcdm: format!("kc-{label}"),
        bpdm: bpdm.map(str::to_owned),
    }
}

fn request(targets: Vec<BridgeEvaluationSubmitTarget>) -> BridgeEvaluationSubmitCoursesRequest {
    BridgeEvaluationSubmitCoursesRequest { targets }
}

fn pending(targets: Vec<BridgeEvaluationSubmitTarget>) -> PendingWrite {
    PendingWrite::Evaluation(
        map_evaluation_request(request(targets)).expect("测试 pending 目标必须有效"),
    )
}

fn fixture_target(label: &str, bpdm: Option<&str>) -> BridgeEvaluationSubmitTarget {
    BridgeEvaluationSubmitTarget {
        rwid: "task-1".to_owned(),
        wjid: "form-1".to_owned(),
        kcdm: format!("course-{label}"),
        bpdm: bpdm.map(str::to_owned),
    }
}

fn response_request(method: HttpMethod, url: &str, body: String) -> ExpectedRequest {
    ExpectedRequest::new(method, url, HttpResponse::new(200, url, body.into_bytes()))
}

fn authority_requests(rows: &[String]) -> Vec<ExpectedRequest> {
    vec![
        response_request(HttpMethod::Get, CAS_URL, String::new()),
        response_request(
            HttpMethod::Get,
            TASKS_URL,
            r#"{"code":200,"result":{"list":[{"rwid":"task-1"}]}}"#.to_owned(),
        ),
        response_request(
            HttpMethod::Get,
            FORMS_URL,
            r#"{"code":200,"result":[{"wjid":"form-1","msid":"mode-1"}]}"#.to_owned(),
        ),
        response_request(
            HttpMethod::Get,
            COURSES_URL,
            format!(r#"{{"code":200,"result":[{}]}}"#, rows.join(",")),
        ),
    ]
}

fn course_row(label: &str, bpdm: Option<&str>) -> String {
    let bpdm = bpdm.map_or_else(String::new, |value| format!(",\"bpdm\":\"{value}\""));
    r#"{"kcdm":"course-$LABEL","kcmc":"Course-$LABEL","bpmc":"Teacher-$LABEL","ypjcs":0,"xypjcs":1,"sxz":"student","pjrdm":"reviewer-$LABEL","pjrmc":"Reviewer-$LABEL","rwh":"row-$LABEL","xn":"2026","xq":"1","xnxq":"2026-2027-1","yxsfktjst":"1"$BPDM}"#
        .replace("$LABEL", label)
        .replace("$BPDM", &bpdm)
}

fn topic_url(label: &str, bpdm: Option<&str>) -> String {
    format!(
        "https://spoc.buaa.edu.cn/pjxt/evaluationMethodSix/getQuestionnaireTopic?id=&rwid=task-1&wjid=form-1&zdmc=STID&ypjcs=0&xypjcs=1&sxz=student&pjrdm=reviewer-{label}&pjrmc=Reviewer-{label}&bpdm={}&bpmc=Teacher-{label}&kcdm=course-{label}&kcmc=Course-{label}&rwh=row-{label}&xn=2026&xq=1&xnxq=2026-2027-1&pjlxid=2&sfksqbpj=1&yxsfktjst=1&yxdm=",
        bpdm.unwrap_or_default(),
    )
}

fn topic_body(label: &str, bpdm: Option<&str>) -> String {
    r#"{"code":200,"result":[{"pjmap":{},"pjxtPjjgPjjgckb":[{"bprdm":"$BPDM","bprmc":"Teacher-$LABEL","kcdm":"course-$LABEL","kcmc":"Course-$LABEL","pjfs":"1","pjid":"evaluation-$LABEL","pjlx":"2","pjrdm":"reviewer-$LABEL","pjrjsdm":"student","pjrxm":"Reviewer-$LABEL","rwh":"row-$LABEL","wjssrwid":"task-1","xnxq":"2026-2027-1"}],"pjxtWjWjbReturnEntity":{"wjzblist":[{"tklist":[{"tmid":"question-$LABEL","tmlx":"1","tmxxlist":[{"tmxxid":"option-$LABEL-1"},{"tmxxid":"option-$LABEL-2"}]}]}]}}]}"#
        .replace("$LABEL", label)
        .replace("$BPDM", bpdm.unwrap_or("teacher-none"))
}

fn revise_request() -> ExpectedRequest {
    response_request(HttpMethod::Post, REVISE_URL, String::new())
}

fn topic_request(label: &str, bpdm: Option<&str>, body: String) -> ExpectedRequest {
    response_request(HttpMethod::Get, &topic_url(label, bpdm), body)
}

fn submit_request(body: &str) -> ExpectedRequest {
    response_request(HttpMethod::Post, SUBMIT_URL, body.to_owned())
}

#[test]
fn 评教请求只接受typed目标并规范化空白末段() {
    let mapped = map_evaluation_request(request(vec![BridgeEvaluationSubmitTarget {
        rwid: " rw-1 ".to_owned(),
        wjid: " wj-1 ".to_owned(),
        kcdm: " kc-1 ".to_owned(),
        bpdm: Some("   ".to_owned()),
    }]))
    .expect("完整 typed 目标应可映射");

    assert_eq!(mapped.targets.len(), 1);
    assert_eq!(mapped.targets[0].rwid, "rw-1");
    assert_eq!(mapped.targets[0].wjid, "wj-1");
    assert_eq!(mapped.targets[0].kcdm, "kc-1");
    assert_eq!(mapped.targets[0].bpdm, None);

    let error = map_evaluation_request(request(vec![BridgeEvaluationSubmitTarget {
        rwid: " ".to_owned(),
        wjid: "wj-2".to_owned(),
        kcdm: "kc-2".to_owned(),
        bpdm: None,
    }]))
    .expect_err("缺少 required identity 必须在网络前拒绝");
    assert_eq!(error.code, BridgeErrorCode::InvalidInput);
}

#[test]
fn 待确认评教批次任一规范化目标相交即冲突() {
    let first = pending(vec![target("one", Some("bp-one")), target("shared", None)]);
    let overlap = pending(vec![target("shared", Some("")), target("three", None)]);
    let disjoint = pending(vec![target("four", None)]);

    assert!(first.conflicts_with(&overlap));
    assert!(overlap.conflicts_with(&first));
    assert!(!first.conflicts_with(&disjoint));
}

#[test]
fn 评教批量结果完整保序映射四态并替换上游文案() {
    let outcomes = [
        domain::EvaluationCourseOutcome::Success,
        domain::EvaluationCourseOutcome::Failure,
        domain::EvaluationCourseOutcome::OutcomeUnknown,
        domain::EvaluationCourseOutcome::Unattempted,
    ];
    let core = domain::EvaluationBatchResult {
        items: outcomes
            .into_iter()
            .enumerate()
            .map(|(index, outcome)| domain::EvaluationCourseResult {
                target: domain::EvaluationSubmitTarget {
                    rwid: format!("rw-{index}"),
                    wjid: format!("wj-{index}"),
                    kcdm: format!("kc-{index}"),
                    bpdm: None,
                },
                course_name: format!("课程-{index}"),
                outcome,
                message: "RAW-UPSTREAM token=PRIVATE".to_owned(),
            })
            .collect(),
        success: false,
        outcome_unknown: true,
    };

    let mapped = map_evaluation_batch(core);

    assert!(!mapped.success);
    assert!(mapped.outcome_unknown);
    assert_eq!(mapped.items.len(), 4);
    assert_eq!(mapped.items[0].course_name, "课程-0");
    assert_eq!(mapped.items[3].target.rwid, "rw-3");
    assert!(matches!(
        mapped.items[0].outcome,
        BridgeEvaluationCourseOutcome::Success
    ));
    assert!(matches!(
        mapped.items[1].outcome,
        BridgeEvaluationCourseOutcome::Failure
    ));
    assert!(matches!(
        mapped.items[2].outcome,
        BridgeEvaluationCourseOutcome::OutcomeUnknown
    ));
    assert!(matches!(
        mapped.items[3].outcome,
        BridgeEvaluationCourseOutcome::Unattempted
    ));
    assert_eq!(
        mapped
            .items
            .iter()
            .map(|item| item.message.as_str())
            .collect::<Vec<_>>(),
        vec![
            "评教已提交",
            "评教未提交，请刷新课程后重试",
            "评教提交结果未知，请刷新课程后核对",
            "前序课程结果未知，本课程未尝试",
        ]
    );
    for item in mapped.items {
        assert!(!item.message.contains("RAW-UPSTREAM"));
        assert!(!item.message.contains("PRIVATE"));
        assert!(!item.message.contains("token"));
    }
}

#[test]
fn 评教准备与提交错误固定脱敏文案() {
    let raw = "RAW-UPSTREAM token=PRIVATE account=PRIVATE";
    let preflight = map_evaluation_preflight_error(&domain::RoutedError {
        error: domain::UbaaError::new(
            domain::ErrorCode::UpstreamChanged,
            domain::ErrorKind::Upstream,
            false,
            raw,
        ),
        resolution: None,
    });
    assert_eq!(preflight.code, BridgeErrorCode::UpstreamChanged);
    assert_eq!(preflight.message, "教学评教资格核对响应无效");

    let commit = map_commit_error(
        BridgeWriteOperation::EvaluationSubmitCourses,
        domain::RoutedError {
            error: domain::UbaaError::new(
                domain::ErrorCode::UpstreamChanged,
                domain::ErrorKind::Upstream,
                false,
                raw,
            ),
            resolution: None,
        },
    );
    assert_eq!(commit.code, BridgeErrorCode::UpstreamChanged);
    assert_eq!(commit.message, "教学评教提交前资格核对响应无效");
    let network = domain::RoutedError {
        error: domain::UbaaError::new(
            domain::ErrorCode::NetworkError,
            domain::ErrorKind::Network,
            true,
            raw,
        ),
        resolution: None,
    };
    let preflight_network = map_evaluation_preflight_error(&network);
    let commit_network = map_commit_error(BridgeWriteOperation::EvaluationSubmitCourses, network);
    assert_eq!(preflight_network.message, "教学评教准备失败");
    assert_eq!(commit_network.message, "教学评教提交失败");
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "token", "account"] {
        assert!(!preflight.message.contains(forbidden));
        assert!(!commit.message.contains(forbidden));
        assert!(!preflight_network.message.contains(forbidden));
        assert!(!commit_network.message.contains(forbidden));
    }
}

#[test]
fn 评教总览文案区分成功确定性partial与结果未知() {
    let batch = |success, outcome_unknown| crate::api::write::BridgeEvaluationBatchResult {
        items: Vec::new(),
        success,
        outcome_unknown,
    };

    assert_eq!(
        evaluation_commit_message(&batch(true, false)),
        "教学评教已全部提交"
    );
    assert_eq!(
        evaluation_commit_message(&batch(false, false)),
        "教学评教部分课程未提交，请刷新课程后重试"
    );
    assert_eq!(
        evaluation_commit_message(&batch(false, true)),
        "教学评教提交结果无法确认，请刷新课程后核对"
    );
    assert_eq!(
        evaluation_commit_message(&batch(true, true)),
        "教学评教提交结果无法确认，请刷新课程后核对"
    );
}

#[tokio::test]
async fn 评教prepare只读取fresh权威并只保存canonical_typed目标() {
    let root = test_root("prepare-evaluation");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let rows = vec![course_row("one", None)];
    let direct = MockTransport::new(authority_requests(&rows));
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 Bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let intent = client
        .prepare_evaluation_submit_courses(request(vec![fixture_target("one", Some(""))]))
        .await
        .expect("fresh authority 中唯一 Allowed 目标应签发 intent");

    assert!(matches!(
        intent.operation,
        BridgeWriteOperation::EvaluationSubmitCourses
    ));
    assert_eq!(intent.resolved_route, BridgeConnectionMode::Direct);
    assert_eq!(intent.target_summary, "提交 1 门课程的教学评教");
    let intents = client.write_intents.lock().await;
    let stored = intents.get(&intent.intent_id).expect("保存一次性意图");
    let PendingWrite::Evaluation(stored_request) = &stored.request else {
        panic!("评教意图只能保存 typed targets");
    };
    assert_eq!(stored_request.targets.len(), 1);
    assert_eq!(stored_request.targets[0].rwid, "task-1");
    assert_eq!(stored_request.targets[0].wjid, "form-1");
    assert_eq!(stored_request.targets[0].kcdm, "course-one");
    assert_eq!(stored_request.targets[0].bpdm, None);
    drop(intents);
    direct
        .assert_exhausted()
        .expect("prepare 只能消费 fresh authority 请求");
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 Bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 评教prepare拒绝与待确认批次任一目标相交() {
    let root = test_root("prepare-evaluation-conflict");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let rows = vec![
        course_row("one", Some("bp-one")),
        course_row("shared", None),
        course_row("three", None),
    ];
    let direct = MockTransport::new(
        authority_requests(&rows)
            .into_iter()
            .chain(authority_requests(&rows)),
    );
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 Bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;

    client
        .prepare_evaluation_submit_courses(request(vec![
            fixture_target("one", Some("bp-one")),
            fixture_target("shared", None),
        ]))
        .await
        .expect("首个批次应签发 intent");
    let conflict = client
        .prepare_evaluation_submit_courses(request(vec![
            fixture_target("shared", Some("")),
            fixture_target("three", None),
        ]))
        .await
        .expect_err("规范化后任一目标相交必须拒绝第二个 intent");

    assert_eq!(conflict.code, BridgeErrorCode::OperationConflict);
    assert_eq!(client.write_intents.lock().await.len(), 1);
    direct
        .assert_exhausted()
        .expect("冲突判定前两个 prepare 都应完成 fresh preflight");
    client.dispose().await.expect("销毁 Bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 评教commit再次读取fresh权威并完整返回四态批次() {
    let root = test_root("commit-evaluation-batch");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, false);
    let labels = ["success", "failure", "unknown", "unattempted"];
    let rows = labels
        .iter()
        .map(|label| course_row(label, Some(&format!("bp-{label}"))))
        .collect::<Vec<_>>();
    let mut requests = authority_requests(&rows);
    requests.extend(authority_requests(&rows));
    requests.extend([
        revise_request(),
        topic_request(
            "success",
            Some("bp-success"),
            topic_body("success", Some("bp-success")),
        ),
        submit_request(r#"{"code":200}"#),
        revise_request(),
        topic_request(
            "failure",
            Some("bp-failure"),
            r#"{"code":200,"result":[]}"#.to_owned(),
        ),
        revise_request(),
        topic_request(
            "unknown",
            Some("bp-unknown"),
            topic_body("unknown", Some("bp-unknown")),
        ),
        submit_request(r#"{"message":"RAW-UPSTREAM token=PRIVATE"}"#),
    ]);
    let direct = MockTransport::new(requests);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 Bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"direct\"\n",
        direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let requested = labels
        .iter()
        .map(|label| fixture_target(label, Some(&format!("bp-{label}"))))
        .collect();
    let intent = client
        .prepare_evaluation_submit_courses(request(requested))
        .await
        .expect("准备评教批次");

    let result = client
        .commit_write(intent.intent_id)
        .await
        .expect("四态批次应作为安全 commit 结果返回");

    assert!(!result.success);
    assert!(result.outcome_unknown);
    assert_eq!(result.resolved_route, Some(BridgeConnectionMode::Direct));
    assert_eq!(result.message, "教学评教提交结果无法确认，请刷新课程后核对");
    assert!(result.cgyy_receipt.is_none());
    assert!(result.ygdk_receipt.is_none());
    let batch = result.evaluation_result.expect("不得丢弃 Core batch");
    assert_eq!(batch.items.len(), 4);
    assert_eq!(batch.items[0].course_name, "Course-success");
    assert_eq!(batch.items[1].course_name, "Course-failure");
    assert_eq!(batch.items[2].course_name, "Course-unknown");
    assert_eq!(batch.items[3].course_name, "Course-unattempted");
    assert!(matches!(
        batch.items[0].outcome,
        BridgeEvaluationCourseOutcome::Success
    ));
    assert!(matches!(
        batch.items[1].outcome,
        BridgeEvaluationCourseOutcome::Failure
    ));
    assert!(matches!(
        batch.items[2].outcome,
        BridgeEvaluationCourseOutcome::OutcomeUnknown
    ));
    assert!(matches!(
        batch.items[3].outcome,
        BridgeEvaluationCourseOutcome::Unattempted
    ));
    for forbidden in ["RAW-UPSTREAM", "PRIVATE", "token"] {
        assert!(!result.message.contains(forbidden));
        assert!(
            batch
                .items
                .iter()
                .all(|item| !item.message.contains(forbidden))
        );
    }
    direct
        .assert_exhausted()
        .expect("commit 必须 fresh 回读后仅提交到 unknown 边界");
    client.dispose().await.expect("销毁 Bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 评教commit路线变化由core原子拒绝并返回实际路线() {
    let root = test_root("commit-evaluation-route-change");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let rows = vec![course_row("one", None)];
    let prepare_direct = MockTransport::new(authority_requests(&rows));
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 Bridge");
    install_core(
        &client,
        store.clone(),
        "[route]\ndefault = \"direct\"\n",
        prepare_direct.clone(),
        MockTransport::new([]),
    )
    .await;
    let intent = client
        .prepare_evaluation_submit_courses(request(vec![fixture_target("one", None)]))
        .await
        .expect("准备 Direct intent");
    prepare_direct
        .assert_exhausted()
        .expect("完成 Direct preflight");
    let commit_direct = MockTransport::new([]);
    let commit_webvpn = MockTransport::new([]);
    install_core(
        &client,
        store,
        "[route]\ndefault = \"webvpn\"\n",
        commit_direct.clone(),
        commit_webvpn.clone(),
    )
    .await;

    let error = client
        .commit_write(intent.intent_id)
        .await
        .expect_err("路线变化必须由 expected-route 原子入口拒绝");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert!(error.retryable);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::WebVpn));
    assert!(
        commit_direct
            .requests()
            .expect("读取 Direct 请求")
            .is_empty()
    );
    assert!(
        commit_webvpn
            .requests()
            .expect("读取 WebVPN 请求")
            .is_empty()
    );
    client.dispose().await.expect("销毁 Bridge");
    let _ = std::fs::remove_dir_all(root);
}

#[tokio::test]
async fn 评教caller_pinned回读只走调用方指定路线() {
    let root = test_root("evaluation-caller-pinned");
    let _ = std::fs::remove_dir_all(&root);
    let store = seed_sessions(&root, true, true);
    let rows = vec![course_row("one", None)];
    let direct = MockTransport::new(authority_requests(&rows));
    let webvpn = MockTransport::new([]);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 Bridge");
    install_core(
        &client,
        store,
        "[route]\ndefault = \"webvpn\"\n",
        direct.clone(),
        webvpn.clone(),
    )
    .await;

    let response = client
        .evaluation_all_on_route(BridgeConnectionMode::Direct)
        .await
        .expect("caller-pinned Direct 读取");

    assert_eq!(response.pinned_route, BridgeConnectionMode::Direct);
    assert_eq!(response.data.courses.len(), 1);
    assert_eq!(response.data.courses[0].id, "task-1_form-1_course-one_");
    direct.assert_exhausted().expect("只消费 Direct authority");
    assert!(webvpn.requests().expect("读取 WebVPN 请求").is_empty());
    client.dispose().await.expect("销毁 Bridge");
    let _ = std::fs::remove_dir_all(root);
}
