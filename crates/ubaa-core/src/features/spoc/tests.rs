use serde_json::Value;

use super::auth::extract_login_token;
use super::calendar::normalize_datetime;
use super::crypto::encrypt_param;
use super::list::AssignmentPageRequest;
use super::parser::{
    AssignmentPage, DetailRaw, SubmissionRaw, map_submission_status, merge_detail, normalize_score,
    parse_envelope, resolve_role_code, summary,
};
use crate::domain::SpocSubmissionStatus;

#[test]
fn frozen_crypto_and_mapping_vectors_are_preserved() {
    let plain = r#"{"pageSize":15,"pageNum":1,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"#;
    let encrypted = "hkJ9jAFVEMFUgJEjbOLv4eRZqXHIsmF+WbYaG1ipT1L1N+BbxRXtBj6Gcjri4Mo+y6q22/FkNm/isiC2+B+/hNejBx2cQJfNp9zoxorVJBa86sID0ROtPQ/2V07JCmVC3qsgIWBokL7EYyiPfilw+0ryJ6e61jRnLn90sQFosew=";

    assert_eq!(encrypt_param(plain), encrypted);
    assert_eq!(
        normalize_datetime(Some("2026-03-31T15:59:59.000+00:00")).as_deref(),
        Some("2026-03-31 23:59:59")
    );
    assert_eq!(
        normalize_datetime(Some("2026-03-24 16:00:00")).as_deref(),
        Some("2026-03-24 16:00:00")
    );
    assert_eq!(normalize_score(Some("Pass")).as_deref(), Some("Pass"));
    assert_eq!(
        normalize_datetime(Some("upstream-fixture")).as_deref(),
        Some("upstream-fixture")
    );
    let unknown = summary(
        "assignment-1".into(),
        "course-1".into(),
        "Fixture Course".into(),
        "Fixture Assignment".into(),
        Some("9"),
        None,
    );
    assert_eq!(unknown.submission_status_text, "未知状态(9)");
    assert_eq!(
        map_submission_status(Some("已提交"), true),
        SpocSubmissionStatus::Submitted
    );
    assert_eq!(
        map_submission_status(Some("未提交"), true),
        SpocSubmissionStatus::Unsubmitted
    );
}

#[test]
fn only_code_200_is_a_success_envelope() {
    let error = parse_envelope::<Value>(r#"{"code":0,"content":{}}"#)
        .expect_err("the frozen implementation accepts only code 200");

    assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
}

#[test]
fn malformed_json_is_never_classified_from_token_text() {
    let error = parse_envelope::<Value>(r#"{"code":200,"content":"token""#)
        .expect_err("malformed JSON must remain a parser failure");

    assert_eq!(error.code, crate::error::ErrorCode::ParseError);
}

#[test]
fn assignment_page_strictly_types_frozen_metadata_and_assignment_term() {
    for body in [
        r#"{"code":200,"content":{"total":"0","pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
        r#"{"code":200,"content":{"total":0,"pageNum":"1","pageSize":15,"pages":1,"hasNextPage":false,"list":[]}}"#,
        r#"{"code":200,"content":{"total":0,"pageNum":1,"pageSize":"15","pages":1,"hasNextPage":false,"list":[]}}"#,
        r#"{"code":200,"content":{"total":1,"pageNum":1,"pageSize":15,"pages":1,"hasNextPage":false,"list":[{"zyid":"a1","zymc":"Fixture","xnxq":7}]}}"#,
    ] {
        let error = parse_envelope::<AssignmentPage>(body)
            .expect_err("mistyped frozen page fields must not be ignored");
        assert_eq!(error.code, crate::error::ErrorCode::ParseError);
    }
}

#[test]
fn assignment_page_uses_the_complete_frozen_defaults() {
    let page = parse_envelope::<AssignmentPage>(r#"{"code":200,"content":{}}"#)
        .expect("the frozen page DTO supplies defaults for every pagination field");

    assert_eq!(page.total, 0);
    assert_eq!(page.page_num, 1);
    assert_eq!(page.page_size, 15);
    assert_eq!(page.pages, 1);
    assert!(!page.has_next_page);
    assert!(page.list.is_empty());
}

#[test]
fn detail_requires_title_and_strict_optional_course_id() {
    for body in [
        r#"{"code":200,"content":{"id":"a1"}}"#,
        r#"{"code":200,"content":{"id":"a1","zymc":7}}"#,
        r#"{"code":200,"content":{"id":"a1","zymc":"Fixture","sskcid":7}}"#,
    ] {
        let error = parse_envelope::<DetailRaw>(body)
            .expect_err("frozen detail identity fields must be strictly typed");
        assert_eq!(error.code, crate::error::ErrorCode::ParseError);
    }
}

#[test]
fn cas_token_requires_the_exact_landing_path() {
    assert_eq!(
        extract_login_token(
            "https://spoc.buaa.edu.cn/spocnew/cas?token=fixture-token",
            crate::domain::ConnectionMode::Direct,
        )
        .as_deref(),
        Some("fixture-token")
    );
    assert!(
        extract_login_token(
            "https://spoc.buaa.edu.cn/not-spocnew/cas?token=fixture-token",
            crate::domain::ConnectionMode::Direct,
        )
        .is_none()
    );
    assert!(
        extract_login_token(
            "https://spoc.buaa.edu.cn/spocnew/cas-extra?token=fixture-token",
            crate::domain::ConnectionMode::Direct,
        )
        .is_none()
    );
}

#[test]
fn cas_token_is_bound_to_the_expected_host_and_route() {
    let direct = "https://spoc.buaa.edu.cn/spocnew/cas?token=fixture-token";
    let gateway = crate::connection::to_webvpn_url(direct).unwrap();
    let evil = "https://evil.example/spocnew/cas?token=fixture-token";
    let gateway_evil = crate::connection::to_webvpn_url(evil).unwrap();

    assert!(
        extract_login_token(evil, crate::domain::ConnectionMode::Direct).is_none(),
        "the path alone must not authorize a terminal host"
    );
    assert!(
        extract_login_token(&gateway, crate::domain::ConnectionMode::Direct).is_none(),
        "Direct must not consume a gateway-routed terminal"
    );
    assert!(
        extract_login_token(direct, crate::domain::ConnectionMode::WebVpn).is_none(),
        "WebVPN must not consume a direct terminal"
    );
    assert_eq!(
        extract_login_token(&gateway, crate::domain::ConnectionMode::WebVpn).as_deref(),
        Some("fixture-token")
    );
    assert!(extract_login_token(&gateway_evil, crate::domain::ConnectionMode::WebVpn).is_none());
}

#[test]
fn role_code_accepts_primitive_and_array_shapes() {
    for (body, expected) in [
        (r#"{"jsdm":"01"}"#, "01"),
        (r#"{"rolecode":"02"}"#, "02"),
        (r#"{"rolecode":["", "03"]}"#, "03"),
        (r#"{"jsdmList":"04"}"#, "04"),
        (r#"{"jsdmList":["05"]}"#, "05"),
        (r#"{"rolecode":6}"#, "6"),
        (r#"{"jsdmList":[false]}"#, "false"),
    ] {
        let value: Value = serde_json::from_str(body).unwrap();
        assert_eq!(resolve_role_code(&value).as_deref(), Some(expected));
    }
}

#[test]
fn global_page_plaintext_has_the_frozen_field_order_and_empty_filters() {
    let request = AssignmentPageRequest::new("2025-20262", 1);

    assert_eq!(
        serde_json::to_string(&request).unwrap(),
        r#"{"pageSize":15,"pageNum":1,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"#
    );
}

#[test]
fn aligned_plaintext_uses_the_frozen_no_extra_block_zero_padding() {
    assert_eq!(
        encrypt_param("1234567890abcdef"),
        "Df9tLndii11SqqHdmdu/fg=="
    );
}

#[test]
fn detail_requires_its_upstream_id() {
    let error = parse_envelope::<DetailRaw>(
        r#"{"code":200,"content":{"zymc":"Fixture","zynr":"<p>safe</p>"}}"#,
    )
    .expect_err("a detail without its frozen id field is not valid");

    assert_eq!(error.code, crate::error::ErrorCode::ParseError);
}

#[test]
fn public_detail_serialization_contains_plain_text_only() {
    let base = summary(
        "assignment-1".into(),
        "course-1".into(),
        "Fixture Course".into(),
        "Fixture Assignment".into(),
        None,
        Some("100"),
    );
    let value = serde_json::to_value(super::detail(
        &base,
        Some("<p>Fixture <strong>content</strong></p>"),
    ))
    .unwrap();

    assert_eq!(value["contentPlainText"], "Fixture content");
    assert!(value.get("contentHtml").is_none());
}

#[test]
fn empty_submission_is_unknown_and_detail_fields_fall_back_to_summary() {
    let mut base = summary(
        "assignment-1".into(),
        "course-1".into(),
        "Fixture Course".into(),
        "Fixture Assignment".into(),
        Some("未做"),
        Some("80"),
    );
    base.start_time = Some("2026-03-01 08:00:00".into());
    base.due_time = Some("2026-03-31 23:59:59".into());
    let raw = DetailRaw {
        id: "assignment-1".into(),
        zymc: "Fixture Assignment".into(),
        zynr: Some("<p>Fixture</p>".into()),
        zyfs: None,
        zykssj: None,
        zyjzsj: None,
        sskcid: Some("course-1".into()),
    };
    let empty_submission = SubmissionRaw {
        tjzt: None,
        tjsj: None,
    };

    let detail = merge_detail("assignment-1", &base, &raw, Some(&empty_submission)).unwrap();

    assert_eq!(
        detail.submission_status,
        crate::domain::SpocSubmissionStatus::Unknown
    );
    assert_eq!(detail.submission_status_text, "未知状态");
    assert_eq!(detail.score.as_deref(), Some("80"));
    assert_eq!(detail.start_time.as_deref(), Some("2026-03-01 08:00:00"));
    assert_eq!(detail.due_time.as_deref(), Some("2026-03-31 23:59:59"));
}

#[test]
fn blank_list_status_and_blank_detail_score_follow_frozen_fallbacks() {
    let mut base = summary(
        "assignment-1".into(),
        "course-1".into(),
        "Fixture Course".into(),
        "Fixture Assignment".into(),
        Some("  "),
        Some("80"),
    );
    assert_eq!(
        base.submission_status,
        crate::domain::SpocSubmissionStatus::Unsubmitted
    );
    let raw = DetailRaw {
        id: "assignment-1".into(),
        zymc: "Fixture Assignment".into(),
        zynr: None,
        zyfs: Some("  ".into()),
        zykssj: None,
        zyjzsj: None,
        sskcid: Some("course-1".into()),
    };
    base.score = Some("80".into());

    let detail = merge_detail("assignment-1", &base, &raw, None).unwrap();

    assert_eq!(detail.score.as_deref(), Some("80"));
}

#[test]
fn detail_enrichment_cannot_replace_summary_identity_fields() {
    let base = summary(
        "assignment-1".into(),
        "summary-course".into(),
        "Fixture Course".into(),
        "Summary title".into(),
        None,
        None,
    );
    let raw = DetailRaw {
        id: "assignment-1".into(),
        zymc: "Detail title".into(),
        zynr: None,
        zyfs: None,
        zykssj: None,
        zyjzsj: None,
        sskcid: Some("detail-course".into()),
    };

    let detail = merge_detail("assignment-1", &base, &raw, None).unwrap();

    assert_eq!(detail.assignment_id, "assignment-1");
    assert_eq!(detail.course_id, "summary-course");
    assert_eq!(detail.title, "Summary title");
}

#[test]
fn envelope_auth_marker_outside_message_is_still_retryable_authentication() {
    let error = parse_envelope::<Value>(r#"{"code":401,"content":{"reason":"token expired"}}"#)
        .expect_err("the frozen classifier scans the complete response body");

    assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
}

#[test]
fn invalidated_login_generation_cannot_repopulate_route_credentials() {
    let state = crate::features::state::RouteFeatureState::default();
    let generation = state.spoc.generation();
    state.clear();

    let stored = state.spoc.store_credential(
        generation,
        super::SpocCredential {
            token: "stale-token".into(),
            role: "01".into(),
        },
    );

    assert!(!stored);
    assert!(state.spoc.credential().is_none());
}
