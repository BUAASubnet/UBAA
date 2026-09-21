//! 评教只持久化可阅读内容，不保存提交资格或问卷内部材料。
use crate::domain::{EvaluationCourse, EvaluationCoursesResponse, EvaluationProgress};
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedEvaluationCourse {
    pub id: String,
    pub kcmc: String,
    pub bpmc: String,
    pub is_evaluated: bool,
}
impl From<EvaluationCourse> for CachedEvaluationCourse {
    fn from(v: EvaluationCourse) -> Self {
        Self {
            id: v.id,
            kcmc: v.kcmc,
            bpmc: v.bpmc,
            is_evaluated: v.is_evaluated,
        }
    }
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedEvaluationCourses {
    pub courses: Vec<CachedEvaluationCourse>,
    pub progress: EvaluationProgress,
}
impl From<EvaluationCoursesResponse> for CachedEvaluationCourses {
    fn from(v: EvaluationCoursesResponse) -> Self {
        Self {
            courses: v.courses.into_iter().map(Into::into).collect(),
            progress: v.progress,
        }
    }
}
