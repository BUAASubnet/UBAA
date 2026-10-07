//! 原子写入口可共享已解析执行器，但不得重复解析或绕过统一发送收尾。
use super::{count_sequence, function_body, rust_tokens, source};

pub(super) fn assert_cgyy_cancel_atomic_route_boundary(facade_dir: &std::path::Path) -> usize {
    let tokens = rust_tokens(&source(&facade_dir.join("write/reservations.rs")));
    let entry_points = ["cgyy_cancel_order", "cgyy_cancel_order_if_route_matches"];
    for entry_point in entry_points {
        let body = function_body(&tokens, entry_point)
            .unwrap_or_else(|| panic!("定位场馆取消入口：{entry_point}"));
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            1,
            "{entry_point} 必须只做一次权威路线解析"
        );
        assert_eq!(
            count_sequence(body, &["cgyy_cancel_order_resolved", "("]),
            1,
            "{entry_point} 必须复用同一个已解析路线执行器"
        );
    }
    let executor =
        function_body(&tokens, "cgyy_cancel_order_resolved").expect("定位场馆取消已解析路线执行器");
    assert_eq!(
        count_sequence(executor, &["resolve_operation", "("]),
        0,
        "最终发送执行器不得再次解析路线"
    );
    assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
    assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    // 两个公开入口共用一个执行器，源码静态计数会比调用语义少一个
    // runtime/finish；这里显式登记并由上方逐函数约束防止抵消漏检。
    entry_points.len() - 1
}

pub(super) fn assert_ygdk_submit_atomic_route_boundary(facade_dir: &std::path::Path) -> usize {
    let tokens = rust_tokens(&source(&facade_dir.join("write/campus.rs")));
    let entry_points = ["ygdk_submit", "ygdk_submit_if_route_matches"];
    for entry_point in entry_points {
        let body = function_body(&tokens, entry_point)
            .unwrap_or_else(|| panic!("定位阳光打卡提交入口：{entry_point}"));
        assert_eq!(
            count_sequence(body, &["validate_ygdk_submit_pre_route", "("]),
            1,
            "{entry_point} 必须在路线解析前完整校验本地输入"
        );
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            1,
            "{entry_point} 必须只做一次权威路线解析"
        );
        assert_eq!(
            count_sequence(body, &["ygdk_submit_resolved", "("]),
            1,
            "{entry_point} 必须复用同一个已解析路线执行器"
        );
    }
    let atomic = function_body(&tokens, "ygdk_submit_if_route_matches")
        .expect("定位阳光打卡 expected-route 原子入口");
    assert_eq!(
        count_sequence(
            atomic,
            &["resolution", ".", "mode", "!", "=", "expected_route"]
        ),
        1,
        "阳光打卡原子入口必须在执行器前比较唯一解析路线"
    );
    let executor =
        function_body(&tokens, "ygdk_submit_resolved").expect("定位阳光打卡已解析路线执行器");
    assert_eq!(
        count_sequence(executor, &["resolve_operation", "("]),
        0,
        "阳光打卡最终发送执行器不得再次解析路线"
    );
    assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
    assert_eq!(
        count_sequence(executor, &["begin_non_idempotent_operation", "("]),
        1
    );
    assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    entry_points.len() - 1
}

pub(super) fn assert_evaluation_submit_atomic_route_boundary(
    facade_dir: &std::path::Path,
) -> usize {
    let tokens = rust_tokens(&source(&facade_dir.join("write/evaluation.rs")));
    let entry_points = [
        "evaluation_submit_courses",
        "evaluation_submit_courses_if_route_matches",
    ];
    for entry_point in entry_points {
        let body = function_body(&tokens, entry_point)
            .unwrap_or_else(|| panic!("定位评教提交入口：{entry_point}"));
        assert_eq!(
            count_sequence(body, &["resolve_operation", "("]),
            1,
            "{entry_point} 必须只做一次权威路线解析"
        );
        assert_eq!(
            count_sequence(body, &["evaluation_submit_courses_resolved", "("]),
            1,
            "{entry_point} 必须复用同一个已解析路线执行器"
        );
    }
    let atomic = function_body(&tokens, "evaluation_submit_courses_if_route_matches")
        .expect("定位评教 expected-route 原子入口");
    assert_eq!(
        count_sequence(
            atomic,
            &["resolution", ".", "mode", "!", "=", "expected_route"]
        ),
        1,
        "评教原子入口必须在 authority 前比较唯一解析路线"
    );
    let executor = function_body(&tokens, "evaluation_submit_courses_resolved")
        .expect("定位评教已解析路线执行器");
    assert_eq!(
        count_sequence(executor, &["resolve_operation", "("]),
        0,
        "评教最终发送执行器不得再次解析路线"
    );
    assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
    assert_eq!(
        count_sequence(executor, &["begin_non_idempotent_operation", "("]),
        1
    );
    assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    entry_points.len() - 1
}

pub(super) fn assert_shared_write_route_boundary(facade_dir: &std::path::Path) -> usize {
    let helpers = [
        ("write/campus.rs", "bykc_select_course"),
        ("write/campus.rs", "bykc_deselect_course"),
        ("write/campus.rs", "bykc_sign_course"),
        ("write/campus.rs", "signin_perform"),
        ("write/reservations.rs", "libbook_reserve"),
        ("write/reservations.rs", "libbook_cancel_booking"),
        ("write/reservations.rs", "cgyy_submit_reservation"),
    ];
    for (file, operation) in helpers {
        let tokens = rust_tokens(&source(&facade_dir.join(file)));
        let executor_name = format!("{operation}_resolved");
        for entry in [
            operation.to_owned(),
            format!("{operation}_if_route_matches"),
        ] {
            let body = function_body(&tokens, &entry).expect("原子写入口存在");
            assert_eq!(
                count_sequence(body, &["resolve_write_route", "("]),
                1,
                "{entry}"
            );
            assert_eq!(
                count_sequence(body, &["resolve_operation", "("]),
                0,
                "{entry}"
            );
            assert_eq!(count_sequence(body, &[&executor_name, "("]), 1, "{entry}");
            if entry.ends_with("_if_route_matches") {
                assert_eq!(
                    count_sequence(body, &["Some", "(", "expected_route", ")"]),
                    1
                );
            }
        }
        let executor = function_body(&tokens, &executor_name).expect("已解析执行器存在");
        assert_eq!(count_sequence(executor, &["resolve_operation", "("]), 0);
        assert_eq!(count_sequence(executor, &["resolve_write_route", "("]), 0);
        assert_eq!(count_sequence(executor, &["runtime_for", "("]), 1);
        assert_eq!(
            count_sequence(executor, &["begin_non_idempotent_operation", "("]),
            1
        );
        assert_eq!(count_sequence(executor, &["finish_routed_write", "("]), 1);
    }
    let tokens = rust_tokens(&source(&facade_dir.join("routing.rs")));
    let resolver = function_body(&tokens, "resolve_write_route").expect("共同写路线辅助存在");
    assert_eq!(count_sequence(resolver, &["resolve_operation", "("]), 1);
    assert_eq!(
        count_sequence(resolver, &["expected_route", ".", "is_some_and"]),
        1
    );
    helpers.len()
}
