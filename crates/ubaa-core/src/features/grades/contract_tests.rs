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
