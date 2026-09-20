use super::{parse_exam, parse_terms, parse_today, parse_weekly_schedule, parse_weeks};
use crate::error::ErrorCode;

pub(crate) const GSMIS_SCHEDULE: &str = r#"{
  "code":1,
  "rwList":[{"BJDM":"sample","XNXQDM":"20261","SCSKRQ":"2026-09-14"}],
  "jgList":[{"BJDM":"sample","KCDM":"demo","KCMC":"Fixture course","XQ":1,
    "KSJCDM":1,"JSJCDM":2,"ZCBH":"0101","JCFADM":"01","JGJSXM":"Fixture teacher"}],
  "jcfaList":[{"skjcList":[
    {"JCFADM":"01","DM":"1","KSSJ":800,"JSSJ":845},
    {"JCFADM":"01","DM":"2","KSSJ":850,"JSSJ":935},
    {"JCFADM":"01","DM":"3","KSSJ":950,"JSSJ":1035}]}]
}"#;

#[test]
fn gsmis_complete_timeline_survives_public_schedule_serialization() {
    let data: crate::domain::WeeklySchedule = serde_json::from_value(serde_json::json!({
        "arrangedList":[],"code":"20261","name":"Fixture",
        "sectionTimes":[{"section":1,"startTime":"08:00","endTime":"08:45"}]
    }))
    .unwrap();
    assert_eq!(
        serde_json::to_value(data).unwrap()["sectionTimes"][0]["startTime"],
        "08:00"
    );
}

pub(crate) fn gsmis_test_runtime(
    body: &str,
) -> (crate::runtime::ClientRuntime, std::path::PathBuf) {
    use crate::domain::ConnectionMode;
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
    struct Transport(String);
    #[async_trait::async_trait]
    impl HttpTransport for Transport {
        async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
            let body = if request.url.ends_with("currentUser.do") {
                return Ok(HttpResponse::new(
                    200,
                    "https://byxt.buaa.edu.cn/jwapp/sys/byrhmhsy/",
                    b"{}".to_vec(),
                ));
            } else if request.url.ends_with("/*default/index.do") {
                "<html>GSMIS</html>"
            } else if request.url.ends_with("kfdxnxqcx.do") {
                r#"{"code":"0","datas":{"kfdxnxqcx":{"totalSize":1,"rows":[{"XNXQDM":"20261","XNXQDM_DISPLAY":"Fixture term"}]}}}"#
            } else {
                &self.0
            };
            Ok(HttpResponse::new(
                200,
                request.url,
                body.as_bytes().to_vec(),
            ))
        }
    }
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let path = std::env::temp_dir().join(format!(
        "gsmis-test-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
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
    (
        crate::runtime::ClientRuntime::new(ConnectionMode::Direct, Transport(body.into()), store)
            .unwrap(),
        path,
    )
}

#[test]
fn gsmis_week_uses_verified_calendar_and_sections() {
    let (mut runtime, path) = gsmis_test_runtime(GSMIS_SCHEDULE);
    runtime.remember_account_name(Some("SY2600001"));
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let weeks = executor.block_on(super::get_weeks(&mut runtime, "20261"));
    let weekly = executor.block_on(super::get_week(&mut runtime, "20261", 2));
    let _ = std::fs::remove_dir_all(path);
    assert_eq!(weeks.unwrap()[0].start_date, "2026-09-07");
    assert_eq!(
        weekly.unwrap().arranged_list[0].end_time.as_deref(),
        Some("09:35")
    );
}

#[test]
fn gsmis_empty_exam_is_success() {
    let (mut runtime, path) =
        gsmis_test_runtime(r#"{"success":true,"countKs":0,"countKcks":0,"countJk":0}"#);
    runtime.remember_account_name(Some("SY2600001"));
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(super::get_exam(&mut runtime, "20261"));
    let _ = std::fs::remove_dir_all(path);
    assert!(result.unwrap().arranged.is_empty());
}

#[test]
fn confirmed_graduate_identity_returns_graduate_terms() {
    use crate::domain::ConnectionMode;
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::session::{FileSessionStore, SessionSnapshot, SessionStore};
    struct GraduateTransport;
    #[async_trait::async_trait]
    impl HttpTransport for GraduateTransport {
        async fn execute(&self, request: HttpRequest) -> crate::error::Result<HttpResponse> {
            let body = if request.url.ends_with("currentUser.do") {
                return Ok(HttpResponse::new(
                    200,
                    "https://byxt.buaa.edu.cn/jwapp/sys/byrhmhsy/",
                    b"{}".to_vec(),
                ));
            } else if request.url.ends_with("/*default/index.do") {
                "<html>GSMIS</html>"
            } else if request.url.ends_with("kfdxnxqcx.do") {
                assert_eq!(request.method, crate::ports::HttpMethod::Post);
                assert!(request.body.is_empty());
                assert_eq!(
                    request.headers.get("Referer").unwrap(),
                    "https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do"
                );
                r#"{"code":"0","datas":{"kfdxnxqcx":{"totalSize":1,"rows":[{"XNXQDM":"20261","XNXQDM_DISPLAY":"Fixture term"}]}}}"#
            } else {
                panic!("unexpected request");
            };
            Ok(HttpResponse::new(
                200,
                request.url,
                body.as_bytes().to_vec(),
            ))
        }
    }
    let path = std::env::temp_dir().join(format!("gsmis-terms-{}", std::process::id()));
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
        crate::runtime::ClientRuntime::new(ConnectionMode::Direct, GraduateTransport, store)
            .unwrap();
    runtime.remember_account_name(Some("SY2600001"));
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(super::get_terms(&mut runtime));
    let _ = std::fs::remove_dir_all(path);
    assert_eq!(result.unwrap()[0].item_code, "20261");
}

#[test]
fn schedule_and_exam_parsers_map_verified_wrappers_and_reject_nonzero_codes() {
    let terms = parse_terms(r#"{"code":"0","datas":[{"itemCode":"2025-2026-1","itemName":"Fixture Term","selected":true,"itemIndex":1}]}"#).unwrap();
    assert_eq!(terms[0].item_code, "2025-2026-1");
    let error = parse_terms(r#"{"code":"1","datas":[]}"#).unwrap_err();
    assert_eq!(error.code, ErrorCode::UpstreamChanged);

    let exam = parse_exam(
        r#"{"code":"0","datas":[{"courseName":"Fixture Course","examDate":"2026-01-01"}]}"#,
    )
    .unwrap();
    assert_eq!(exam.arranged.len(), 1);
}

#[test]
fn schedule_week_and_today_wrappers_preserve_frozen_nonzero_code_tolerance() {
    // LocalScheduleApi.kt 只对学期和考试检查 code；另外三个本地解析器
    // 直接返回解码后的 datas 载荷。
    let weeks = parse_weeks(
        r#"{"code":"7","datas":[{"startDate":"2026-01-01","endDate":"2026-01-07","term":"fixture","curWeek":false,"serialNumber":1,"name":"第1周"}]}"#,
    )
    .expect("frozen weeks parser does not gate on code");
    assert_eq!(weeks.len(), 1);

    let weekly = parse_weekly_schedule(
        r#"{"code":"7","datas":{"arrangedList":[],"code":"fixture","name":"Fixture"}}"#,
    )
    .expect("frozen weekly parser does not gate on code");
    assert_eq!(weekly.code, "fixture");

    let today = parse_today(
        r#"{"code":"7","datas":[{"bizName":"Fixture","place":null,"time":null,"shortName":null}]}"#,
    )
    .expect("frozen today parser does not gate on code");
    assert_eq!(today.len(), 1);
}
#[test]
fn student_number_classification_does_not_assume_continuing_education_is_undergraduate() {
    assert_eq!(super::classify_student_number("19000001"), Some(false));
    assert_eq!(super::classify_student_number("SY2600001"), Some(true));
    assert_eq!(super::classify_student_number("sy2600001"), Some(true));
    assert_eq!(super::classify_student_number("Sy2600001"), Some(true));
    assert_eq!(super::classify_student_number(" by2600001 "), Some(true));
    assert_eq!(super::classify_student_number("623000001"), None);
    assert_eq!(super::classify_student_number("staff"), None);
    assert_eq!(super::classify_student_number("SY"), None);
}
