//! Route-owned, process-local state for read-only feature workflows.

use std::collections::{HashMap, HashSet};
use std::future::Future;
use std::hash::Hash;
use std::sync::Mutex as SyncMutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use tokio::sync::Mutex;

/// State shared only by runtimes and read workers for one route/client.
#[derive(Debug, Default)]
pub(crate) struct RouteFeatureState {
    pub(crate) bykc: BykcState,
    pub(crate) libbook: LibBookState,
    pub(crate) classroom: ClassroomState,
    pub(crate) signin: SigninState,
    pub(crate) spoc: SpocState,
    pub(crate) judge: JudgeState,
    pub(crate) ygdk: YgdkState,
}

impl RouteFeatureState {
    pub(crate) fn clear(&self) {
        self.bykc.clear();
        self.libbook.clear();
        self.classroom.clear();
        self.signin.clear();
        self.spoc.clear();
        self.judge.clear();
        self.ygdk.clear();
    }
}

/// 路线内存中的博雅业务会话，不写入主认证会话文件。
#[allow(dead_code)]
#[derive(Debug, Default)]
pub(crate) struct BykcState {
    credential: SyncMutex<Option<crate::features::bykc::BykcCredential>>,
    login: Mutex<()>,
}

#[allow(dead_code)]
impl BykcState {
    pub(crate) fn credential(&self) -> Option<crate::features::bykc::BykcCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn set(&self, value: crate::features::bykc::BykcCredential) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(value);
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn clear(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }
}

/// 路线内存中的图书馆业务会话，不写入磁盘。
#[derive(Debug, Default)]
pub(crate) struct LibBookState {
    credential: SyncMutex<Option<crate::features::libbook::LibBookCredential>>,
    login: Mutex<()>,
}

impl LibBookState {
    pub(crate) fn credential(&self) -> Option<crate::features::libbook::LibBookCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) fn set(&self, value: crate::features::libbook::LibBookCredential) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(value);
    }

    pub(crate) fn clear_credential(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    fn clear(&self) {
        self.clear_credential();
    }
}

/// 路线内存中的阳光打卡业务会话，不写入磁盘。
#[derive(Debug, Default)]
#[allow(dead_code)]
pub(crate) struct YgdkState {
    credential: SyncMutex<Option<crate::features::ygdk::YgdkCredential>>,
    login: Mutex<()>,
}
impl YgdkState {
    #[allow(dead_code)]
    pub(crate) fn credential(&self) -> Option<crate::features::ygdk::YgdkCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    #[allow(dead_code)]
    pub(crate) fn set(&self, value: crate::features::ygdk::YgdkCredential) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(value);
    }
    pub(crate) fn clear(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }
    #[allow(dead_code)]
    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }
}

/// 路线内存中的 iClass 业务会话，不写入主认证会话文件。
#[allow(dead_code)]
#[derive(Default)]
pub(crate) struct SigninState {
    invalidations: AtomicU64,
    login: Mutex<()>,
    credential: SyncMutex<Option<crate::features::signin::SigninCredential>>,
}

impl SigninState {
    pub(crate) fn generation(&self) -> u64 {
        self.invalidations.load(Ordering::Acquire)
    }

    pub(crate) fn credential(&self) -> Option<crate::features::signin::SigninCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(crate) fn store_credential(
        &self,
        generation: u64,
        credential: crate::features::signin::SigninCredential,
    ) -> bool {
        if self.generation() != generation {
            return false;
        }
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(credential);
        true
    }

    pub(crate) fn clear_credential(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
        self.clear_credential();
    }
}

impl std::fmt::Debug for SigninState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SigninState")
            .field("generation", &self.generation())
            .field("credential", &"[已隐藏]")
            .finish()
    }
}

/// Once-per-route Classroom bootstrap state.
#[derive(Debug, Default)]
pub(crate) struct ClassroomState {
    sync: Mutex<()>,
    // The low bit is the synchronized flag. Higher bits form an invalidation generation.
    generation_and_synced: AtomicU64,
}

impl ClassroomState {
    pub(crate) async fn ensure_synced<F, Fut>(&self, synchronize: F)
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = bool>,
    {
        if self.is_synced() {
            return;
        }
        let _guard = self.sync.lock().await;
        if self.is_synced() {
            return;
        }
        let generation = self.generation_and_synced.load(Ordering::Acquire);
        if synchronize().await {
            let _ = self.generation_and_synced.compare_exchange(
                generation,
                generation | 1,
                Ordering::AcqRel,
                Ordering::Acquire,
            );
        }
    }

    fn is_synced(&self) -> bool {
        self.generation_and_synced.load(Ordering::Acquire) & 1 == 1
    }

    pub(crate) fn clear(&self) {
        let _ =
            self.generation_and_synced
                .fetch_update(Ordering::AcqRel, Ordering::Acquire, |state| {
                    Some((state & !1).wrapping_add(2))
                });
    }
}

/// Route-owned SPOC credential and serialized login state.
#[derive(Default)]
pub(crate) struct SpocState {
    invalidations: AtomicU64,
    login: Mutex<()>,
    credential: SyncMutex<Option<crate::features::spoc::SpocCredential>>,
}

impl SpocState {
    pub(super) fn credential(&self) -> Option<crate::features::spoc::SpocCredential> {
        self.credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(super) fn store_credential(
        &self,
        generation: u64,
        credential: crate::features::spoc::SpocCredential,
    ) -> bool {
        let mut cached = self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.generation() != generation {
            return false;
        }
        *cached = Some(credential);
        true
    }

    pub(super) fn clear_credential(&self) {
        *self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    pub(super) async fn login_guard(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.login.lock().await
    }

    pub(super) fn generation(&self) -> u64 {
        self.invalidations.load(Ordering::Acquire)
    }

    fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
        // A concurrent holder may still be using the old credential; the generation check
        // prevents it from repopulating this cache after invalidation.
        let mut credential = self
            .credential
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        *credential = None;
    }
}

impl std::fmt::Debug for SpocState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SpocState")
            .field("generation", &self.generation())
            .field("credential", &"[REDACTED]")
            .finish()
    }
}

pub(super) const JUDGE_ASSIGNMENT_CACHE_LIMIT: usize = 128;
pub(super) const JUDGE_DETAIL_CACHE_LIMIT: usize = 1_024;
pub(super) const JUDGE_HISTORICAL_CACHE_LIMIT: usize = 128;

struct TimedEntry<T> {
    value: T,
    cached_at: Instant,
}

#[derive(Default)]
struct JudgeCache {
    courses: Option<TimedEntry<Vec<crate::features::judge::Course>>>,
    assignments: HashMap<String, TimedEntry<crate::features::judge::AssignmentList>>,
    details: HashMap<(String, String), TimedEntry<crate::domain::JudgeAssignmentDetail>>,
    historical_courses: HashMap<String, TimedEntry<()>>,
}

/// Route/client-owned Judge caches and historical cutoff state.
#[derive(Default)]
pub(crate) struct JudgeState {
    invalidations: AtomicU64,
    cache: SyncMutex<JudgeCache>,
}

impl JudgeState {
    pub(crate) fn generation(&self) -> u64 {
        self.invalidations.load(Ordering::Acquire)
    }

    pub(crate) fn courses(
        &self,
        generation: u64,
        now: Instant,
        ttl: Duration,
    ) -> Option<Vec<crate::features::judge::Course>> {
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
        courses: Vec<crate::features::judge::Course>,
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
    ) -> Option<crate::features::judge::AssignmentList> {
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
        assignments: crate::features::judge::AssignmentList,
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
    ) -> Option<crate::domain::JudgeAssignmentDetail> {
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
        detail: crate::domain::JudgeAssignmentDetail,
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

    pub(crate) fn historical_courses(&self, generation: u64) -> HashSet<String> {
        let cache = self.cache();
        if self.generation() != generation {
            return HashSet::new();
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

    fn clear(&self) {
        self.invalidations.fetch_add(1, Ordering::AcqRel);
        *self.cache() = JudgeCache::default();
    }

    fn cache(&self) -> std::sync::MutexGuard<'_, JudgeCache> {
        self.cache
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    #[cfg(test)]
    fn cache_counts(&self) -> (usize, usize, usize, usize) {
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

fn is_fresh(cached_at: Instant, now: Instant, ttl: Duration) -> bool {
    now.saturating_duration_since(cached_at) < ttl
}

fn insert_bounded<K, V>(
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
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{Duration, Instant};

    use crate::domain::{JudgeAssignmentDetail, JudgeSubmissionStatus};
    use crate::features::bykc::BykcCredential;
    use crate::features::judge::{Assignment, AssignmentList, Course};

    use super::{BykcState, ClassroomState, JudgeState};

    #[test]
    fn 博雅凭据仅驻留路线状态且调试输出脱敏() {
        let state = BykcState::default();
        state.set(BykcCredential {
            token: "仅用于测试的令牌".to_owned(),
        });
        let credential = state.credential().unwrap();
        assert_eq!(credential.token, "仅用于测试的令牌");
        assert!(!format!("{credential:?}").contains("仅用于测试的令牌"));

        state.clear();
        assert!(state.credential().is_none());
    }

    #[test]
    fn concurrent_classroom_bootstraps_use_one_double_checked_sync() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .unwrap();
        runtime.block_on(async {
            let state = Arc::new(ClassroomState::default());
            let calls = Arc::new(AtomicUsize::new(0));
            let first_state = Arc::clone(&state);
            let first_calls = Arc::clone(&calls);
            let second_state = Arc::clone(&state);
            let second_calls = Arc::clone(&calls);

            let first = tokio::spawn(async move {
                first_state
                    .ensure_synced(|| async move {
                        first_calls.fetch_add(1, Ordering::SeqCst);
                        tokio::time::sleep(Duration::from_millis(10)).await;
                        true
                    })
                    .await;
            });
            let second = tokio::spawn(async move {
                second_state
                    .ensure_synced(|| async move {
                        second_calls.fetch_add(1, Ordering::SeqCst);
                        true
                    })
                    .await;
            });
            first.await.unwrap();
            second.await.unwrap();

            assert_eq!(calls.load(Ordering::SeqCst), 1);
        });
    }

    #[test]
    fn failed_or_cleared_classroom_sync_remains_retryable() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        runtime.block_on(async {
            let state = ClassroomState::default();
            let calls = AtomicUsize::new(0);

            state
                .ensure_synced(|| async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    false
                })
                .await;
            state
                .ensure_synced(|| async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    true
                })
                .await;
            state.clear();
            state
                .ensure_synced(|| async {
                    calls.fetch_add(1, Ordering::SeqCst);
                    true
                })
                .await;

            assert_eq!(calls.load(Ordering::SeqCst), 3);
        });
    }

    #[test]
    fn judge_cache_prunes_expired_entries_and_does_not_store_empty_lists() {
        let state = JudgeState::default();
        let generation = state.generation();
        let now = Instant::now();
        let expired_at = now
            .checked_sub(Duration::from_secs(301))
            .expect("test Instant supports a five-minute subtraction");
        let course = Course {
            course_id: "1".into(),
            course_name: "Course".into(),
        };
        let assignment = Assignment {
            assignment_id: "101".into(),
            course_id: "1".into(),
            course_name: "Course".into(),
            title: "Assignment".into(),
        };
        let detail = JudgeAssignmentDetail {
            course_id: "1".into(),
            course_name: "Course".into(),
            assignment_id: "101".into(),
            title: "Assignment".into(),
            start_time: None,
            due_time: None,
            max_score: None,
            my_score: None,
            total_problems: 0,
            submitted_count: 0,
            submission_status: JudgeSubmissionStatus::Unknown,
            submission_status_text: "未知状态".into(),
            problems: Vec::new(),
            content_plain_text: None,
        };

        assert!(state.store_courses(generation, vec![course], expired_at));
        assert!(state.store_assignments(
            generation,
            "1",
            AssignmentList {
                assignments: vec![assignment],
                raw_anchor_count: 3,
            },
            expired_at,
        ));
        assert!(state.store_detail(generation, "1", "101", detail, expired_at));

        assert!(
            state
                .courses(generation, now, Duration::from_mins(5))
                .is_none()
        );
        assert!(
            state
                .assignments(generation, "1", now, Duration::from_mins(5))
                .is_none()
        );
        assert!(
            state
                .detail(generation, "1", "101", now, Duration::from_mins(2))
                .is_none()
        );
        assert_eq!(state.cache_counts(), (0, 0, 0, 0));

        assert!(state.store_assignments(
            generation,
            "1",
            AssignmentList {
                assignments: Vec::new(),
                raw_anchor_count: 2,
            },
            now,
        ));
        assert!(
            state
                .assignments(generation, "1", now, Duration::from_mins(5))
                .is_none()
        );
    }

    #[test]
    fn judge_cache_is_bounded_and_clear_removes_every_entry() {
        let state = JudgeState::default();
        let generation = state.generation();
        let now = Instant::now();
        for index in 0..=super::JUDGE_ASSIGNMENT_CACHE_LIMIT {
            let course_id = index.to_string();
            assert!(state.store_assignments(
                generation,
                &course_id,
                AssignmentList {
                    assignments: vec![Assignment {
                        assignment_id: "1".into(),
                        course_id: course_id.clone(),
                        course_name: "Course".into(),
                        title: "Assignment".into(),
                    }],
                    raw_anchor_count: 1,
                },
                now,
            ));
            assert!(state.mark_historical(generation, &course_id, now));
        }
        for index in 0..=super::JUDGE_DETAIL_CACHE_LIMIT {
            let assignment_id = index.to_string();
            assert!(state.store_detail(
                generation,
                "1",
                &assignment_id,
                JudgeAssignmentDetail {
                    course_id: "1".into(),
                    course_name: "Course".into(),
                    assignment_id: assignment_id.clone(),
                    title: "Assignment".into(),
                    start_time: None,
                    due_time: None,
                    max_score: None,
                    my_score: None,
                    total_problems: 0,
                    submitted_count: 0,
                    submission_status: JudgeSubmissionStatus::Unknown,
                    submission_status_text: "未知状态".into(),
                    problems: Vec::new(),
                    content_plain_text: None,
                },
                now,
            ));
        }

        let (_, assignments, details, historical) = state.cache_counts();
        assert_eq!(assignments, super::JUDGE_ASSIGNMENT_CACHE_LIMIT);
        assert_eq!(details, super::JUDGE_DETAIL_CACHE_LIMIT);
        assert!(historical <= super::JUDGE_HISTORICAL_CACHE_LIMIT);

        state.clear();
        assert_eq!(state.cache_counts(), (0, 0, 0, 0));
        assert_ne!(state.generation(), generation);
        assert!(!state.store_assignments(
            generation,
            "stale",
            AssignmentList {
                assignments: Vec::new(),
                raw_anchor_count: 0,
            },
            now,
        ));
    }

    #[test]
    fn invalidated_judge_generation_cannot_repopulate_any_cache() {
        let state = JudgeState::default();
        let generation = state.generation();
        let now = Instant::now();
        state.clear();

        assert!(!state.store_courses(
            generation,
            vec![Course {
                course_id: "1".into(),
                course_name: "Stale Course".into(),
            }],
            now,
        ));
        assert!(!state.store_assignments(
            generation,
            "1",
            AssignmentList {
                assignments: vec![Assignment {
                    assignment_id: "101".into(),
                    course_id: "1".into(),
                    course_name: "Stale Course".into(),
                    title: "Stale Assignment".into(),
                }],
                raw_anchor_count: 1,
            },
            now,
        ));
        assert!(!state.mark_historical(generation, "1", now));
        assert_eq!(state.cache_counts(), (0, 0, 0, 0));
    }
}
