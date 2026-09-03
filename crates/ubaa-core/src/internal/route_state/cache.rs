//! 路线内存缓存共用的 TTL 与容量辅助。

use std::collections::HashMap;
use std::hash::Hash;
use std::time::{Duration, Instant};

use crate::domain::{Assignment, Course, JudgeAssignmentDetail};

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

/// Judge 课程下的作业集合及解析统计。
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct AssignmentList {
    pub(crate) assignments: Vec<Assignment>,
    pub(crate) raw_anchor_count: usize,
}

impl AssignmentList {
    pub(crate) fn filtered_unique_count(&self) -> usize {
        self.assignments.len()
    }
}

pub(crate) const JUDGE_ASSIGNMENT_CACHE_LIMIT: usize = 128;
pub(crate) const JUDGE_DETAIL_CACHE_LIMIT: usize = 1_024;
pub(crate) const JUDGE_HISTORICAL_CACHE_LIMIT: usize = 128;

#[derive(Default)]
struct JudgeCache {
    courses: Option<TimedEntry<Vec<Course>>>,
    assignments: HashMap<String, TimedEntry<AssignmentList>>,
    details: HashMap<(String, String), TimedEntry<JudgeAssignmentDetail>>,
    historical_courses: HashMap<String, TimedEntry<()>>,
}

/// 路线/客户端拥有的 Judge 缓存和历史截止状态。
#[derive(Default)]
pub(crate) struct JudgeState {
    invalidations: std::sync::atomic::AtomicU64,
    cache: std::sync::Mutex<JudgeCache>,
}

impl JudgeState {
    pub(crate) fn generation(&self) -> u64 {
        self.invalidations
            .load(std::sync::atomic::Ordering::Acquire)
    }

    pub(crate) fn courses(
        &self,
        generation: u64,
        now: Instant,
        ttl: Duration,
    ) -> Option<Vec<Course>> {
        let mut cache = self.cache();
        if self.generation() != generation {
            return None;
        }
        if cache
            .courses
            .as_ref()
            .is_some_and(|entry| !is_fresh(entry.cached_at, now, ttl))
        {
            cache.courses = None;
        }
        cache.courses.as_ref().map(|entry| entry.value.clone())
    }

    pub(crate) fn store_courses(
        &self,
        generation: u64,
        courses: Vec<Course>,
        now: Instant,
    ) -> bool {
        let mut cache = self.cache();
        if self.generation() != generation {
            return false;
        }
        cache.courses = (!courses.is_empty()).then_some(TimedEntry {
            value: courses,
            cached_at: now,
        });
        true
    }

    pub(crate) fn assignments(
        &self,
        generation: u64,
        course_id: &str,
        now: Instant,
        ttl: Duration,
    ) -> Option<AssignmentList> {
        let mut cache = self.cache();
        if self.generation() != generation {
            return None;
        }
        cache
            .assignments
            .retain(|_, entry| is_fresh(entry.cached_at, now, ttl));
        cache
            .assignments
            .get(course_id)
            .map(|entry| entry.value.clone())
    }

    pub(crate) fn store_assignments(
        &self,
        generation: u64,
        course_id: &str,
        assignments: AssignmentList,
        now: Instant,
    ) -> bool {
        let mut cache = self.cache();
        if self.generation() != generation {
            return false;
        }
        if assignments.assignments.is_empty() {
            cache.assignments.remove(course_id);
            return true;
        }
        insert_bounded(
            &mut cache.assignments,
            course_id.to_string(),
            assignments,
            now,
            JUDGE_ASSIGNMENT_CACHE_LIMIT,
        );
        true
    }

    pub(crate) fn detail(
        &self,
        generation: u64,
        course_id: &str,
        assignment_id: &str,
        now: Instant,
        ttl: Duration,
    ) -> Option<JudgeAssignmentDetail> {
        let mut cache = self.cache();
        if self.generation() != generation {
            return None;
        }
        cache
            .details
            .retain(|_, entry| is_fresh(entry.cached_at, now, ttl));
        cache
            .details
            .get(&(course_id.to_string(), assignment_id.to_string()))
            .map(|entry| entry.value.clone())
    }

    pub(crate) fn store_detail(
        &self,
        generation: u64,
        course_id: &str,
        assignment_id: &str,
        detail: JudgeAssignmentDetail,
        now: Instant,
    ) -> bool {
        let mut cache = self.cache();
        if self.generation() != generation {
            return false;
        }
        insert_bounded(
            &mut cache.details,
            (course_id.to_string(), assignment_id.to_string()),
            detail,
            now,
            JUDGE_DETAIL_CACHE_LIMIT,
        );
        true
    }

    pub(crate) fn historical_courses(&self, generation: u64) -> std::collections::HashSet<String> {
        let cache = self.cache();
        if self.generation() != generation {
            return std::collections::HashSet::new();
        }
        cache.historical_courses.keys().cloned().collect()
    }

    pub(crate) fn mark_historical(&self, generation: u64, course_id: &str, now: Instant) -> bool {
        let mut cache = self.cache();
        if self.generation() != generation {
            return false;
        }
        insert_bounded(
            &mut cache.historical_courses,
            course_id.to_string(),
            (),
            now,
            JUDGE_HISTORICAL_CACHE_LIMIT,
        );
        true
    }

    pub(crate) fn clear(&self) {
        self.invalidations
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
        *self.cache() = JudgeCache::default();
    }

    fn cache(&self) -> std::sync::MutexGuard<'_, JudgeCache> {
        self.cache
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    #[cfg(test)]
    pub(crate) fn cache_counts(&self) -> (usize, usize, usize, usize) {
        let cache = self.cache();
        (
            usize::from(cache.courses.is_some()),
            cache.assignments.len(),
            cache.details.len(),
            cache.historical_courses.len(),
        )
    }
}

impl std::fmt::Debug for JudgeState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let cache = self.cache();
        formatter
            .debug_struct("JudgeState")
            .field("generation", &self.generation())
            .field("courses_cached", &cache.courses.is_some())
            .field("assignment_cache_entries", &cache.assignments.len())
            .field("detail_cache_entries", &cache.details.len())
            .field("historical_course_entries", &cache.historical_courses.len())
            .finish()
    }
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
            (cached_at + ttl)
                .checked_sub(Duration::from_nanos(1))
                .expect("测试时间应支持纳秒回退"),
            ttl
        ));
        assert!(!is_fresh(cached_at, cached_at + ttl, ttl));
        assert!(!is_fresh(
            cached_at,
            cached_at + ttl + Duration::from_nanos(1),
            ttl
        ));
        assert!(is_fresh(
            cached_at,
            cached_at
                .checked_sub(Duration::from_secs(1))
                .expect("测试时间应支持一秒回退"),
            ttl
        ));
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
