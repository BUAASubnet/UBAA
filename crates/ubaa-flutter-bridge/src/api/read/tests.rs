use super::evaluation::map_evaluation;
use super::methods::ensure_caller_pinned_route;
use super::*;
use crate::api::client::{BridgeClient, BridgeConnectionMode, BridgeErrorCode};
use ubaa_core::facade as domain;

fn target(
    rwid: &str,
    wjid: &str,
    kcdm: &str,
    bpdm: Option<&str>,
) -> domain::EvaluationSubmitTarget {
    domain::EvaluationSubmitTarget {
        rwid: rwid.to_owned(),
        wjid: wjid.to_owned(),
        kcdm: kcdm.to_owned(),
        bpdm: bpdm.map(str::to_owned),
    }
}

fn course(
    id: &str,
    eligibility: domain::ActionEligibility,
    submit_target: Option<domain::EvaluationSubmitTarget>,
) -> domain::EvaluationCourse {
    domain::EvaluationCourse {
        id: id.to_owned(),
        kcmc: format!("课程-{id}"),
        bpmc: format!("班级-{id}"),
        is_evaluated: false,
        submit_eligibility: eligibility,
        submit_target,
    }
}

#[test]
fn 评教读取只投影安全展示字段与一致的typed目标() {
    let projected = map_evaluation(domain::EvaluationCoursesResponse {
        courses: vec![
            course(
                "rw-1_wj-1_kc-1_bp-1",
                domain::ActionEligibility::Allowed,
                Some(target("rw-1", "wj-1", "kc-1", Some("bp-1"))),
            ),
            course("denied", domain::ActionEligibility::Denied, None),
            course("unknown", domain::ActionEligibility::Unknown, None),
            course("missing", domain::ActionEligibility::Allowed, None),
            course(
                "contradictory",
                domain::ActionEligibility::Denied,
                Some(target("rw-2", "wj-2", "kc-2", None)),
            ),
            course(
                "blank",
                domain::ActionEligibility::Allowed,
                Some(target(" ", "wj-3", "kc-3", Some(""))),
            ),
        ],
        progress: domain::EvaluationProgress {
            total_courses: 6,
            evaluated_courses: 0,
            pending_courses: 6,
        },
    });

    let allowed = &projected.courses[0];
    assert_eq!(allowed.id, "rw-1_wj-1_kc-1_bp-1");
    assert_eq!(allowed.kcmc, "课程-rw-1_wj-1_kc-1_bp-1");
    assert_eq!(allowed.bpmc, "班级-rw-1_wj-1_kc-1_bp-1");
    assert!(!allowed.is_evaluated);
    assert!(matches!(
        allowed.submit_eligibility,
        BridgeActionEligibility::Allowed
    ));
    let allowed_target = allowed.submit_target.as_ref().expect("一致目标应透传");
    assert_eq!(allowed_target.rwid, "rw-1");
    assert_eq!(allowed_target.wjid, "wj-1");
    assert_eq!(allowed_target.kcdm, "kc-1");
    assert_eq!(allowed_target.bpdm.as_deref(), Some("bp-1"));

    assert!(matches!(
        projected.courses[1].submit_eligibility,
        BridgeActionEligibility::Denied
    ));
    assert!(matches!(
        projected.courses[2].submit_eligibility,
        BridgeActionEligibility::Unknown
    ));
    for index in [1, 2, 3, 4, 5] {
        assert!(projected.courses[index].submit_target.is_none());
    }
    for index in [3, 4, 5] {
        assert!(matches!(
            projected.courses[index].submit_eligibility,
            BridgeActionEligibility::Unknown
        ));
    }
}

#[test]
fn 评教读取对跨字段矛盾和整批重复目标失败关闭() {
    let shared = target("rw-1", "wj-1", "kc-1", None);
    let mut duplicate_empty_bpdm = shared.clone();
    duplicate_empty_bpdm.bpdm = Some(String::new());
    let canonical_id = "rw-1_wj-1_kc-1_";
    let mut evaluated = course(
        canonical_id,
        domain::ActionEligibility::Allowed,
        Some(target("rw-2", "wj-2", "kc-2", None)),
    );
    evaluated.id = "rw-2_wj-2_kc-2_".to_owned();
    evaluated.is_evaluated = true;
    let mut blank_name = course(
        "rw-3_wj-3_kc-3_",
        domain::ActionEligibility::Allowed,
        Some(target("rw-3", "wj-3", "kc-3", None)),
    );
    blank_name.kcmc = "  ".to_owned();
    let mut blank_teacher = course(
        "rw-5_wj-5_kc-5_",
        domain::ActionEligibility::Allowed,
        Some(target("rw-5", "wj-5", "kc-5", None)),
    );
    blank_teacher.bpmc = String::new();
    let projected = map_evaluation(domain::EvaluationCoursesResponse {
        courses: vec![
            course(
                canonical_id,
                domain::ActionEligibility::Allowed,
                Some(shared),
            ),
            course(
                canonical_id,
                domain::ActionEligibility::Allowed,
                Some(duplicate_empty_bpdm),
            ),
            course(
                "wrong-id",
                domain::ActionEligibility::Allowed,
                Some(target("rw-4", "wj-4", "kc-4", None)),
            ),
            evaluated,
            blank_name,
            blank_teacher,
        ],
        progress: domain::EvaluationProgress::default(),
    });

    for course in projected.courses {
        assert!(matches!(
            course.submit_eligibility,
            BridgeActionEligibility::Unknown
        ));
        assert!(course.submit_target.is_none());
    }
}

#[test]
fn 评教重复计数归并非canonical空白身份但公开投影仍严格拒绝() {
    let canonical = target("rw-1", "wj-1", "kc-1", None);
    let whitespace_alias = target(" rw-1 ", "wj-1 ", " kc-1", Some("   "));
    let projected = map_evaluation(domain::EvaluationCoursesResponse {
        courses: vec![
            course(
                "rw-1_wj-1_kc-1_",
                domain::ActionEligibility::Allowed,
                Some(canonical),
            ),
            course(
                "rw-1_wj-1_kc-1_",
                domain::ActionEligibility::Allowed,
                Some(whitespace_alias),
            ),
        ],
        progress: domain::EvaluationProgress::default(),
    });

    assert!(projected.courses.iter().all(|course| {
        matches!(course.submit_eligibility, BridgeActionEligibility::Unknown)
            && course.submit_target.is_none()
    }));
}

#[tokio::test]
async fn 评教公开caller_pinned读取入口() {
    let root = std::env::temp_dir().join(format!(
        "ubaa-bridge-evaluation-read-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let _ = std::fs::remove_dir_all(&root);
    let client = BridgeClient::open(root.to_string_lossy().into_owned()).expect("打开 Bridge");
    client.dispose().await.expect("先销毁 Bridge");

    let error = client
        .evaluation_all_on_route(BridgeConnectionMode::Direct)
        .await
        .expect_err("销毁后的 caller-pinned 读取必须拒绝");

    assert_eq!(error.code, BridgeErrorCode::ClientDisposed);
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn caller_pinned读取拒绝core返回不同路线() {
    ensure_caller_pinned_route(BridgeConnectionMode::Direct, BridgeConnectionMode::Direct)
        .expect("相同路线应通过");

    let error =
        ensure_caller_pinned_route(BridgeConnectionMode::Direct, BridgeConnectionMode::WebVpn)
            .expect_err("Core 返回不同路线必须失败关闭");

    assert_eq!(error.code, BridgeErrorCode::OperationConflict);
    assert_eq!(error.resolved_route, Some(BridgeConnectionMode::WebVpn));
    assert!(!error.message.contains("http"));
}
