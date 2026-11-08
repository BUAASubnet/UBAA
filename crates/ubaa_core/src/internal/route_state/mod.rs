//! 路线专属功能状态的聚合入口.

mod ihome;
pub(crate) use ihome::IhomeState;
mod cache;
mod classroom;
mod credentials;
pub(crate) use credentials::CredentialState;

pub(crate) use cache::{AssignmentList, JudgeState};
#[cfg(test)]
use cache::{JUDGE_ASSIGNMENT_CACHE_LIMIT, JUDGE_DETAIL_CACHE_LIMIT};
pub(crate) use classroom::ClassroomState;
#[cfg(test)]
pub(crate) use credentials::StoreCredentialHook;
pub(crate) use credentials::{
    BykcCredential, BykcState, CgyyState, FinanceCredential, LibBookCredential, LibBookState,
    SigninCredential, SigninState, SpocCredential, SpocState, YgdkCredential, YgdkState,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum StudentKind {
    Undergraduate,
    Graduate,
}

/// 仅由一条路线/一个客户端的运行时和读取工作线程共享的状态。
#[derive(Debug, Default)]
pub(crate) struct RouteFeatureState {
    lifecycle_generation: std::sync::Mutex<u64>,
    pub(crate) academic_identity: std::sync::Mutex<Option<(u64, StudentKind)>>,
    pub(crate) academic_identity_read: tokio::sync::Mutex<()>,
    pub(crate) bykc: BykcState,
    pub(crate) cgyy: CgyyState,
    pub(crate) libbook: LibBookState,
    pub(crate) classroom: ClassroomState,
    pub(crate) signin: SigninState,
    pub(crate) spoc: SpocState,
    pub(crate) judge: JudgeState,
    pub(crate) ygdk: YgdkState,
    pub(crate) ihome: IhomeState,
    pub(crate) finance: CredentialState<FinanceCredential>,
}

impl RouteFeatureState {
    pub(crate) fn lifecycle_generation(&self) -> u64 {
        *self.lifecycle_lock()
    }
    pub(crate) fn clear(&self) {
        self.clear_locked(&mut self.lifecycle_lock());
    }
    pub(crate) fn clear_if_generation(&self, expected: u64) {
        let mut generation = self.lifecycle_lock();
        if *generation == expected {
            self.clear_locked(&mut generation);
        }
    }
    fn lifecycle_lock(&self) -> std::sync::MutexGuard<'_, u64> {
        self.lifecycle_generation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
    // 先取路线生命周期锁，再取业务私有同步锁；清理期间不等待网络或异步锁。
    // 代次快照也取生命周期锁，避免新读取组在业务清理尚未完成时捕获新代次。
    fn clear_locked(&self, generation: &mut std::sync::MutexGuard<'_, u64>) {
        **generation = generation.wrapping_add(1);
        *self
            .academic_identity
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
        self.bykc.clear();
        self.cgyy.clear();
        self.libbook.clear();
        self.classroom.clear();
        self.signin.clear();
        self.spoc.clear();
        self.judge.clear();
        self.ygdk.clear();
        self.ihome.clear();
        self.finance.clear();
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::thread;
    use std::time::{Duration, Instant};

    use crate::domain::{Assignment, Course, JudgeAssignmentDetail, JudgeSubmissionStatus};

    use super::{
        AssignmentList, BykcCredential, BykcState, JudgeState, RouteFeatureState, SigninCredential,
        SigninState, StoreCredentialHook, YgdkCredential, YgdkState,
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
    fn 清除不能让旧阳光打卡登录重新写入凭据() {
        let state = Arc::new(YgdkState::default());
        let hook = Arc::new(StoreCredentialHook::default());
        state.set_store_hook(Arc::clone(&hook));

        let writer_state = Arc::clone(&state);
        let writer = thread::spawn(move || {
            let generation = writer_state.generation();
            writer_state.store_credential(
                generation,
                YgdkCredential {
                    uid: 42,
                    token: "旧登录返回的测试令牌".into(),
                },
            );
        });

        hook.wait_until_paused();
        state.clear();
        hook.release();
        writer.join().unwrap();

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
        assert_eq!(state.cache_counts(), (0, 0, 0));

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

        let (_, assignments, details) = state.cache_counts();
        assert_eq!(assignments, super::JUDGE_ASSIGNMENT_CACHE_LIMIT);
        assert_eq!(details, super::JUDGE_DETAIL_CACHE_LIMIT);

        state.clear();
        assert_eq!(state.cache_counts(), (0, 0, 0));
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
        assert_eq!(state.cache_counts(), (0, 0, 0));
    }
}
