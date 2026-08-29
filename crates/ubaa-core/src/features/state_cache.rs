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
