use super::{Assignment, Course};

/// 课程顺序与课内读取阶段只有游标可以推进，网络读取和缓存复用共用相同规则。
pub(in crate::facade) struct JudgeScanCursor {
    courses: Vec<Course>,
    course_index: usize,
    stage: CourseStage,
    failed_courses: usize,
}

enum CourseStage {
    Assignments,
    Details { items: Vec<Assignment>, next: usize },
}

impl JudgeScanCursor {
    pub(in crate::facade) fn new(courses: Vec<Course>) -> Self {
        Self {
            courses,
            course_index: 0,
            stage: CourseStage::Assignments,
            failed_courses: 0,
        }
    }

    pub(in crate::facade) fn courses(&self) -> &[Course] {
        &self.courses
    }

    pub(in crate::facade) fn current_course(&self) -> Option<&Course> {
        self.courses.get(self.course_index)
    }

    pub(in crate::facade) fn current_assignment(&self) -> Option<&Assignment> {
        match &self.stage {
            CourseStage::Assignments => None,
            CourseStage::Details { items, next } => Some(&items[*next]),
        }
    }

    pub(in crate::facade) fn accept_assignments(&mut self, items: Vec<Assignment>) {
        if items.is_empty() {
            self.advance_course();
        } else {
            self.stage = CourseStage::Details { items, next: 0 };
        }
    }

    pub(in crate::facade) fn finish_detail(&mut self) {
        let CourseStage::Details { items, next } = &mut self.stage else {
            unreachable!("读取详情后才能推进详情游标");
        };
        *next += 1;
        if *next == items.len() {
            self.advance_course();
        }
    }

    pub(in crate::facade) fn fail_course(&mut self) {
        self.failed_courses += 1;
        self.advance_course();
    }

    /// 只调整尚未处理的详情，等优先级保留原索引顺序。
    pub(in crate::facade) fn prioritize_pending<K: Ord>(
        &mut self,
        rank: impl FnMut(&Assignment) -> K,
    ) {
        if let CourseStage::Details { items, next } = &mut self.stage {
            items[*next..].sort_by_cached_key(rank);
        }
    }

    pub(in crate::facade) fn finished(&self) -> bool {
        self.course_index >= self.courses.len()
    }

    pub(in crate::facade) fn failed_courses(&self) -> usize {
        self.failed_courses
    }

    pub(in crate::facade) fn complete(&self) -> bool {
        self.finished() && self.failed_courses == 0
    }

    fn advance_course(&mut self) {
        self.course_index += 1;
        self.stage = CourseStage::Assignments;
    }
}
