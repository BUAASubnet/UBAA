use super::{parse_scores, parse_term_code};

#[test]
fn gsmis_empty_grades_are_success_without_schedule_dependency() {
    let (mut runtime, path) = crate::features::schedule::contract_tests::gsmis_test_runtime(
        r#"{"code":"0","datas":{"xscjcx":{"totalSize":0,"pageNumber":1,"rows":[]}}}"#,
    );
    runtime.remember_account_name(Some("SY2600001"));
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(super::get_grades(&mut runtime, "20261"));
    let _ = std::fs::remove_dir_all(path);
    assert!(result.unwrap().grades.is_empty());
}

#[test]
fn gsmis_paginated_grades_compute_graduate_points() {
    use crate::domain::ConnectionMode;
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
    struct Transport;
    #[async_trait::async_trait]
    impl HttpTransport for Transport {
        async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
            assert!(
                request.url.contains("/wdcjapp/"),
                "grades must not query schedules"
            );
            let body = if request.url.ends_with("index.do") {
                "<html>GSMIS</html>".to_string()
            } else if request.url.ends_with("xscjcx.do") {
                let params: std::collections::BTreeMap<_, _> =
                    url::form_urlencoded::parse(&request.body)
                        .into_owned()
                        .collect();
                assert_eq!(params.get("pageSize").unwrap(), "12");
                let page: usize = params["pageNumber"].parse().unwrap();
                let range = if page == 1 { 1..13 } else { 13..14 };
                let rows: Vec<_> = range.map(|i| serde_json::json!({"WID":format!("sample-{i}"),"XNXQDM":"20261","KCMC":"Fixture","XF":2,"CJXSZ":"60","CJFZDM":"0","SFYX":"1"})).collect();
                serde_json::json!({"code":0,"datas":{"xscjcx":{"totalSize":13,"pageNumber":page,"rows":rows}}}).to_string()
            } else if request.url.ends_with("cjfzdjcx.do") {
                r#"{"code":0,"datas":{"cjfzdjcx":{"totalSize":0,"rows":[]}}}"#.to_string()
            } else {
                panic!("unexpected request")
            };
            Ok(HttpResponse::new(200, request.url, body.into_bytes()))
        }
    }
    let path = std::env::temp_dir().join(format!("gsmis-grades-{}", std::process::id()));
    let store = FileSessionStore::new(&path).unwrap();
    store
        .compare_exchange(
            store.load_versioned().unwrap().revision,
            Some(&SessionSnapshot {
                mode: ConnectionMode::Direct,
                cookies: vec![],
                authenticated_at: 1,
                last_activity: 1,
            }),
        )
        .unwrap();
    let mut runtime =
        crate::runtime::ClientRuntime::new(ConnectionMode::Direct, Transport, store).unwrap();
    runtime.remember_account_name(Some("SY2600001"));
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(super::get_grades(&mut runtime, "20261"));
    let _ = std::fs::remove_dir_all(path);
    let grades = result.unwrap().grades;
    assert_eq!(grades.len(), 13);
    assert_eq!(grades[0].grade_point.as_deref(), Some("1"));
}

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
