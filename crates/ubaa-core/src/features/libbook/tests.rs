//! 图书馆 parser 与冻结加密向量单元合同。

use super::crypto::encrypt_reserve_request;
use super::parser::parse_area_detail_for_day;
use super::parser::parse_bookings_for_request;
use super::{parse_area_detail_for, parse_libraries, parse_seats};
use crate::domain::{ActionEligibility, LibBookReserveRequest};
use crate::error::ErrorCode;

type SeatStatusCase = (
    &'static str,
    &'static str,
    Option<i32>,
    ActionEligibility,
    Option<&'static str>,
);

const SEAT_STATUS_CASES: &[SeatStatusCase] = &[
    (
        "字符串允许",
        r#"{"id":" seat-safe ","status":"1"}"#,
        Some(1),
        ActionEligibility::Allowed,
        Some("seat-safe"),
    ),
    (
        "整数允许",
        r#"{"id":"seat-safe","status":1}"#,
        Some(1),
        ActionEligibility::Allowed,
        Some("seat-safe"),
    ),
    (
        "状态二拒绝",
        r#"{"id":"seat-safe","status":"2"}"#,
        Some(2),
        ActionEligibility::Denied,
        Some("seat-safe"),
    ),
    (
        "状态三拒绝",
        r#"{"id":"seat-safe","status":3}"#,
        Some(3),
        ActionEligibility::Denied,
        Some("seat-safe"),
    ),
    (
        "其它整数未知",
        r#"{"id":"seat-safe","status":9}"#,
        Some(9),
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态缺失",
        r#"{"id":"seat-safe"}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态为空",
        r#"{"id":"seat-safe","status":null}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态畸形",
        r#"{"id":"seat-safe","status":"bad"}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态前导零",
        r#"{"id":"seat-safe","status":"01"}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态显式正号",
        r#"{"id":"seat-safe","status":"+1"}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态布尔",
        r#"{"id":"seat-safe","status":true}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态对象",
        r#"{"id":"seat-safe","status":{"value":1}}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态小数",
        r#"{"id":"seat-safe","status":1.5}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "状态溢出",
        r#"{"id":"seat-safe","status":2147483648}"#,
        None,
        ActionEligibility::Unknown,
        None,
    ),
    (
        "目标为空",
        r#"{"id":"   ","status":1}"#,
        Some(1),
        ActionEligibility::Unknown,
        None,
    ),
];

#[test]
fn 解析图书馆楼层和座位状态() {
    let libraries = parse_libraries(
        r#"{"code":0,"data":[{"id":"a","name":"图书馆","freeNum":3,"totalNum":10,"storeys":[{"id":"1","name":"一层","freeNum":3,"totalNum":10}]}]}"#,
    )
    .unwrap();
    assert_eq!(libraries[0].storeys[0].name, "一层");

    let seats = parse_seats(
        r#"{"code":1,"data":[{"id":"s","name":"座位","no":"001","status":"1","statusName":"可用"}]}"#,
    )
    .unwrap();
    assert_eq!(seats[0].status, Some(1));
    assert_eq!(seats[0].reserve_eligibility, ActionEligibility::Allowed);
    assert_eq!(seats[0].reserve_target.as_deref(), Some("s"));
}

#[test]
fn 座位状态矩阵只从严格整数与非空目标派生预约资格() {
    for &(case, row, status, eligibility, target) in SEAT_STATUS_CASES {
        let body = format!(r#"{{"code":1,"data":[{row}]}}"#);
        let seats = parse_seats(&body).expect("状态矩阵应保持座位行并安全归类");
        assert_eq!(seats.len(), 1, "{case}");
        assert_eq!(seats[0].status, status, "{case}");
        assert_eq!(seats[0].reserve_eligibility, eligibility, "{case}");
        assert_eq!(seats[0].reserve_target.as_deref(), target, "{case}");
    }
}

#[test]
fn 座位列表按冻结实现的座位号升序输出() {
    let seats = parse_seats(
        r#"{"code":1,"data":[{"id":"s2","name":"座位2","no":"010","status":"1"},{"id":"s1","name":"座位1","no":"002","status":"1"}]}"#,
    )
    .unwrap();
    assert_eq!(
        seats
            .iter()
            .map(|seat| seat.no.as_str())
            .collect::<Vec<_>>(),
        vec!["002", "010"]
    );
}

#[test]
fn 预约分页缺少总数时回退为当前条数() {
    let page = parse_bookings_for_request(
        r#"{"code":0,"data":{"data":[{"id":"b1","no":"001"}]}}"#,
        2,
        10,
    )
    .unwrap();
    assert_eq!(page.bookings.len(), 1);
    assert_eq!((page.page, page.limit), (2, 10));
    assert_eq!(page.total, 1);
}

#[test]
fn 分区详情缺少区域编号时回退请求编号() {
    let detail = parse_area_detail_for(
        "area-42",
        r#"{"code":0,"data":{"area":{"name":"自习区"},"date":{"list":[]}}}"#,
    )
    .unwrap();
    assert_eq!(detail.id, "area-42");
}

#[test]
fn 解析区域时段并补充标签() {
    let detail = parse_area_detail_for(
        "",
        r#"{"code":0,"data":{"id":"a","name":"自习区","availableDates":["2026-08-27"],"timeSlots":[{"id":"t","start":"08:00","end":"10:00"}]}}"#,
    )
    .unwrap();
    assert_eq!(detail.time_slots[0].label, "08:00-10:00");
}

#[test]
fn 预约权威按目标日期而不是首日选择时段() {
    let detail = parse_area_detail_for_day(
        "area-safe",
        "2026-09-04",
        r#"{"code":1,"data":{"area":{"id":"area-safe"},"date":{"list":[{"day":"2026-09-03","times":[{"id":"other-segment","start":"08:00","end":"09:00"}]},{"day":"2026-09-04","times":[{"id":"segment-safe","start":"10:00","end":"12:00"}] }]}}}"#,
    )
    .expect("目标日期应可解析")
    .expect("目标日期应存在");

    assert_eq!(detail.available_dates, ["2026-09-04"]);
    assert_eq!(detail.time_slots.len(), 1);
    assert_eq!(detail.time_slots[0].id, "segment-safe");
    assert_eq!(detail.time_slots[0].start, "10:00");
    assert_eq!(detail.time_slots[0].end, "12:00");
}

#[test]
fn 预约权威拒绝重复目标日期() {
    let error = parse_area_detail_for_day(
        "area-safe",
        "2026-09-04",
        r#"{"code":1,"data":{"area":{"id":"area-safe"},"date":{"list":[{"day":"2026-09-04","times":[]},{"day":"2026-09-04","times":[]}]}}}"#,
    )
    .expect_err("重复日期不能提供唯一预约权威");

    assert_eq!(error.code, ErrorCode::UpstreamChanged);
    assert!(!error.retryable);
}

#[test]
fn reserve_request_matches_frozen_golden_vector() {
    let encrypted = encrypt_reserve_request(&LibBookReserveRequest {
        area_id: "8".into(),
        seat_id: "101".into(),
        day: "2026-05-08".into(),
        segment: "seg-1".into(),
        start_time: String::new(),
        end_time: String::new(),
    })
    .expect("vector should encrypt");
    assert_eq!(
        encrypted,
        "lGWxL9YCYE0sXIQzPsUCs3jfaFPunT/NyR93uF2nVP1OQPYYihpMRBvm7jxYdUZNTMCyIRtdY8d3DgCNz8G3lmeWmPjvy6jV2KeuJXR8nrOmk26JK+ATZB1VXBNOFebA"
    );
}

#[test]
fn 座位数字原语按冻结实现转为文本() {
    let body = serde_json::json!({
        "code": 0,
        "data": [{"id": 101, "name": 7, "no": 12, "status": 1}]
    })
    .to_string();
    let seats = parse_seats(&body).expect("解析座位");
    assert_eq!(seats[0].id, "101");
    assert_eq!(seats[0].no, "12");
    assert_eq!(seats[0].status, Some(1));
    assert_eq!(seats[0].reserve_eligibility, ActionEligibility::Allowed);
    assert_eq!(seats[0].reserve_target.as_deref(), Some("101"));
}
