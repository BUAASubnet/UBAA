use super::*;
use crate::{
    cache::{CacheInvalidation, CacheKey, CacheLimits, CachePayload},
    domain::{ConnectionMode, TodayClass},
};

const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";

struct Fixture(crate::test_tmp::TestTempDir);
impl Fixture {
    fn new() -> Self {
        Self(crate::test_tmp::test_temp_dir("ubaa_core_cache_shared_read").unwrap())
    }

    fn open(&self) -> OfflineRepository {
        OfflineRepository::open(
            &self.0,
            ACCOUNT,
            CacheKey::new([9; 32]),
            CacheLimits::default(),
        )
        .unwrap()
    }
}

fn today() -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-11-17".into(),
        },
    }
}

fn class(name: &str) -> CachePayload {
    CachePayload::Today(vec![TodayClass {
        biz_name: name.into(),
        place: None,
        time: None,
        short_name: None,
    }])
}

#[test]
fn shared_read_second_competition_preserves_previous_content_and_next_ticket() {
    let dir = Fixture::new();
    let (mut a, mut b) = (dir.open(), dir.open());
    let scope = today();
    let saved = a.begin_read(scope.clone()).unwrap();
    a.publish(&saved, class("旧缓存"), 100, CacheCompleteness::Complete)
        .unwrap();
    let first = a.begin_read(scope.clone()).unwrap();
    let pending = b.begin_read(scope.clone()).unwrap();
    assert_eq!(
        a.publish(&first, class("本轮"), 101, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    );
    let SharedReadRecovery::Retry(retry) = a.recover_shared_read(&first, true).unwrap() else {
        panic!("第一次竞争应补发票据");
    };
    assert_eq!(b.validate_read(&pending), Err(CacheError::Superseded));
    let winner = b.begin_read(scope.clone()).unwrap();
    assert_eq!(
        a.publish(&retry, class("本轮"), 101, CacheCompleteness::Complete),
        Err(CacheError::Superseded)
    );
    let SharedReadRecovery::Superseded(Some(record)) =
        a.recover_shared_read(&retry, false).unwrap()
    else {
        panic!("第二次竞争应保留旧缓存");
    };
    assert_eq!(record.payload, class("旧缓存"));
    assert_eq!(record.fetched_at, 100);
    assert_eq!(a.read(&scope, 102).unwrap(), Some(record));
    b.validate_read(&winner).unwrap();
}

#[test]
fn shared_read_prefers_newer_complete_even_with_later_request_pending() {
    let dir = Fixture::new();
    let (mut a, mut b) = (dir.open(), dir.open());
    let scope = today();
    let first = a.begin_read(scope.clone()).unwrap();
    let complete = b.begin_read(scope.clone()).unwrap();
    b.publish(&complete, class("已更新"), 100, CacheCompleteness::Complete)
        .unwrap();
    let winner = b.begin_read(scope).unwrap();
    let SharedReadRecovery::Reuse(record) = a.recover_shared_read(&first, true).unwrap() else {
        panic!("已完成的较新缓存优先");
    };
    assert_eq!(record.payload, class("已更新"));
    b.validate_read(&winner).unwrap();
}

#[test]
fn shared_read_cannot_revive_earlier_local_ticket_after_external_replacement() {
    let dir = Fixture::new();
    let (mut a, mut b) = (dir.open(), dir.open());
    let scope = today();
    let old = a.begin_read(scope.clone()).unwrap();
    drop(a.begin_read(scope.clone()).unwrap());
    let winner = b.begin_read(scope).unwrap();
    assert!(matches!(
        a.recover_shared_read(&old, true),
        Err(CacheError::Superseded)
    ));
    b.validate_read(&winner).unwrap();
}

#[test]
fn shared_read_cannot_cross_invalidation_even_after_another_instance_saves() {
    let dir = Fixture::new();
    let (mut a, mut b) = (dir.open(), dir.open());
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::SigninToday {
            date: "20261117".into(),
        },
    };
    let old = a.begin_read(scope.clone()).unwrap();
    b.invalidate(
        scope.route,
        &CacheInvalidation::Signin {
            date: "20261117".into(),
        },
    )
    .unwrap();
    let winner = b.begin_read(scope).unwrap();
    b.publish(
        &winner,
        CachePayload::SigninToday(Vec::new()),
        100,
        CacheCompleteness::Complete,
    )
    .unwrap();
    assert!(matches!(
        a.recover_shared_read(&old, true),
        Err(CacheError::Superseded)
    ));
}

#[test]
fn shared_read_can_retry_after_competing_failure_retains_previous_record() {
    let dir = Fixture::new();
    let (mut a, mut b) = (dir.open(), dir.open());
    let scope = today();
    let saved = a.begin_read(scope.clone()).unwrap();
    a.publish(&saved, class("旧缓存"), 100, CacheCompleteness::Complete)
        .unwrap();
    let first = a.begin_read(scope.clone()).unwrap();
    let newer = b.begin_read(scope).unwrap();
    b.record_failure(&newer, 101).unwrap();
    assert!(matches!(
        a.recover_shared_read(&first, true),
        Ok(SharedReadRecovery::Retry(_))
    ));
}
