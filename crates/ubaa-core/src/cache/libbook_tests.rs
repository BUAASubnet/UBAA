use super::*;
use crate::domain::{ActionEligibility, ConnectionMode, LibBookBooking, LibBookSeat};

#[test]
fn 图书馆持久类型剥离预约取消资格() {
    let seat = CachedLibBookSeat::from(LibBookSeat {
        id: "s1".into(),
        reserve_eligibility: ActionEligibility::Allowed,
        reserve_target: Some("s1".into()),
        ..Default::default()
    });
    let booking = CachedLibBookBooking::from(LibBookBooking {
        id: "b1".into(),
        cancel_eligibility: ActionEligibility::Allowed,
        cancel_target: Some("b1".into()),
        ..Default::default()
    });
    for value in [
        serde_json::to_value(seat).unwrap(),
        serde_json::to_value(booking).unwrap(),
    ] {
        for key in [
            "reserve_eligibility",
            "reserve_target",
            "cancel_eligibility",
            "cancel_target",
        ] {
            assert!(value.get(key).is_none());
        }
    }
}

#[test]
fn 图书馆查询完整隔离时段楼层日期分页() {
    let base = CacheQuery::LibBookSeats {
        area_id: "a1".into(),
        day: "2026-09-22".into(),
        start_time: "08:00".into(),
        end_time: "09:00".into(),
    };
    for changed in [
        CacheQuery::LibBookSeats {
            area_id: "a2".into(),
            day: "2026-09-22".into(),
            start_time: "08:00".into(),
            end_time: "09:00".into(),
        },
        CacheQuery::LibBookSeats {
            area_id: "a1".into(),
            day: "2026-09-23".into(),
            start_time: "08:00".into(),
            end_time: "09:00".into(),
        },
        CacheQuery::LibBookSeats {
            area_id: "a1".into(),
            day: "2026-09-22".into(),
            start_time: "09:00".into(),
            end_time: "10:00".into(),
        },
    ] {
        assert_ne!(
            serde_json::to_vec(&base).unwrap(),
            serde_json::to_vec(&changed).unwrap()
        );
    }
    for query in [
        CacheQuery::LibBookLibraries {
            day: "2026-02-30".into(),
        },
        CacheQuery::LibBookAreas {
            premises_id: "p".into(),
            storey_id: Some(" ".into()),
            day: "2026-09-22".into(),
        },
        CacheQuery::LibBookBookings { page: 0, limit: 20 },
    ] {
        assert_eq!(
            CacheScope {
                route: ConnectionMode::Direct,
                query
            }
            .validate(),
            Err(CacheError::InvalidInput)
        );
    }
    let payload = CachePayload::LibBookBookings(CachedLibBookBookingsPage {
        page: 2,
        limit: 20,
        ..Default::default()
    });
    assert!(!payload.matches(&CacheQuery::LibBookBookings { page: 1, limit: 20 }));
    assert!(payload.matches(&CacheQuery::LibBookBookings { page: 2, limit: 20 }));
}
