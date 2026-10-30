//! 分区公开日程的关联与兼容合同，只使用合成响应。

use super::test_response::parse_area_schedule_for;
use crate::error::ErrorCode;
use serde_json::{Value, json};

fn response(dates: &Value) -> String {
    json!({"code": 1, "data": {"area": {"name": "合成分区"}, "date": {"list": dates}}}).to_string()
}

#[test]
fn 分区日程保留两个日期各自原始时段() {
    let body = response(&json!([
        {"day":"2026-09-04","times":[{"id":"first-slot","start":"08:00","end":"10:00"}]},
        {"day":"2026-09-05","times":[{"id":"second-slot","start":"14:00","end":"16:00","label":"同名时段"}]}
    ]));
    let schedule =
        serde_json::to_value(parse_area_schedule_for("area-safe", &body).unwrap()).unwrap();
    assert_eq!(schedule["id"], "area-safe");
    assert_eq!(schedule["days"][0]["day"], "2026-09-04");
    assert_eq!(schedule["days"][0]["timeSlots"][0]["id"], "first-slot");
    assert_eq!(schedule["days"][1]["day"], "2026-09-05");
    assert_eq!(
        schedule["days"][1]["timeSlots"][0],
        json!({
            "id":"second-slot","start":"14:00","end":"16:00","label":"同名时段"
        })
    );
}

#[test]
fn 分区日程空日期的时段不能转移给后一天() {
    let body = response(&json!([
        {"day":"","times":[{"id":"unowned-slot","start":"08:00","end":"10:00"}]},
        {"date":"2026-09-05","times":[{"id":"owned-slot","start":"14:00","end":"16:00"}]}
    ]));
    let schedule =
        serde_json::to_value(parse_area_schedule_for("area-safe", &body).unwrap()).unwrap();
    assert_eq!(schedule["days"].as_array().map(Vec::len), Some(1));
    assert_eq!(schedule["days"][0]["day"], "2026-09-05");
    assert_eq!(schedule["days"][0]["timeSlots"][0]["id"], "owned-slot");
}

#[test]
fn 分区日程重复日期必须拒绝而不能任取首项() {
    let body = response(&json!([
        {"day":"2026-09-05","times":[]},
        {"day":"2026-09-05","times":[]}
    ]));
    let error = parse_area_schedule_for("area-safe", &body).expect_err("重复日期不能形成唯一日程");
    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    assert!(!error.retryable);
}

#[test]
fn 分区日程保留空时段日期且不从旧顶层字段推测关联() {
    let schedule = parse_area_schedule_for(
        "area-safe",
        &response(&json!([
            {"day":"2026-09-04"}, {"day":"2026-09-05","times":[]}
        ])),
    )
    .unwrap();
    assert_eq!(schedule.days.len(), 2);
    assert!(schedule.days.iter().all(|day| day.time_slots.is_empty()));
    let legacy = r#"{"code":1,"data":{"availableDates":["2026-09-04"],"timeSlots":[{"id":"unowned","start":"08:00","end":"10:00"}]}}"#;
    assert!(
        parse_area_schedule_for("area-safe", legacy)
            .unwrap()
            .days
            .is_empty()
    );
    assert!(
        parse_area_schedule_for("area-safe", &response(&json!([])))
            .unwrap()
            .days
            .is_empty()
    );
}

#[test]
fn 分区日程拒绝畸形或不完整时段而不伪装空结果() {
    for times in [
        json!({}),
        json!([null]),
        json!([{"id":"slot","start":"08:00"}]),
        json!([{"id":" ","start":"08:00","end":"10:00"}]),
    ] {
        let error = parse_area_schedule_for(
            "area-safe",
            &response(&json!([
                {"day":"2026-09-04","times":times}
            ])),
        )
        .expect_err("畸形时段必须明确报错");
        assert_eq!(error.code, ErrorCode::UpstreamChanged);
    }
}

#[test]
fn 分区日程信封错误保持错误类别() {
    let error =
        parse_area_schedule_for("area-safe", r#"{"code":500,"message":"未登录"}"#).unwrap_err();
    assert_eq!(error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(
        parse_area_schedule_for("area-safe", "无效响应")
            .unwrap_err()
            .code,
        ErrorCode::UpstreamChanged
    );
}
