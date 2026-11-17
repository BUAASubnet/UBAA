use super::{parse_scores, parse_term_code};

#[test]
fn grades_require_verified_term_shape_and_map_e_m_d_payload() {
    let term = parse_term_code("2025-2026-1").unwrap();
    assert_eq!(term.year, "2025-2026");
    assert_eq!(term.semester, 1);
    assert!(parse_term_code("2025/2026/1").is_err());
    let data = parse_scores("2025-2026-1", r#"{"e":0,"m":"ok","d":{"a":{"kcmc":"Fixture","kch":"C-1","xf":"2.0","kccj":95,"fslx":"normal","kclx":"required"}}}"#).unwrap();
    assert_eq!(data.grades[0].course_name.as_deref(), Some("Fixture"));
    assert_eq!(data.grades[0].score.as_deref(), Some("95"));
}

#[test]
fn diagnostics_contract_成绩区分语法类型和业务状态且不保存成绩值() {
    for (body, reason, code) in [
        ("{", "json_invalid", None),
        (r#"{"e":0,"d":[]}"#, "response_shape_invalid", None),
        (
            r#"{"e":99,"m":"PRIVATE","d":{}}"#,
            "business_code_nonzero",
            Some(99),
        ),
    ] {
        let error = parse_scores("2025-2026-1", body).unwrap_err();
        assert_eq!(error.diagnostic().reason.as_deref(), Some(reason));
        assert_eq!(error.diagnostic().upstream_code, code);
        assert!(!error.diagnostic().to_json().unwrap().contains("PRIVATE"));
    }
}
