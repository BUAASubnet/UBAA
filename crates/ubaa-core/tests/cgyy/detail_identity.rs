use ubaa_core::facade::ErrorCode;

use super::cancel_support::{ORDER_ID, Scenario, cleanup, client_for, runtime};

#[test]
fn 订单详情不能把空响应或其他订单呈现为当前目标() {
    for (index, body) in [
        r#"{"code":200,"data":null}"#,
        r#"{"code":200}"#,
        r#"{"code":200,"data":{}}"#,
        r#"{"code":200,"data":{"id":0}}"#,
        r#"{"code":200,"data":{"id":-1}}"#,
        r#"{"code":200,"data":{"id":78,"theme":"其他订单"}}"#,
    ]
    .into_iter()
    .enumerate()
    {
        let scenario = Scenario::new([body.to_owned()]);
        let (mut client, root) = client_for(&format!("detail-identity-{index}"), scenario.clone());
        let error = runtime()
            .block_on(client.cgyy_order_detail(ORDER_ID))
            .expect_err("缺失或不同身份不能成为详情成功结果");
        assert_eq!(error.code, ErrorCode::UpstreamChanged);
        assert_eq!(scenario.detail_count(), 1);
        assert_eq!(scenario.cancel_count(), 0);
        cleanup(root);
    }
}

#[test]
fn 订单详情保留同一目标的上游内容() {
    let scenario = Scenario::new([
        r#"{"code":200,"data":{"id":77,"theme":"合成研讨","orderStatus":2}}"#.to_owned(),
    ]);
    let (mut client, root) = client_for("detail-same-identity", scenario.clone());
    let order = runtime()
        .block_on(client.cgyy_order_detail(ORDER_ID))
        .unwrap()
        .data;
    assert_eq!(order.id, ORDER_ID);
    assert_eq!(order.theme.as_deref(), Some("合成研讨"));
    assert_eq!(order.order_status, Some(2));
    assert_eq!(scenario.cancel_count(), 0);
    cleanup(root);
}

#[test]
fn 实时包装详情展示实际订单字段但不从展示推导取消资格() {
    let scenario = Scenario::new([
        r#"{"code":200,"data":{"orderInfo":{"tradeNo":"synthetic-trade","venueSiteId":4,"reservationDate":"2026-10-03","theme":"合成活动","orderStatus":1,"checkStatus":1,"phone":"synthetic-phone"},"venueInfoBean":{"venueName":"合成场馆","siteName":"二层","campusName":"合成校区"},"orderDetailList":[],"orderBuddyList":[],"checkLogList":[]}}"#.to_owned(),
    ]);
    let (mut client, root) = client_for("detail-live-wrapper", scenario.clone());
    let order = runtime()
        .block_on(client.cgyy_order_detail(ORDER_ID))
        .unwrap()
        .data;
    assert_eq!(order.id, ORDER_ID);
    assert_eq!(order.trade_no.as_deref(), Some("synthetic-trade"));
    assert_eq!(order.theme.as_deref(), Some("合成活动"));
    assert_eq!(order.venue_name.as_deref(), Some("合成场馆"));
    assert_eq!(order.site_name.as_deref(), Some("二层"));
    assert_eq!(order.campus_name.as_deref(), Some("合成校区"));
    assert_eq!(order.phone.as_deref(), Some("synthetic-phone"));
    assert_eq!(
        order.cancel_eligibility,
        ubaa_core::facade::ActionEligibility::Unknown
    );
    assert!(order.cancel_target.is_none());
    assert!(order.cancelled_target.is_none());
    assert_eq!(scenario.cancel_count(), 0);
    cleanup(root);
}

#[test]
fn 实时包装缺失订单依据或明确错身份仍拒绝() {
    for (index, body) in [
        r#"{"code":200,"data":{"orderInfo":{}}}"#,
        r#"{"code":200,"data":{"orderInfo":{"theme":"不能冒充完整详情"}}}"#,
        r#"{"code":200,"data":{"orderInfo":{"id":78,"tradeNo":"synthetic","venueSiteId":4,"orderStatus":1}}}"#,
    ].into_iter().enumerate() {
        let scenario = Scenario::new([body.to_owned()]);
        let (mut client, root) = client_for(&format!("detail-invalid-wrapper-{index}"), scenario.clone());
        let error = runtime().block_on(client.cgyy_order_detail(ORDER_ID)).unwrap_err();
        assert_eq!(error.code, ErrorCode::UpstreamChanged);
        assert_eq!(scenario.cancel_count(), 0);
        cleanup(root);
    }
}
