//! 路线内存缓存共用的 TTL 与容量辅助。

use std::collections::HashMap;
use std::hash::Hash;
use std::time::{Duration, Instant};

pub(super) struct TimedEntry<T> {
    pub(super) value: T,
    pub(super) cached_at: Instant,
}

pub(super) fn is_fresh(cached_at: Instant, now: Instant, ttl: Duration) -> bool {
    now.saturating_duration_since(cached_at) < ttl
}

pub(super) fn insert_bounded<K, V>(
    map: &mut HashMap<K, TimedEntry<V>>,
    key: K,
    value: V,
    now: Instant,
    limit: usize,
) where
    K: Clone + Eq + Hash,
{
    if !map.contains_key(&key)
        && map.len() >= limit
        && let Some(oldest) = map
            .iter()
            .min_by_key(|(_, entry)| entry.cached_at)
            .map(|(key, _)| key.clone())
    {
        map.remove(&oldest);
    }
    map.insert(
        key,
        TimedEntry {
            value,
            cached_at: now,
        },
    );
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::time::{Duration, Instant};

    use super::{TimedEntry, insert_bounded, is_fresh};

    #[test]
    fn ttl_boundary_is_strict_and_past_cached_time_is_safe() {
        let cached_at = Instant::now();
        let ttl = Duration::from_secs(5);
        assert!(is_fresh(cached_at, cached_at, ttl));
        assert!(is_fresh(
            cached_at,
            cached_at + ttl - Duration::from_nanos(1),
            ttl
        ));
        assert!(!is_fresh(cached_at, cached_at + ttl, ttl));
        assert!(!is_fresh(
            cached_at,
            cached_at + ttl + Duration::from_nanos(1),
            ttl
        ));
        assert!(is_fresh(cached_at, cached_at - Duration::from_secs(1), ttl));
        assert!(!is_fresh(cached_at, cached_at, Duration::ZERO));
    }

    #[test]
    fn bounded_insert_evicts_only_the_unique_oldest_and_updates_existing_keys() {
        let base = Instant::now();
        let mut map = HashMap::new();
        insert_bounded(&mut map, "old", 1, base, 2);
        insert_bounded(&mut map, "new", 2, base + Duration::from_secs(1), 2);
        insert_bounded(&mut map, "new", 3, base + Duration::from_secs(2), 2);
        assert_eq!(map.len(), 2);
        assert!(map.contains_key("old"));
        assert_eq!(map["new"].value, 3);

        insert_bounded(&mut map, "latest", 4, base + Duration::from_secs(3), 2);
        assert_eq!(map.len(), 2);
        assert!(map.contains_key("new"));
        assert!(map.contains_key("latest"));

        let entry: &TimedEntry<_> = &map["latest"];
        assert_eq!(entry.cached_at, base + Duration::from_secs(3));
    }
}
