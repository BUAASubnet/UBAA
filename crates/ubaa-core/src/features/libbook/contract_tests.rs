use super::{parse_area_detail_for, parse_bookings, parse_libraries, parse_seats};

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
