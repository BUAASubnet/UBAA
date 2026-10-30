use super::ygdk;
use crate::facade::{
    CacheCompleteness, CacheError, CacheInvalidation, CacheKey, CacheLimits, CachePayload,
    CachePublication, CachedYgdkOverview, ConnectionMode, OfflineCache, YgdkOverview,
};
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT: AtomicU64 = AtomicU64::new(0);
fn now(day: &str) -> i64 {
    chrono::DateTime::parse_from_rfc3339(day)
        .unwrap()
        .timestamp()
}
fn cache() -> (std::path::PathBuf, OfflineCache) {
    let root = std::env::temp_dir().join(format!(
        "ubaa-ygdk-period-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&root).unwrap();
    let cache = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "synthetic",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    (root, cache)
}
fn value(term: Option<i32>, classify: i32, count: i32) -> CachedYgdkOverview {
    let mut data = YgdkOverview {
        classify_id: classify,
        ..YgdkOverview::default()
    };
    data.summary.term_id = term;
    data.summary.term_count = count;
    data.summary.week_count = Some(count);
    data.summary.day_count = Some(count);
    data.summary.month_count = Some(count);
    data.into()
}
fn save(
    cache: &OfflineCache,
    route: ConnectionMode,
    at: i64,
    data: &CachedYgdkOverview,
    complete: bool,
) -> (crate::facade::CacheScope, CachePublication) {
    let parent = cache
        .begin(ygdk::selection_scope(route, at).unwrap())
        .unwrap();
    ygdk::publish(cache, &parent, data, at, at, complete).unwrap()
}
#[test]
fn 阳光概览按已观察学期分类路线与校园日历周独立保存() {
    let (root, cache) = cache();
    let monday = now("2026-09-21T00:00:00+08:00");
    let next = now("2026-09-28T00:00:00+08:00");
    let direct = ConnectionMode::Direct;
    let first = save(&cache, direct, monday, &value(Some(10), 1, 2), true).0;
    let second = save(&cache, direct, monday + 1, &value(Some(11), 1, 3), true).0;
    let other = save(
        &cache,
        ConnectionMode::WebVpn,
        monday,
        &value(Some(10), 2, 4),
        true,
    )
    .0;
    assert_ne!(first, second);
    assert_eq!(
        cache.read(&first, next).unwrap().unwrap().payload,
        CachePayload::YgdkOverview(value(Some(10), 1, 2))
    );
    assert!(ygdk::read(&cache, direct, monday - 1).unwrap().is_none());
    assert!(ygdk::read(&cache, direct, next).unwrap().is_none());
    let third = save(&cache, direct, next, &value(Some(11), 1, 5), true).0;
    assert_ne!(third, second);
    assert!(cache.read(&other, next).unwrap().is_some());
    let current = ygdk::read(&cache, direct, monday + 2).unwrap().unwrap();
    assert_eq!(current.scope, second);
    assert_eq!(current.fetched_at, monday + 1);
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 阳光跨日跨月不沿用日月计数_不改写原取得时间() {
    let (root, cache) = cache();
    let at = now("2026-09-30T23:59:59+08:00");
    let route = ConnectionMode::Direct;
    let scope = save(&cache, route, at, &value(Some(10), 1, 2), true).0;
    let later = ygdk::read(&cache, route, at + 1).unwrap().unwrap();
    let CachePayload::YgdkOverview(data) = later.payload else {
        panic!("错误载荷")
    };
    assert_eq!(data.summary.day_count, None);
    assert_eq!(data.summary.month_count, None);
    assert_eq!(data.summary.week_count, Some(2));
    assert_eq!(later.fetched_at, at);
    assert_eq!(
        cache.read(&scope, at).unwrap().unwrap().payload,
        CachePayload::YgdkOverview(value(Some(10), 1, 2))
    );
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 阳光部分结果保留完整范围_未知学期与跨日读取不能冒充完整() {
    let (root, cache) = cache();
    let at = now("2026-09-22T12:00:00+08:00");
    let route = ConnectionMode::Direct;
    let full = save(&cache, route, at, &value(Some(10), 1, 2), true).0;
    assert_eq!(
        save(&cache, route, at + 1, &value(Some(10), 1, 0), false).1,
        CachePublication::Preserved
    );
    save(&cache, route, at + 2, &value(None, 1, 0), false);
    assert_eq!(
        ygdk::read(&cache, route, at + 2).unwrap().unwrap().scope,
        full
    );
    let other = save(&cache, route, at + 3, &value(Some(11), 1, 3), false).0;
    assert_eq!(
        cache.read(&other, at).unwrap().unwrap().completeness,
        CacheCompleteness::Partial
    );
    assert_eq!(
        ygdk::read(&cache, route, at + 3).unwrap().unwrap().scope,
        full
    );
    let parent = cache
        .begin(ygdk::selection_scope(route, at).unwrap())
        .unwrap();
    assert!(matches!(
        ygdk::publish(
            &cache,
            &parent,
            &value(Some(10), 1, 3),
            at,
            at + 86_400,
            true
        ),
        Err(CacheError::Superseded)
    ));
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn 阳光迟到父票据与写后失效不能重建旧周期或撤销新读取() {
    let (root, cache) = cache();
    let at = now("2026-09-22T12:00:00+08:00");
    let route = ConnectionMode::Direct;
    let parent = cache
        .begin(ygdk::selection_scope(route, at).unwrap())
        .unwrap();
    let scope = save(&cache, route, at + 1, &value(Some(10), 1, 2), true).0;
    let newer = cache.begin(scope.clone()).unwrap();
    assert!(matches!(
        ygdk::publish(&cache, &parent, &value(Some(10), 1, 3), at, at + 2, true),
        Err(CacheError::Superseded)
    ));
    cache.validate_read(&newer).unwrap();
    let other = save(
        &cache,
        ConnectionMode::WebVpn,
        at,
        &value(Some(10), 1, 2),
        true,
    )
    .0;
    cache
        .invalidate(route, &CacheInvalidation::Ygdk { classify_id: 1 })
        .unwrap();
    assert!(cache.read(&scope, at).unwrap().is_none());
    assert!(ygdk::read(&cache, route, at).unwrap().is_none());
    assert!(cache.read(&other, at).unwrap().is_some());
    assert!(matches!(
        cache.validate_read(&newer),
        Err(CacheError::Superseded)
    ));
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 阳光未知学期不完整_范围和载荷必须一致() {
    use crate::facade::{CacheQuery, CacheScope};
    let (root, cache) = cache();
    let at = now("2026-09-22T12:00:00+08:00");
    let route = ConnectionMode::Direct;
    let unknown = save(&cache, route, at, &value(None, 1, 0), true).0;
    assert_eq!(
        cache.read(&unknown, at).unwrap().unwrap().completeness,
        CacheCompleteness::Partial
    );
    let mismatched = cache.begin(unknown).unwrap();
    assert!(matches!(
        cache.publish(
            &mismatched,
            CachePayload::YgdkOverview(value(Some(10), 1, 2)),
            at
        ),
        Err(CacheError::InvalidInput)
    ));
    let non_monday = CacheScope {
        route,
        query: CacheQuery::YgdkOverviewSelection {
            week_start: "2026-09-22".into(),
        },
    };
    assert!(matches!(
        cache.begin(non_monday),
        Err(CacheError::InvalidInput)
    ));
    drop(cache);
    let reopened = OfflineCache::open(
        &root,
        "0123456789abcdef0123456789abcdef",
        "synthetic",
        CacheKey::new([9; 32]),
        CacheLimits::default(),
    )
    .unwrap();
    let cached = ygdk::read(&reopened, route, at).unwrap().unwrap();
    assert_eq!(cached.fetched_at, at);
    assert_eq!(cached.completeness, CacheCompleteness::Partial);
    drop(reopened);
    std::fs::remove_dir_all(root).unwrap();
}
