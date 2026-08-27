use ubaa_core::features::cgyy::{
    parse_day_info, parse_order_detail, parse_orders, parse_purpose_types, parse_sites,
};

#[test]
fn 解析场馆站点和用途类型() {
    let sites = parse_sites(include_str!("../../../fixtures/readonly/cgyy-sites.json")).unwrap();
    assert_eq!(sites[0].id, 4);
    assert_eq!(sites[0].site_name, "二层");
    let purposes = parse_purpose_types(r#"{"code":200,"data":[]}"#).unwrap();
    assert_eq!(purposes.len(), 10);
    assert_eq!(purposes[2].key, 3);
}

#[test]
fn 状态二的时段不可预约() {
    let body = include_str!("../../../fixtures/readonly/cgyy-day.json");
    let result = parse_day_info(body, 4, "2026-03-29").unwrap();
    assert_eq!(result.time_slots[0].label, "14:00-15:35");
    assert!(!result.spaces[0].slots[0].is_reservable);
}

#[test]
fn 解析订单分页和详情完整字段() {
    let body = include_str!("../../../fixtures/readonly/cgyy-orders.json");
    let page = parse_orders(body).unwrap();
    assert_eq!(
        page.content[0].purpose_type_name.as_deref(),
        Some("学术研讨类（竞赛、答辩、展示等小组讨论）")
    );
    assert_eq!(page.content[0].check_content.as_deref(), Some("材料不完整"));
    let detail =
        parse_order_detail(r#"{"code":200,"data":{"id":9,"theme":"课程讨论","joinerNum":3}}"#)
            .unwrap();
    assert_eq!(detail.theme.as_deref(), Some("课程讨论"));
    assert_eq!(detail.joiner_num, Some(3));
}
