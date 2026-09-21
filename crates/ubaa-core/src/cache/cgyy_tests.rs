use super::*;
use crate::domain::{ActionEligibility, CgyyCancelOrderTarget, CgyyOrder};

#[test]
fn 研讨室订单缓存不保存资格和内部材料() {
    let saved = CachedCgyyOrder::from(CgyyOrder {
        id: 42,
        phone: Some("合成联系方式".into()),
        joiners: Some("合成人员".into()),
        trade_no: Some("合成交易号".into()),
        cancel_eligibility: ActionEligibility::Allowed,
        cancel_target: Some(CgyyCancelOrderTarget { order_id: 42 }),
        cancelled_target: Some(CgyyCancelOrderTarget { order_id: 42 }),
        theme: Some("合成活动".into()),
        ..Default::default()
    });
    let value = serde_json::to_value(saved).unwrap();
    assert_eq!(value["theme"], "合成活动");
    for key in [
        "phone",
        "joiners",
        "trade_no",
        "cancel_eligibility",
        "cancel_target",
        "cancelled_target",
    ] {
        assert!(value.get(key).is_none());
    }
}
#[test]
fn 研讨室查询精确隔离日期页码并拒绝错归属载荷() {
    let query = CacheScope {
        route: crate::domain::ConnectionMode::Direct,
        query: CacheQuery::CgyyDay {
            site_id: 1,
            date: "2026-09-22".into(),
        },
    };
    assert!(query.validate().is_ok());
    let data = CachePayload::CgyyDay(CachedCgyyDayInfo {
        venue_site_id: 1,
        reservation_date: "2026-09-23".into(),
        ..Default::default()
    });
    assert!(!data.matches(&query.query));
    let bad = CacheScope {
        route: query.route,
        query: CacheQuery::CgyyDay {
            site_id: 1,
            date: "2026-02-30".into(),
        },
    };
    assert_eq!(bad.validate(), Err(CacheError::InvalidInput));
    let orders = CacheScope {
        route: query.route,
        query: CacheQuery::CgyyOrders { page: 0, size: 20 },
    };
    assert!(orders.validate().is_ok());
    assert_ne!(orders.query, CacheQuery::CgyyOrders { page: 1, size: 20 });
    assert!(
        !CachePayload::CgyyDetail(CachedCgyyOrder::default())
            .matches(&CacheQuery::CgyyDetail { order_id: 42 })
    );
}

#[test]
fn 研讨室槽位只保存显示状态而不保存预约资格或审计数据() {
    let slot = CachedCgyySlotStatus::from(crate::domain::CgyySlotStatus {
        time_id: 1,
        reservation_status: Some(1),
        reservation_eligibility: ActionEligibility::Allowed,
        reservation_target: Some(crate::domain::CgyyReservationTarget {
            venue_site_id: 4,
            reservation_date: "2026-09-22".into(),
            space_id: 6,
            time_id: 1,
            venue_space_group_id: None,
            time_ordinal: 0,
        }),
        trade_no: Some("合成内部号".into()),
        take_up_explain: Some("合成内部说明".into()),
        ..Default::default()
    });
    let value = serde_json::to_value(slot).unwrap();
    assert_eq!(value["reservation_status"], 1);
    for key in [
        "reservation_eligibility",
        "reservation_target",
        "trade_no",
        "order_id",
        "take_up",
        "take_up_explain",
    ] {
        assert!(value.get(key).is_none());
    }
}
