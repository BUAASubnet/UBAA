//! 图书馆 parser 与冻结加密向量单元合同。

use super::crypto::encrypt_reserve_request;
use super::{parse_area_detail_for, parse_bookings, parse_libraries, parse_seats};
use crate::domain::LibBookReserveRequest;

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
    assert!(seats[0].is_available);
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
    let page = parse_bookings(r#"{"code":0,"data":{"data":[{"id":"b1","no":"001"}]}}"#).unwrap();
    assert_eq!(page.bookings.len(), 1);
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
    assert_eq!(seats[0].status, "1");
    assert!(seats[0].is_available);
}
