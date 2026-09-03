use super::{
    parse_day_context, parse_lock_code, parse_order_detail, parse_orders,
    parse_purpose_types_with_source, parse_sites,
};

#[test]
fn 解析场馆站点和用途类型() {
    let sites = parse_sites(include_str!(
        "../../../../../fixtures/readonly/cgyy-sites.json"
    ))
    .unwrap();
    assert_eq!(sites[0].id, 4);
    assert_eq!(sites[0].site_name, "二层");
    let purposes = parse_purpose_types_with_source(r#"{"code":200,"data":[]}"#)
        .unwrap()
        .0;
    assert_eq!(purposes.len(), 10);
    assert_eq!(purposes[2].key, 3);
}

#[test]
fn 场馆响应缺少或非二百代码时拒绝成功() {
    assert!(parse_sites(r#"{"data":[]}"#).is_err());
    assert!(parse_sites(r#"{"code":0,"data":[]}"#).is_err());
}

#[test]
fn 旧版场馆包装会展开场馆下的站点列表() {
    let body = r#"{"code":200,"data":[{"id":9,"venueName":"沙河研讨室","campusName":"沙河校区","siteList":[{"id":"101","siteName":"一层"}]}]}"#;
    let sites = parse_sites(body).unwrap();
    assert_eq!(sites.len(), 1);
    assert_eq!(sites[0].id, 101);
    assert_eq!(sites[0].site_name, "一层");
    assert_eq!(sites[0].venue_name, "沙河研讨室");
    assert_eq!(sites[0].campus_name, "沙河校区");
}

#[test]
fn 状态二的时段不可预约() {
    let body = include_str!("../../../../../fixtures/readonly/cgyy-day.json");
    let result = parse_day_context(body, 4, "2026-03-29").unwrap().info;
    assert_eq!(result.time_slots[0].label, "14:00-15:35");
    assert!(!result.spaces[0].slots[0].is_reservable);
}

#[test]
fn 日期空间槽位按时间编号排序() {
    let body = r#"{
        "code":200,
        "data":{
            "spaceTimeInfo":[
                {"id":242,"beginTime":"14:00","endTime":"15:35"},
                {"id":101,"beginTime":"08:00","endTime":"09:35"}
            ],
            "reservationDateSpaceInfo":{
                "2026-03-29":[
                    {"id":6,"spaceName":"测试房间","101":{"reservationStatus":1},"242":{"reservationStatus":1}}
                ]
            }
        }
    }"#;
    let result = parse_day_context(body, 4, "2026-03-29").unwrap().info;
    assert_eq!(
        result.spaces[0]
            .slots
            .iter()
            .map(|slot| slot.time_id)
            .collect::<Vec<_>>(),
        vec![101, 242]
    );
}

#[test]
fn 预约上下文令牌不进入公共序列化输出() {
    let day = parse_day_context(
        r#"{"code":200,"data":{"token":"reservation-token"}}"#,
        4,
        "2026-03-29",
    )
    .unwrap()
    .info;
    let value = serde_json::to_value(day).unwrap();

    assert!(value.get("reservationToken").is_none());
    assert!(!value.to_string().contains("reservation-token"));
}

#[test]
fn 解析订单分页和详情完整字段() {
    let body = include_str!("../../../../../fixtures/readonly/cgyy-orders.json");
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

#[test]
fn 成功订单空数据按冻结实现映射为空页和空详情() {
    let page = parse_orders(r#"{"code":200,"data":null}"#).unwrap();
    assert!(page.content.is_empty());
    assert_eq!(page.total_elements, 0);
    assert_eq!(page.size, 20);
    assert_eq!(page.number, 0);

    let detail = parse_order_detail(r#"{"code":200,"data":null}"#).unwrap();
    assert_eq!(detail.id, 0);
}

#[test]
fn 订单缺少数据字段时按旧版映射为空对象() {
    let page =
        parse_orders(r#"{"code":200,"message":"OK","content":[{"id":99}],"totalElements":1}"#)
            .unwrap();
    assert!(page.content.is_empty());
    assert_eq!(page.total_elements, 0);

    let detail = parse_order_detail(r#"{"code":200,"message":"OK"}"#).unwrap();
    assert_eq!(detail.id, 0);
}

#[test]
fn 锁码和日期响应遵守旧版成功信封与空数据语义() {
    assert!(parse_lock_code(r#"{"data":{"lockCode":"fixture"}}"#).is_err());
    assert!(parse_lock_code(r#"{"code":500,"data":{"lockCode":"fixture"}}"#).is_err());
    let empty_lock_code = parse_lock_code(r#"{"code":200,"data":null}"#).unwrap();
    assert!(!empty_lock_code.available);
    assert!(parse_day_context(r#"{"code":200}"#, 4, "2026-03-29").is_err());
}

#[test]
fn 锁码公共序列化不暴露上游原始数据() {
    let lock_code =
        parse_lock_code(r#"{"code":200,"data":{"lockCode":"fixture-secret","orderId":7}}"#)
            .unwrap();
    let serialized = serde_json::to_string(&lock_code).unwrap();
    assert!(!serialized.contains("fixture-secret"));
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&serialized).unwrap(),
        serde_json::json!({"available": true})
    );
}

#[test]
fn cgyy_lock_code_parser_returns_safe_availability_summary() {
    let result = parse_lock_code(r#"{"code":200,"data":{"orderId":7,"lockCode":"1234"}}"#).unwrap();
    assert!(result.available);
}
