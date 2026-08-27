use ubaa_core::features::libbook::{parse_area_detail, parse_libraries, parse_seats};

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
fn 解析区域时段并补充标签() {
    let detail = parse_area_detail(
        r#"{"code":0,"data":{"id":"a","name":"自习区","availableDates":["2026-08-27"],"timeSlots":[{"id":"t","start":"08:00","end":"10:00"}]}}"#,
    )
    .unwrap();
    assert_eq!(detail.time_slots[0].label, "08:00-10:00");
}
