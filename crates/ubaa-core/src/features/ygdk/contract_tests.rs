use super::{parse_items, parse_overview, parse_records};

#[test]
fn 解析阳光打卡概览并选择跑步项目() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育","term_num":10,"week_num":2}]}}"#;
    let items = r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","type":1,"sort":1}]}}"#;
    let count = r#"{"code":1,"result":{"term_good_count_show":3,"week_count":1,"month_count":2,"day_count":1}}"#;
    let term = r#"{"code":1,"result":{"term_id":9,"name":"2025秋"}}"#;
    let overview = parse_overview(classify, items, count, term).unwrap();
    assert_eq!(overview.default_item_id, 2);
    assert_eq!(overview.summary.term_count, 3);
}

#[test]
fn 解析记录图片和分页状态并拒绝非法页码() {
    let items =
        parse_items(r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#).unwrap();
    let body = r#"{"code":1,"result":{"total":3,"list":[{"record_id":8,"item_id":2,"start_time":"2025-08-01 08:00","end_time":"2025-08-01 09:00","isopen":1,"images_fmt":["https://img/1"],"create_time_fmt":"2025-08-01 09:01"}]}}"#;
    let page = parse_records(body, &items, 1, 2).unwrap();
    assert!(page.has_more);
    assert_eq!(page.content[0].item_name.as_deref(), Some("跑步"));
    assert_eq!(page.content[0].images, vec!["https://img/1"]);
    assert!(parse_records(body, &items, 0, 2).is_err());
}
