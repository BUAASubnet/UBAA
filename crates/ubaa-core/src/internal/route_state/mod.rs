//! 路线专属功能状态的聚合入口.

mod cache;
mod classroom;
mod credentials;

pub(crate) use cache::{AssignmentList, JudgeState};
#[cfg(test)]
use cache::{JUDGE_ASSIGNMENT_CACHE_LIMIT, JUDGE_DETAIL_CACHE_LIMIT, JUDGE_HISTORICAL_CACHE_LIMIT};
pub(crate) use classroom::ClassroomState;
#[cfg(test)]
pub(crate) use credentials::StoreCredentialHook;
pub(crate) use credentials::{
    BykcCredential, BykcState, CgyyState, LibBookCredential, LibBookState, SigninCredential,
    SigninState, SpocCredential, SpocState, YgdkCredential, YgdkState,
};

/// 仅由一条路线/一个客户端的运行时和读取工作线程共享的状态。
#[derive(Debug, Default)]
pub(crate) struct RouteFeatureState {
    pub(crate) bykc: BykcState,
    pub(crate) cgyy: CgyyState,
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
        self.cgyy.clear();
        self.libbook.clear();
        self.classroom.clear();
        self.signin.clear();
        self.spoc.clear();
        self.judge.clear();
        self.ygdk.clear();
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;
    use std::time::{Duration, Instant};

    use crate::domain::{Assignment, Course, JudgeAssignmentDetail, JudgeSubmissionStatus};

    use super::{
        AssignmentList, BykcCredential, BykcState, ClassroomState, JudgeState, RouteFeatureState,
        SigninCredential, SigninState, StoreCredentialHook, YgdkCredential,
    };

    #[test]
    fn 聚合路线状态调试输出不泄露业务令牌() {
        let state = RouteFeatureState::default();
        state.cgyy.set("cgyy-state-secret-token".into());
        state.ygdk.set(YgdkCredential {
            uid: 42,
            token: "ygdk-state-secret-token".into(),
        });

        let rendered = format!("{state:?}");
        assert!(!rendered.contains("cgyy-state-secret-token"));
        assert!(!rendered.contains("ygdk-state-secret-token"));
    }

    #[test]
    fn 清除不能让旧签到凭据越过失效代数回写() {
        let state = Arc::new(SigninState::default());
        let hook = Arc::new(StoreCredentialHook::default());
        state.set_store_hook(Arc::clone(&hook));
        let generation = state.generation();

        let writer_state = Arc::clone(&state);
        let writer = thread::spawn(move || {
            writer_state.store_credential(
                generation,
                SigninCredential {
                    user_id: "test-user".into(),
                    session_id: "stale-session".into(),
                },
            )
        });

        hook.wait_until_paused();
        let clearer_state = Arc::clone(&state);
        let clearer = thread::spawn(move || clearer_state.clear());
        while state.generation() == generation {
            thread::yield_now();
        }
        hook.release();

        assert!(writer.join().unwrap());
        clearer.join().unwrap();
        assert!(state.credential().is_none());
    }

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
