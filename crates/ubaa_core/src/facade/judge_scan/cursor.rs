use super::{Assignment, Course};

/// 课程顺序与课内读取阶段只有游标可以推进，网络读取和缓存复用共用相同规则。
pub(in crate::facade) struct JudgeScanCursor {
    courses: Vec<Course>,
    course_index: usize,
    stage: CourseStage,
    failed_courses: usize,
    prepared: std::collections::BTreeMap<
        (String, String),
        crate::features::judge::parallel::PreparedDetail,
    >,
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
            prepared: std::collections::BTreeMap::default(),
        }
    }

    pub(in crate::facade) fn courses(&self) -> &[Course] {
        &self.courses
    }

    pub(in crate::facade) fn prioritize_courses<K: Ord>(&mut self, rank: impl FnMut(&Course) -> K) {
        self.courses.sort_by_cached_key(rank);
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

    pub(in crate::facade) fn pending_assignments(&self) -> &[Assignment] {
        match &self.stage {
            CourseStage::Details { items, next } => &items[*next..],
            CourseStage::Assignments => &[],
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

    pub(in crate::facade) fn push_prepared(
        &mut self,
        value: crate::features::judge::parallel::PreparedDetail,
    ) {
        self.prepared.insert(value.key.clone(), value);
    }

    pub(in crate::facade) fn take_prepared(
        &mut self,
    ) -> Option<crate::features::judge::parallel::PreparedDetail> {
        let assignment = self.current_assignment()?;
        self.prepared.remove(&(
            assignment.course_id.clone(),
            assignment.assignment_id.clone(),
        ))
    }

    pub(in crate::facade) fn has_prepared(&self, assignment: &Assignment) -> bool {
        self.prepared.contains_key(&(
            assignment.course_id.clone(),
            assignment.assignment_id.clone(),
        ))
    }

    pub(in crate::facade) fn drain_prepared(
        &mut self,
    ) -> Vec<crate::features::judge::parallel::PreparedDetail> {
        std::mem::take(&mut self.prepared).into_values().collect()
    }

    pub(in crate::facade) fn clear_prepared(&mut self) {
        self.prepared.clear();
    }

    fn advance_course(&mut self) {
        self.prepared.clear();
        self.course_index += 1;
        self.stage = CourseStage::Assignments;
    }
}
