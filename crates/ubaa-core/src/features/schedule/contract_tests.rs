use super::{parse_exam, parse_terms, parse_today, parse_weekly_schedule, parse_weeks};
use crate::error::ErrorCode;

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
